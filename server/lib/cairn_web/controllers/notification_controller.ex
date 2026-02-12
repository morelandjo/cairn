defmodule MurmuringWeb.NotificationController do
  use MurmuringWeb, :controller

  alias Murmuring.Notifications

  # GET /api/v1/users/me/notification-preferences
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    prefs = Notifications.get_preferences(user_id)

    json(conn, %{
      preferences:
        Enum.map(prefs, fn p ->
          %{
            id: p.id,
            server_id: p.server_id,
            channel_id: p.channel_id,
            level: p.level,
            dnd_enabled: p.dnd_enabled,
            quiet_hours_start: p.quiet_hours_start,
            quiet_hours_end: p.quiet_hours_end
          }
        end)
    })
  end

  # PUT /api/v1/users/me/notification-preferences
  def update(conn, params) do
    user_id = conn.assigns.current_user.id

    case Notifications.upsert_preference(%{
           user_id: user_id,
           server_id: params["server_id"],
           channel_id: params["channel_id"],
           level: params["level"],
           dnd_enabled: params["dnd_enabled"],
           quiet_hours_start: parse_time(params["quiet_hours_start"]),
           quiet_hours_end: parse_time(params["quiet_hours_end"])
         }) do
      {:ok, pref} ->
        json(conn, %{
          preference: %{
            id: pref.id,
            server_id: pref.server_id,
            channel_id: pref.channel_id,
            level: pref.level,
            dnd_enabled: pref.dnd_enabled,
            quiet_hours_start: pref.quiet_hours_start,
            quiet_hours_end: pref.quiet_hours_end
          }
        })

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  defp parse_time(nil), do: nil

  defp parse_time(str) when is_binary(str) do
    case Time.from_iso8601(str) do
      {:ok, time} -> time
      _ -> nil
    end
  end

  defp parse_time(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
