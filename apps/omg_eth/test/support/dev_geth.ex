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

defmodule OMG.Eth.DevGeth do
  @moduledoc """
  Helper module for deployment of contracts to dev geth.
  """

  @doc """
  Run geth in temp dir, kill it with SIGKILL when done.
  """

  require Logger

  alias OMG.Eth

  def start do
    {:ok, _} = Application.ensure_all_started(:briefly)
    {:ok, _} = Application.ensure_all_started(:erlexec)
    {:ok, _} = Application.ensure_all_started(:ethereumex)
    {:ok, homedir} = Briefly.create(directory: true)

    geth_pid =
      launch(
        "geth --dev --dev.period=1 --ws --wsorigins='*' --rpc --rpcapi=personal,eth,web3,admin --datadir #{homedir} 2>&1"
      )

    {:ok, :ready} = Eth.WaitFor.eth_rpc()

    on_exit = fn -> stop(geth_pid) end

    {:ok, on_exit}
  end

  # PRIVATE

  defp stop(pid) do
    # NOTE: monitor is required to stop_and_wait, don't know why? `monitor: true` on run doesn't work
    _ = Process.monitor(pid)
    {:exit_status, 35_072} = Exexec.stop_and_wait(pid)
    :ok
  end

  defp launch(cmd) do
    _ = Logger.debug("Starting geth")

    {:ok, geth_proc, _ref, [{:stream, geth_out, _stream_server}]} =
      Exexec.run(cmd, stdout: :stream, kill_command: "pkill -9 geth")

    wait_for_geth_start(geth_out)

    _ =
      if Application.get_env(:omg_eth, :node_logging_in_debug) do
        %Task{} =
          fn ->
            geth_out |> Enum.each(&OMG.Eth.DevNode.default_logger/1)
          end
          |> Task.async()
      end

    geth_proc
  end

  defp wait_for_geth_start(geth_out) do
    OMG.Eth.DevNode.wait_for_start(geth_out, "IPC endpoint opened", 15_000)
  end
end
