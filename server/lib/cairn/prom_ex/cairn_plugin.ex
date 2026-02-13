defmodule Cairn.PromEx.CairnPlugin do
  @moduledoc """
  Custom PromEx plugin for Cairn-specific metrics:
  - WebSocket connections
  - Federation activity counts
  - Voice channel participants
  """

  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    Polling.build(
      :cairn_custom_metrics,
      poll_rate,
      {__MODULE__, :execute_metrics, []},
      [
        last_value("cairn.websocket.connections.total",
          description: "Total WebSocket connections"
        ),
        last_value("cairn.federation.nodes.active",
          description: "Number of active federation nodes"
        )
      ]
    )
  end

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :cairn_event_metrics,
      [
        counter("cairn.messages.sent.total",
          event_name: [:cairn, :message, :sent],
          description: "Total messages sent"
        ),
        counter("cairn.federation.activities.total",
          event_name: [:cairn, :federation, :activity],
          description: "Total federation activities",
          tags: [:direction, :type]
        ),
        counter("cairn.auth.login.total",
          event_name: [:cairn, :auth, :login],
          description: "Total login attempts",
          tags: [:result]
        ),
        counter("cairn.voice.joins.total",
          event_name: [:cairn, :voice, :join],
          description: "Total voice channel joins"
        )
      ]
    )
  end

  def execute_metrics do
    # WebSocket connections (count from Phoenix presence)
    ws_count =
      try do
        CairnWeb.Presence.list("presence:global") |> map_size()
      rescue
        _ -> 0
      end

    :telemetry.execute([:cairn, :websocket, :connections], %{total: ws_count})

    # Active federation nodes
    fed_count =
      try do
        Cairn.Federation.list_nodes_by_status("active") |> length()
      rescue
        _ -> 0
      end

    :telemetry.execute([:cairn, :federation, :nodes], %{active: fed_count})
  end
end
