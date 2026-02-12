defmodule CairnWeb.ModerationController do
  use CairnWeb, :controller

  alias Cairn.Moderation
  alias Cairn.Servers.Permissions

  # POST /api/v1/servers/:server_id/mutes
  def mute(conn, %{"server_id" => server_id, "user_id" => target_user_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "mute_members") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      expires_at =
        case params["duration_seconds"] do
          nil ->
            nil

          secs when is_integer(secs) ->
            DateTime.add(DateTime.utc_now(), secs, :second)

          secs when is_binary(secs) ->
            DateTime.add(DateTime.utc_now(), String.to_integer(secs), :second)
        end

      case Moderation.mute_user(%{
             server_id: server_id,
             user_id: target_user_id,
             muted_by_id: user_id,
             reason: params["reason"],
             channel_id: params["channel_id"],
             expires_at: expires_at
           }) do
        {:ok, mute} ->
          conn
          |> put_status(:created)
          |> json(%{mute: %{id: mute.id, user_id: mute.user_id, expires_at: mute.expires_at}})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/mutes/:user_id
  def unmute(conn, %{"server_id" => server_id, "user_id" => target_user_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "mute_members") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      :ok = Moderation.unmute_user(server_id, target_user_id, user_id)
      json(conn, %{ok: true})
    end
  end

  # GET /api/v1/servers/:server_id/mutes
  def list_mutes(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "mute_members") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      mutes = Moderation.list_mutes(server_id)
      json(conn, %{mutes: mutes})
    end
  end

  # POST /api/v1/servers/:server_id/kicks/:user_id
  def kick(conn, %{"server_id" => server_id, "user_id" => target_user_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "kick_members") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      :ok = Moderation.kick_user(server_id, target_user_id, user_id)
      json(conn, %{ok: true})
    end
  end

  # POST /api/v1/servers/:server_id/bans
  def ban(conn, %{"server_id" => server_id, "user_id" => target_user_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "ban_members") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      expires_at =
        case params["duration_seconds"] do
          nil ->
            nil

          secs when is_integer(secs) ->
            DateTime.add(DateTime.utc_now(), secs, :second)

          secs when is_binary(secs) ->
            DateTime.add(DateTime.utc_now(), String.to_integer(secs), :second)
        end

      case Moderation.ban_user(%{
             server_id: server_id,
             user_id: target_user_id,
             banned_by_id: user_id,
             reason: params["reason"],
             expires_at: expires_at
           }) do
        {:ok, ban} ->
          conn
          |> put_status(:created)
          |> json(%{ban: %{id: ban.id, user_id: ban.user_id, expires_at: ban.expires_at}})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/bans/:user_id
  def unban(conn, %{"server_id" => server_id, "user_id" => target_user_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "ban_members") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      :ok = Moderation.unban_user(server_id, target_user_id, user_id)
      json(conn, %{ok: true})
    end
  end

  # GET /api/v1/servers/:server_id/bans
  def list_bans(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "ban_members") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      bans = Moderation.list_bans(server_id)
      json(conn, %{bans: bans})
    end
  end

  # GET /api/v1/servers/:server_id/moderation-log
  def mod_log(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      log = Moderation.list_mod_log(server_id)
      json(conn, %{log: log})
    end
  end

  # POST /api/v1/messages/:message_id/report
  def report_message(conn, %{"message_id" => message_id} = params) do
    user_id = conn.assigns.current_user.id

    message = Cairn.Chat.get_message!(message_id)
    channel = Cairn.Chat.get_channel!(message.channel_id)

    case Moderation.create_report(%{
           message_id: message_id,
           reporter_id: user_id,
           server_id: channel.server_id,
           reason: params["reason"] || "no reason given",
           details: params["details"]
         }) do
      {:ok, report} ->
        conn |> put_status(:created) |> json(%{report: %{id: report.id, status: report.status}})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  # GET /api/v1/servers/:server_id/reports
  def list_reports(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_messages") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      reports = Moderation.list_reports(server_id)
      json(conn, %{reports: reports})
    end
  end

  # PUT /api/v1/servers/:server_id/reports/:report_id
  def resolve_report(conn, %{"server_id" => server_id, "report_id" => report_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_messages") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Moderation.resolve_report(report_id, user_id, params) do
        {:ok, report} ->
          json(conn, %{
            report: %{
              id: report.id,
              status: report.status,
              resolution_action: report.resolution_action
            }
          })

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "report not found"})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # GET /api/v1/servers/:server_id/auto-mod-rules
  def list_auto_mod_rules(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      rules = Moderation.list_auto_mod_rules(server_id)

      json(conn, %{
        rules:
          Enum.map(rules, fn r ->
            %{id: r.id, rule_type: r.rule_type, enabled: r.enabled, config: r.config}
          end)
      })
    end
  end

  # POST /api/v1/servers/:server_id/auto-mod-rules
  def create_auto_mod_rule(conn, %{"server_id" => server_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Moderation.create_auto_mod_rule(Map.put(params, "server_id", server_id)) do
        {:ok, rule} ->
          conn
          |> put_status(:created)
          |> json(%{
            rule: %{
              id: rule.id,
              rule_type: rule.rule_type,
              enabled: rule.enabled,
              config: rule.config
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # PUT /api/v1/servers/:server_id/auto-mod-rules/:rule_id
  def update_auto_mod_rule(conn, %{"server_id" => server_id, "rule_id" => rule_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      rule = Moderation.get_auto_mod_rule!(rule_id)

      case Moderation.update_auto_mod_rule(rule, params) do
        {:ok, updated} ->
          json(conn, %{
            rule: %{
              id: updated.id,
              rule_type: updated.rule_type,
              enabled: updated.enabled,
              config: updated.config
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/auto-mod-rules/:rule_id
  def delete_auto_mod_rule(conn, %{"server_id" => server_id, "rule_id" => rule_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      rule = Moderation.get_auto_mod_rule!(rule_id)
      {:ok, _} = Moderation.delete_auto_mod_rule(rule)
      json(conn, %{ok: true})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
