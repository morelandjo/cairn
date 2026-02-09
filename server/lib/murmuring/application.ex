defmodule Murmuring.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Murmuring.Telemetry.setup()

    redis_url = Application.get_env(:murmuring, :redis_url, "redis://localhost:6380")

    children = [
      MurmuringWeb.Telemetry,
      Murmuring.Repo,
      {Redix, {redis_url, [name: :murmuring_redis]}},
      {DNSCluster, query: Application.get_env(:murmuring, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Murmuring.PubSub},
      MurmuringWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Murmuring.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MurmuringWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
