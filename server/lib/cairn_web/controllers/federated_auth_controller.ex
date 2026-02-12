defmodule CairnWeb.FederatedAuthController do
  use CairnWeb, :controller

  alias Cairn.Federation.FederatedAuth
  alias Cairn.Servers

  @doc """
  POST /api/v1/federation/auth-token
  Authenticated — issue a federated token for the target domain.
  """
  def issue_token(conn, %{"target_instance" => target_instance}) do
    user = conn.assigns.current_user

    if is_nil(user.did) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "User must have a DID to use federated auth"})
    else
      {:ok, token} = FederatedAuth.issue_token(user, target_instance)
      json(conn, %{token: token})
    end
  end

  def issue_token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "target_instance is required"})
  end

  @doc """
  POST /api/v1/federated/join/:server_id
  Federated token — join a server as a federated user.
  """
  def join_server(conn, %{"server_id" => server_id}) do
    federated_user = conn.assigns.federated_user

    case Servers.get_server(server_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Server not found"})

      server ->
        if Servers.is_federated_member?(server.id, federated_user.id) do
          json(conn, %{ok: true, already_member: true})
        else
          case Servers.add_federated_member(server.id, federated_user.id) do
            {:ok, _member} ->
              conn |> put_status(:created) |> json(%{ok: true, server_id: server.id})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{errors: format_errors(changeset)})
          end
        end
    end
  end

  @doc """
  GET /api/v1/federated/servers/:id/channels
  Federated token — list channels in a server.
  """
  def server_channels(conn, %{"id" => server_id}) do
    federated_user = conn.assigns.federated_user

    if Servers.is_federated_member?(server_id, federated_user.id) do
      channels = Cairn.Chat.list_server_channels(server_id)

      json(conn, %{
        channels:
          Enum.map(channels, fn ch ->
            %{
              id: ch.id,
              name: ch.name,
              type: ch.type,
              position: ch.position
            }
          end)
      })
    else
      conn |> put_status(:forbidden) |> json(%{error: "Not a member of this server"})
    end
  end

  @doc """
  POST /api/v1/federated/invites/:code/use
  Federated token — use an invite to join a server.
  """
  def use_invite(conn, %{"code" => code}) do
    federated_user = conn.assigns.federated_user

    case Cairn.Chat.get_invite_by_code(code) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Invite not found or expired"})

      invite ->
        if Servers.is_federated_member?(invite.server_id, federated_user.id) do
          json(conn, %{ok: true, already_member: true, server_id: invite.server_id})
        else
          case Servers.add_federated_member(invite.server_id, federated_user.id) do
            {:ok, _member} ->
              conn
              |> put_status(:created)
              |> json(%{ok: true, server_id: invite.server_id})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{errors: format_errors(changeset)})
          end
        end
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
