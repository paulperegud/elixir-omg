# WARN: this is purpose specific and hacky
# consider reducing your eth finality margins in the watcher's config to speed things up

{:ok, _} = Application.ensure_all_started(:ethereumex)
alias OMG.{API, Eth}
alias OMG.API.Crypto
alias OMG.API.DevCrypto
alias OMG.API.State.Transaction
alias OMG.API.TestHelper
alias OMG.API.Integration.DepositHelper
alias OMG.API.Utxo

require Utxo

import Eth.Encoding

eth = Eth.zero_address()
weth_enc = "0xc778417E063141139Fce010982780140Aa0cD5Ab"
weth = weth_enc |> String.downcase() |> from_hex

#
import_file("../alices.exs")

if {:ok, true} != Eth.RootChain.has_token(weth),
  do: {:ok, _} = weth |> Eth.RootChain.add_token(alice.addr) |> Eth.DevHelpers.transact_sync!()

# TODO: probably not useful, forgot about other ways to do stuff
do_geth_call = fn geth_call ->
  command = "geth --exec '#{geth_call}' attach http://localhost:8545" |> to_charlist()
  :os.cmd(command)
end

get_status = fn ->
  ~c(echo '{}' | http POST #{watcher}/status.get) |> :os.cmd() |> Poison.decode!()
end

get_status.()

send_on_root = fn from, to, currency, value ->
  if currency == eth do
    transfer_opts = [from: to_hex(from.addr), to: to_hex(to), value: to_hex(value)]

    txmap =
      Eth.Defaults.tx_defaults()
      # generous in case we want to send to a contract like weth
      |> Keyword.put(:gas, to_hex(100_000))
      |> Keyword.merge(transfer_opts)
      |> Enum.into(%{})

    {:ok, txhash} = Ethereumex.HttpClient.eth_send_transaction(txmap)

    {:ok, from_hex(txhash)}
    |> Eth.DevHelpers.transact_sync!()
  else
    Eth.Token.transfer(from.addr, to, value, currency)
    |> Eth.DevHelpers.transact_sync!()
  end
end

do_unlock = fn account ->
  account_enc = account.addr |> to_hex()
  passphrase = "ThisIsATestnetPassphrase"
  {:ok, true} = Ethereumex.HttpClient.request("personal_unlockAccount", [account_enc, passphrase, 0], [])
end

alices |> Enum.map(do_unlock)

get_utxos = fn address ->
  addr_enc = address |> to_hex()

  ~c(echo '{"address": "#{addr_enc}"}' | http POST #{watcher}/account.get_utxos)
  |> :os.cmd()
  |> Poison.decode!()
  |> Map.get("data")
end

# remember to wait until all the blocks that concern address get consumed by the Watcher
# otherwise you'll end up starting invalid exits (exiting from an old state)
get_composed_exit = fn utxo_pos ->
  ~c(echo '{"utxo_pos": #{utxo_pos}}' | http POST #{watcher}/utxo.get_exit_data)
  |> :os.cmd()
  |> Poison.decode!()
  |> Map.get("data")
end

# same comment as above
get_composed_exits = fn address ->
  get_utxos.(address)
  |> Enum.map(&Map.get(&1, "utxo_pos"))
  |> Enum.map(get_composed_exit)
end

#
# usage
# get_composed_exits.(alice.addr)

start_exit = fn composed_exit, account ->
  Eth.RootChain.start_exit(
    composed_exit["utxo_pos"],
    from_hex(composed_exit["txbytes"]),
    from_hex(composed_exit["proof"]),
    account.addr
  )
end

start_exits = fn composed_exits, account ->
  composed_exits
  |> Enum.map(&start_exit.(&1, account))
end

process_exits = fn token_addr, n_to_process, account ->
  Eth.RootChain.process_exits(token_addr, 0, n_to_process, account.addr, nil, gas: 200_000 * n_to_process)
  |> Eth.DevHelpers.transact_sync!()
end

submit_tx = fn tx ->
  ~c(echo '{"transaction": "#{tx}"}' | http POST #{watcher}/transaction.submit)
  |> :os.cmd()
  |> Poison.decode!()
  |> Map.get("data")
end

split_amount_wei = 1_000_000_000

split_utxos = fn starting_utxo_pos, starting_amount, currency, account ->
  Utxo.position(blknum, txindex, oindex) = Utxo.Position.decode(starting_utxo_pos)
  carry_on_output = [{account, starting_amount - 3 * split_amount_wei}]
  split_output = {account, split_amount_wei}
  split_outputs = List.duplicate(split_output, 3)

  TestHelper.create_encoded([{blknum, txindex, oindex, account}], currency, carry_on_output ++ split_outputs)
  |> to_hex()
  |> submit_tx.()
end

split_utxos_until = fn target, currency, account ->
  utxos = get_utxos.(account.addr) |> Enum.filter(&(from_hex(&1["currency"]) == currency))
  n_utxos = utxos |> Enum.count()
  n_splits = div(max(0, target - n_utxos) + 2, 3)
  max_utxo = utxos |> Enum.max_by(& &1["amount"])
  starting_amount = max_utxo["amount"]
  starting_utxo_pos = max_utxo["utxo_pos"]

  List.duplicate(:do, n_splits)
  |> Enum.reduce({starting_amount, starting_utxo_pos}, fn _i, {amount, utxo_pos} ->
    %{"blknum" => blknum, "txindex" => txindex} = IO.inspect(split_utxos.(utxo_pos, amount, currency, account))
    {amount - 3 * split_amount_wei, Utxo.Position.encode(Utxo.position(blknum, txindex, 0))}
  end)
end

# usage:
# split_utxos_until.(100, eth, alice)
# split_utxos_until.(100, weth, alice)

# remember to wait until all the blocks that concern address get consumed by the Watcher
# otherwise you'll end up starting invalid IFEs (exiting from an old state)
spend_and_start_ife = fn account ->
  utxos = get_utxos.(account.addr) |> Enum.take(2)

  {inputs, outputs} =
    utxos
    |> Enum.map(fn utxo ->
      amount = utxo["amount"]
      currency = utxo["currency"] |> from_hex()
      Utxo.position(blknum, txindex, oindex) = Utxo.Position.decode(utxo["utxo_pos"])
      {{blknum, txindex, oindex, account}, {account, currency, amount}}
    end)
    |> Enum.unzip()

  tx = TestHelper.create_encoded(inputs, outputs) |> to_hex()

  %{"txhash" => _} = tx |> submit_tx.() |> IO.inspect()

  %{"data" => get_in_flight_exit_response} =
    ~c(echo '{"txbytes": "#{tx}"}' | http POST #{watcher}/in_flight_exit.get_data)
    |> :os.cmd()
    |> Poison.decode!()

  raw_txbytes = get_in_flight_exit_response["in_flight_tx"] |> from_hex()

  # call root chain function that initiates in-flight exit
  {:ok, %{"status" => "0x1"}} =
    OMG.Eth.RootChain.in_flight_exit(
      raw_txbytes,
      get_in_flight_exit_response["input_txs"] |> from_hex(),
      get_in_flight_exit_response["input_txs_inclusion_proofs"] |> from_hex(),
      get_in_flight_exit_response["in_flight_tx_sigs"] |> from_hex(),
      account.addr
    )
    |> Eth.DevHelpers.transact_sync!()
    |> IO.inspect()

  {:ok, txhash1} = OMG.Eth.RootChain.piggyback_in_flight_exit(raw_txbytes, 0, account.addr)
  {:ok, txhash2} = OMG.Eth.RootChain.piggyback_in_flight_exit(raw_txbytes, 1, account.addr)
  {:ok, txhash3} = OMG.Eth.RootChain.piggyback_in_flight_exit(raw_txbytes, 4, account.addr)
  {:ok, txhash4} = OMG.Eth.RootChain.piggyback_in_flight_exit(raw_txbytes, 5, account.addr)

  [txhash1, txhash2, txhash3, txhash4] |> Enum.map(&Eth.WaitFor.eth_receipt(&1, 60_000))
end

#
# usage
# spend_and_start_ife.(alice)

# this might fail if your Watcher isn't fully synced
do_one_invalid_se = fn account ->
  [%{"utxo_pos" => exiting_pos, "currency" => currency, "amount" => amount}] = get_utxos.(account.addr) |> Enum.take(1)
  one_exit = get_composed_exit.(exiting_pos)
  Utxo.position(blknum, txindex, oindex) = Utxo.Position.decode(exiting_pos)
  currency = currency |> from_hex()
  tx = TestHelper.create_encoded([{blknum, txindex, oindex, account}], [{account, currency, amount}]) |> to_hex()
  %{"txhash" => _} = tx |> submit_tx.() |> IO.inspect()
  start_exit.(one_exit, account)
end

do_challenge = fn exiting_pos, account ->
  %{"data" => challenge} =
    ~c(echo '{"utxo_pos": #{exiting_pos}}' | http POST #{watcher}/utxo.get_challenge_data)
    |> :os.cmd()
    |> Poison.decode!()
    |> IO.inspect()

  {:ok, %{"status" => "0x1"}} =
    OMG.Eth.RootChain.challenge_exit(
      challenge["utxo_pos"],
      Eth.Encoding.from_hex(challenge["txbytes"]),
      challenge["input_index"],
      Eth.Encoding.from_hex(challenge["sig"]),
      account.addr
    )
    |> Eth.DevHelpers.transact_sync!()
end

get_invalid_ses = fn ->
  get_status.()
  |> get_in(["data", "byzantine_events"])
  |> Enum.filter(&(&1["event"] == "invalid_exit"))
end

# this might fail if your Watcher isn't fully synced
do_all_se_challenges = fn account ->
  get_invalid_ses.()
  |> Enum.map(&get_in(&1, ["details", "utxo_pos"]))
  |> IO.inspect(label: :will_challenge_these)
  |> Enum.map(&do_challenge.(&1, account))
end

#
# usage:
# do_one_invalid_se.(alice)
# wait till synced & optionally repeat as desired
# wait till all exits recognized
# do_all_se_challenges.(alice)
