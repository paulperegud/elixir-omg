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

defmodule OMG.ChildChainRPC.Web.Controller.Transaction do
  @moduledoc """
  Provides endpoint action to submit transaction to the Child Chain.
  """

  use OMG.ChildChainRPC.Web, :controller

  alias OMG.ChildChain
  alias OMG.ChildChainRPC.Web.View

  def submit(conn, params) do
    with {:ok, txbytes} <- expect(params, "transaction", :hex),
         {:ok, details} <- ChildChain.submit(txbytes) do
      conn
      |> put_view(View.Transaction)
      |> render(:submit, result: details)
    end
  end
end
