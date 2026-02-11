defmodule Murmuring.Chat.ReactionsTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.{Accounts, Chat, Servers}

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "rxnuser_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_channel do
    owner = create_user("owner")
    {:ok, server} = Servers.create_server(%{name: "RxnTest", creator_id: owner.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    {:ok, msg} =
      Chat.create_message(%{content: "React to me", channel_id: channel.id, author_id: owner.id})

    %{owner: owner, server: server, channel: channel, message: msg}
  end

  describe "reactions" do
    test "add and list reactions" do
      %{owner: owner, message: msg} = setup_channel()
      user2 = create_user("user2")

      {:ok, _} = Chat.add_reaction(msg.id, owner.id, "thumbsup")
      {:ok, _} = Chat.add_reaction(msg.id, user2.id, "thumbsup")
      {:ok, _} = Chat.add_reaction(msg.id, owner.id, "heart")

      reactions = Chat.list_reactions(msg.id)
      assert length(reactions) == 2

      thumbsup = Enum.find(reactions, &(&1.emoji == "thumbsup"))
      assert thumbsup.count == 2

      heart = Enum.find(reactions, &(&1.emoji == "heart"))
      assert heart.count == 1
    end

    test "remove reaction" do
      %{owner: owner, message: msg} = setup_channel()

      {:ok, _} = Chat.add_reaction(msg.id, owner.id, "thumbsup")
      assert length(Chat.list_reactions(msg.id)) == 1

      :ok = Chat.remove_reaction(msg.id, owner.id, "thumbsup")
      assert length(Chat.list_reactions(msg.id)) == 0
    end

    test "duplicate reaction is rejected" do
      %{owner: owner, message: msg} = setup_channel()

      {:ok, _} = Chat.add_reaction(msg.id, owner.id, "thumbsup")
      assert {:error, _} = Chat.add_reaction(msg.id, owner.id, "thumbsup")
    end

    test "list_reactions_with_users returns user details" do
      %{owner: owner, message: msg} = setup_channel()

      {:ok, _} = Chat.add_reaction(msg.id, owner.id, "fire")

      reactions = Chat.list_reactions_with_users(msg.id)
      assert length(reactions) == 1
      assert hd(reactions).emoji == "fire"
      assert hd(reactions).user_id == owner.id
    end
  end
end
