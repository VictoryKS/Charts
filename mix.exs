defmodule Contex.MixProject do
  use Mix.Project

  def project do
    [
      app: :charts,
      version: "1.12.2",
      elixir: "~> 1.9",
      description: "Charts library for Elixir",
      package: package(),
      deps: deps(),
    ]
  end
  
  defp package() do
    [
      name: "charts",
      files: ~w(lib mix.exs README* LICENSE*),
      licenses: ["MIT"],
      maintainers: ["VictoryKS", "TotallyNotMay"],
      links: %{"GitHub" => "https://github.com/VictoryKS/charts"}
    ]
  end

  def application do
    [
      extra_applications: [:eex]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:nitro, "~> 7.9.3"}
    ]
  end

end