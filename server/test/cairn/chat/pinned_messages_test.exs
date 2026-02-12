defmodule Cairn.Chat.PinnedMessagesTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Chat, Servers}

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "pinuser_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_channel do
    owner = create_user("owner")
    {:ok, server} = Servers.create_server(%{name: "PinTest", creator_id: owner.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})
    %{owner: owner, server: server, channel: channel}
  end

  describe "pin/unpin messages" do
    test "pin and list pinned messages" do
      %{owner: owner, channel: channel} = setup_channel()

      {:ok, msg} =
        Chat.create_message(%{content: "Hello!", channel_id: channel.id, author_id: owner.id})

      {:ok, pin} = Chat.pin_message(channel.id, msg.id, owner.id)
      assert pin.message_id == msg.id

      pins = Chat.list_pins(channel.id)
      assert length(pins) == 1
      assert hd(pins).content == "Hello!"
    end

    test "unpin a message" do
      %{owner: owner, channel: channel} = setup_channel()

      {:ok, msg} =
        Chat.create_message(%{content: "Pin me", channel_id: channel.id, author_id: owner.id})

      {:ok, _} = Chat.pin_message(channel.id, msg.id, owner.id)
      assert length(Chat.list_pins(channel.id)) == 1

      :ok = Chat.unpin_message(channel.id, msg.id)
      assert length(Chat.list_pins(channel.id)) == 0
    end

    test "max 50 pins per channel" do
      %{owner: owner, channel: channel} = setup_channel()

      for i <- 1..50 do
        {:ok, msg} =
          Chat.create_message(%{content: "Msg #{i}", channel_id: channel.id, author_id: owner.id})

        {:ok, _} = Chat.pin_message(channel.id, msg.id, owner.id)
      end

      {:ok, msg51} =
        Chat.create_message(%{content: "Msg 51", channel_id: channel.id, author_id: owner.id})

      assert {:error, :max_pins_reached} = Chat.pin_message(channel.id, msg51.id, owner.id)
    end

    test "duplicate pin is rejected" do
      %{owner: owner, channel: channel} = setup_channel()

      {:ok, msg} =
        Chat.create_message(%{content: "Dup", channel_id: channel.id, author_id: owner.id})

      {:ok, _} = Chat.pin_message(channel.id, msg.id, owner.id)
      assert {:error, _} = Chat.pin_message(channel.id, msg.id, owner.id)
    end
  end
end
