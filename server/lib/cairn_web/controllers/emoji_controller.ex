defmodule CairnWeb.EmojiController do
  use CairnWeb, :controller

  alias Cairn.Chat
  alias Cairn.Servers.Permissions

  # GET /api/v1/servers/:server_id/emojis
  def index(conn, %{"server_id" => server_id}) do
    emojis = Chat.list_emojis(server_id)

    json(conn, %{
      emojis:
        Enum.map(emojis, fn e ->
          %{id: e.id, name: e.name, file_key: e.file_key, animated: e.animated}
        end)
    })
  end

  # POST /api/v1/servers/:server_id/emojis
  def create(conn, %{"server_id" => server_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Chat.create_emoji(%{
             name: params["name"],
             file_key: params["file_key"],
             animated: params["animated"] || false,
             server_id: server_id,
             uploader_id: user_id
           }) do
        {:ok, emoji} ->
          conn
          |> put_status(:created)
          |> json(%{
            emoji: %{
              id: emoji.id,
              name: emoji.name,
              file_key: emoji.file_key,
              animated: emoji.animated
            }
          })

        {:error, :max_emojis_reached} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "maximum emojis reached (50)"})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/emojis/:emoji_id
  def delete(conn, %{"server_id" => server_id, "emoji_id" => emoji_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      emoji = Chat.get_emoji!(emoji_id)
      {:ok, _} = Chat.delete_emoji(emoji)
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
