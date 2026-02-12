defmodule Cairn.Audit.Pruner do
  @moduledoc """
  Oban worker that prunes old audit log entries.
  Runs daily by default.
  """

  use Oban.Worker, queue: :moderation, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    retention_days = Application.get_env(:cairn, :audit_retention_days, 90)

    case Cairn.Audit.prune(retention_days) do
      {:ok, count} ->
        if count > 0, do: Logger.info("Pruned #{count} audit log entries")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
