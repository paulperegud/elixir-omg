# Copyright 2018 OmiseGO Pte Ltd
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

defmodule OMG.Watcher.Web.View.InflightExit do
  @moduledoc """
  The transaction view for rendering json
  """

  use OMG.Watcher.Web, :view

  alias OMG.API.Utxo
  alias OMG.Watcher.Web.Serializers

  def render("in_flight_exit.json", %{in_flight_exit: in_flight_exit}) do
    in_flight_exit
    |> Serializers.Response.serialize(:success)
  end

  def render("competitor.json", %{competitor: competitor}) do
    competitor
    |> Map.update!(:competing_txid, &Utxo.Position.encode/1)
    |> Serializers.Response.serialize(:success)
  end

  def render("prove_canonical.json", %{prove_canonical: prove_canonical}) do
    prove_canonical
    |> Map.update!(:inflight_txid, &Utxo.Position.encode/1)
    |> Serializers.Response.serialize(:success)
  end
end
