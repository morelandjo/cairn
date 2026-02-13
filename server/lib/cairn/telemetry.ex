defmodule Cairn.Telemetry do
  @moduledoc """
  Custom telemetry handlers for Cairn.

  Attaches handlers for slow queries, request logging,
  and provides a foundation for Prometheus export in Phase 6.
  """

  require Logger

  @slow_query_threshold_ms 100

  def setup do
    :telemetry.attach(
      "cairn-slow-queries",
      [:cairn, :repo, :query],
      &__MODULE__.handle_slow_query/4,
      %{}
    )

    :telemetry.attach(
      "cairn-request-stop",
      [:phoenix, :endpoint, :stop],
      &__MODULE__.handle_request_stop/4,
      %{}
    )
  end

  def handle_slow_query(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.total_time, :native, :millisecond)

    if duration_ms > @slow_query_threshold_ms do
      Logger.warning("Slow query (#{duration_ms}ms): #{metadata.query}")
    end
  end

  def handle_request_stop(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "Request completed",
      method: metadata.conn.method,
      path: metadata.conn.request_path,
      status: metadata.conn.status,
      duration_ms: duration_ms
    )
  end
end
