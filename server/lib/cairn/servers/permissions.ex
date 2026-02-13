defmodule Cairn.Servers.Permissions do
  @moduledoc """
  Permission resolution for server members.
  Resolves effective permissions from assigned roles using additive OR.
  Server creators bypass all permission checks.

  Channel-level overrides:
  1. Compute server-level permissions (additive OR across @everyone + member's roles)
  2. Apply channel role overrides sorted by role priority (low->high)
  3. Apply channel user-specific overrides (highest specificity)
  4. "deny" overrides "grant"; "inherit" falls through to server level
  5. Server creator still bypasses all
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Accounts.Role
  alias Cairn.Servers.{Server, ServerMember, MemberRole, ChannelPermissionOverride}

  @permission_keys ~w(
    send_messages read_messages manage_messages
    manage_channels manage_roles manage_server
    kick_members ban_members invite_members
    manage_webhooks attach_files use_voice
    mute_members deafen_members move_members
  )

  def permission_keys, do: @permission_keys

  @doc """
  Check if a user has a specific permission in a server.
  Server creators always have all permissions.
  """
  def has_permission?(server_id, user_id, permission) when is_binary(permission) do
    if server_creator?(server_id, user_id) do
      true
    else
      perms = effective_permissions(server_id, user_id)
      Map.get(perms, permission, false)
    end
  end

  @doc """
  Check if a user has a specific permission in a channel.
  Applies channel-level overrides on top of server permissions.
  """
  def has_channel_permission?(server_id, user_id, channel_id, permission)
      when is_binary(permission) do
    if server_creator?(server_id, user_id) do
      true
    else
      perms = effective_channel_permissions(server_id, user_id, channel_id)
      Map.get(perms, permission, false)
    end
  end

  @doc """
  Returns the full effective permission map for a user in a server.
  Combines @everyone role + the user's assigned roles (additive OR).
  """
  def effective_permissions(server_id, user_id) do
    if server_creator?(server_id, user_id) do
      Map.new(@permission_keys, fn k -> {k, true} end)
    else
      roles = get_user_roles(server_id, user_id)
      merge_permissions(roles)
    end
  end

  @doc """
  Returns effective permissions for a user in a specific channel.
  Applies channel overrides on top of server-level permissions.
  """
  def effective_channel_permissions(server_id, user_id, channel_id) do
    if server_creator?(server_id, user_id) do
      Map.new(@permission_keys, fn k -> {k, true} end)
    else
      server_perms = effective_permissions(server_id, user_id)
      apply_channel_overrides(server_perms, server_id, user_id, channel_id)
    end
  end

  defp server_creator?(server_id, user_id) do
    from(s in Server, where: s.id == ^server_id and s.creator_id == ^user_id)
    |> Repo.exists?()
  end

  defp get_user_roles(server_id, user_id) do
    member =
      from(sm in ServerMember,
        where: sm.server_id == ^server_id and sm.user_id == ^user_id
      )
      |> Repo.one()

    case member do
      nil ->
        []

      _ ->
        # Include @everyone role
        everyone_query =
          from r in Role,
            where: r.server_id == ^server_id and r.name == "@everyone"

        # Include the primary role from server_members
        primary_role_query =
          from sm in ServerMember,
            where: sm.server_id == ^server_id and sm.user_id == ^user_id,
            join: r in Role,
            on: r.id == sm.role_id,
            select: r

        # Include additional roles from server_member_roles join table
        additional_roles_query =
          from mr in MemberRole,
            where: mr.server_member_id == ^member.id,
            join: r in Role,
            on: r.id == mr.role_id,
            select: r

        everyone_roles = Repo.all(everyone_query)
        primary_roles = Repo.all(primary_role_query)
        additional_roles = Repo.all(additional_roles_query)

        (everyone_roles ++ primary_roles ++ additional_roles) |> Enum.uniq_by(& &1.id)
    end
  end

  defp merge_permissions(roles) do
    sorted = Enum.sort_by(roles, & &1.priority)

    Enum.reduce(sorted, %{}, fn role, acc ->
      Enum.reduce(role.permissions || %{}, acc, fn {key, value}, inner_acc ->
        if key in @permission_keys do
          current = Map.get(inner_acc, key, false)
          Map.put(inner_acc, key, current || value)
        else
          inner_acc
        end
      end)
    end)
  end

  defp apply_channel_overrides(server_perms, server_id, user_id, channel_id) do
    overrides =
      from(o in ChannelPermissionOverride,
        where: o.channel_id == ^channel_id,
        left_join: r in Role,
        on: o.role_id == r.id,
        select: %{
          role_id: o.role_id,
          user_id: o.user_id,
          permissions: o.permissions,
          role_priority: r.priority
        }
      )
      |> Repo.all()

    user_role_ids = get_user_role_ids(server_id, user_id)

    # Split into role overrides and user overrides
    {role_overrides, user_overrides} =
      Enum.split_with(overrides, fn o -> not is_nil(o.role_id) end)

    # Filter role overrides to only those matching user's roles, sort by priority
    applicable_role_overrides =
      role_overrides
      |> Enum.filter(fn o -> o.role_id in user_role_ids end)
      |> Enum.sort_by(fn o -> o.role_priority || 0 end)

    # Apply role overrides (low priority first)
    perms_after_roles =
      Enum.reduce(applicable_role_overrides, server_perms, fn override, acc ->
        apply_override(acc, override.permissions)
      end)

    # Apply user-specific overrides (highest specificity)
    user_override = Enum.find(user_overrides, fn o -> o.user_id == user_id end)

    if user_override do
      apply_override(perms_after_roles, user_override.permissions)
    else
      perms_after_roles
    end
  end

  defp apply_override(perms, override_permissions) do
    Enum.reduce(override_permissions, perms, fn {key, value}, acc ->
      if key in @permission_keys do
        case value do
          "grant" -> Map.put(acc, key, true)
          "deny" -> Map.put(acc, key, false)
          "inherit" -> acc
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  defp get_user_role_ids(server_id, user_id) do
    member =
      from(sm in ServerMember,
        where: sm.server_id == ^server_id and sm.user_id == ^user_id
      )
      |> Repo.one()

    case member do
      nil ->
        []

      _ ->
        everyone_ids =
          from(r in Role,
            where: r.server_id == ^server_id and r.name == "@everyone",
            select: r.id
          )
          |> Repo.all()

        primary_role_ids =
          if member.role_id, do: [member.role_id], else: []

        additional_role_ids =
          from(mr in MemberRole,
            where: mr.server_member_id == ^member.id,
            select: mr.role_id
          )
          |> Repo.all()

        (everyone_ids ++ primary_role_ids ++ additional_role_ids) |> Enum.uniq()
    end
  end
end
