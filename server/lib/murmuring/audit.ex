defmodule Murmuring.Audit do
  @moduledoc """
  Audit logging context.
  Records security-relevant events with configurable IP logging and auto-pruning.
  """

  import Ecto.Query
  alias Murmuring.Repo
  alias Murmuring.Audit.AuditLog

  @retention_days 90

  @doc """
  Log an audit event.

  ## Options
    * `:actor_id` — UUID of the user who performed the action
    * `:target_id` — UUID or identifier of the affected resource
    * `:target_type` — type of target (e.g., "user", "server", "node")
    * `:metadata` — additional context (map)
    * `:ip_address` — client IP (only stored if IP logging is enabled)
  """
  def log(event_type, opts \\ []) do
    ip =
      if Application.get_env(:murmuring, :audit_log_ip, false) do
        Keyword.get(opts, :ip_address)
      else
        nil
      end

    attrs = %{
      event_type: to_string(event_type),
      actor_id: Keyword.get(opts, :actor_id),
      target_id: Keyword.get(opts, :target_id) |> maybe_to_string(),
      target_type: Keyword.get(opts, :target_type),
      metadata: Keyword.get(opts, :metadata, %{}),
      ip_address: ip
    }

    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc "List audit logs with optional filters."
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    event_type = Keyword.get(opts, :event_type)
    actor_id = Keyword.get(opts, :actor_id)

    query =
      from(a in AuditLog,
        order_by: [desc: a.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if event_type do
        from a in query, where: a.event_type == ^event_type
      else
        query
      end

    query =
      if actor_id do
        from a in query, where: a.actor_id == ^actor_id
      else
        query
      end

    Repo.all(query)
  end

  @doc "Prune audit logs older than the retention period."
  def prune(retention_days \\ @retention_days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_days * 86_400, :second)

    {count, _} =
      from(a in AuditLog, where: a.inserted_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(val), do: to_string(val)
end
