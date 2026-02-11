defmodule Murmuring.ServersTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.{Accounts, Servers}

  defp create_user(attrs \\ %{}) do
    username = Map.get(attrs, :username, "user_#{System.unique_integer([:positive])}")

    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        username: username,
        password: "testpassword123!"
      })

    user
  end

  describe "create_server/1" do
    test "creates a server with default roles and adds creator as owner" do
      user = create_user()

      {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: user.id})

      assert server.name == "Test Server"
      assert server.creator_id == user.id

      # Should have 4 default roles
      roles = Servers.list_server_roles(server.id)
      assert length(roles) == 4
      role_names = Enum.map(roles, & &1.name)
      assert "@everyone" in role_names
      assert "Moderator" in role_names
      assert "Admin" in role_names
      assert "Owner" in role_names

      # Creator should be a member with Owner role
      assert Servers.is_member?(server.id, user.id)
      members = Servers.list_members(server.id)
      assert length(members) == 1
      assert hd(members).role_name == "Owner"
    end

    test "validates name required" do
      user = create_user()
      {:error, changeset} = Servers.create_server(%{creator_id: user.id})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates name length" do
      user = create_user()
      long_name = String.duplicate("a", 101)
      {:error, changeset} = Servers.create_server(%{name: long_name, creator_id: user.id})
      assert %{name: _} = errors_on(changeset)
    end
  end

  describe "list_user_servers/1" do
    test "returns servers the user belongs to" do
      user = create_user()
      other_user = create_user(%{username: "other"})

      {:ok, server1} = Servers.create_server(%{name: "Server 1", creator_id: user.id})
      {:ok, _server2} = Servers.create_server(%{name: "Server 2", creator_id: other_user.id})

      servers = Servers.list_user_servers(user.id)
      assert length(servers) == 1
      assert hd(servers).id == server1.id
    end
  end

  describe "membership" do
    setup do
      owner = create_user(%{username: "owner"})
      member = create_user(%{username: "member"})
      {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: owner.id})
      %{owner: owner, member: member, server: server}
    end

    test "add_member/2 adds user with @everyone role", %{server: server, member: member} do
      {:ok, sm} = Servers.add_member(server.id, member.id)
      assert sm.server_id == server.id
      assert sm.user_id == member.id
      assert sm.role_id != nil
    end

    test "remove_member/2 removes membership", %{server: server, member: member} do
      {:ok, _} = Servers.add_member(server.id, member.id)
      assert Servers.is_member?(server.id, member.id)

      {1, _} = Servers.remove_member(server.id, member.id)
      refute Servers.is_member?(server.id, member.id)
    end

    test "is_member?/2 returns correct value", %{server: server, member: member, owner: owner} do
      assert Servers.is_member?(server.id, owner.id)
      refute Servers.is_member?(server.id, member.id)
    end

    test "list_members/1 returns all members with roles", %{
      server: server,
      member: member,
      owner: owner
    } do
      {:ok, _} = Servers.add_member(server.id, member.id)

      members = Servers.list_members(server.id)
      assert length(members) == 2

      owner_member = Enum.find(members, &(&1.id == owner.id))
      assert owner_member.role_name == "Owner"

      regular_member = Enum.find(members, &(&1.id == member.id))
      assert regular_member.role_name == "@everyone"
    end

    test "update_member_role/3 changes a member's role", %{server: server, member: member} do
      {:ok, _} = Servers.add_member(server.id, member.id)

      roles = Servers.list_server_roles(server.id)
      mod_role = Enum.find(roles, &(&1.name == "Moderator"))

      {:ok, updated} = Servers.update_member_role(server.id, member.id, mod_role.id)
      assert updated.role_id == mod_role.id
    end
  end

  describe "roles" do
    setup do
      user = create_user()
      {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: user.id})
      %{user: user, server: server}
    end

    test "create_server_role/2 creates a custom role", %{server: server} do
      {:ok, role} =
        Servers.create_server_role(server.id, %{
          name: "Custom Role",
          permissions: %{"send_messages" => true},
          priority: 25
        })

      assert role.name == "Custom Role"
      assert role.server_id == server.id
      assert role.priority == 25
    end

    test "list_server_roles/1 returns roles ordered by priority", %{server: server} do
      roles = Servers.list_server_roles(server.id)
      priorities = Enum.map(roles, & &1.priority)
      assert priorities == Enum.sort(priorities, :desc)
    end

    test "update_role/2 updates role attributes", %{server: server} do
      roles = Servers.list_server_roles(server.id)
      mod_role = Enum.find(roles, &(&1.name == "Moderator"))

      {:ok, updated} = Servers.update_role(mod_role, %{color: "#ff0000"})
      assert updated.color == "#ff0000"
    end

    test "delete_role/1 removes a role", %{server: server} do
      {:ok, role} =
        Servers.create_server_role(server.id, %{name: "Temp Role", permissions: %{}, priority: 10})

      {:ok, _} = Servers.delete_role(role)
      assert length(Servers.list_server_roles(server.id)) == 4
    end
  end

  describe "server CRUD" do
    test "get_server/1 returns server" do
      user = create_user()
      {:ok, server} = Servers.create_server(%{name: "Test", creator_id: user.id})
      found = Servers.get_server(server.id)
      assert found.id == server.id
    end

    test "update_server/2 updates server attributes" do
      user = create_user()
      {:ok, server} = Servers.create_server(%{name: "Test", creator_id: user.id})
      {:ok, updated} = Servers.update_server(server, %{name: "Updated", description: "New desc"})
      assert updated.name == "Updated"
      assert updated.description == "New desc"
    end

    test "delete_server/1 deletes server" do
      user = create_user()
      {:ok, server} = Servers.create_server(%{name: "Test", creator_id: user.id})
      {:ok, _} = Servers.delete_server(server)
      assert Servers.get_server(server.id) == nil
    end
  end
end
