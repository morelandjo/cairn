defmodule MurmuringWeb.ServerController do
  use MurmuringWeb, :controller

  alias Murmuring.{Chat, Servers}
  alias Murmuring.Servers.Permissions

  # GET /api/v1/servers
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    servers = Servers.list_user_servers(user_id)

    json(conn, %{
      servers: Enum.map(servers, &serialize_server/1)
    })
  end

  # POST /api/v1/servers
  def create(conn, params) do
    user_id = conn.assigns.current_user.id

    case Servers.create_server(Map.put(params, "creator_id", user_id)) do
      {:ok, server} ->
        conn
        |> put_status(:created)
        |> json(%{server: serialize_server(server)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  # GET /api/v1/servers/:id
  def show(conn, %{"id" => id}) do
    case Servers.get_server(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "server not found"})

      server ->
        json(conn, %{server: serialize_server(server)})
    end
  end

  # PUT /api/v1/servers/:id
  def update(conn, %{"id" => id} = params) do
    user_id = conn.assigns.current_user.id

    with server when not is_nil(server) <- Servers.get_server(id),
         true <- Permissions.has_permission?(server.id, user_id, "manage_server") do
      case Servers.update_server(server, params) do
        {:ok, updated} ->
          json(conn, %{server: serialize_server(updated)})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    else
      nil -> conn |> put_status(:not_found) |> json(%{error: "server not found"})
      false -> conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    end
  end

  # DELETE /api/v1/servers/:id
  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    with server when not is_nil(server) <- Servers.get_server(id),
         true <- Permissions.has_permission?(server.id, user_id, "manage_server") do
      {:ok, _} = Servers.delete_server(server)
      json(conn, %{ok: true})
    else
      nil -> conn |> put_status(:not_found) |> json(%{error: "server not found"})
      false -> conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    end
  end

  # GET /api/v1/servers/:server_id/members
  def members(conn, %{"server_id" => server_id}) do
    members = Servers.list_members(server_id)
    json(conn, %{members: members})
  end

  # GET /api/v1/servers/:server_id/channels
  def channels(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id
    channels = Chat.list_user_server_channels(server_id, user_id)

    json(conn, %{channels: Enum.map(channels, &serialize_channel/1)})
  end

  # POST /api/v1/servers/:server_id/channels
  def create_channel(conn, %{"server_id" => server_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_channels") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      channel_params = Map.put(params, "server_id", server_id)

      case Chat.create_channel(channel_params) do
        {:ok, channel} ->
          Chat.add_member(channel.id, user_id, "owner")

          conn
          |> put_status(:created)
          |> json(%{channel: serialize_channel(channel)})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # GET /api/v1/servers/:server_id/roles
  def roles(conn, %{"server_id" => server_id}) do
    roles = Servers.list_server_roles(server_id)

    json(conn, %{
      roles:
        Enum.map(roles, fn r ->
          %{
            id: r.id,
            name: r.name,
            permissions: r.permissions,
            priority: r.priority,
            color: r.color
          }
        end)
    })
  end

  # POST /api/v1/servers/:server_id/roles
  def create_role(conn, %{"server_id" => server_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Servers.create_server_role(server_id, params) do
        {:ok, role} ->
          conn
          |> put_status(:created)
          |> json(%{
            role: %{
              id: role.id,
              name: role.name,
              permissions: role.permissions,
              priority: role.priority,
              color: role.color
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # PUT /api/v1/servers/:server_id/roles/:role_id
  def update_role(conn, %{"server_id" => server_id, "role_id" => role_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      role = Servers.get_role!(role_id)

      case Servers.update_role(role, params) do
        {:ok, updated} ->
          json(conn, %{
            role: %{
              id: updated.id,
              name: updated.name,
              permissions: updated.permissions,
              priority: updated.priority,
              color: updated.color
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/roles/:role_id
  def delete_role(conn, %{"server_id" => server_id, "role_id" => role_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      role = Servers.get_role!(role_id)
      {:ok, _} = Servers.delete_role(role)
      json(conn, %{ok: true})
    end
  end

  # POST /api/v1/servers/:server_id/join
  def join(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    case Servers.add_member(server_id, user_id) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> conn |> put_status(:conflict) |> json(%{error: "already a member"})
    end
  end

  # POST /api/v1/servers/:server_id/leave
  def leave(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id
    Servers.remove_member(server_id, user_id)
    json(conn, %{ok: true})
  end

  # GET /api/v1/servers/:server_id/categories
  def list_categories(conn, %{"server_id" => server_id}) do
    categories = Chat.list_categories(server_id)

    json(conn, %{
      categories:
        Enum.map(categories, fn c ->
          %{id: c.id, name: c.name, position: c.position, server_id: c.server_id}
        end)
    })
  end

  # POST /api/v1/servers/:server_id/categories
  def create_category(conn, %{"server_id" => server_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_channels") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Chat.create_category(Map.put(params, "server_id", server_id)) do
        {:ok, category} ->
          conn
          |> put_status(:created)
          |> json(%{
            category: %{
              id: category.id,
              name: category.name,
              position: category.position,
              server_id: category.server_id
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # PUT /api/v1/servers/:server_id/categories/:category_id
  def update_category(conn, %{"server_id" => server_id, "category_id" => category_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_channels") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      category = Chat.get_category!(category_id)

      case Chat.update_category(category, params) do
        {:ok, updated} ->
          json(conn, %{
            category: %{id: updated.id, name: updated.name, position: updated.position}
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/categories/:category_id
  def delete_category(conn, %{"server_id" => server_id, "category_id" => category_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_channels") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      category = Chat.get_category!(category_id)
      {:ok, _} = Chat.delete_category(category)
      json(conn, %{ok: true})
    end
  end

  # PUT /api/v1/servers/:server_id/channels/reorder
  def reorder_channels(conn, %{"server_id" => server_id, "channels" => channels}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_channels") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      {:ok, _} = Chat.reorder_channels(channels)
      json(conn, %{ok: true})
    end
  end

  # PUT /api/v1/servers/:id/channels/:cid/overrides/role/:role_id
  def set_role_override(
        conn,
        %{"id" => server_id, "cid" => channel_id, "role_id" => role_id} = params
      ) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Servers.set_channel_override(channel_id, %{
             role_id: role_id,
             permissions: params["permissions"] || %{}
           }) do
        {:ok, override} ->
          json(conn, %{
            override: %{
              id: override.id,
              role_id: override.role_id,
              permissions: override.permissions
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:id/channels/:cid/overrides/role/:role_id
  def delete_role_override(conn, %{"id" => server_id, "cid" => channel_id, "role_id" => role_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      Servers.delete_channel_override(channel_id, role_id: role_id)
      json(conn, %{ok: true})
    end
  end

  # PUT /api/v1/servers/:id/channels/:cid/overrides/user/:user_id
  def set_user_override(
        conn,
        %{"id" => server_id, "cid" => channel_id, "user_id" => target_user_id} = params
      ) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Servers.set_channel_override(channel_id, %{
             user_id: target_user_id,
             permissions: params["permissions"] || %{}
           }) do
        {:ok, override} ->
          json(conn, %{
            override: %{
              id: override.id,
              user_id: override.user_id,
              permissions: override.permissions
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:id/channels/:cid/overrides/user/:user_id
  def delete_user_override(conn, %{
        "id" => server_id,
        "cid" => channel_id,
        "user_id" => target_user_id
      }) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      Servers.delete_channel_override(channel_id, user_id: target_user_id)
      json(conn, %{ok: true})
    end
  end

  # GET /api/v1/servers/:id/channels/:cid/overrides
  def list_overrides(conn, %{"id" => server_id, "cid" => channel_id}) do
    user_id = conn.assigns.current_user.id

    unless Servers.is_member?(server_id, user_id) do
      conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    else
      overrides = Servers.list_channel_overrides(channel_id)
      json(conn, %{overrides: overrides})
    end
  end

  # POST /api/v1/servers/:id/members/:uid/roles/:role_id
  def add_member_role(conn, %{"id" => server_id, "uid" => target_user_id, "role_id" => role_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Servers.add_member_role(server_id, target_user_id, role_id) do
        {:ok, _} ->
          json(conn, %{ok: true})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "member not found"})

        {:error, changeset} ->
          conn |> put_status(:conflict) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:id/members/:uid/roles/:role_id
  def remove_member_role(conn, %{"id" => server_id, "uid" => target_user_id, "role_id" => role_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_roles") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Servers.remove_member_role(server_id, target_user_id, role_id) do
        :ok ->
          json(conn, %{ok: true})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "member not found"})
      end
    end
  end

  defp serialize_channel(c) do
    %{
      id: c.id,
      name: c.name,
      type: c.type,
      description: c.description,
      topic: c.topic,
      server_id: c.server_id,
      position: c.position,
      category_id: c.category_id,
      slow_mode_seconds: c.slow_mode_seconds,
      history_accessible: c.history_accessible
    }
  end

  defp serialize_server(server) do
    %{
      id: server.id,
      name: server.name,
      description: server.description,
      icon_key: server.icon_key,
      creator_id: server.creator_id,
      inserted_at: server.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
