defmodule CairnWeb.UserChannelTest do
  use CairnWeb.ChannelCase

  alias Cairn.{Accounts, Auth}

  @valid_password "secure_password_123"

  setup do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "uc_user_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)

    {:ok, socket} =
      connect(CairnWeb.UserSocket, %{"token" => tokens.access_token})

    {:ok, socket: socket, user: user}
  end

  describe "join" do
    test "joins own user channel", %{socket: socket, user: user} do
      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, CairnWeb.UserChannel, "user:#{user.id}")
    end

    test "rejects join to another user's channel", %{socket: socket} do
      other_id = Ecto.UUID.generate()

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, CairnWeb.UserChannel, "user:#{other_id}")
    end
  end

  describe "notifications" do
    test "receives dm_request push", %{socket: socket, user: user} do
      {:ok, _reply, _socket} =
        subscribe_and_join(socket, CairnWeb.UserChannel, "user:#{user.id}")

      # Simulate a PubSub broadcast (as InboxHandler would do)
      Phoenix.PubSub.broadcast(
        Cairn.PubSub,
        "user:#{user.id}",
        {:dm_request,
         %{
           sender_did: "did:cairn:alice123",
           sender_username: "alice",
           channel_id: Ecto.UUID.generate()
         }}
      )

      assert_push "dm_request", %{
        sender_did: "did:cairn:alice123",
        sender_username: "alice"
      }
    end

    test "receives dm_request_response push", %{socket: socket, user: user} do
      {:ok, _reply, _socket} =
        subscribe_and_join(socket, CairnWeb.UserChannel, "user:#{user.id}")

      Phoenix.PubSub.broadcast(
        Cairn.PubSub,
        "user:#{user.id}",
        {:dm_request_response,
         %{
           request_id: Ecto.UUID.generate(),
           status: "accepted",
           channel_id: Ecto.UUID.generate()
         }}
      )

      assert_push "dm_request_response", %{
        status: "accepted"
      }
    end
  end
end
