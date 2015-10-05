# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :code_reloader,
  enabled: false,
  reloadable_compilers: [:gettext, :phoenix, :elixir, :erlang],
  reloadable_paths: ["lib", "web"]
