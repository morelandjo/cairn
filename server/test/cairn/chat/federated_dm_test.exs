defmodule Cairn.Chat.FederatedDmTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Chat, Federation}

  @valid_password "secure_password_123"

  setup do
    {:ok, {user1, _codes}} =
      Accounts.register_user(%{
        "username" => "alice_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    # Simulate a federated user
    {:ok, federated_user} =
      Federation.get_or_create_federated_user(%{
        did: "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}",
        username: "bob",
        display_name: "Bob Remote",
        home_instance: "instance-b.com",
        public_key: "pending",
        actor_uri: "https://instance-b.com/users/bob",
        last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })

    {:ok, user: user1, federated_user: federated_user}
  end

  describe "create_federated_dm/2" do
    test "creates a DM channel with local and federated members", %{
      user: user,
      federated_user: fu
    } do
      {:ok, channel} = Chat.create_federated_dm(user.id, fu.id)

      assert channel.type == "dm"
      assert Chat.is_member?(channel.id, user.id)
      assert Chat.is_federated_channel_member?(channel.id, fu.id)
    end

    test "returns existing channel on duplicate call", %{user: user, federated_user: fu} do
      {:ok, channel1} = Chat.create_federated_dm(user.id, fu.id)
      {:ok, channel2} = Chat.create_federated_dm(user.id, fu.id)

      assert channel1.id == channel2.id
    end
  end

  describe "find_federated_dm/2" do
    test "finds existing federated DM", %{user: user, federated_user: fu} do
      {:ok, channel} = Chat.create_federated_dm(user.id, fu.id)
      found = Chat.find_federated_dm(user.id, fu.id)

      assert found.id == channel.id
    end

    test "returns nil when no DM exists", %{user: user, federated_user: fu} do
      assert Chat.find_federated_dm(user.id, fu.id) == nil
    end
  end

  describe "add_federated_member/3" do
    test "adds a federated user to a channel", %{federated_user: fu} do
      {:ok, channel} = Chat.create_channel(%{name: "test-dm", type: "dm"})
      {:ok, member} = Chat.add_federated_member(channel.id, fu.id)

      assert member.federated_user_id == fu.id
      assert member.channel_id == channel.id
      assert member.role == "member"
    end
  end

  describe "DM request CRUD" do
    setup %{user: user, federated_user: fu} do
      {:ok, channel} = Chat.create_federated_dm(user.id, fu.id)

      {:ok, request} =
        Chat.create_dm_request(%{
          channel_id: channel.id,
          sender_id: user.id,
          recipient_did: fu.did,
          recipient_instance: "instance-b.com",
          status: "pending"
        })

      {:ok, channel: channel, request: request}
    end

    test "creates a DM request", %{request: request, user: user, federated_user: fu} do
      assert request.sender_id == user.id
      assert request.recipient_did == fu.did
      assert request.status == "pending"
    end

    test "lists requests for a DID", %{federated_user: fu} do
      requests = Chat.list_dm_requests_for_did(fu.did)
      assert length(requests) == 1
      assert hd(requests).status == "pending"
    end

    test "lists sent requests", %{user: user} do
      requests = Chat.list_sent_dm_requests(user.id)
      assert length(requests) == 1
    end

    test "finds existing request", %{user: user, federated_user: fu} do
      found = Chat.find_dm_request(user.id, fu.did)
      assert found != nil
    end

    test "updates request status", %{request: request} do
      {:ok, updated} = Chat.update_dm_request(request, %{status: "accepted"})
      assert updated.status == "accepted"
    end

    test "counts recent requests", %{user: user} do
      count = Chat.count_recent_dm_requests(user.id)
      assert count == 1
    end

    test "counts pending requests for DID", %{federated_user: fu} do
      count = Chat.count_pending_dm_requests_for_did(fu.did)
      assert count == 1
    end

    test "enforces unique constraint on sender + recipient", %{
      user: user,
      federated_user: fu,
      channel: channel
    } do
      result =
        Chat.create_dm_request(%{
          channel_id: channel.id,
          sender_id: user.id,
          recipient_did: fu.did,
          recipient_instance: "instance-b.com",
          status: "pending"
        })

      assert {:error, changeset} = result
      assert changeset.errors[:sender_id] || changeset.errors[:recipient_did]
    end
  end

  describe "DM blocks" do
    setup %{user: user} do
      blocked_did =
        "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"

      {:ok, blocked_did: blocked_did, user: user}
    end

    test "blocks a DID", %{user: user, blocked_did: blocked_did} do
      {:ok, block} = Chat.block_dm_sender(user.id, blocked_did)
      assert block.blocked_did == blocked_did
    end

    test "checks if DID is blocked", %{user: user, blocked_did: blocked_did} do
      refute Chat.is_dm_blocked?(user.id, blocked_did)
      {:ok, _} = Chat.block_dm_sender(user.id, blocked_did)
      assert Chat.is_dm_blocked?(user.id, blocked_did)
    end

    test "unblocks a DID", %{user: user, blocked_did: blocked_did} do
      {:ok, _} = Chat.block_dm_sender(user.id, blocked_did)
      assert Chat.is_dm_blocked?(user.id, blocked_did)
      :ok = Chat.unblock_dm_sender(user.id, blocked_did)
      refute Chat.is_dm_blocked?(user.id, blocked_did)
    end

    test "lists blocked DIDs", %{user: user, blocked_did: blocked_did} do
      {:ok, _} = Chat.block_dm_sender(user.id, blocked_did)
      blocks = Chat.list_dm_blocks(user.id)
      assert length(blocks) == 1
      assert hd(blocks).blocked_did == blocked_did
    end

    test "prevents duplicate blocks", %{user: user, blocked_did: blocked_did} do
      {:ok, _} = Chat.block_dm_sender(user.id, blocked_did)
      assert {:error, _} = Chat.block_dm_sender(user.id, blocked_did)
    end
  end
end
