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

defmodule OMG.State.Measure do
  @moduledoc """
  Counting business metrics sent to Datadog
  """

  import OMG.Status.Metric.Event, only: [name: 1]

  alias OMG.State.Core
  alias OMG.State.MeasurementCalculation
  alias OMG.Status.Metric.Datadog

  @supported_events [[:process, OMG.State]]
  def supported_events, do: @supported_events

  def handle_event([:process, OMG.State], _, %Core{} = state, _config) do
    Enum.each(MeasurementCalculation.calculate(state), fn
      {key, value} -> _ = Datadog.gauge(name(key), value)
      {key, value, metadata} -> _ = Datadog.gauge(name(key), value, tags: [metadata])
    end)
  end
end
