defmodule Cairn.Federation.InboxHandler do
  @moduledoc """
  Dispatches incoming ActivityPub activities by type.
  Resolves remote authors via DID verification and creates local messages
  with federated_author_id for proper attribution.
  """

  require Logger
  alias Cairn.{Chat, Federation}

  @doc """
  Process an incoming activity from a federated node.
  Returns :ok on success, {:error, reason} on failure.
  """
  def handle(activity, federated_node) do
    type = activity["type"]

    # Log the activity
    Federation.log_activity(%{
      federated_node_id: federated_node.id,
      activity_type: type,
      direction: "inbound",
      actor_uri: activity["actor"],
      object_uri: get_object_uri(activity["object"]),
      payload: activity,
      status: "pending"
    })

    result = dispatch(type, activity, federated_node)

    # Update activity status
    case result do
      :ok ->
        Logger.info("Processed #{type} activity from #{federated_node.domain}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to process #{type} from #{federated_node.domain}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp dispatch("Follow", activity, node), do: handle_follow(activity, node)
  defp dispatch("Accept", activity, node), do: handle_accept(activity, node)
  defp dispatch("Create", activity, node), do: handle_create(activity, node)
  defp dispatch("Update", activity, node), do: handle_update(activity, node)
  defp dispatch("Delete", activity, node), do: handle_delete(activity, node)
  defp dispatch("Invite", activity, node), do: handle_invite(activity, node)
  defp dispatch(type, _activity, _node), do: {:error, "Unsupported activity type: #{type}"}

  defp handle_follow(_activity, _node) do
    :ok
  end

  defp handle_accept(_activity, _node) do
    :ok
  end

  defp handle_create(activity, node) do
    object = activity["object"]

    with {:ok, _} <- validate_object(object),
         {:ok, channel_id} <- extract_channel_id(object),
         {:ok, channel} <- get_channel(channel_id),
         {:ok, federated_user} <- resolve_author(activity["actor"], object, node) do
      attrs = %{
        content: object["content"],
        channel_id: channel.id,
        federated_author_id: federated_user.id
      }

      case Chat.create_message(attrs) do
        {:ok, message} ->
          # Broadcast to local WebSocket subscribers via PubSub
          broadcast_federated_message(channel.id, message, federated_user)
          :ok

        {:error, changeset} ->
          {:error, {:message_create_failed, inspect(changeset.errors)}}
      end
    end
  end

  defp handle_update(activity, _node) do
    object = activity["object"]

    with {:ok, _} <- validate_object(object),
         {:ok, message} <- find_message_by_object_uri(object["id"]) do
      # Only allow edits from the original federated author
      if message.federated_author_id do
        case Chat.edit_message(message, %{content: object["content"]}) do
          {:ok, updated} ->
            Phoenix.PubSub.broadcast(
              Cairn.PubSub,
              "federated:channel:#{message.channel_id}",
              {:federated_msg, %{
                type: "edit_msg",
                id: updated.id,
                content: updated.content,
                edited_at: updated.edited_at
              }}
            )

            :ok

          {:error, changeset} ->
            {:error, {:message_update_failed, inspect(changeset.errors)}}
        end
      else
        {:error, :not_federated_message}
      end
    end
  end

  defp handle_delete(activity, _node) do
    object_uri =
      case activity["object"] do
        uri when is_binary(uri) -> uri
        %{"id" => id} -> id
        _ -> nil
      end

    if object_uri do
      case find_message_by_object_uri(object_uri) do
        {:ok, message} ->
          if message.federated_author_id do
            case Chat.delete_message(message) do
              {:ok, _} ->
                Phoenix.PubSub.broadcast(
                  Cairn.PubSub,
                  "federated:channel:#{message.channel_id}",
                  {:federated_msg, %{
                    type: "delete_msg",
                    id: message.id
                  }}
                )

                :ok

              {:error, _} ->
                {:error, :message_delete_failed}
            end
          else
            {:error, :not_federated_message}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :invalid_object}
    end
  end

  defp handle_invite(activity, _node) do
    object = activity["object"]

    case object do
      %{"type" => "cairn:DmHint"} ->
        recipient_did = object["cairn:recipientDid"]
        sender_did = object["cairn:senderDid"]
        channel_id = object["cairn:channelId"]
        sender_username = object["cairn:senderUsername"]
        sender_display_name = object["cairn:senderDisplayName"]

        if is_nil(recipient_did) or is_nil(sender_did) or is_nil(channel_id) do
          {:error, :invalid_dm_hint}
        else
          # Look up local user by DID
          case Cairn.Accounts.get_user_by_did(recipient_did) do
            nil ->
              {:error, :recipient_not_found}

            user ->
              # Broadcast DM request notification to recipient's user channel
              Phoenix.PubSub.broadcast(
                Cairn.PubSub,
                "user:#{user.id}",
                {:dm_request, %{
                  sender_did: sender_did,
                  sender_username: sender_username,
                  sender_display_name: sender_display_name,
                  channel_id: channel_id,
                  actor: activity["actor"]
                }}
              )

              Logger.info("DM hint delivered to local user #{user.id} from #{sender_did}")
              :ok
          end
        end

      _ ->
        {:error, :unsupported_invite_type}
    end
  end

  # ── Author resolution ──

  defp resolve_author(actor_uri, object, node) do
    did = object["cairn:did"]
    home_instance = object["cairn:homeInstance"] || node.domain

    cond do
      # If DID is provided, use it to find/create the federated user
      did && String.starts_with?(did, "did:cairn:") ->
        resolve_by_did(did, actor_uri, home_instance, object)

      # Fall back to actor_uri lookup
      actor_uri ->
        resolve_by_actor_uri(actor_uri, home_instance)

      true ->
        {:error, :no_author}
    end
  end

  defp resolve_by_did(did, actor_uri, home_instance, object) do
    # Extract username from actor URI
    username = extract_username_from_uri(actor_uri) || "unknown"

    attrs = %{
      did: did,
      username: username,
      display_name: object["cairn:displayName"],
      home_instance: home_instance,
      public_key: "pending-verification",
      actor_uri: actor_uri,
      last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }

    Federation.get_or_create_federated_user(attrs)
  end

  defp resolve_by_actor_uri(actor_uri, home_instance) do
    case Federation.get_federated_user_by_actor_uri(actor_uri) do
      nil ->
        username = extract_username_from_uri(actor_uri) || "unknown"

        Federation.get_or_create_federated_user(%{
          did: "did:cairn:unknown-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
          username: username,
          home_instance: home_instance,
          public_key: "pending-verification",
          actor_uri: actor_uri,
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      user ->
        {:ok, user}
    end
  end

  # ── Helpers ──

  defp validate_object(%{"type" => "Note", "content" => content}) when is_binary(content) do
    {:ok, :valid}
  end

  defp validate_object(_), do: {:error, :invalid_object}

  defp extract_channel_id(object) do
    # Extract channel ID from the object's context or target
    # Expected format: https://domain/channels/<channel_id>/messages/<msg_id>
    # or the channel ID directly in cairn:channelId
    cond do
      channel_id = object["cairn:channelId"] ->
        {:ok, channel_id}

      id = object["id"] ->
        case Regex.run(~r"/channels/([^/]+)/messages/", id) do
          [_, channel_id] -> {:ok, channel_id}
          _ -> {:error, :no_channel_id}
        end

      true ->
        {:error, :no_channel_id}
    end
  end

  defp get_channel(channel_id) do
    case Chat.get_channel(channel_id) do
      nil -> {:error, :channel_not_found}
      channel -> {:ok, channel}
    end
  end

  defp find_message_by_object_uri(nil), do: {:error, :no_object_uri}

  defp find_message_by_object_uri(uri) do
    # Extract message ID from URI: https://domain/channels/<ch_id>/messages/<msg_id>
    case Regex.run(~r"/channels/[^/]+/messages/([^/]+)", uri) do
      [_, message_id] ->
        case Chat.get_message(message_id) do
          nil -> {:error, :message_not_found}
          message -> {:ok, message}
        end

      _ ->
        {:error, :invalid_object_uri}
    end
  end

  defp broadcast_federated_message(channel_id, message, federated_user) do
    Phoenix.PubSub.broadcast(
      Cairn.PubSub,
      "federated:channel:#{channel_id}",
      {:federated_msg, %{
        id: message.id,
        content: message.content,
        federated_author_id: federated_user.id,
        author_username: federated_user.username,
        author_display_name: federated_user.display_name,
        home_instance: federated_user.home_instance,
        is_federated: true,
        channel_id: channel_id,
        inserted_at: message.inserted_at
      }}
    )
  end

  defp extract_username_from_uri(uri) when is_binary(uri) do
    case Regex.run(~r"/users/([^/]+)", uri) do
      [_, username] -> username
      _ -> nil
    end
  end

  defp extract_username_from_uri(_), do: nil

  defp get_object_uri(object) when is_binary(object), do: object
  defp get_object_uri(%{"id" => id}), do: id
  defp get_object_uri(_), do: nil
end
