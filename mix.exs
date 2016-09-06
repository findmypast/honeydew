defmodule Honeydew.Mixfile do
  use Mix.Project

  @version "0.0.11"

  def project do
    [app: :honeydew,
     version: @version,
     elixir: "~> 1.3.0",
     deps: deps,
     package: package,
     description: "Pluggable local/remote job queue + worker pool with permanent workers."]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      # mod: {Honeydew, []},
      applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:gen_stage, ">= 0.5.0"},
      {:amqp, ">= 0.1.4"},
      {:amqp_client, git: "https://github.com/dsrosario/amqp_client.git", branch: "erlang_otp_19", override: true},
      {:riakc, ">= 2.4.1"}
    ]
  end

  defp package do
    [maintainers: ["Michael Shapiro"],
     licenses: ["MIT"],
     links: %{"GitHub": "https://github.com/koudelka/elixir-honeydew"}]
  end
end
