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

defmodule OMG.Watcher.ExitProcessor.Canonicity do
  @moduledoc """
  Encapsulates managing and executing the behaviors related to treating exits by the child chain and watchers
  Keeps a state of exits that are in progress, updates it with news from the root chain, compares to the
  state of the ledger (`OMG.State`), issues notifications as it finds suitable.

  Should manage all kinds of exits allowed in the protocol and handle the interactions between them.

  This is the functional, zero-side-effect part of the exit processor. Logic should go here:
    - orchestrating the persistence of the state
    - finding invalid exits, disseminating them as events according to rules
    - enabling to challenge invalid exits
    - figuring out critical failure of invalid exit challenging (aka `:unchallenged_exit` event)
    - MoreVP protocol managing in general

  For the imperative shell, see `OMG.Watcher.ExitProcessor`
  """

  alias OMG.Block
  alias OMG.Crypto
  alias OMG.State.Transaction
  alias OMG.Utxo
  alias OMG.Watcher.Event
  alias OMG.Watcher.ExitProcessor
  alias OMG.Watcher.ExitProcessor.Core
  alias OMG.Watcher.ExitProcessor.DoubleSpend
  alias OMG.Watcher.ExitProcessor.InFlightExitInfo
  alias OMG.Watcher.ExitProcessor.KnownTx

  import OMG.Watcher.ExitProcessor.Tools

  require Utxo

  use OMG.Utils.LoggerExt

  @type competitor_data_t :: %{
          in_flight_txbytes: binary(),
          in_flight_input_index: non_neg_integer(),
          competing_txbytes: binary(),
          competing_input_index: non_neg_integer(),
          competing_sig: Crypto.sig_t(),
          competing_tx_pos: nil | Utxo.Position.t(),
          competing_proof: binary()
        }

  @type prove_canonical_data_t :: %{
          in_flight_txbytes: binary(),
          in_flight_tx_pos: Utxo.Position.t(),
          in_flight_proof: binary()
        }

  # Gets the list of open IFEs that have the competitors _somewhere_
  @spec get_ife_txs_with_competitors(Core.t(), KnownTx.known_txs_by_input_t()) :: list(Event.NonCanonicalIFE.t())
  def get_ife_txs_with_competitors(%Core{in_flight_exits: ifes}, known_txs_by_input) do
    ifes
    |> Map.values()
    |> Stream.map(fn ife -> {ife, DoubleSpend.find_competitor(known_txs_by_input, ife.tx)} end)
    |> Stream.filter(fn {_ife, maybe_competitor} -> !is_nil(maybe_competitor) end)
    |> Stream.filter(fn {ife, %DoubleSpend{known_tx: %KnownTx{utxo_pos: utxo_pos}}} ->
      InFlightExitInfo.is_viable_competitor?(ife, utxo_pos)
    end)
    |> Stream.map(fn {ife, _double_spend} -> Transaction.raw_txbytes(ife.tx) end)
    |> Enum.uniq()
    |> Enum.map(fn txbytes -> %Event.NonCanonicalIFE{txbytes: txbytes} end)
  end

  # Gets the list of open IFEs that have the competitors _somewhere_
  @spec get_invalid_ife_challenges(Core.t()) :: list(Event.InvalidIFEChallenge.t())
  def get_invalid_ife_challenges(%Core{in_flight_exits: ifes}) do
    ifes
    |> Map.values()
    |> Stream.filter(&InFlightExitInfo.is_invalidly_challenged?/1)
    |> Stream.map(&Transaction.raw_txbytes(&1.tx))
    |> Enum.uniq()
    |> Enum.map(fn txbytes -> %Event.InvalidIFEChallenge{txbytes: txbytes} end)
  end

  @doc """
  Gets the root chain contract-required set of data to challenge a non-canonical ife
  """
  @spec get_competitor_for_ife(ExitProcessor.Request.t(), Core.t(), binary()) ::
          {:ok, competitor_data_t()}
          | {:error, :competitor_not_found}
          | {:error, :ife_not_known_for_tx}
          | {:error, :no_viable_competitor_found}
          | {:error, Transaction.decode_error()}
  def get_competitor_for_ife(
        %ExitProcessor.Request{blocks_result: blocks},
        %Core{} = state,
        ife_txbytes
      ) do
    known_txs_by_input = KnownTx.get_all_from_blocks_appendix(blocks, state)
    # find its competitor and use it to prepare the requested data
    with {:ok, ife_tx} <- Transaction.decode(ife_txbytes),
         {:ok, ife} <- get_ife(ife_tx, state.in_flight_exits),
         {:ok, double_spend} <- get_competitor(known_txs_by_input, ife.tx),
         %DoubleSpend{known_tx: %KnownTx{utxo_pos: utxo_pos}} = double_spend,
         true <- check_viable_competitor(ife, utxo_pos),
         do: {:ok, prepare_competitor_response(double_spend, ife.tx, blocks)}
  end

  @doc """
  Gets the root chain contract-required set of data to challenge an ife appearing as non-canonical in the root chain
  contract but which is known to be canonical locally because included in one of the blocks
  """
  @spec prove_canonical_for_ife(Core.t(), binary()) ::
          {:ok, prove_canonical_data_t()} | {:error, :no_viable_canonical_proof_found}
  def prove_canonical_for_ife(%Core{} = state, ife_txbytes) do
    with {:ok, raw_ife_tx} <- Transaction.decode(ife_txbytes),
         {:ok, ife} <- get_ife(raw_ife_tx, state.in_flight_exits),
         true <- check_is_invalidly_challenged(ife),
         do: {:ok, prepare_canonical_response(ife)}
  end

  defp prepare_competitor_response(
         %DoubleSpend{
           index: in_flight_input_index,
           known_spent_index: competing_input_index,
           known_tx: %KnownTx{signed_tx: known_signed_tx, utxo_pos: known_tx_utxo_pos}
         },
         signed_ife_tx,
         blocks
       ) do
    {:ok, input_witnesses} = Transaction.Signed.get_witnesses(signed_ife_tx)
    owner = input_witnesses[in_flight_input_index]

    %{
      in_flight_txbytes: signed_ife_tx |> Transaction.raw_txbytes(),
      in_flight_input_index: in_flight_input_index,
      competing_txbytes: known_signed_tx |> Transaction.raw_txbytes(),
      competing_input_index: competing_input_index,
      competing_sig: find_sig!(known_signed_tx, owner),
      competing_tx_pos: known_tx_utxo_pos || Utxo.position(0, 0, 0),
      competing_proof: maybe_calculate_proof(known_tx_utxo_pos, blocks)
    }
  end

  defp prepare_canonical_response(%InFlightExitInfo{tx: tx, tx_seen_in_blocks_at: {pos, proof}}),
    do: %{in_flight_txbytes: Transaction.raw_txbytes(tx), in_flight_tx_pos: pos, in_flight_proof: proof}

  defp maybe_calculate_proof(nil, _), do: <<>>

  defp maybe_calculate_proof(Utxo.position(blknum, txindex, _), blocks) do
    blocks
    |> Enum.find(fn %Block{number: number} -> blknum == number end)
    |> Block.inclusion_proof(txindex)
  end

  defp get_competitor(known_txs_by_input, signed_ife_tx) do
    known_txs_by_input
    |> DoubleSpend.find_competitor(signed_ife_tx)
    |> case do
      nil -> {:error, :competitor_not_found}
      value -> {:ok, value}
    end
  end

  defp check_viable_competitor(ife, utxo_pos),
    do: if(InFlightExitInfo.is_viable_competitor?(ife, utxo_pos), do: true, else: {:error, :no_viable_competitor_found})

  defp check_is_invalidly_challenged(ife),
    do: if(InFlightExitInfo.is_invalidly_challenged?(ife), do: true, else: {:error, :no_viable_canonical_proof_found})
end
