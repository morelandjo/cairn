defmodule CairnWeb.Admin.FederationController do
  use CairnWeb, :controller

  alias Cairn.Federation

  def index(conn, _params) do
    nodes = Federation.list_nodes()

    json(conn, %{
      nodes:
        Enum.map(nodes, fn n ->
          %{
            id: n.id,
            domain: n.domain,
            node_id: n.node_id,
            status: n.status,
            protocol_version: n.protocol_version,
            inserted_at: n.inserted_at
          }
        end)
    })
  end

  def create(conn, %{"domain" => domain} = params) do
    attrs = %{
      domain: domain,
      node_id: params["node_id"] || "",
      public_key: params["public_key"] || "",
      inbox_url: params["inbox_url"] || "https://#{domain}/inbox",
      protocol_version: params["protocol_version"] || "0.1.0",
      privacy_manifest: params["privacy_manifest"] || %{},
      status: params["status"] || "pending"
    }

    case Federation.register_node(attrs) do
      {:ok, node} ->
        conn
        |> put_status(:created)
        |> json(%{
          node: %{
            id: node.id,
            domain: node.domain,
            node_id: node.node_id,
            status: node.status,
            protocol_version: node.protocol_version
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Federation.get_node(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Node not found"})

      node ->
        json(conn, %{
          node: %{
            id: node.id,
            domain: node.domain,
            node_id: node.node_id,
            public_key: node.public_key,
            inbox_url: node.inbox_url,
            status: node.status,
            protocol_version: node.protocol_version,
            privacy_manifest: node.privacy_manifest,
            inserted_at: node.inserted_at,
            updated_at: node.updated_at
          }
        })
    end
  end

  def block(conn, %{"id" => id}) do
    case Federation.get_node(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Node not found"})

      node ->
        {:ok, node} = Federation.block_node(node)
        json(conn, %{node: %{id: node.id, domain: node.domain, status: node.status}})
    end
  end

  def unblock(conn, %{"id" => id}) do
    case Federation.get_node(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Node not found"})

      node ->
        {:ok, node} = Federation.unblock_node(node)
        json(conn, %{node: %{id: node.id, domain: node.domain, status: node.status}})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Federation.get_node(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Node not found"})

      node ->
        {:ok, _} = Federation.delete_node(node)
        json(conn, %{ok: true})
    end
  end

  def rotate_key(conn, _params) do
    config = Application.get_env(:cairn, :federation, [])

    if Keyword.get(config, :enabled, false) do
      :ok = Cairn.Federation.NodeIdentity.rotate_key()

      Cairn.Audit.log("federation.key_rotated",
        actor_id: conn.assigns.current_user.id,
        metadata: %{new_node_id: Cairn.Federation.NodeIdentity.node_id()}
      )

      json(conn, %{
        ok: true,
        node_id: Cairn.Federation.NodeIdentity.node_id(),
        public_key: Cairn.Federation.NodeIdentity.public_key_base64(),
        previous_public_key: Cairn.Federation.NodeIdentity.previous_public_key_base64(),
        message: "Key rotated. Previous key available for 7-day grace period."
      })
    else
      conn
      |> put_status(400)
      |> json(%{error: "Federation is not enabled"})
    end
  end

  def activities(conn, params) do
    opts = [
      limit: min(String.to_integer(params["limit"] || "50"), 100),
      node_id: params["node_id"],
      direction: params["direction"]
    ]

    activities = Federation.list_activities(opts)

    json(conn, %{
      activities:
        Enum.map(activities, fn a ->
          %{
            id: a.id,
            activity_type: a.activity_type,
            direction: a.direction,
            actor_uri: a.actor_uri,
            object_uri: a.object_uri,
            status: a.status,
            error: a.error,
            node_domain: a.federated_node.domain,
            inserted_at: a.inserted_at
          }
        end)
    })
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
