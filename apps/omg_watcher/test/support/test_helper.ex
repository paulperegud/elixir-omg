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

defmodule OMG.Watcher.TestHelper do
  @moduledoc """
  Module provides common testing functions used by App's tests.
  """
  alias ExUnit.CaptureLog
  alias OMG.Utils.HttpRPC.Encoding
  alias OMG.Utxo

  require Utxo

  import ExUnit.Assertions
  use Phoenix.ConnTest

  @endpoint OMG.WatcherRPC.Web.Endpoint
  @api_version "0.2"

  def wait_for_process(pid, timeout \\ :infinity) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _, _} ->
        :ok
    after
      timeout ->
        throw({:timeouted_waiting_for, pid})
    end
  end

  def success?(path, body \\ nil) do
    response_body = rpc_call(path, body, 200)
    %{"version" => @api_version, "success" => true, "data" => data} = response_body
    data
  end

  def no_success?(path, body \\ nil) do
    response_body = rpc_call(path, body, 200)
    %{"version" => @api_version, "success" => false, "data" => data} = response_body
    data
  end

  def server_error?(path, body \\ nil) do
    response_body = rpc_call(path, body, 500)
    %{"version" => @api_version, "success" => false, "data" => data} = response_body
    data
  end

  def rpc_call(path, body \\ nil, expected_resp_status \\ 200) do
    response = post(put_req_header(build_conn(), "content-type", "application/json"), path, body)
    # CORS check
    assert ["*"] == get_resp_header(response, "access-control-allow-origin")

    required_headers = [
      "access-control-allow-origin",
      "access-control-expose-headers",
      "access-control-allow-credentials"
    ]

    for header <- required_headers do
      assert header in Keyword.keys(response.resp_headers)
    end

    # CORS check
    assert response.status == expected_resp_status
    Jason.decode!(response.resp_body)
  end

  def create_topic(main_topic, subtopic), do: main_topic <> ":" <> subtopic

  @doc """
  Decodes specified keys in map from hex to binary
  """
  @spec decode16(map(), list()) :: map()
  def decode16(data, keys) do
    keys
    |> Enum.filter(&Map.has_key?(data, &1))
    |> Enum.into(
      %{},
      fn key ->
        value = data[key]

        with true <- is_binary(value),
             {:ok, bin} <- Encoding.from_hex(value) do
          {key, bin}
        else
          _ -> {key, value}
        end
      end
    )
    |> (&Map.merge(data, &1)).()
  end

  def get_balance(address, token) do
    encoded_token = Encoding.to_hex(token)

    address
    |> get_balance()
    |> Enum.find(%{"amount" => 0}, fn %{"currency" => currency} -> encoded_token == currency end)
    |> Map.get("amount")
  end

  def get_utxos(address) do
    success?("/account.get_utxos", %{"address" => Encoding.to_hex(address)})
  end

  def get_exitable_utxos(address) do
    success?("/account.get_exitable_utxos", %{"address" => Encoding.to_hex(address)})
  end

  def get_balance(address) do
    success?("/account.get_balance", %{"address" => Encoding.to_hex(address)})
  end

  def get_exit_data(blknum, txindex, oindex) do
    utxo_pos = Utxo.Position.encode(Utxo.position(blknum, txindex, oindex))

    data = success?("utxo.get_exit_data", %{utxo_pos: utxo_pos})

    decode16(data, ["txbytes", "proof", "sigs"])
  end

  def get_exit_challenge(blknum, txindex, oindex) do
    utxo_pos = Utxo.position(blknum, txindex, oindex) |> Utxo.Position.encode()

    data = success?("utxo.get_challenge_data", %{utxo_pos: utxo_pos})

    decode16(data, ["txbytes", "sig"])
  end

  def get_in_flight_exit(transaction) do
    exit_data = success?("in_flight_exit.get_data", %{txbytes: Encoding.to_hex(transaction)})

    decode16(exit_data, ["in_flight_tx", "input_txs", "input_txs_inclusion_proofs", "in_flight_tx_sigs"])
  end

  def get_in_flight_exit_competitors(transaction) do
    competitor_data = success?("in_flight_exit.get_competitor", %{txbytes: Encoding.to_hex(transaction)})

    decode16(competitor_data, ["in_flight_txbytes", "competing_txbytes", "competing_sig", "competing_proof"])
  end

  def get_prove_canonical(transaction) do
    competitor_data = success?("in_flight_exit.prove_canonical", %{txbytes: Encoding.to_hex(transaction)})

    decode16(competitor_data, ["in_flight_txbytes", "in_flight_proof"])
  end

  def submit(transaction) do
    submission_info = success?("transaction.submit", %{transaction: Encoding.to_hex(transaction)})

    decode16(submission_info, ["txhash"])
  end

  def get_input_challenge_data(transaction, input_index) do
    proof_data =
      success?("in_flight_exit.get_input_challenge_data", %{
        txbytes: Encoding.to_hex(transaction),
        input_index: input_index
      })

    decode16(proof_data, [
      "in_flight_txbytes",
      "in_flight_input_index",
      "spending_txbytes",
      "spending_input_index",
      "spending_sig"
    ])
  end

  def get_output_challenge_data(transaction, output_index) do
    proof_data =
      success?("in_flight_exit.get_output_challenge_data", %{
        txbytes: Encoding.to_hex(transaction),
        output_index: output_index
      })

    decode16(proof_data, [
      "in_flight_txbytes",
      "in_flight_output_pos",
      "in_flight_proof",
      "spending_txbytes",
      "spending_input_index",
      "spending_sig"
    ])
  end

  def capture_log(function, max_waiting_ms \\ 2_000) do
    CaptureLog.capture_log(fn ->
      logs = CaptureLog.capture_log(fn -> function.() end)

      case logs do
        "" -> wait_for_log(max_waiting_ms)
        logs -> logs
      end
    end)
  end

  defp wait_for_log(max_waiting_ms, sleep_time_ms \\ 20) do
    steps = :erlang.ceil(max_waiting_ms / sleep_time_ms)

    Enum.reduce_while(1..steps, nil, fn _, _ ->
      logs = CaptureLog.capture_log(fn -> Process.sleep(sleep_time_ms) end)

      case logs do
        "" -> {:cont, ""}
        logs -> {:halt, logs}
      end
    end)
  end
end
