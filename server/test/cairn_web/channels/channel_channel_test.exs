defmodule MurmuringWeb.ChannelChannelTest do
  use MurmuringWeb.ChannelCase, async: true

  alias Murmuring.{Accounts, Auth, Chat, Servers}

  @valid_password "secure_password_123"

  # Wait for the after_join presence tracking to complete, then drain
  # any presence_diff broadcasts from the mailbox so they don't interfere
  # with assert_reply/assert_broadcast later.
  defp wait_for_presence do
    assert_push "presence_state", _, 2000
    # Give presence_diff time to arrive, then flush it
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

  setup do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "wsuser_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: user.id})
    {:ok, channel} = Chat.create_channel(%{name: "ws-test", type: "public", server_id: server.id})
    Chat.add_member(channel.id, user.id)

    {:ok, access_token, _claims} = Auth.Token.generate_access_token(user.id)

    {:ok, socket} = connect(MurmuringWeb.UserSocket, %{"token" => access_token})

    {:ok, socket: socket, user: user, channel: channel, server: server}
  end

  test "joins a public channel", %{socket: socket, channel: channel} do
    {:ok, _reply, _socket} = subscribe_and_join(socket, "channel:#{channel.id}", %{})
  end

  test "rejects join for nonexistent channel", %{socket: socket} do
    assert {:error, %{reason: "channel not found"}} =
             subscribe_and_join(socket, "channel:#{Ecto.UUID.generate()}", %{})
  end

  test "sends and receives messages", %{socket: socket, channel: channel} do
    {:ok, _reply, socket} = subscribe_and_join(socket, "channel:#{channel.id}", %{})
    wait_for_presence()

    ref = push(socket, "new_msg", %{"content" => "Hello from WS!"})
    assert_reply ref, :ok

    assert_broadcast "new_msg", %{content: "Hello from WS!"}, 1000
  end

  test "edits a message", %{socket: socket, channel: channel, user: user} do
    {:ok, _reply, socket} = subscribe_and_join(socket, "channel:#{channel.id}", %{})
    wait_for_presence()

    {:ok, message} =
      Chat.create_message(%{
        content: "Original",
        channel_id: channel.id,
        author_id: user.id
      })

    ref = push(socket, "edit_msg", %{"id" => message.id, "content" => "Edited"})
    assert_reply ref, :ok

    assert_broadcast "edit_msg", %{id: _, content: "Edited"}
  end

  test "deletes a message", %{socket: socket, channel: channel, user: user} do
    {:ok, _reply, socket} = subscribe_and_join(socket, "channel:#{channel.id}", %{})
    wait_for_presence()

    {:ok, message} =
      Chat.create_message(%{
        content: "To delete",
        channel_id: channel.id,
        author_id: user.id
      })

    ref = push(socket, "delete_msg", %{"id" => message.id})
    assert_reply ref, :ok

    assert_broadcast "delete_msg", %{id: _}
  end

  test "typing event is handled without error", %{socket: socket, channel: channel} do
    {:ok, _reply, socket} = subscribe_and_join(socket, "channel:#{channel.id}", %{})
    wait_for_presence()

    push(socket, "typing", %{})
    # broadcast_from! sends to all except sender — in test the process
    # is both sender and subscriber, so we may or may not see it.
    # Just verify no crash.
    :timer.sleep(50)
  end

  test "rate limits messages", %{socket: socket, channel: channel} do
    {:ok, _reply, socket} = subscribe_and_join(socket, "channel:#{channel.id}", %{})
    wait_for_presence()

    # Send 21 messages rapidly (burst limit is 20)
    results =
      for i <- 1..25 do
        ref = push(socket, "new_msg", %{"content" => "msg #{i}"})

        receive do
          %Phoenix.Socket.Reply{ref: ^ref, status: status} -> status
        after
          1000 -> :timeout
        end
      end

    assert :error in results
  end
end
