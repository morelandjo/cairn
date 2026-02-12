defmodule MurmuringWeb.ChannelController do
  use MurmuringWeb, :controller

  alias Murmuring.Chat

  def index(conn, _params) do
    channels = Chat.list_channels()

    json(conn, %{channels: Enum.map(channels, &channel_json/1)})
  end

  def create(conn, params) do
    user_id = conn.assigns.current_user.id
    server_id = params["server_id"]

    # Check manage_channels permission if creating in a server
    with true <- has_channel_create_permission?(server_id, user_id),
         {:ok, channel} <- Chat.create_channel(params) do
      Chat.add_member(channel.id, user_id, "owner")

      conn
      |> put_status(:created)
      |> json(%{channel: channel_json(channel)})
    else
      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "insufficient permissions"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  defp has_channel_create_permission?(nil, _user_id), do: true

  defp has_channel_create_permission?(server_id, user_id) do
    Murmuring.Servers.Permissions.has_permission?(server_id, user_id, "manage_channels")
  end

  def show(conn, %{"id" => id}) do
    case Chat.get_channel(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "channel not found"})

      channel ->
        json(conn, %{channel: channel_json(channel)})
    end
  end

  def messages(conn, %{"id" => channel_id} = params) do
    user_id = conn.assigns.current_user.id

    channel = Chat.get_channel!(channel_id)

    if channel.type == "public" or Chat.is_member?(channel_id, user_id) do
      opts = [limit: min(String.to_integer(params["limit"] || "50"), 100)]

      opts =
        if params["before"] do
          case DateTime.from_iso8601(params["before"]) do
            {:ok, dt, _} -> Keyword.put(opts, :before, dt)
            _ -> opts
          end
        else
          opts
        end

      messages = Chat.list_messages(channel_id, opts)

      json(conn, %{
        messages:
          Enum.map(messages, fn m ->
            msg = %{
              id: m.id,
              content: m.content,
              encrypted_content:
                if(m.encrypted_content, do: Base.encode64(m.encrypted_content), else: nil),
              nonce: if(m.nonce, do: Base.encode64(m.nonce), else: nil),
              author_id: m.author_id,
              author_username: m.author_username,
              author_display_name: m.author_display_name,
              channel_id: m.channel_id,
              reply_to_id: m[:reply_to_id],
              reactions: m[:reactions] || [],
              edited_at: m.edited_at,
              deleted_at: m.deleted_at,
              inserted_at: m.inserted_at
            }

            if m[:reply_to_content] do
              Map.put(msg, :reply_to, %{
                content: m.reply_to_content,
                author_username: m[:reply_to_author_username]
              })
            else
              msg
            end
          end)
      })
    else
      conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  def members(conn, %{"id" => channel_id}) do
    members = Chat.list_members(channel_id)
    json(conn, %{members: members})
  end

  # PUT /api/v1/channels/:id/slow-mode
  def set_slow_mode(conn, %{"id" => channel_id, "seconds" => seconds}) do
    user_id = conn.assigns.current_user.id
    channel = Chat.get_channel!(channel_id)

    unless has_manage_channels_permission?(channel, user_id) do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Chat.update_channel(channel, %{slow_mode_seconds: seconds}) do
        {:ok, updated} ->
          json(conn, %{channel: %{id: updated.id, slow_mode_seconds: updated.slow_mode_seconds}})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  defp has_manage_channels_permission?(channel, user_id) do
    if channel.server_id do
      Murmuring.Servers.Permissions.has_channel_permission?(
        channel.server_id,
        user_id,
        channel.id,
        "manage_channels"
      )
    else
      true
    end
  end

  # GET /api/v1/channels/:id/messages/:message_id/thread
  def thread(conn, %{"id" => _channel_id, "message_id" => message_id}) do
    replies = Chat.get_thread(message_id)

    json(conn, %{
      replies:
        Enum.map(replies, fn m ->
          %{
            id: m.id,
            content: m.content,
            encrypted_content:
              if(m.encrypted_content, do: Base.encode64(m.encrypted_content), else: nil),
            nonce: if(m.nonce, do: Base.encode64(m.nonce), else: nil),
            author_id: m.author_id,
            author_username: m.author_username,
            author_display_name: m.author_display_name,
            channel_id: m.channel_id,
            reply_to_id: m.reply_to_id,
            edited_at: m.edited_at,
            deleted_at: m.deleted_at,
            inserted_at: m.inserted_at
          }
        end)
    })
  end

  # GET /api/v1/channels/:id/messages/:message_id/reactions
  def list_reactions(conn, %{"id" => _channel_id, "message_id" => message_id}) do
    reactions = Chat.list_reactions(message_id)
    json(conn, %{reactions: reactions})
  end

  # POST /api/v1/channels/:id/messages/:message_id/reactions
  def add_reaction(conn, %{"id" => _channel_id, "message_id" => message_id, "emoji" => emoji}) do
    user_id = conn.assigns.current_user.id

    case Chat.add_reaction(message_id, user_id, emoji) do
      {:ok, _} -> conn |> put_status(:created) |> json(%{ok: true})
      {:error, _} -> conn |> put_status(:conflict) |> json(%{error: "already reacted"})
    end
  end

  # DELETE /api/v1/channels/:id/messages/:message_id/reactions/:emoji
  def remove_reaction(conn, %{"id" => _channel_id, "message_id" => message_id, "emoji" => emoji}) do
    user_id = conn.assigns.current_user.id
    :ok = Chat.remove_reaction(message_id, user_id, emoji)
    json(conn, %{ok: true})
  end

  # GET /api/v1/channels/:id/pins
  def list_pins(conn, %{"id" => channel_id}) do
    pins = Chat.list_pins(channel_id)
    json(conn, %{pins: pins})
  end

  # POST /api/v1/channels/:id/pins
  def pin_message(conn, %{"id" => channel_id, "message_id" => message_id}) do
    user_id = conn.assigns.current_user.id
    channel = Chat.get_channel!(channel_id)

    unless has_manage_messages_permission?(channel, user_id) do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Chat.pin_message(channel_id, message_id, user_id) do
        {:ok, pin} ->
          conn |> put_status(:created) |> json(%{pin: %{id: pin.id, message_id: pin.message_id}})

        {:error, :max_pins_reached} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "maximum pins reached (50)"})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/channels/:id/pins/:message_id
  def unpin_message(conn, %{"id" => channel_id, "message_id" => message_id}) do
    user_id = conn.assigns.current_user.id
    channel = Chat.get_channel!(channel_id)

    unless has_manage_messages_permission?(channel, user_id) do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      :ok = Chat.unpin_message(channel_id, message_id)
      json(conn, %{ok: true})
    end
  end

  defp has_manage_messages_permission?(channel, user_id) do
    if channel.server_id do
      Murmuring.Servers.Permissions.has_channel_permission?(
        channel.server_id,
        user_id,
        channel.id,
        "manage_messages"
      )
    else
      true
    end
  end

  defp channel_json(c) do
    %{
      id: c.id,
      name: c.name,
      type: c.type,
      description: c.description,
      topic: c.topic,
      server_id: c.server_id,
      history_accessible: c.history_accessible
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
