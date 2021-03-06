use Mix.Config

# We need to start OMG.ChildChainRPC.Web.Endpoint with HTTP server for Performance and Watcher tests to work
# as a drawback lightweight (without HTTP server) controller tests are no longer an option.
config :omg_child_chain_rpc, OMG.ChildChainRPC.Web.Endpoint,
  http: [port: 9656],
  server: true

config :omg_child_chain_rpc, OMG.ChildChainRPC.Tracer,
  service: :omg_child_chain_rpc,
  adapter: SpandexDatadog.Adapter,
  disabled?: true,
  env: "test",
  type: :web

config :omg_child_chain_rpc, environment: :test
