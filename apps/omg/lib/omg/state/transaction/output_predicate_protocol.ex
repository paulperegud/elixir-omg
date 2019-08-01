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

defmodule OMG.State.Transaction.OutputPredicateProtocol do
  @moduledoc """
  Code allowing outputs being spent by txs to be unlocked.

  Intended to be called in stateful validation
  """

  alias OMG.Crypto
  alias OMG.State.Transaction

  @doc """
  True if a particular witness can unlock a particular output to be spent, given being put in a particular transaction
  """
  def can_spend?(witness, output_spent, _raw_tx) when is_binary(witness) do
    output_spent.owner == witness
  end

  # FIXME: here we could add checking of the exchange_addr versus the order signed by owner
  def can_spend?(
        {<<"output_type_is_deposit", payload_preimage::binary>> = preimage, exchange_addr},
        input_utxo,
        %Transaction.Settlement{}
      )
      when is_binary(preimage) and is_binary(exchange_addr) and exchange_addr == binary_part(payload_preimage, 0, 20) do
    input_utxo.owner == preimage |> Crypto.hash() |> binary_part(0, 20)
  end

  def can_spend?({preimage, exchange_addr}, _, _) when is_binary(preimage) and is_binary(exchange_addr),
    do: false
end
