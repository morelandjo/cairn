defmodule Murmuring.PromEx.MurmuringPlugin do
  @moduledoc """
  Custom PromEx plugin for Murmuring-specific metrics:
  - WebSocket connections
  - Federation activity counts
  - Voice channel participants
  """

  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    Polling.build(
      :murmuring_custom_metrics,
      poll_rate,
      {__MODULE__, :execute_metrics, []},
      [
        last_value("murmuring.websocket.connections.total",
          description: "Total WebSocket connections"
        ),
        last_value("murmuring.federation.nodes.active",
          description: "Number of active federation nodes"
        )
      ]
    )
  end

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :murmuring_event_metrics,
      [
        counter("murmuring.messages.sent.total",
          event_name: [:murmuring, :message, :sent],
          description: "Total messages sent"
        ),
        counter("murmuring.federation.activities.total",
          event_name: [:murmuring, :federation, :activity],
          description: "Total federation activities",
          tags: [:direction, :type]
        ),
        counter("murmuring.auth.login.total",
          event_name: [:murmuring, :auth, :login],
          description: "Total login attempts",
          tags: [:result]
        ),
        counter("murmuring.voice.joins.total",
          event_name: [:murmuring, :voice, :join],
          description: "Total voice channel joins"
        )
      ]
    )
  end

  def execute_metrics do
    # WebSocket connections (count from Phoenix presence)
    ws_count =
      try do
        MurmuringWeb.Presence.list("presence:global") |> map_size()
      rescue
        _ -> 0
      end

    :telemetry.execute([:murmuring, :websocket, :connections], %{total: ws_count})

    # Active federation nodes
    fed_count =
      try do
        Murmuring.Federation.list_nodes_by_status("active") |> length()
      rescue
        _ -> 0
      end

    :telemetry.execute([:murmuring, :federation, :nodes], %{active: fed_count})
  end
end
