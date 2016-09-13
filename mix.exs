defmodule Honeydew.Mixfile do
  use Mix.Project

  def project do
    [app: :honeydew,
     version: "0.1.0",
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
      {:amqp, ">= 0.1.4", only: :dev},
      {:amqp_client, git: "https://github.com/dsrosario/amqp_client.git", branch: "erlang_otp_19", override: true, only: :dev},
      {:riakc, ">= 2.4.1", only: :dev},
      {:amnesia, ">= 0.2.5", only: :dev}
    ]
  end

  defp package do
    [maintainers: ["Michael Shapiro"],
     licenses: ["MIT"],
     links: %{"GitHub": "https://github.com/koudelka/elixir-honeydew"}]
  end
end
