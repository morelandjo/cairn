defmodule Cairn.Federation.ActivityPub do
  @moduledoc """
  ActivityPub serializers for converting internal entities to AP JSON-LD format.
  """

  alias Cairn.Federation

  def serialize_user(user, _domain) do
    user_url = Federation.local_url("/users/#{user.username}")

    actor = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Person",
      "id" => user_url,
      "preferredUsername" => user.username,
      "name" => user.display_name || user.username,
      "inbox" => "#{user_url}/inbox",
      "outbox" => "#{user_url}/outbox",
      "publicKey" => %{
        "id" => "#{user_url}#main-key",
        "owner" => user_url,
        "publicKeyPem" => user.identity_public_key || ""
      }
    }

    case Map.get(user, :did) do
      nil -> actor
      did -> Map.put(actor, "alsoKnownAs", [did])
    end
  end

  def serialize_server(server, _domain) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Group",
      "id" => Federation.local_url("/servers/#{server.id}"),
      "name" => server.name,
      "summary" => server.description
    }
  end

  def serialize_channel(channel, _domain) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "OrderedCollection",
      "id" => Federation.local_url("/channels/#{channel.id}"),
      "name" => channel.name,
      "summary" => channel.description
    }
  end

  def serialize_message(message, channel_id, _domain, author \\ nil) do
    config = Application.get_env(:cairn, :federation, [])
    domain = Keyword.get(config, :domain, "localhost")

    note = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Note",
      "id" => Federation.local_url("/channels/#{channel_id}/messages/#{message.id}"),
      "attributedTo" => Federation.local_url("/users/#{message.author_id}"),
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

  def wrap_activity(type, actor_uri, object, _domain) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => type,
      "id" => Federation.local_url("/activities/#{Ecto.UUID.generate()}"),
      "actor" => actor_uri,
      "object" => object
    }
  end
end
