defmodule Cairn.Federation do
  @moduledoc """
  Context for managing federation: federated nodes and activities.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Federation.FederatedNode
  alias Cairn.Federation.FederatedUser
  alias Cairn.Federation.FederationActivity

  # ── URL Helpers ──

  @doc "Build a URL for the local node using the correct scheme."
  def local_url(path \\ "") do
    scheme = if Application.get_env(:cairn, :force_ssl, true), do: "https", else: "http"
    "#{scheme}://#{config_domain()}#{path}"
  end

  @doc "Build a URL for a remote federated node using its known transport security."
  def node_url(%FederatedNode{} = node, path \\ "") do
    scheme = if node.secure, do: "https", else: "http"
    "#{scheme}://#{node.domain}#{path}"
  end

  defp config_domain do
    config = Application.get_env(:cairn, :federation, [])
    Keyword.get(config, :domain, "localhost")
  end

  # ── Federated Nodes ──

  def list_nodes do
    Repo.all(from n in FederatedNode, order_by: [asc: n.domain])
  end

  def list_nodes_by_status(status) do
    Repo.all(from n in FederatedNode, where: n.status == ^status, order_by: [asc: n.domain])
  end

  def get_node(id), do: Repo.get(FederatedNode, id)

  def get_node_by_domain(domain) do
    Repo.get_by(FederatedNode, domain: domain)
  end

  def get_node_by_node_id(node_id) do
    Repo.get_by(FederatedNode, node_id: node_id)
  end

  def register_node(attrs) do
    %FederatedNode{}
    |> FederatedNode.changeset(attrs)
    |> Repo.insert()
  end

  def update_node(%FederatedNode{} = node, attrs) do
    node
    |> FederatedNode.changeset(attrs)
    |> Repo.update()
  end

  def activate_node(%FederatedNode{} = node) do
    update_node(node, %{status: "active"})
  end

  def block_node(%FederatedNode{} = node) do
    update_node(node, %{status: "blocked"})
  end

  def unblock_node(%FederatedNode{} = node) do
    update_node(node, %{status: "active"})
  end

  def delete_node(%FederatedNode{} = node) do
    Repo.delete(node)
  end

  def active_node?(domain) do
    Repo.exists?(from n in FederatedNode, where: n.domain == ^domain and n.status == "active")
  end

  def blocked_node?(domain) do
    Repo.exists?(from n in FederatedNode, where: n.domain == ^domain and n.status == "blocked")
  end

  # ── Federated Users ──

  def get_federated_user_by_did(did) do
    Repo.get_by(FederatedUser, did: did)
  end

  def get_federated_user_by_actor_uri(actor_uri) do
    Repo.get_by(FederatedUser, actor_uri: actor_uri)
  end

  def get_federated_user(id), do: Repo.get(FederatedUser, id)

  @doc """
  Get or create a federated user by DID. If the user exists, updates their
  profile data. If not, creates a new record.
  """
  def get_or_create_federated_user(attrs) do
    case get_federated_user_by_did(attrs.did || attrs[:did]) do
      nil ->
        %FederatedUser{}
        |> FederatedUser.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> FederatedUser.changeset(attrs)
        |> Repo.update()
    end
  end

  # ── Federation Activities ──

  def log_activity(attrs) do
    %FederationActivity{}
    |> FederationActivity.changeset(attrs)
    |> Repo.insert()
  end

  def list_activities(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    node_id = Keyword.get(opts, :node_id)
    direction = Keyword.get(opts, :direction)

    query =
      from a in FederationActivity,
        order_by: [desc: a.inserted_at],
        limit: ^limit,
        preload: [:federated_node]

    query =
      if node_id do
        from a in query, where: a.federated_node_id == ^node_id
      else
        query
      end

    query =
      if direction do
        from a in query, where: a.direction == ^direction
      else
        query
      end

    Repo.all(query)
  end

  def update_activity(%FederationActivity{} = activity, attrs) do
    activity
    |> FederationActivity.changeset(attrs)
    |> Repo.update()
  end
end
