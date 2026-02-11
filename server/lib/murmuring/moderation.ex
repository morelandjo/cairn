defmodule Murmuring.Moderation do
  @moduledoc """
  The Moderation context — mutes, bans, kicks, and moderation log.
  """

  import Ecto.Query
  alias Murmuring.Repo
  alias Murmuring.Moderation.{ServerMute, ServerBan, ModLog, UnmuteWorker, UnbanWorker}
  alias Murmuring.Servers

  # Mutes

  def mute_user(attrs) do
    Repo.transaction(fn ->
      {:ok, mute} =
        %ServerMute{}
        |> ServerMute.changeset(attrs)
        |> Repo.insert()

      log_action(attrs.server_id, attrs.muted_by_id, "mute", %{
        target_user_id: attrs.user_id,
        reason: attrs[:reason],
        expires_at: attrs[:expires_at]
      })

      # Schedule auto-unmute if expires_at is set
      if mute.expires_at do
        delay = DateTime.diff(mute.expires_at, DateTime.utc_now(), :second)

        if delay > 0 do
          %{mute_id: mute.id}
          |> UnmuteWorker.new(schedule_in: delay)
          |> Oban.insert()
        end
      end

      mute
    end)
  end

  def unmute_user(server_id, user_id, moderator_id) do
    from(m in ServerMute,
      where: m.server_id == ^server_id and m.user_id == ^user_id
    )
    |> Repo.delete_all()

    log_action(server_id, moderator_id, "unmute", %{target_user_id: user_id})
    :ok
  end

  def is_muted?(server_id, user_id, channel_id \\ nil) do
    now = DateTime.utc_now()

    query =
      from(m in ServerMute,
        where: m.server_id == ^server_id and m.user_id == ^user_id,
        where: is_nil(m.expires_at) or m.expires_at > ^now
      )

    # Check for server-wide mute OR channel-specific mute
    query =
      if channel_id do
        from(m in query,
          where: is_nil(m.channel_id) or m.channel_id == ^channel_id
        )
      else
        from(m in query, where: is_nil(m.channel_id))
      end

    Repo.exists?(query)
  end

  def list_mutes(server_id) do
    from(m in ServerMute,
      where: m.server_id == ^server_id,
      join: u in assoc(m, :user),
      order_by: [desc: m.inserted_at],
      select: %{
        id: m.id,
        user_id: m.user_id,
        username: u.username,
        channel_id: m.channel_id,
        reason: m.reason,
        expires_at: m.expires_at,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
  end

  def get_mute(id), do: Repo.get(ServerMute, id)

  def delete_mute(%ServerMute{} = mute), do: Repo.delete(mute)

  # Bans

  def ban_user(attrs) do
    Repo.transaction(fn ->
      {:ok, ban} =
        %ServerBan{}
        |> ServerBan.changeset(attrs)
        |> Repo.insert()

      # Remove from server
      Servers.remove_member(attrs.server_id, attrs.user_id)

      log_action(attrs.server_id, attrs.banned_by_id, "ban", %{
        target_user_id: attrs.user_id,
        reason: attrs[:reason],
        expires_at: attrs[:expires_at]
      })

      # Schedule auto-unban if expires_at is set
      if ban.expires_at do
        delay = DateTime.diff(ban.expires_at, DateTime.utc_now(), :second)

        if delay > 0 do
          %{ban_id: ban.id}
          |> UnbanWorker.new(schedule_in: delay)
          |> Oban.insert()
        end
      end

      ban
    end)
  end

  def unban_user(server_id, user_id, moderator_id) do
    from(b in ServerBan,
      where: b.server_id == ^server_id and b.user_id == ^user_id
    )
    |> Repo.delete_all()

    log_action(server_id, moderator_id, "unban", %{target_user_id: user_id})
    :ok
  end

  def is_banned?(server_id, user_id) do
    now = DateTime.utc_now()

    from(b in ServerBan,
      where: b.server_id == ^server_id and b.user_id == ^user_id,
      where: is_nil(b.expires_at) or b.expires_at > ^now
    )
    |> Repo.exists?()
  end

  def list_bans(server_id) do
    from(b in ServerBan,
      where: b.server_id == ^server_id,
      join: u in assoc(b, :user),
      order_by: [desc: b.inserted_at],
      select: %{
        id: b.id,
        user_id: b.user_id,
        username: u.username,
        reason: b.reason,
        expires_at: b.expires_at,
        inserted_at: b.inserted_at
      }
    )
    |> Repo.all()
  end

  def get_ban(id), do: Repo.get(ServerBan, id)

  def delete_ban(%ServerBan{} = ban), do: Repo.delete(ban)

  # Kicks

  def kick_user(server_id, user_id, moderator_id) do
    Servers.remove_member(server_id, user_id)
    log_action(server_id, moderator_id, "kick", %{target_user_id: user_id})
    :ok
  end

  # Moderation log

  def log_action(server_id, moderator_id, action, details \\ %{}) do
    target_user_id = details[:target_user_id]
    target_message_id = details[:target_message_id]
    target_channel_id = details[:target_channel_id]

    %ModLog{}
    |> ModLog.changeset(%{
      server_id: server_id,
      moderator_id: moderator_id,
      action: action,
      details: details,
      target_user_id: target_user_id,
      target_message_id: target_message_id,
      target_channel_id: target_channel_id
    })
    |> Repo.insert()
  end

  def list_mod_log(server_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(l in ModLog,
      where: l.server_id == ^server_id,
      order_by: [desc: l.inserted_at],
      limit: ^limit,
      join: mod in assoc(l, :moderator),
      left_join: target in assoc(l, :target_user),
      select: %{
        id: l.id,
        action: l.action,
        details: l.details,
        moderator_id: l.moderator_id,
        moderator_username: mod.username,
        target_user_id: l.target_user_id,
        target_username: target.username,
        inserted_at: l.inserted_at
      }
    )
    |> Repo.all()
  end

  # Reports

  alias Murmuring.Moderation.MessageReport

  def create_report(attrs) do
    %MessageReport{}
    |> MessageReport.changeset(attrs)
    |> Repo.insert()
  end

  def list_reports(server_id, opts \\ []) do
    status = Keyword.get(opts, :status)

    query =
      from(r in MessageReport,
        where: r.server_id == ^server_id,
        order_by: [desc: r.inserted_at],
        join: reporter in assoc(r, :reporter),
        select: %{
          id: r.id,
          reason: r.reason,
          details: r.details,
          status: r.status,
          message_id: r.message_id,
          reporter_id: r.reporter_id,
          reporter_username: reporter.username,
          resolution_action: r.resolution_action,
          inserted_at: r.inserted_at
        }
      )

    query =
      if status do
        from(r in query, where: r.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  def resolve_report(report_id, resolved_by_id, resolution) do
    case Repo.get(MessageReport, report_id) do
      nil ->
        {:error, :not_found}

      report ->
        report
        |> MessageReport.changeset(%{
          status: resolution["status"] || "actioned",
          resolution_action: resolution["action"],
          resolved_by_id: resolved_by_id
        })
        |> Repo.update()
    end
  end

  # Auto-mod rules

  alias Murmuring.Moderation.AutoModRule

  def create_auto_mod_rule(attrs) do
    %AutoModRule{}
    |> AutoModRule.changeset(attrs)
    |> Repo.insert()
  end

  def list_auto_mod_rules(server_id) do
    from(r in AutoModRule, where: r.server_id == ^server_id)
    |> Repo.all()
  end

  def get_auto_mod_rule!(id), do: Repo.get!(AutoModRule, id)

  def update_auto_mod_rule(%AutoModRule{} = rule, attrs) do
    rule
    |> AutoModRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_auto_mod_rule(%AutoModRule{} = rule) do
    Repo.delete(rule)
  end
end
