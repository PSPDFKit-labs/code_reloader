defmodule CodeReloader.Mixfile do
  use Mix.Project

  def project do
    [app: :code_reloader,
     version: "0.0.1",
     elixir: "~> 1.1.1",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [applications: [:logger, :mix, :fs],
     mod: {CodeReloader, []}]
  end

  defp deps do
    [
      {:fs, "~> 0.9.1"},
      {:plug, "~> 1.0", optional: true},
    ]
  end
end
