defmodule Cairn.Servers.PermissionsTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Servers}
  alias Cairn.Servers.Permissions

  defp create_user(attrs \\ %{}) do
    username = Map.get(attrs, :username, "user_#{System.unique_integer([:positive])}")

    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        username: username,
        password: "testpassword123!"
      })

    user
  end

  defp create_server_with_member do
    owner = create_user(%{username: "owner"})
    member = create_user(%{username: "member"})
    {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: owner.id})
    {:ok, _} = Servers.add_member(server.id, member.id)
    %{owner: owner, member: member, server: server}
  end

  describe "has_permission?/3" do
    test "server creator always has all permissions" do
      %{owner: owner, server: server} = create_server_with_member()

      for perm <- Permissions.permission_keys() do
        assert Permissions.has_permission?(server.id, owner.id, perm),
               "Creator should have #{perm}"
      end
    end

    test "regular member gets @everyone permissions" do
      %{member: member, server: server} = create_server_with_member()

      assert Permissions.has_permission?(server.id, member.id, "send_messages")
      assert Permissions.has_permission?(server.id, member.id, "read_messages")
      assert Permissions.has_permission?(server.id, member.id, "attach_files")
      assert Permissions.has_permission?(server.id, member.id, "use_voice")

      refute Permissions.has_permission?(server.id, member.id, "manage_channels")
      refute Permissions.has_permission?(server.id, member.id, "manage_server")
      refute Permissions.has_permission?(server.id, member.id, "kick_members")
      refute Permissions.has_permission?(server.id, member.id, "ban_members")
    end

    test "member with Moderator role gets moderator permissions" do
      %{member: member, server: server} = create_server_with_member()

      roles = Servers.list_server_roles(server.id)
      mod_role = Enum.find(roles, &(&1.name == "Moderator"))
      {:ok, _} = Servers.update_member_role(server.id, member.id, mod_role.id)

      assert Permissions.has_permission?(server.id, member.id, "manage_messages")
      assert Permissions.has_permission?(server.id, member.id, "kick_members")
      assert Permissions.has_permission?(server.id, member.id, "mute_members")

      refute Permissions.has_permission?(server.id, member.id, "manage_channels")
      refute Permissions.has_permission?(server.id, member.id, "manage_server")
    end

    test "non-member has no permissions" do
      outsider = create_user(%{username: "outsider"})
      owner = create_user(%{username: "svr_owner"})
      {:ok, server} = Servers.create_server(%{name: "Test", creator_id: owner.id})

      refute Permissions.has_permission?(server.id, outsider.id, "send_messages")
      refute Permissions.has_permission?(server.id, outsider.id, "read_messages")
    end
  end

  describe "effective_permissions/2" do
    test "returns full permission map for creator" do
      %{owner: owner, server: server} = create_server_with_member()

      perms = Permissions.effective_permissions(server.id, owner.id)

      for key <- Permissions.permission_keys() do
        assert Map.get(perms, key) == true,
               "Creator should have #{key} in effective_permissions"
      end
    end

    test "returns @everyone permissions for regular member" do
      %{member: member, server: server} = create_server_with_member()

      perms = Permissions.effective_permissions(server.id, member.id)

      assert perms["send_messages"] == true
      assert perms["read_messages"] == true
      assert perms["attach_files"] == true
      assert perms["use_voice"] == true
      assert Map.get(perms, "manage_server") in [nil, false]
    end

    test "admin role grants all except manage_server" do
      %{member: member, server: server} = create_server_with_member()

      roles = Servers.list_server_roles(server.id)
      admin_role = Enum.find(roles, &(&1.name == "Admin"))
      {:ok, _} = Servers.update_member_role(server.id, member.id, admin_role.id)

      perms = Permissions.effective_permissions(server.id, member.id)

      assert perms["manage_channels"] == true
      assert perms["manage_roles"] == true
      assert perms["ban_members"] == true
      assert Map.get(perms, "manage_server") in [nil, false]
    end
  end

  describe "permission_keys/0" do
    test "returns the 15 protocol permissions" do
      keys = Permissions.permission_keys()
      assert length(keys) == 15
      assert "send_messages" in keys
      assert "manage_server" in keys
    end
  end
end
