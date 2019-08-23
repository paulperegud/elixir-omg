# Copyright 2019 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.Performance.ByzantineEventsTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false
  use OMG.ChildChain.Integration.Fixtures
  use OMG.Watcher.Fixtures
  alias OMG.Eth
  require OMG.Utxo

  alias OMG.Eth
  alias OMG.Eth.RootChain
  alias OMG.Performance
  alias OMG.State.Transaction
  alias OMG.Utxo
  alias OMG.Watcher.HttpRPC.Client
  alias OMG.Watcher.TestHelper

  @moduletag :integration
  @moduletag timeout: 70_000_000

  @tag fixtures: [:child_chain, :contract, 
    :watcher] 
  #:db_initialized, :root_chain_contract_config]
  test "time response for asking for exit data", %{contract: %{contract_addr: contract}} do
    :observer.start()
    dos_users = 1_000
    ntx_to_send = 10_000
    spenders = generate_users(4)
    total_exits = length(spenders) * ntx_to_send * dos_users

    IO.puts("""
    dos users: #{dos_users}
    spenders: #{length(spenders)}
    ntx_toxend: #{ntx_to_send}
    exits per dos user: #{length(spenders) * ntx_to_send}
    total exits: #{total_exits}
    """)

    Performance.start_extended_perftest(ntx_to_send, spenders, contract)
    transaction_in_child_chain(length(spenders) * ntx_to_send)
    # watcher run
    #{:ok, started_apps} = Application.ensure_all_started(:omg_db)
    #{:ok, started_watcher} = Application.ensure_all_started(:omg_watcher)
    #{:ok, started_watcher_api} = Application.ensure_all_started(:omg_watcher_rpc)
    #[] = OMG.Watcher.DB.Repo.all(OMG.Watcher.DB.Block)

    TestHelper.watcher_synchronize()

    exit_info = generate_exit_info()
    assert length(exit_info) * dos_users == total_exits

    statistics =
      Enum.map(1..dos_users, fn _ ->
        Task.async(fn ->
          exit_info = exit_info |> Enum.shuffle()
          :timer.tc(fn -> exit_info |> get_exit_data() end)
        end)
      end)
      |> Enum.map(fn task -> Task.await(task, :infinity) |> gather_result_statistics() end)

    times = statistics |> Enum.map(&Map.get(&1, :time))
    correct_exits = statistics |> Enum.map(&Map.get(&1, :correct)) |> Enum.sum()
    error_exits = statistics |> Enum.map(&Map.get(&1, :error)) |> Enum.sum()

    IO.puts("""
    max dos user time: #{Enum.max(times) / 1_000}
    min dos user time: #{Enum.min(times) / 1_000}
    average dos user time: #{Enum.sum(times) / length(times) / 1_000}
    correct exits: #{correct_exits}
    time per exit: #{Enum.sum(times) / total_exits}
    error exits: #{error_exits}
    """)

    assert error_exits == 0
  end

  def gather_result_statistics({time, exits_data}) do
    Enum.reduce(exits_data, %{correct: 0, error: 0}, fn
      %{"proof" => _}, stats -> Map.update!(stats, :correct, &(&1 + 1))
      _, stats -> Map.update!(stats, :error, &(&1 + 1))
    end)
    |> Map.put(:time, time)
  end

  defp transaction_in_child_chain(txs) do
    {:ok, interval} = RootChain.get_child_block_interval()

    Eth.WaitFor.repeat_until_ok(
      fn %{blknum: blknum, wait_for_txs: txs, interval: interval} ->
        {:ok, top_block} = RootChain.get_mined_child_block()

        {blknum, txs} =
          if top_block > blknum do
            {:ok, block} = get_block(blknum + interval)
            IO.puts("(#{txs - length(block.transactions)})get blknum #{blknum + interval} [[#{length(block.transactions)}]]")
            {blknum + interval, txs - length(block.transactions)}
          else
            {blknum, txs}
          end

        if txs <= 0,
          do: {:ok, -txs},
          else: %{blknum: blknum, wait_for_txs: txs, interval: interval}
      end,
      %{blknum: 0, wait_for_txs: txs, interval: interval}
    )
  end

  defp generate_exit_info do
    %{interval: interval, counter: length_block} = block_info() |> IO.inspect()

    1..length_block
    |> Enum.map(&generate_exit_info_block(&1 * interval))
    |> Enum.concat()
  end

  defp block_info do
    {:ok, interval} = RootChain.get_child_block_interval()
    {:ok, top_block} = RootChain.get_mined_child_block()
    %{interval: interval, counter: trunc(top_block / interval)}
  end

  defp get_block(blknum) do
    {:ok, {block_hash, _timestamp}} = RootChain.get_child_chain(blknum)
    child_chain_url = Application.get_env(:omg_watcher, :child_chain_url)

    Enum.find(Stream.iterate(0, fn _ -> Client.get_block(block_hash, child_chain_url) end), fn
      {:ok, _} -> true
      _ -> false
    end)
  end

  defp generate_exit_info_block(blknum) do
    {:ok, block} = get_block(blknum)

    Enum.zip(block.transactions, Stream.iterate(0, &(&1 + 1)))
    |> Enum.map(fn {tx, nr} ->
      recover_tx = Transaction.Recovered.recover_from!(tx)
      outputs = Transaction.get_outputs(recover_tx)
      position = Utxo.position(blknum, nr, Enum.random(0..(length(outputs) - 1)))
      utxo_pos = Utxo.Position.encode(position)
      %{utxo_pos: utxo_pos, recover_tx: recover_tx}
      utxo_pos
    end)
  end

  defp get_exit_data(utxos) when is_list(utxos) do
    Enum.map(utxos, &get_exit_data/1)
  end

  # %{utxo_pos: utxo_pos}) do
  defp get_exit_data(utxo_pos) do
    ret = TestHelper.get_exit_data(utxo_pos)
    #    IO.write(".")
    ret
  rescue
    error in MatchError ->
      IO.write("\e[41m≠#{inspect(error)}\e[0m")
      error

    error ->
      IO.write("\e[46m©\e[0m")
      error
  end

  defp generate_users(size, opts \\ [initial_funds: trunc(:math.pow(10, 18))]) do
    async_generate_user = fn _ -> Task.async(fn -> generate_user(opts) end) end

    Enum.chunk_every(1..size, 10)
    |> Enum.map(fn chunk ->
      Enum.map(chunk, async_generate_user)
      |> Enum.map(&Task.await(&1, :infinity))
    end)
    |> List.flatten()
  end

  defp generate_user(opts) do
    user = OMG.TestHelper.generate_entity()
    {:ok, _user} = Eth.DevHelpers.import_unlock_fund(user, opts)
    user
  end
end
