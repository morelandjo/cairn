defmodule CairnWeb.PrivateChannelTest do
  use CairnWeb.ChannelCase, async: true

  alias Cairn.{Accounts, Auth, Chat, Servers}

  @valid_password "secure_password_123"

  # Drain any presence messages that arrive after joining
  # (Presence.track broadcasts a diff to all subscribers)
  defp drain_presence do
    # Give presence_diff time to arrive, then flush non-blocking
    Process.sleep(50)
    flush_presence()
  end

  defp flush_presence do
    receive do
      %Phoenix.Socket.Message{event: "presence" <> _} -> flush_presence()
      %Phoenix.Socket.Broadcast{event: "presence" <> _} -> flush_presence()
    after
      0 -> :ok
    end
  end

  defp create_user_and_socket(suffix) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "private_user_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, access_token, _claims} = Auth.Token.generate_access_token(user.id)
    {:ok, socket} = connect(CairnWeb.UserSocket, %{"token" => access_token})

    {user, socket}
  end

  setup do
    {user1, socket1} = create_user_and_socket("a")
    {user2, socket2} = create_user_and_socket("b")

    {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: user1.id})

    {:ok, channel} =
      Chat.create_channel(%{name: "private-test", type: "private", server_id: server.id})

    Chat.add_member(channel.id, user1.id)
    Chat.add_member(channel.id, user2.id)

    {:ok, socket1: socket1, socket2: socket2, user1: user1, user2: user2, channel: channel}
  end

  test "members can join a private channel", %{socket1: socket1, channel: channel} do
    {:ok, _reply, _socket} = subscribe_and_join(socket1, "channel:#{channel.id}", %{})
  end

  test "non-members cannot join a private channel", %{channel: channel} do
    {_outsider, outsider_socket} = create_user_and_socket("outsider")

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(outsider_socket, "channel:#{channel.id}", %{})
  end

  test "sends encrypted messages on private channel", %{socket1: socket1, channel: channel} do
    {:ok, _reply, socket} = subscribe_and_join(socket1, "channel:#{channel.id}", %{})

    assert_push "presence_state", _
    drain_presence()

    ref =
      push(socket, "new_msg", %{
        "content" => nil,
        "encrypted_content" => Base.encode64("encrypted_payload"),
        "nonce" => Base.encode64("test_nonce_value"),
        "mls_epoch" => 1
      })

    assert_reply ref, :ok
    assert_broadcast "new_msg", %{encrypted_content: _, nonce: _}, 1000
  end

  test "mls_commit event stores and broadcasts", %{socket1: socket1, channel: channel} do
    {:ok, _reply, socket} = subscribe_and_join(socket1, "channel:#{channel.id}", %{})

    assert_push "presence_state", _
    drain_presence()

    commit_data = Base.encode64("fake_commit_data")

    ref = push(socket, "mls_commit", %{"data" => commit_data, "epoch" => 1})
    assert_reply ref, :ok

    # broadcast_from! doesn't send to self, so we verify via DB
    messages = Chat.Mls.get_pending_messages(channel.id, [])
    assert length(messages) >= 1

    commit_msg = Enum.find(messages, &(&1.message_type == "commit"))
    assert commit_msg != nil
    assert commit_msg.data == "fake_commit_data"
  end

  test "mls_welcome event stores and broadcasts", %{
    socket1: socket1,
    user2: user2,
    channel: channel
  } do
    {:ok, _reply, socket} = subscribe_and_join(socket1, "channel:#{channel.id}", %{})

    assert_push "presence_state", _
    drain_presence()

    welcome_data = Base.encode64("fake_welcome_data")

    ref =
      push(socket, "mls_welcome", %{
        "data" => welcome_data,
        "recipient_id" => user2.id
      })

    assert_reply ref, :ok

    # Verify stored
    messages = Chat.Mls.get_pending_messages(channel.id, recipient_id: user2.id)
    welcome_msg = Enum.find(messages, &(&1.message_type == "welcome"))
    assert welcome_msg != nil
    assert welcome_msg.recipient_id == user2.id
  end

  test "mls_proposal event stores and broadcasts", %{socket1: socket1, channel: channel} do
    {:ok, _reply, socket} = subscribe_and_join(socket1, "channel:#{channel.id}", %{})

    assert_push "presence_state", _
    drain_presence()

    proposal_data = Base.encode64("fake_proposal_data")

    ref = push(socket, "mls_proposal", %{"data" => proposal_data, "epoch" => 2})
    assert_reply ref, :ok

    messages = Chat.Mls.get_pending_messages(channel.id, [])
    proposal_msg = Enum.find(messages, &(&1.message_type == "proposal"))
    assert proposal_msg != nil
    assert proposal_msg.epoch == 2
  end

  test "both members exchange MLS commits over WebSocket", %{
    socket1: socket1,
    socket2: socket2,
    channel: channel
  } do
    {:ok, _reply, _s1} = subscribe_and_join(socket1, "channel:#{channel.id}", %{})
    assert_push "presence_state", _
    drain_presence()

    {:ok, _reply, s2} = subscribe_and_join(socket2, "channel:#{channel.id}", %{})
    assert_push "presence_state", _
    drain_presence()

    # User 2 sends a commit
    commit_data = Base.encode64("user2_commit")
    ref = push(s2, "mls_commit", %{"data" => commit_data, "epoch" => 3})
    assert_reply ref, :ok

    # User 1 should receive the broadcast
    assert_broadcast "mls_commit", %{data: ^commit_data, epoch: 3}, 1000
  end
end
