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

defmodule OMG.Watcher.DB.TxOutput do
  @moduledoc """
  Ecto schema for transaction's output or input
  """
  use Ecto.Schema

  alias OMG.State.Transaction
  alias OMG.Utxo
  alias OMG.Watcher.DB
  alias OMG.Watcher.DB.Repo
  alias OMG.Watcher.UtxoExit.Core

  require Utxo

  import Ecto.Query, only: [from: 2, where: 2]
  import Utxo, only: [is_deposit: 1]

  @type balance() :: %{
          currency: binary(),
          amount: non_neg_integer()
        }

  @type exit_t() :: %{
          utxo_pos: pos_integer(),
          txbytes: binary(),
          proof: binary(),
          sigs: binary()
        }

  @primary_key false
  schema "txoutputs" do
    field(:blknum, :integer, primary_key: true)
    field(:txindex, :integer, primary_key: true)
    field(:oindex, :integer, primary_key: true)
    field(:owner, :binary)
    field(:amount, OMG.Watcher.DB.Types.IntegerType)
    field(:currency, :binary)
    field(:proof, :binary)
    field(:spending_tx_oindex, :integer)
    field(:childchain_utxohash, :binary)

    belongs_to(:creating_transaction, DB.Transaction, foreign_key: :creating_txhash, references: :txhash, type: :binary)
    belongs_to(:spending_transaction, DB.Transaction, foreign_key: :spending_txhash, references: :txhash, type: :binary)

    many_to_many(
      :ethevents,
      DB.EthEvent,
      join_through: "ethevents_txoutputs",
      join_keys: [childchain_utxohash: :childchain_utxohash, rootchain_txhash: :rootchain_txhash]
    )

    timestamps([type: :utc_datetime])
  end

  @spec compose_utxo_exit(Utxo.Position.t()) :: {:ok, exit_t()} | {:error, :utxo_not_found}
  def compose_utxo_exit(Utxo.position(_, _, _) = decoded_utxo_pos) when is_deposit(decoded_utxo_pos),
    do: get_by_position(decoded_utxo_pos) |> Core.compose_deposit_exit(decoded_utxo_pos)

  def compose_utxo_exit(Utxo.position(blknum, _, _) = decoded_utxo_pos),
    # TODO: Make use of Block API's block.get when available
    do: DB.Transaction.get_by_blknum(blknum) |> Core.compose_output_exit(decoded_utxo_pos)

  @spec get_by_position(Utxo.Position.t()) :: map() | nil
  def get_by_position(Utxo.position(blknum, txindex, oindex)) do
    Repo.get_by(__MODULE__, blknum: blknum, txindex: txindex, oindex: oindex)
  end

  def get_utxos(owner) do
    query =
      from(
        txo in __MODULE__,
        preload: [:ethevents],
        left_join: ethevent in assoc(txo, :ethevents),
        where: txo.owner == ^owner and is_nil(txo.spending_txhash) and (is_nil(ethevent) or ethevent.event_type != ^:exit),
        order_by: [asc: :blknum, asc: :txindex, asc: :oindex]
      )

    Repo.all(query)
  end

  @spec get_balance(OMG.Crypto.address_t()) :: list(balance())
  def get_balance(owner) do
    query =
      from(
        txo in __MODULE__,
        left_join: ethevent in assoc(txo, :ethevents),
        where: txo.owner == ^owner and is_nil(txo.spending_txhash) and (is_nil(ethevent) or ethevent.event_type != ^:exit),
        group_by: txo.currency,
        select: {txo.currency, sum(txo.amount)}
      )

    Repo.all(query)
    |> Enum.map(fn {currency, amount} ->
      # defends against sqlite that returns integer here
      amount = amount |> Decimal.new() |> Decimal.to_integer()
      %{currency: currency, amount: amount}
    end)
  end

  @spec spend_utxos([map()]) :: :ok
  def spend_utxos(db_inputs) do
    db_inputs
    |> Enum.each(fn {Utxo.position(blknum, txindex, oindex), spending_oindex, spending_txhash} ->
      _ =
        DB.TxOutput
        |> where(blknum: ^blknum, txindex: ^txindex, oindex: ^oindex)
        |> Repo.update_all(set: [spending_tx_oindex: spending_oindex, spending_txhash: spending_txhash])
    end)
  end

  @spec create_outputs(pos_integer(), integer(), binary(), Transaction.any_flavor_t()) :: [map()]
  def create_outputs(
        blknum,
        txindex,
        txhash,
        tx
      ) do
    # zero-value outputs are not inserted, tx can have no outputs at all
    outputs =
      tx
      |> Transaction.get_outputs()
      |> Enum.with_index()
      |> Enum.flat_map(fn {%{currency: currency, owner: owner, amount: amount}, oindex} ->
        create_output(blknum, txindex, oindex, txhash, owner, currency, amount)
      end)

    outputs
  end

  defp create_output(_blknum, _txindex, _txhash, _oindex, _owner, _currency, 0), do: []

  defp create_output(blknum, txindex, oindex, txhash, owner, currency, amount) when amount > 0,
    do: [
      %{
        blknum: blknum,
        txindex: txindex,
        oindex: oindex,
        owner: owner,
        amount: amount,
        currency: currency,
        creating_txhash: txhash
      }
    ]

  @spec create_inputs(Transaction.any_flavor_t(), binary()) :: [tuple()]
  def create_inputs(tx, spending_txhash) do
    tx
    |> Transaction.get_inputs()
    |> Enum.with_index()
    |> Enum.map(fn {Utxo.position(_, _, _) = input_utxo_pos, index} ->
      {input_utxo_pos, index, spending_txhash}
    end)
  end

  @spec get_sorted_grouped_utxos(OMG.Crypto.address_t()) :: %{OMG.Crypto.address_t() => list(%__MODULE__{})}
  def get_sorted_grouped_utxos(owner) do
    # TODO: use clever DB query to get following out of DB
    get_utxos(owner)
    |> Enum.group_by(& &1.currency)
    |> Enum.map(fn {k, v} -> {k, Enum.sort_by(v, & &1.amount, &>=/2)} end)
    |> Map.new()
  end
end
