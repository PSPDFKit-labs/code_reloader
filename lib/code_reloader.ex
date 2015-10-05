defmodule CodeReloader do
  use Application
  @moduledoc """
  A plug and module to handle automatic code reloading.

  For each request, Phoenix checks if any of the modules previously
  compiled requires recompilation via `__phoenix_recompile__?/0` and then
  calls `mix compile` for sources exclusive to the `web` directory.

  To avoid race conditions, all code reloads are funneled through a
  sequential call operation.
  """

  ## Server delegation

  @doc """
  Reloads code within the paths specified in the `:reloadable_paths`
  config for the endpoint by invoking the `:reloadable_compilers`.

  This is configured in your application environment like:

      config :your_app, YourApp.Endpoint,
        reloadable_paths: ["web"],
        reloadable_compilers: [:gettext, :phoenix, :elixir]

  Keep in mind that the paths passed to `:reloadable_paths` must be
  a subset of the paths specified in the `:elixirc_paths` option of
  `project/0` in `mix.exs` while `:reloadable_compilers` is a subset
  of `:compilers`.
  """
  @spec reload!() :: :ok | :noop | {:error, binary()}
  defdelegate reload!(), to: CodeReloader.Server

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(CodeReloader.Server, []),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CodeReloader.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
