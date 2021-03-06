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

defmodule OMG.Eth.Application do
  @moduledoc false

  alias OMG.Eth

  use Application
  use OMG.Utils.LoggerExt

  def start(_type, _args) do
    DeferredConfig.populate(:omg_eth)

    _ = Logger.info("Started #{inspect(__MODULE__)}, config used: #{inspect(Eth.Diagnostics.get_child_chain_config())}")

    OMG.Eth.Supervisor.start_link()
  end
end
