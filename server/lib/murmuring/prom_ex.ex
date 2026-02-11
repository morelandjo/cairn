defmodule Murmuring.PromEx do
  @moduledoc """
  PromEx configuration for Prometheus metrics.

  Exposes metrics at GET /metrics in Prometheus text format.
  Includes Phoenix, Ecto, BEAM, and Oban plugins.
  """

  use PromEx, otp_app: :murmuring

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: MurmuringWeb.Router, endpoint: MurmuringWeb.Endpoint},
      {PromEx.Plugins.Ecto, repos: [Murmuring.Repo]},
      {PromEx.Plugins.Oban, oban_supervisors: [Oban]},
      Murmuring.PromEx.MurmuringPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
