defmodule MurmuringWeb.ChannelChannel do
  use MurmuringWeb, :channel

  alias Murmuring.Chat
  alias Murmuring.Chat.Mls
  alias Murmuring.Chat.Sanitizer
  alias Murmuring.{Bots, Moderation, RateLimiter}
  alias Murmuring.Moderation.AutoMod
  alias Murmuring.Servers.Permissions
  alias MurmuringWeb.Presence

  @impl true
  def join("channel:" <> channel_id, _params, socket) do
    is_federated = socket.assigns[:is_federated] || false

    case Chat.get_channel(channel_id) do
      nil ->
        {:error, %{reason: "channel not found"}}

      channel ->
        authorized =
          if is_federated do
            federated_user_id = socket.assigns.federated_user_id
            server_id = channel.server_id

            cond do
              # Federated users can join DM channels where they are a member
              channel.type == "dm" ->
                Chat.is_federated_channel_member?(channel_id, federated_user_id)

              # Federated users can join server channels via server membership
              server_id != nil ->
                Murmuring.Servers.is_federated_member?(server_id, federated_user_id)

              true ->
                false
            end
          else
            user_id = socket.assigns.user_id

            if channel.type == "public" or Chat.is_member?(channel_id, user_id) do
              # Auto-add to public channels
              if channel.type == "public" and not Chat.is_member?(channel_id, user_id) do
                Chat.add_member(channel_id, user_id)
              end

              true
            else
              false
            end
          end

        if authorized do
          # Subscribe to federated message broadcasts (separate topic from Phoenix channel)
          Phoenix.PubSub.subscribe(Murmuring.PubSub, "federated:channel:#{channel_id}")
          send(self(), :after_join)

          {:ok,
           assign(socket,
             channel_id: channel_id,
             channel_type: channel.type,
             server_id: channel.server_id
           )}
        else
          {:error, %{reason: "unauthorized"}}
        end
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    is_federated = socket.assigns[:is_federated] || false

    if is_federated do
      fu = socket.assigns.federated_user

      Presence.track(socket, fu.id, %{
        username: fu.username,
        display_name: fu.display_name,
        home_instance: fu.home_instance,
        is_federated: true,
        online_at: System.system_time(:second)
      })
    else
      user_id = socket.assigns.user_id
      user = Murmuring.Accounts.get_user!(user_id)

      Presence.track(socket, user_id, %{
        username: user.username,
        display_name: user.display_name,
        online_at: System.system_time(:second)
      })
    end

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Handle federated message broadcasts from PubSub
  def handle_info({:federated_msg, payload}, socket) do
    push(socket, "new_msg", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_msg", %{"content" => content} = payload, socket) do
    user_id = socket.assigns.user_id
    channel_id = socket.assigns.channel_id

    cond do
      not check_server_permission(socket, "send_messages") ->
        {:reply, {:error, %{reason: "insufficient permissions"}}, socket}

      check_bot_channel_restricted?(socket) ->
        {:reply, {:error, %{reason: "bot_channel_restricted"}}, socket}

      check_muted?(socket) ->
        {:reply, {:error, %{reason: "muted"}}, socket}

      check_slow_mode?(socket) ->
        {:reply, {:error, %{reason: "slow_mode"}}, socket}

      true ->
        case RateLimiter.check(:message, user_id) do
          :ok ->
            sanitized_content = Sanitizer.sanitize(content)

            # Auto-mod check
            server_id = socket.assigns[:server_id]

            case maybe_auto_mod(server_id, sanitized_content) do
              {:violation, _action, rule_type} ->
                {:reply, {:error, %{reason: "auto_mod", rule: rule_type}}, socket}

              :ok ->
                attrs = %{
                  content: sanitized_content,
                  channel_id: channel_id,
                  author_id: user_id,
                  reply_to_id: payload["reply_to_id"]
                }

                attrs =
                  if payload["encrypted_content"] do
                    nonce = payload["nonce"]

                    Map.merge(attrs, %{
                      encrypted_content: Base.decode64!(payload["encrypted_content"]),
                      nonce: if(nonce && nonce != "", do: Base.decode64!(nonce), else: nil),
                      content: nil,
                      mls_epoch: payload["mls_epoch"]
                    })
                  else
                    attrs
                  end

                case Chat.create_message(attrs) do
                  {:ok, message} ->
                    user = Murmuring.Accounts.get_user!(user_id)

                    broadcast!(socket, "new_msg", %{
                      id: message.id,
                      content: message.content,
                      encrypted_content:
                        if(message.encrypted_content,
                          do: Base.encode64(message.encrypted_content),
                          else: nil
                        ),
                      nonce: if(message.nonce, do: Base.encode64(message.nonce), else: nil),
                      author_id: user_id,
                      author_username: user.username,
                      author_display_name: user.display_name,
                      is_bot: user.is_bot || false,
                      channel_id: channel_id,
                      reply_to_id: message.reply_to_id,
                      inserted_at: message.inserted_at
                    })

                    {:reply, :ok, socket}

                  {:error, changeset} ->
                    {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
                end
            end

          {:error, :rate_limited} ->
            {:reply, {:error, %{reason: "rate_limited"}}, socket}
        end
    end
  end

  def handle_in("edit_msg", %{"id" => message_id, "content" => content}, socket) do
    user_id = socket.assigns.user_id

    case Chat.get_message(message_id) do
      nil ->
        {:reply, {:error, %{reason: "not found"}}, socket}

      message when message.author_id != user_id ->
        {:reply, {:error, %{reason: "unauthorized"}}, socket}

      message ->
        sanitized = Sanitizer.sanitize(content)

        case Chat.edit_message(message, %{content: sanitized}) do
          {:ok, updated} ->
            broadcast!(socket, "edit_msg", %{
              id: updated.id,
              content: updated.content,
              edited_at: updated.edited_at
            })

            {:reply, :ok, socket}

          {:error, changeset} ->
            {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
        end
    end
  end

  def handle_in("delete_msg", %{"id" => message_id}, socket) do
    user_id = socket.assigns.user_id

    case Chat.get_message(message_id) do
      nil ->
        {:reply, {:error, %{reason: "not found"}}, socket}

      message when message.author_id != user_id ->
        # Allow if user has manage_messages permission
        if check_server_permission(socket, "manage_messages") do
          case Chat.delete_message(message) do
            {:ok, _} ->
              broadcast!(socket, "delete_msg", %{id: message_id})
              {:reply, :ok, socket}

            {:error, _} ->
              {:reply, {:error, %{reason: "delete failed"}}, socket}
          end
        else
          {:reply, {:error, %{reason: "unauthorized"}}, socket}
        end

      message ->
        case Chat.delete_message(message) do
          {:ok, _} ->
            broadcast!(socket, "delete_msg", %{id: message_id})
            {:reply, :ok, socket}

          {:error, _} ->
            {:reply, {:error, %{reason: "delete failed"}}, socket}
        end
    end
  end

  def handle_in("typing", _payload, socket) do
    user_id = socket.assigns.user_id

    case RateLimiter.check(:typing, user_id) do
      :ok ->
        user = Murmuring.Accounts.get_user!(user_id)

        broadcast_from!(socket, "typing", %{
          user_id: user_id,
          username: user.username
        })

        {:noreply, socket}

      {:error, :rate_limited} ->
        {:noreply, socket}
    end
  end

  # ==================== Reactions ====================

  def handle_in("add_reaction", %{"message_id" => message_id, "emoji" => emoji}, socket) do
    user_id = socket.assigns.user_id

    case Chat.add_reaction(message_id, user_id, emoji) do
      {:ok, _reaction} ->
        broadcast!(socket, "reaction_added", %{
          message_id: message_id,
          emoji: emoji,
          user_id: user_id
        })

        {:reply, :ok, socket}

      {:error, _} ->
        {:reply, {:error, %{reason: "already reacted"}}, socket}
    end
  end

  def handle_in("remove_reaction", %{"message_id" => message_id, "emoji" => emoji}, socket) do
    user_id = socket.assigns.user_id

    :ok = Chat.remove_reaction(message_id, user_id, emoji)

    broadcast!(socket, "reaction_removed", %{
      message_id: message_id,
      emoji: emoji,
      user_id: user_id
    })

    {:reply, :ok, socket}
  end

  # ==================== MLS Protocol Events ====================

  def handle_in("mls_commit", %{"data" => data} = payload, socket) do
    user_id = socket.assigns.user_id
    channel_id = socket.assigns.channel_id

    case Mls.store_commit(channel_id, user_id, Base.decode64!(data), payload["epoch"]) do
      {:ok, msg} ->
        broadcast_from!(socket, "mls_commit", %{
          channel_id: channel_id,
          data: data,
          epoch: msg.epoch,
          sender_id: user_id
        })

        {:reply, :ok, socket}

      {:error, _} ->
        {:reply, {:error, %{reason: "failed to store commit"}}, socket}
    end
  end

  def handle_in(
        "mls_welcome",
        %{"data" => data, "recipient_id" => recipient_id} = _payload,
        socket
      ) do
    user_id = socket.assigns.user_id
    channel_id = socket.assigns.channel_id

    case Mls.store_welcome(channel_id, user_id, recipient_id, Base.decode64!(data)) do
      {:ok, _msg} ->
        # Welcome is targeted — broadcast to all but the recipient picks it up
        broadcast_from!(socket, "mls_welcome", %{
          channel_id: channel_id,
          data: data,
          recipient_id: recipient_id,
          sender_id: user_id
        })

        {:reply, :ok, socket}

      {:error, _} ->
        {:reply, {:error, %{reason: "failed to store welcome"}}, socket}
    end
  end

  def handle_in("mls_proposal", %{"data" => data} = payload, socket) do
    user_id = socket.assigns.user_id
    channel_id = socket.assigns.channel_id

    case Mls.store_proposal(channel_id, user_id, Base.decode64!(data), payload["epoch"]) do
      {:ok, msg} ->
        broadcast_from!(socket, "mls_proposal", %{
          channel_id: channel_id,
          data: data,
          epoch: msg.epoch,
          sender_id: user_id
        })

        {:reply, :ok, socket}

      {:error, _} ->
        {:reply, {:error, %{reason: "failed to store proposal"}}, socket}
    end
  end

  defp check_slow_mode?(socket) do
    server_id = socket.assigns[:server_id]
    channel_id = socket.assigns[:channel_id]
    user_id = socket.assigns.user_id

    if server_id do
      channel = Chat.get_channel(channel_id)

      cond do
        is_nil(channel) ->
          false

        channel.slow_mode_seconds == 0 ->
          false

        # Moderators exempt from slow mode
        Permissions.has_channel_permission?(server_id, user_id, channel_id, "manage_channels") ->
          false

        true ->
          case RateLimiter.check({:slow_mode, channel_id}, user_id) do
            :ok -> false
            {:error, :rate_limited} -> true
          end
      end
    else
      false
    end
  end

  defp check_bot_channel_restricted?(socket) do
    user_id = socket.assigns.user_id
    channel_id = socket.assigns.channel_id
    server_id = socket.assigns[:server_id]

    if server_id do
      user = Murmuring.Accounts.get_user!(user_id)

      if user.is_bot do
        case Bots.get_bot_for_user(user_id, server_id) do
          nil ->
            false

          bot ->
            bot.allowed_channels != [] and
              channel_id not in Enum.map(bot.allowed_channels, &to_string/1)
        end
      else
        false
      end
    else
      false
    end
  end

  defp maybe_auto_mod(nil, _content), do: :ok
  defp maybe_auto_mod(server_id, content), do: AutoMod.check_message(server_id, content)

  defp check_muted?(socket) do
    server_id = socket.assigns[:server_id]
    channel_id = socket.assigns[:channel_id]

    if server_id do
      Moderation.is_muted?(server_id, socket.assigns.user_id, channel_id)
    else
      false
    end
  end

  defp check_server_permission(socket, permission) do
    server_id = socket.assigns[:server_id]
    channel_id = socket.assigns[:channel_id]

    if server_id do
      Permissions.has_channel_permission?(
        server_id,
        socket.assigns.user_id,
        channel_id,
        permission
      )
    else
      # DM channels (no server) — always allow
      true
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
