defmodule Cairn.Chat.CustomEmojiTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Chat, Servers}

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "emoji_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_server do
    owner = create_user("owner")
    {:ok, server} = Servers.create_server(%{name: "EmojiTest", creator_id: owner.id})
    %{owner: owner, server: server}
  end

  describe "custom emojis" do
    test "create, list, and delete emoji" do
      %{owner: owner, server: server} = setup_server()

      {:ok, emoji} =
        Chat.create_emoji(%{
          name: "party_parrot",
          file_key: "emojis/party_parrot.gif",
          animated: true,
          server_id: server.id,
          uploader_id: owner.id
        })

      assert emoji.name == "party_parrot"
      assert emoji.animated == true

      emojis = Chat.list_emojis(server.id)
      assert length(emojis) == 1

      {:ok, _} = Chat.delete_emoji(emoji)
      assert length(Chat.list_emojis(server.id)) == 0
    end

    test "duplicate name in same server is rejected" do
      %{owner: owner, server: server} = setup_server()

      {:ok, _} =
        Chat.create_emoji(%{
          name: "cool_emoji",
          file_key: "emojis/cool.png",
          server_id: server.id,
          uploader_id: owner.id
        })

      assert {:error, _} =
               Chat.create_emoji(%{
                 name: "cool_emoji",
                 file_key: "emojis/cool2.png",
                 server_id: server.id,
                 uploader_id: owner.id
               })
    end

    test "max 50 emojis per server" do
      %{owner: owner, server: server} = setup_server()

      for i <- 1..50 do
        {:ok, _} =
          Chat.create_emoji(%{
            name: "emoji_#{i}",
            file_key: "emojis/e#{i}.png",
            server_id: server.id,
            uploader_id: owner.id
          })
      end

      assert {:error, :max_emojis_reached} =
               Chat.create_emoji(%{
                 name: "emoji_51",
                 file_key: "emojis/e51.png",
                 server_id: server.id,
                 uploader_id: owner.id
               })
    end
  end
end
