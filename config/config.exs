# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# By default, the umbrella project as well as each child
# application will require this configuration file, ensuring
# they all use the same configuration. While one could
# configure all applications here, we prefer to delegate
# back to each application for organization purposes.
import_config "../apps/*/config/config.exs"

# Sample configuration (overrides the imported configuration above):
config :logger, level: :debug

config :logger, :console,
  level: :debug,
  #format: "$date $time [$level] $metadata⋅$message⋅\n",
  format: {OMG.Utils.LoggerExt, :format},
  discard_threshold: 2000,
  metadata: [:module, :function, :line, :file, :request_id],
  remove_module: [
    ":telemetry32",
    "OMG.RootChainCoordinator",
    "Plug.Logger",
    "OMG.Eth.DevNode",
    "OMG.Eth.DevGeth",
    "OMG.Performance.SenderServer",
    "OMG.Watcher.HttpRPC.Adapter",
    "OMG.Watcher.BlockGetter:239",
    "OMG.Watcher.ExitProcessor:(432|444|456|467|465)",
    "Ecto.Adapters.SQL:809.*\n.*\n.*\n.*source=\"txoutputs\"",
    "Phoenix.Logger:157.*\n.*Controller.Status.*\n.*get_status",
    "Phoenix.Logger:157.*\n.*Controller.Utxo.*\n.*get_utxo_exit",
    "OMG.Eth.EthereumHeight:55"
    #         "Phoenix.Logger",
  #     ":application_controller",
  #  "OMG,Watcher.Web.Controller.Utxo",
    #        "BlockQueue.Core", 
    #         "API.FeeChecker",
    #         "FreshBlocks",
    #         "BlockQueue",
    #         "Plug.Logger",
    #         "Ecto.LogEntry",
    #         "OMG.DB", 
    #         "OMG.API.RootChainCoordinator", 
    #     "OMG.Watcher.BlockGetter",
    #     "OMG.Watcher.DB",
  #   "Watcher.Fixtures", 
    #     "Eth.DevGeth", 
  #  "BlockQueue.Server","Ecto.","Plug.Logger",
    #    "OMG.API.EthereumEventListener",
    #    "Performance.SenderServer"
  ] |> Enum.join("|")

config :logger,
  backends: [:console]

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: System.get_env("APP_ENV"),
  included_environments: [:dev, :prod, System.get_env("APP_ENV")],
  server_name: elem(:inet.gethostname(), 1),
  tags: %{
    application: System.get_env("ELIXIR_SERVICE"),
    eth_network: System.get_env("ETHEREUM_NETWORK"),
    eth_node: System.get_env("ETH_NODE")
  }

import_config "#{Mix.env()}.exs"
