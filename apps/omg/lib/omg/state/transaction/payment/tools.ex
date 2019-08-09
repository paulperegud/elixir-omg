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

defmodule OMG.State.Transaction.Payment.Tools do
  @moduledoc """
  Some useful shared tools to work with payment-like transactions
  """

  alias OMG.State.Transaction
  alias OMG.Utxo

  require Transaction
  require Utxo

  def reconstruct_inputs(inputs_rlp) do
    with {:ok, inputs} <- parse_inputs(inputs_rlp),
         {:ok, inputs} <- inputs_without_gaps(inputs),
         do: {:ok, filter_non_zero_inputs(inputs)}
  end

  def reconstruct_metadata([]), do: {:ok, nil}
  def reconstruct_metadata([metadata]) when Transaction.is_metadata(metadata), do: {:ok, metadata}
  def reconstruct_metadata([_]), do: {:error, :malformed_metadata}

  defp parse_int!(binary), do: :binary.decode_unsigned(binary, :big)

  defp parse_inputs(inputs_rlp) do
    {:ok, Enum.map(inputs_rlp, &parse_input!/1)}
  rescue
    _ -> {:error, :malformed_inputs}
  end

  def filter_non_zero_inputs(inputs), do: Enum.filter(inputs, &Utxo.Position.non_zero?/1)

  # FIXME: we predetermine the input_pointer type, this is most likely bad - how to dispatch here?
  defp parse_input!(input_pointer), do: InputPointer.UtxoPosition.reconstruct(input_pointer)

  defp inputs_without_gaps(inputs),
    do: check_for_gaps(inputs, Utxo.position(0, 0, 0), {:error, :inputs_contain_gaps})

  # Check if any consecutive pair of elements contains empty followed by non-empty element
  # which means there is a gap
  def check_for_gaps(items, empty, error) do
    items
    # discard - discards last unpaired element from a comparison
    |> Stream.chunk_every(2, 1, :discard)
    |> Enum.any?(fn
      [^empty, elt] when elt != empty -> true
      _ -> false
    end)
    |> if(do: error, else: {:ok, items})
  end
end
