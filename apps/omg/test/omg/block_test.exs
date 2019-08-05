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

defmodule OMG.BlockTest do
  @moduledoc """
  Simple unit test of part of `OMG.Block`.
  """

  use ExUnitFixtures
  use ExUnit.Case, async: true

  alias OMG.Block
  alias OMG.TestHelper

  defp eth, do: OMG.Eth.RootChain.eth_pseudo_address()

  @tag fixtures: [:stable_alice, :stable_bob]
  test "Block merkle proof smoke test", %{
    stable_alice: alice
  } do
    # this checks merkle proof normally tested via speaking to the contract (integration tests) against
    # a fixed binary. The motivation for having such test is a quick test of whether the merkle proving didn't change

    # odd number of transactions, just in case
    tx_1 = TestHelper.create_encoded([{1, 0, 0, alice}], eth(), [{alice, 7}])
    tx_2 = TestHelper.create_encoded([{1, 1, 0, alice}], eth(), [{alice, 2}])
    tx_3 = TestHelper.create_encoded([{1, 0, 1, alice}], eth(), [{alice, 2}])

    txs = [tx_1, tx_2, tx_3]
    assert Block.inclusion_proof(txs, 1) == Block.inclusion_proof(%Block{transactions: txs}, 1)

    assert %Block{transactions: [tx_1, tx_2, tx_3]} |> Block.inclusion_proof(2) ==
             <<41, 13, 236, 217, 84, 139, 98, 168, 214, 3, 69, 169, 136, 56, 111, 200, 75, 166, 188, 149, 72, 64, 8,
               246, 54, 47, 147, 22, 14, 243, 229, 99, 245, 210, 240, 167, 47, 68, 138, 150, 187, 231, 146, 45, 253,
               168, 222, 199, 121, 72, 198, 53, 164, 202, 115, 216, 140, 224, 121, 174, 101, 48, 199, 130, 137, 7, 64,
               168, 235, 6, 206, 155, 228, 34, 203, 141, 165, 205, 175, 194, 181, 140, 10, 94, 36, 3, 108, 87, 141, 226,
               164, 51, 200, 40, 255, 125, 59, 142, 192, 158, 2, 111, 220, 48, 83, 101, 223, 201, 78, 24, 154, 129, 179,
               140, 117, 151, 179, 217, 65, 194, 121, 240, 66, 232, 32, 110, 11, 216, 236, 213, 14, 238, 56, 227, 134,
               189, 98, 190, 155, 237, 185, 144, 112, 105, 81, 182, 95, 224, 83, 189, 157, 138, 82, 26, 247, 83, 209,
               57, 226, 218, 222, 255, 246, 211, 48, 187, 84, 3, 246, 59, 20, 243, 59, 87, 130, 116, 22, 13, 227, 165,
               13, 244, 239, 236, 240, 224, 219, 115, 188, 221, 61, 165, 97, 123, 221, 17, 247, 192, 161, 31, 73, 219,
               34, 246, 41, 56, 122, 18, 218, 117, 150, 249, 209, 112, 77, 116, 101, 23, 124, 99, 216, 142, 199, 215,
               41, 44, 35, 169, 170, 29, 139, 234, 126, 36, 53, 229, 85, 164, 166, 14, 55, 154, 90, 53, 243, 244, 82,
               186, 230, 1, 33, 7, 63, 182, 238, 173, 225, 206, 169, 46, 217, 154, 205, 203, 4, 90, 103, 38, 178, 248,
               113, 7, 232, 166, 22, 32, 162, 50, 207, 77, 125, 91, 87, 102, 179, 149, 46, 16, 122, 214, 108, 10, 104,
               199, 44, 184, 158, 79, 180, 48, 56, 65, 150, 110, 64, 98, 167, 106, 185, 116, 81, 227, 185, 251, 82, 106,
               92, 235, 127, 130, 224, 38, 204, 90, 74, 237, 60, 34, 165, 140, 189, 61, 42, 199, 84, 201, 53, 44, 84,
               54, 246, 56, 4, 45, 202, 153, 3, 78, 131, 99, 101, 22, 61, 4, 207, 253, 139, 70, 168, 116, 237, 245, 207,
               174, 99, 7, 125, 232, 95, 132, 154, 102, 4, 38, 105, 123, 6, 168, 41, 199, 13, 209, 64, 156, 173, 103,
               106, 163, 55, 164, 133, 228, 114, 138, 11, 36, 13, 146, 179, 239, 123, 60, 55, 45, 6, 209, 137, 50, 43,
               253, 95, 97, 241, 231, 32, 62, 162, 252, 164, 164, 150, 88, 249, 250, 183, 170, 99, 40, 156, 145, 183,
               199, 182, 200, 50, 166, 208, 230, 147, 52, 255, 91, 10, 52, 131, 208, 157, 171, 78, 191, 217, 205, 123,
               202, 37, 5, 247, 190, 245, 156, 193, 193, 46, 204, 112, 143, 255, 38, 174, 74, 241, 154, 190, 133, 42,
               254, 158, 32, 200, 98, 45, 239, 16, 209, 61, 209, 105, 245, 80, 245, 120, 189, 163, 67, 217, 113, 122,
               19, 133, 98, 224, 9, 59, 56, 10, 17, 32, 120, 157, 83, 207, 16>>
  end

  @tag fixtures: [:alice]
  test "Block merkle proof smoke test for deposit transactions",
       %{alice: alice} do
    tx = TestHelper.create_encoded([], eth(), [{alice, 7}])

    proof =
      %Block{transactions: [tx]}
      |> Block.inclusion_proof(0)

    assert is_binary(proof)
    assert byte_size(proof) == 32 * 16
  end
end
