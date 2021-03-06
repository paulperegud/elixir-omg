# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :omg_watcher_rpc, OMG.WatcherRPC.Web.Endpoint,
  render_errors: [view: OMG.WatcherRPC.Web.Views.Error, accepts: ~w(json)],
  pubsub: [name: OMG.WatcherRPC.PubSub, adapter: Phoenix.PubSub.PG2],
  instrumenters: [SpandexPhoenix.Instrumenter],
  enable_cors: true

config :omg_watcher_rpc, OMG.WatcherRPC.Tracer,
  service: :web,
  adapter: SpandexDatadog.Adapter,
  disabled?: {:system, "DD_DISABLED", false, {String, :to_existing_atom}},
  env: {:system, "APP_ENV"},
  type: :web

config :spandex_phoenix, tracer: OMG.WatcherRPC.Tracer

import_config "#{Mix.env()}.exs"
