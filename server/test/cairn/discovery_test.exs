defmodule Cairn.DiscoveryTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Discovery, Servers}

  @valid_password "secure_password_123"

  defp create_user(username) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  test "list and unlist server in directory" do
    user = create_user("discuser")
    {:ok, server} = Servers.create_server(%{name: "Public Server", creator_id: user.id})

    {:ok, entry} =
      Discovery.list_server(server.id, %{
        description: "A great server",
        tags: ["gaming", "fun"]
      })

    assert entry.description == "A great server"
    assert entry.tags == ["gaming", "fun"]
    assert entry.member_count >= 1

    # Should appear in directory
    entries = Discovery.list_directory()
    assert length(entries) == 1
    assert hd(entries).server_name == "Public Server"

    # Unlist
    {:ok, _} = Discovery.unlist_server(server.id)
    assert Discovery.list_directory() == []
  end

  test "list_directory filters by tag" do
    user = create_user("disctag")
    {:ok, server1} = Servers.create_server(%{name: "Gaming Server", creator_id: user.id})
    {:ok, server2} = Servers.create_server(%{name: "Music Server", creator_id: user.id})

    {:ok, _} = Discovery.list_server(server1.id, %{tags: ["gaming"]})
    {:ok, _} = Discovery.list_server(server2.id, %{tags: ["music"]})

    gaming = Discovery.list_directory(tag: "gaming")
    assert length(gaming) == 1
    assert hd(gaming).server_name == "Gaming Server"
  end

  test "update_member_count refreshes count" do
    user = create_user("disccount")
    {:ok, server} = Servers.create_server(%{name: "Count Server", creator_id: user.id})

    {:ok, entry} = Discovery.list_server(server.id)
    initial_count = entry.member_count

    # Add another member
    user2 = create_user("disccount2")
    Servers.add_member(server.id, user2.id)

    Discovery.update_member_count(server.id)
    updated = Discovery.get_entry(server.id)
    assert updated.member_count == initial_count + 1
  end

  test "unlist non-listed server is a no-op" do
    user = create_user("discnoop")
    {:ok, server} = Servers.create_server(%{name: "Not Listed", creator_id: user.id})

    assert {:ok, :not_listed} = Discovery.unlist_server(server.id)
  end
end
