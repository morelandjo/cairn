defmodule Cairn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Cairn.Telemetry.setup()

    redis_url = Application.get_env(:cairn, :redis_url, "redis://localhost:6380")

    federation_config = Application.get_env(:cairn, :federation, [])

    federation_children =
      if Keyword.get(federation_config, :enabled, false) do
        node_key_opts =
          case Keyword.get(federation_config, :node_key_path) do
            nil -> []
            path -> [key_path: path]
          end

        [
          {Cairn.Federation.NodeIdentity, node_key_opts},
          {Cairn.Federation.HLC, [node_id: Keyword.get(federation_config, :domain, "local")]}
        ]
      else
        []
      end

    prom_ex_children =
      if Application.get_env(:cairn, :start_prom_ex, true) do
        [Cairn.PromEx]
      else
        []
      end

    children =
      [
        CairnWeb.Telemetry
      ] ++
        prom_ex_children ++
        [
          Cairn.Repo,
          {Oban, Application.fetch_env!(:cairn, Oban)},
          {Redix, {redis_url, [name: :cairn_redis]}},
          Cairn.Auth.PasswordValidator,
          Cairn.RateLimiter,
          CairnWeb.Plugs.RateLimiter,
          {DNSCluster, query: Application.get_env(:cairn, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Cairn.PubSub},
          CairnWeb.Presence,
          CairnWeb.Endpoint
        ] ++ federation_children

    opts = [strategy: :one_for_one, name: Cairn.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CairnWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
