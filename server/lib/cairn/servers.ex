defmodule Murmuring.Servers do
  @moduledoc """
  The Servers context — server/guild CRUD and membership management.
  """

  import Ecto.Query
  alias Murmuring.Repo
  alias Murmuring.Servers.{Server, ServerMember, MemberRole, ChannelPermissionOverride}
  alias Murmuring.Accounts.Role

  # Server CRUD

  def create_server(attrs) do
    Repo.transaction(fn ->
      changeset = Server.changeset(%Server{}, attrs)

      case Repo.insert(changeset) do
        {:ok, server} ->
          # Create default roles for the server
          {:ok, everyone_role} =
            create_server_role(server.id, %{
              name: "@everyone",
              permissions: %{
                "send_messages" => true,
                "read_messages" => true,
                "attach_files" => true,
                "use_voice" => true
              },
              priority: 0
            })

          _mod_role =
            create_server_role(server.id, %{
              name: "Moderator",
              permissions: %{
                "send_messages" => true,
                "read_messages" => true,
                "manage_messages" => true,
                "kick_members" => true,
                "mute_members" => true,
                "deafen_members" => true,
                "move_members" => true,
                "attach_files" => true,
                "use_voice" => true
              },
              priority: 50
            })

          _admin_role =
            create_server_role(server.id, %{
              name: "Admin",
              permissions: %{
                "send_messages" => true,
                "read_messages" => true,
                "manage_messages" => true,
                "manage_channels" => true,
                "manage_roles" => true,
                "kick_members" => true,
                "ban_members" => true,
                "invite_members" => true,
                "manage_webhooks" => true,
                "attach_files" => true,
                "use_voice" => true,
                "mute_members" => true,
                "deafen_members" => true,
                "move_members" => true
              },
              priority: 90
            })

          {:ok, owner_role} =
            create_server_role(server.id, %{
              name: "Owner",
              permissions: %{
                "send_messages" => true,
                "read_messages" => true,
                "manage_messages" => true,
                "manage_channels" => true,
                "manage_roles" => true,
                "manage_server" => true,
                "kick_members" => true,
                "ban_members" => true,
                "invite_members" => true,
                "manage_webhooks" => true,
                "attach_files" => true,
                "use_voice" => true,
                "mute_members" => true,
                "deafen_members" => true,
                "move_members" => true
              },
              priority: 100
            })

          # Add creator as owner member
          {:ok, _member} =
            %ServerMember{}
            |> ServerMember.changeset(%{
              server_id: server.id,
              user_id: server.creator_id,
              role_id: owner_role.id
            })
            |> Repo.insert()

          %{server | server_members: [], roles: [everyone_role]}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def get_server!(id), do: Repo.get!(Server, id)

  def get_server(id), do: Repo.get(Server, id)

  def update_server(%Server{} = server, attrs) do
    server
    |> Server.changeset(attrs)
    |> Repo.update()
  end

  def delete_server(%Server{} = server) do
    Repo.delete(server)
  end

  def list_user_servers(user_id) do
    from(s in Server,
      join: sm in ServerMember,
      on: sm.server_id == s.id,
      where: sm.user_id == ^user_id,
      order_by: [asc: s.name],
      select: s
    )
    |> Repo.all()
  end

  # Membership

  def add_member(server_id, user_id, role_id \\ nil) do
    if Murmuring.Moderation.is_banned?(server_id, user_id) do
      {:error, :banned}
    else
      role_id = role_id || get_everyone_role_id(server_id)

      %ServerMember{}
      |> ServerMember.changeset(%{server_id: server_id, user_id: user_id, role_id: role_id})
      |> Repo.insert()
    end
  end

  def remove_member(server_id, user_id) do
    from(sm in ServerMember,
      where: sm.server_id == ^server_id and sm.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  def is_member?(server_id, user_id) do
    from(sm in ServerMember,
      where: sm.server_id == ^server_id and sm.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  def get_member(server_id, user_id) do
    Repo.get_by(ServerMember, server_id: server_id, user_id: user_id)
  end

  def list_members(server_id) do
    from(sm in ServerMember,
      where: sm.server_id == ^server_id,
      join: u in assoc(sm, :user),
      left_join: r in assoc(sm, :role),
      select: %{
        id: u.id,
        username: u.username,
        display_name: u.display_name,
        role_id: sm.role_id,
        role_name: r.name
      }
    )
    |> Repo.all()
  end

  def member_count(server_id) do
    from(sm in ServerMember, where: sm.server_id == ^server_id, select: count(sm.id))
    |> Repo.one()
  end

  def update_member_role(server_id, user_id, role_id) do
    case get_member(server_id, user_id) do
      nil ->
        {:error, :not_found}

      member ->
        member
        |> ServerMember.changeset(%{role_id: role_id})
        |> Repo.update()
    end
  end

  # Roles

  def create_server_role(server_id, attrs) do
    # Ensure string keys and set server_id
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("server_id", server_id)

    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
  end

  def list_server_roles(server_id) do
    from(r in Role,
      where: r.server_id == ^server_id,
      order_by: [desc: r.priority]
    )
    |> Repo.all()
  end

  def get_role!(id), do: Repo.get!(Role, id)

  def update_role(%Role{} = role, attrs) do
    role
    |> Role.changeset(attrs)
    |> Repo.update()
  end

  def delete_role(%Role{} = role) do
    Repo.delete(role)
  end

  defp get_everyone_role_id(server_id) do
    from(r in Role,
      where: r.server_id == ^server_id and r.name == "@everyone",
      select: r.id
    )
    |> Repo.one()
  end

  # Multi-role management

  def add_member_role(server_id, user_id, role_id) do
    case get_member(server_id, user_id) do
      nil ->
        {:error, :not_found}

      member ->
        %MemberRole{}
        |> MemberRole.changeset(%{server_member_id: member.id, role_id: role_id})
        |> Repo.insert()
    end
  end

  def remove_member_role(server_id, user_id, role_id) do
    case get_member(server_id, user_id) do
      nil ->
        {:error, :not_found}

      member ->
        from(mr in MemberRole,
          where: mr.server_member_id == ^member.id and mr.role_id == ^role_id
        )
        |> Repo.delete_all()

        :ok
    end
  end

  def list_member_roles(server_id, user_id) do
    case get_member(server_id, user_id) do
      nil ->
        []

      member ->
        from(mr in MemberRole,
          where: mr.server_member_id == ^member.id,
          join: r in Role,
          on: r.id == mr.role_id,
          select: %{id: r.id, name: r.name, priority: r.priority, color: r.color}
        )
        |> Repo.all()
    end
  end

  # Channel permission overrides

  def set_channel_override(channel_id, attrs) do
    # Try to find existing override
    existing =
      cond do
        attrs[:role_id] || attrs["role_id"] ->
          rid = attrs[:role_id] || attrs["role_id"]
          Repo.get_by(ChannelPermissionOverride, channel_id: channel_id, role_id: rid)

        attrs[:user_id] || attrs["user_id"] ->
          uid = attrs[:user_id] || attrs["user_id"]
          Repo.get_by(ChannelPermissionOverride, channel_id: channel_id, user_id: uid)

        true ->
          nil
      end

    case existing do
      nil ->
        %ChannelPermissionOverride{}
        |> ChannelPermissionOverride.changeset(Map.put(attrs, :channel_id, channel_id))
        |> Repo.insert()

      override ->
        override
        |> ChannelPermissionOverride.changeset(attrs)
        |> Repo.update()
    end
  end

  def delete_channel_override(channel_id, opts) do
    query =
      cond do
        opts[:role_id] ->
          from(o in ChannelPermissionOverride,
            where: o.channel_id == ^channel_id and o.role_id == ^opts[:role_id]
          )

        opts[:user_id] ->
          from(o in ChannelPermissionOverride,
            where: o.channel_id == ^channel_id and o.user_id == ^opts[:user_id]
          )
      end

    Repo.delete_all(query)
    :ok
  end

  def list_channel_overrides(channel_id) do
    from(o in ChannelPermissionOverride,
      where: o.channel_id == ^channel_id,
      left_join: r in Role,
      on: o.role_id == r.id,
      select: %{
        id: o.id,
        role_id: o.role_id,
        user_id: o.user_id,
        permissions: o.permissions,
        role_name: r.name
      }
    )
    |> Repo.all()
  end

  # ── Federated Members ──

  alias Murmuring.Servers.FederatedMember

  def add_federated_member(server_id, federated_user_id, role_id \\ nil) do
    role_id = role_id || get_everyone_role_id(server_id)

    %FederatedMember{}
    |> FederatedMember.changeset(%{
      server_id: server_id,
      federated_user_id: federated_user_id,
      role_id: role_id
    })
    |> Repo.insert()
  end

  def is_federated_member?(server_id, federated_user_id) do
    from(fm in FederatedMember,
      where: fm.server_id == ^server_id and fm.federated_user_id == ^federated_user_id
    )
    |> Repo.exists?()
  end

  def list_federated_members(server_id) do
    from(fm in FederatedMember,
      where: fm.server_id == ^server_id,
      join: fu in assoc(fm, :federated_user),
      left_join: r in assoc(fm, :role),
      select: %{
        id: fu.id,
        username: fu.username,
        display_name: fu.display_name,
        home_instance: fu.home_instance,
        did: fu.did,
        role_id: fm.role_id,
        role_name: r.name,
        is_federated: true
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns both local and federated members of a server.
  """
  def list_all_members(server_id) do
    local = list_members(server_id) |> Enum.map(&Map.put(&1, :is_federated, false))
    federated = list_federated_members(server_id)
    local ++ federated
  end
end
