defmodule Cairn.Federation.ActivityPubTest do
  use ExUnit.Case, async: true

  alias Cairn.Federation.ActivityPub

  describe "serialize_user/2" do
    test "serializes user as AP Person" do
      user = %{
        username: "alice",
        display_name: "Alice",
        identity_public_key: "base64key=="
      }

      result = ActivityPub.serialize_user(user, "example.com")

      assert result["type"] == "Person"
      assert result["id"] == "https://example.com/users/alice"
      assert result["preferredUsername"] == "alice"
      assert result["name"] == "Alice"
      assert result["inbox"] == "https://example.com/users/alice/inbox"
      assert result["outbox"] == "https://example.com/users/alice/outbox"
      assert result["publicKey"]["publicKeyPem"] == "base64key=="
    end
  end

  describe "serialize_server/2" do
    test "serializes server as AP Group" do
      server = %{id: "srv-123", name: "My Server", description: "A cool server"}
      result = ActivityPub.serialize_server(server, "example.com")

      assert result["type"] == "Group"
      assert result["id"] == "https://example.com/servers/srv-123"
      assert result["name"] == "My Server"
    end
  end

  describe "serialize_message/3" do
    test "serializes message as AP Note" do
      message = %{
        id: "msg-456",
        author_id: "user-789",
        content: "Hello world",
        inserted_at: ~U[2026-02-10 15:00:00Z]
      }

      result = ActivityPub.serialize_message(message, "ch-123", "example.com")

      assert result["type"] == "Note"
      assert result["id"] == "https://example.com/channels/ch-123/messages/msg-456"
      assert result["content"] == "Hello world"
      assert result["attributedTo"] == "https://example.com/users/user-789"
      assert result["cairn:channelId"] == "ch-123"
    end

    test "includes DID extension fields when author has DID" do
      message = %{
        id: "msg-456",
        author_id: "user-789",
        content: "Hello world",
        inserted_at: ~U[2026-02-10 15:00:00Z]
      }

      author = %{did: "did:cairn:abc123", display_name: "Alice"}

      result = ActivityPub.serialize_message(message, "ch-123", "example.com", author)

      assert result["cairn:did"] == "did:cairn:abc123"
      assert result["cairn:homeInstance"] == "example.com"
      assert result["cairn:displayName"] == "Alice"
    end

    test "omits DID fields when author has no DID" do
      message = %{
        id: "msg-456",
        author_id: "user-789",
        content: "Hello world",
        inserted_at: ~U[2026-02-10 15:00:00Z]
      }

      result = ActivityPub.serialize_message(message, "ch-123", "example.com", nil)

      refute Map.has_key?(result, "cairn:did")
      refute Map.has_key?(result, "cairn:homeInstance")
    end
  end

  describe "wrap_activity/4" do
    test "wraps object in activity" do
      object = %{"type" => "Note", "content" => "hello"}

      result =
        ActivityPub.wrap_activity(
          "Create",
          "https://example.com/users/alice",
          object,
          "example.com"
        )

      assert result["type"] == "Create"
      assert result["actor"] == "https://example.com/users/alice"
      assert result["object"] == object
      assert result["id"] =~ "https://example.com/activities/"
    end
  end
end
