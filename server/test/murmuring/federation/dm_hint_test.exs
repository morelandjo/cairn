defmodule Murmuring.Federation.DmHintTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.{Accounts, Federation}
  alias Murmuring.Federation.InboxHandler

  @valid_password "secure_password_123"

  setup do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "hint_user_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, user} =
      Accounts.update_user_did(user, %{
        did: "did:murmuring:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}",
        rotation_public_key: :crypto.strong_rand_bytes(32)
      })

    {:ok, node} =
      Federation.register_node(%{
        domain: "sender-instance.com",
        node_id: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        public_key: :crypto.strong_rand_bytes(32) |> Base.encode64(),
        inbox_url: "https://sender-instance.com/inbox",
        status: "active",
        protocol_version: "0.1.0"
      })

    {:ok, user: user, node: node}
  end

  describe "InboxHandler.handle/2 with Invite (DmHint)" do
    test "processes DM hint for known local user", %{user: user, node: node} do
      activity = %{
        "type" => "Invite",
        "actor" => "https://sender-instance.com/users/alice",
        "object" => %{
          "type" => "murmuring:DmHint",
          "murmuring:channelId" => Ecto.UUID.generate(),
          "murmuring:senderDid" => "did:murmuring:alice123",
          "murmuring:senderUsername" => "alice",
          "murmuring:senderDisplayName" => "Alice",
          "murmuring:recipientDid" => user.did
        },
        "target" => "https://localhost/users/#{user.username}"
      }

      assert :ok = InboxHandler.handle(activity, node)
    end

    test "returns error for unknown recipient DID", %{node: node} do
      activity = %{
        "type" => "Invite",
        "actor" => "https://sender-instance.com/users/alice",
        "object" => %{
          "type" => "murmuring:DmHint",
          "murmuring:channelId" => Ecto.UUID.generate(),
          "murmuring:senderDid" => "did:murmuring:alice123",
          "murmuring:senderUsername" => "alice",
          "murmuring:senderDisplayName" => "Alice",
          "murmuring:recipientDid" => "did:murmuring:nonexistent"
        },
        "target" => "https://localhost/users/unknown"
      }

      assert {:error, :recipient_not_found} = InboxHandler.handle(activity, node)
    end

    test "returns error for invalid DM hint (missing fields)", %{node: node} do
      activity = %{
        "type" => "Invite",
        "actor" => "https://sender-instance.com/users/alice",
        "object" => %{
          "type" => "murmuring:DmHint"
          # Missing required fields
        },
        "target" => "https://localhost/users/unknown"
      }

      assert {:error, :invalid_dm_hint} = InboxHandler.handle(activity, node)
    end

    test "returns error for unsupported invite type", %{node: node} do
      activity = %{
        "type" => "Invite",
        "actor" => "https://sender-instance.com/users/alice",
        "object" => %{
          "type" => "SomethingElse"
        },
        "target" => "https://localhost/users/unknown"
      }

      assert {:error, :unsupported_invite_type} = InboxHandler.handle(activity, node)
    end
  end
end
