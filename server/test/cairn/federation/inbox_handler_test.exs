defmodule Cairn.Federation.InboxHandlerTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Chat, Federation}
  alias Cairn.Federation.InboxHandler

  setup do
    {:ok, node} =
      Federation.register_node(%{
        domain: "inbox-test.example.com",
        node_id: "inbox_node_1",
        public_key: "key",
        inbox_url: "https://inbox-test.example.com/inbox",
        protocol_version: "0.1.0",
        status: "active"
      })

    # Create a server and channel for message tests
    {:ok, {user, _codes}} =
      Cairn.Accounts.register_user(%{
        username: "inbox_owner_#{:erlang.unique_integer([:positive])}",
        password: "TestPassword123!",
        display_name: "Inbox Owner"
      })

    {:ok, server} =
      Cairn.Servers.create_server(%{name: "Inbox Server", creator_id: user.id})

    {:ok, channel} =
      Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    %{node: node, channel: channel, user: user, server: server}
  end

  describe "handle/2 - Follow/Accept" do
    test "processes Follow activity", %{node: node} do
      activity = %{
        "type" => "Follow",
        "actor" => "https://inbox-test.example.com/users/alice",
        "object" => "https://local.example.com/channels/ch-123"
      }

      assert :ok = InboxHandler.handle(activity, node)

      # Verify activity was logged
      activities = Federation.list_activities(node_id: node.id)
      assert length(activities) == 1
      assert hd(activities).activity_type == "Follow"
      assert hd(activities).direction == "inbound"
    end
  end

  describe "handle/2 - Create" do
    test "creates message from federated actor with DID", %{node: node, channel: channel} do
      activity = %{
        "type" => "Create",
        "actor" => "https://inbox-test.example.com/users/bob",
        "object" => %{
          "type" => "Note",
          "id" => "https://inbox-test.example.com/channels/#{channel.id}/messages/#{Ecto.UUID.generate()}",
          "content" => "Hello from remote",
          "cairn:channelId" => channel.id,
          "cairn:did" => "did:cairn:testdid123",
          "cairn:homeInstance" => "inbox-test.example.com",
          "cairn:displayName" => "Bob Remote"
        }
      }

      assert :ok = InboxHandler.handle(activity, node)

      # Verify message was created
      messages = Chat.list_messages(channel.id)
      assert length(messages) == 1
      msg = hd(messages)
      assert msg.content == "Hello from remote"
    end

    test "creates message from federated actor without DID (fallback)", %{node: node, channel: channel} do
      activity = %{
        "type" => "Create",
        "actor" => "https://inbox-test.example.com/users/charlie",
        "object" => %{
          "type" => "Note",
          "id" => "https://inbox-test.example.com/channels/#{channel.id}/messages/#{Ecto.UUID.generate()}",
          "content" => "No DID message",
          "cairn:channelId" => channel.id
        }
      }

      assert :ok = InboxHandler.handle(activity, node)

      messages = Chat.list_messages(channel.id)
      assert length(messages) == 1
      assert hd(messages).content == "No DID message"
    end

    test "rejects Create with invalid object", %{node: node} do
      activity = %{
        "type" => "Create",
        "actor" => "https://inbox-test.example.com/users/bob",
        "object" => %{"type" => "Image"}
      }

      assert {:error, _} = InboxHandler.handle(activity, node)
    end

    test "rejects Create for nonexistent channel", %{node: node} do
      fake_channel_id = Ecto.UUID.generate()

      activity = %{
        "type" => "Create",
        "actor" => "https://inbox-test.example.com/users/bob",
        "object" => %{
          "type" => "Note",
          "id" => "https://inbox-test.example.com/channels/#{fake_channel_id}/messages/#{Ecto.UUID.generate()}",
          "content" => "To nowhere",
          "cairn:channelId" => fake_channel_id
        }
      }

      assert {:error, _} = InboxHandler.handle(activity, node)
    end
  end

  describe "handle/2 - Update" do
    test "updates federated message content", %{node: node, channel: channel} do
      # First create a federated user and message
      {:ok, fed_user} =
        Federation.get_or_create_federated_user(%{
          did: "did:cairn:updatetest",
          username: "updater",
          home_instance: "inbox-test.example.com",
          public_key: :crypto.strong_rand_bytes(32),
          actor_uri: "https://inbox-test.example.com/users/updater",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      {:ok, message} =
        Chat.create_message(%{
          content: "Original content",
          channel_id: channel.id,
          federated_author_id: fed_user.id
        })

      activity = %{
        "type" => "Update",
        "actor" => "https://inbox-test.example.com/users/updater",
        "object" => %{
          "type" => "Note",
          "id" => "https://inbox-test.example.com/channels/#{channel.id}/messages/#{message.id}",
          "content" => "Updated content"
        }
      }

      assert :ok = InboxHandler.handle(activity, node)

      updated = Chat.get_message!(message.id)
      assert updated.content == "Updated content"
      assert updated.edited_at != nil
    end
  end

  describe "handle/2 - Delete" do
    test "soft-deletes federated message", %{node: node, channel: channel} do
      {:ok, fed_user} =
        Federation.get_or_create_federated_user(%{
          did: "did:cairn:deletetest",
          username: "deleter",
          home_instance: "inbox-test.example.com",
          public_key: :crypto.strong_rand_bytes(32),
          actor_uri: "https://inbox-test.example.com/users/deleter",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      {:ok, message} =
        Chat.create_message(%{
          content: "To be deleted",
          channel_id: channel.id,
          federated_author_id: fed_user.id
        })

      activity = %{
        "type" => "Delete",
        "actor" => "https://inbox-test.example.com/users/deleter",
        "object" => "https://inbox-test.example.com/channels/#{channel.id}/messages/#{message.id}"
      }

      assert :ok = InboxHandler.handle(activity, node)

      deleted = Chat.get_message!(message.id)
      assert deleted.deleted_at != nil
      assert deleted.content == nil
    end
  end

  describe "handle/2 - unsupported" do
    test "rejects unsupported activity type", %{node: node} do
      activity = %{
        "type" => "Announce",
        "actor" => "https://inbox-test.example.com/users/bob"
      }

      assert {:error, _} = InboxHandler.handle(activity, node)
    end
  end
end
