defmodule Cairn.Chat.CategoriesTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Chat, Servers}

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "catuser_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_server do
    owner = create_user("owner")
    {:ok, server} = Servers.create_server(%{name: "CatTest", creator_id: owner.id})
    %{owner: owner, server: server}
  end

  describe "category CRUD" do
    test "create, update, list, delete categories" do
      %{server: server} = setup_server()

      {:ok, cat1} = Chat.create_category(%{name: "General", server_id: server.id, position: 0})
      {:ok, cat2} = Chat.create_category(%{name: "Games", server_id: server.id, position: 1})

      categories = Chat.list_categories(server.id)
      assert length(categories) == 2
      assert hd(categories).name == "General"

      {:ok, updated} = Chat.update_category(cat1, %{name: "Updated"})
      assert updated.name == "Updated"

      {:ok, _} = Chat.delete_category(cat2)
      assert length(Chat.list_categories(server.id)) == 1
    end
  end

  describe "channel reordering" do
    test "reorder channels with positions and categories" do
      %{server: server} = setup_server()

      {:ok, cat} = Chat.create_category(%{name: "Text", server_id: server.id})
      {:ok, ch1} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})
      {:ok, ch2} = Chat.create_channel(%{name: "random", type: "public", server_id: server.id})

      {:ok, _} =
        Chat.reorder_channels([
          %{"id" => ch1.id, "position" => 1, "category_id" => cat.id},
          %{"id" => ch2.id, "position" => 0, "category_id" => cat.id}
        ])

      channels = Chat.list_server_channels_ordered(server.id)
      assert hd(channels).name == "random"
      assert hd(channels).category_id == cat.id
    end
  end
end
