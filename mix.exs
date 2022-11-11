defmodule LadderParser.MixProject do
  use Mix.Project

  def project do
    [
      app: :ladder_parser,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      default_task: "run"
    ]
  end

  # ank

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ParseApp, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.2.1"}
    ]
  end
end
