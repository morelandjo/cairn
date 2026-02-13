defmodule Cairn.Federation.ActivityPub do
  @moduledoc """
  ActivityPub serializers for converting internal entities to AP JSON-LD format.
  """

  def serialize_user(user, domain) do
    actor = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Person",
      "id" => "https://#{domain}/users/#{user.username}",
      "preferredUsername" => user.username,
      "name" => user.display_name || user.username,
      "inbox" => "https://#{domain}/users/#{user.username}/inbox",
      "outbox" => "https://#{domain}/users/#{user.username}/outbox",
      "publicKey" => %{
        "id" => "https://#{domain}/users/#{user.username}#main-key",
        "owner" => "https://#{domain}/users/#{user.username}",
        "publicKeyPem" => user.identity_public_key || ""
      }
    }

    case Map.get(user, :did) do
      nil -> actor
      did -> Map.put(actor, "alsoKnownAs", [did])
    end
  end

  def serialize_server(server, domain) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Group",
      "id" => "https://#{domain}/servers/#{server.id}",
      "name" => server.name,
      "summary" => server.description
    }
  end

  def serialize_channel(channel, domain) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "OrderedCollection",
      "id" => "https://#{domain}/channels/#{channel.id}",
      "name" => channel.name,
      "summary" => channel.description
    }
  end

  def serialize_message(message, channel_id, domain, author \\ nil) do
    note = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Note",
      "id" => "https://#{domain}/channels/#{channel_id}/messages/#{message.id}",
      "attributedTo" => "https://#{domain}/users/#{message.author_id}",
      "content" => message.content,
      "published" => DateTime.to_iso8601(message.inserted_at),
      "cairn:channelId" => channel_id
    }

    # Add DID and home instance extension fields if author has a DID
    case author do
      %{did: did} when is_binary(did) ->
        note
        |> Map.put("cairn:did", did)
        |> Map.put("cairn:homeInstance", domain)
        |> Map.put("cairn:displayName", Map.get(author, :display_name))

      _ ->
        note
    end
  end

  def wrap_activity(type, actor_uri, object, domain) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => type,
      "id" => "https://#{domain}/activities/#{Ecto.UUID.generate()}",
      "actor" => actor_uri,
      "object" => object
    }
  end
end
