defmodule Murmuring.Servers.ChannelPermissionsTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.{Accounts, Chat, Servers}
  alias Murmuring.Servers.Permissions

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "cpuser_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_server_and_channel do
    owner = create_user("owner")
    member = create_user("member")

    {:ok, server} = Servers.create_server(%{name: "PermTest", creator_id: owner.id})
    {:ok, _} = Servers.add_member(server.id, member.id)
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    %{owner: owner, member: member, server: server, channel: channel}
  end

  describe "channel permission overrides" do
    test "deny override blocks a server-level grant" do
      %{member: member, server: server, channel: channel} = setup_server_and_channel()

      # Member can send_messages at server level (from @everyone role)
      assert Permissions.has_permission?(server.id, member.id, "send_messages")

      # Deny send_messages for @everyone in this channel
      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "deny"}
        })

      # Now member should be denied at channel level
      refute Permissions.has_channel_permission?(
               server.id,
               member.id,
               channel.id,
               "send_messages"
             )

      # But still granted at server level
      assert Permissions.has_permission?(server.id, member.id, "send_messages")
    end

    test "grant override adds a permission not in server level" do
      %{member: member, server: server, channel: channel} = setup_server_and_channel()

      # Member does NOT have manage_messages at server level
      refute Permissions.has_permission?(server.id, member.id, "manage_messages")

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"manage_messages" => "grant"}
        })

      assert Permissions.has_channel_permission?(
               server.id,
               member.id,
               channel.id,
               "manage_messages"
             )
    end

    test "inherit falls through to server level" do
      %{member: member, server: server, channel: channel} = setup_server_and_channel()

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "inherit"}
        })

      # Should still be granted (falls through to server level)
      assert Permissions.has_channel_permission?(
               server.id,
               member.id,
               channel.id,
               "send_messages"
             )
    end

    test "user-specific override takes precedence over role override" do
      %{member: member, server: server, channel: channel} = setup_server_and_channel()

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      # Deny for @everyone role
      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "deny"}
        })

      # Grant for specific user
      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          user_id: member.id,
          permissions: %{"send_messages" => "grant"}
        })

      # User override wins
      assert Permissions.has_channel_permission?(
               server.id,
               member.id,
               channel.id,
               "send_messages"
             )
    end

    test "server creator bypasses channel overrides" do
      %{owner: owner, server: server, channel: channel} = setup_server_and_channel()

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "deny"}
        })

      # Owner always bypasses
      assert Permissions.has_channel_permission?(server.id, owner.id, channel.id, "send_messages")
    end
  end

  describe "multi-role" do
    test "additional roles add permissions via join table" do
      %{member: member, server: server} = setup_server_and_channel()

      # Member doesn't have manage_messages
      refute Permissions.has_permission?(server.id, member.id, "manage_messages")

      # Give member the Moderator role via join table
      mod_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "Moderator"))

      {:ok, _} = Servers.add_member_role(server.id, member.id, mod_role.id)

      # Now member should have manage_messages (from Moderator role)
      assert Permissions.has_permission?(server.id, member.id, "manage_messages")
    end

    test "removing a role removes its permissions" do
      %{member: member, server: server} = setup_server_and_channel()

      mod_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "Moderator"))

      {:ok, _} = Servers.add_member_role(server.id, member.id, mod_role.id)
      assert Permissions.has_permission?(server.id, member.id, "manage_messages")

      :ok = Servers.remove_member_role(server.id, member.id, mod_role.id)
      refute Permissions.has_permission?(server.id, member.id, "manage_messages")
    end

    test "list_member_roles returns additional roles" do
      %{member: member, server: server} = setup_server_and_channel()

      mod_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "Moderator"))

      {:ok, _} = Servers.add_member_role(server.id, member.id, mod_role.id)

      roles = Servers.list_member_roles(server.id, member.id)
      assert length(roles) == 1
      assert hd(roles).name == "Moderator"
    end
  end

  describe "override CRUD" do
    test "set_channel_override creates and updates" do
      %{server: server, channel: channel} = setup_server_and_channel()

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      {:ok, override} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "deny"}
        })

      assert override.permissions == %{"send_messages" => "deny"}

      # Update existing
      {:ok, updated} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "grant"}
        })

      assert updated.id == override.id
      assert updated.permissions == %{"send_messages" => "grant"}
    end

    test "delete_channel_override removes override" do
      %{server: server, channel: channel} = setup_server_and_channel()

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "deny"}
        })

      assert length(Servers.list_channel_overrides(channel.id)) == 1

      :ok = Servers.delete_channel_override(channel.id, role_id: everyone_role.id)
      assert length(Servers.list_channel_overrides(channel.id)) == 0
    end

    test "list_channel_overrides returns all overrides for a channel" do
      %{member: member, server: server, channel: channel} = setup_server_and_channel()

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          role_id: everyone_role.id,
          permissions: %{"send_messages" => "deny"}
        })

      {:ok, _} =
        Servers.set_channel_override(channel.id, %{
          user_id: member.id,
          permissions: %{"send_messages" => "grant"}
        })

      overrides = Servers.list_channel_overrides(channel.id)
      assert length(overrides) == 2
    end
  end
end
