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

    {:ok, count} = Cairn.Audit.prune(retention_days)
    if count > 0, do: Logger.info("Pruned #{count} audit log entries")
    :ok
  end
end
