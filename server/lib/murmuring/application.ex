defmodule Murmuring.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Murmuring.Telemetry.setup()

    redis_url = Application.get_env(:murmuring, :redis_url, "redis://localhost:6380")

    federation_config = Application.get_env(:murmuring, :federation, [])

    federation_children =
      if Keyword.get(federation_config, :enabled, false) do
        node_key_opts =
          case Keyword.get(federation_config, :node_key_path) do
            nil -> []
            path -> [key_path: path]
          end

        [
          {Murmuring.Federation.NodeIdentity, node_key_opts},
          {Murmuring.Federation.HLC, [node_id: Keyword.get(federation_config, :domain, "local")]}
        ]
      else
        []
      end

    prom_ex_children =
      if Application.get_env(:murmuring, :start_prom_ex, true) do
        [Murmuring.PromEx]
      else
        []
      end

    children =
      [
        MurmuringWeb.Telemetry
      ] ++
        prom_ex_children ++
        [
        Murmuring.Repo,
        {Oban, Application.fetch_env!(:murmuring, Oban)},
        {Redix, {redis_url, [name: :murmuring_redis]}},
        Murmuring.Auth.PasswordValidator,
        Murmuring.RateLimiter,
        MurmuringWeb.Plugs.RateLimiter,
        {DNSCluster, query: Application.get_env(:murmuring, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Murmuring.PubSub},
        MurmuringWeb.Presence,
        MurmuringWeb.Endpoint
      ] ++ federation_children

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
