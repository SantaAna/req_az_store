defmodule ReqAzStore.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_az_store,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def package do
  [
    description: "a minmal Req plugin for azure storage requests",
    license: ["Apache-2.0"],
  ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.4.14"},
      {:plug, "~> 1.15", only: [:dev, :test]}
    ]
  end
end
