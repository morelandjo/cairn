defmodule Murmuring.Federation.Handshake do
  @moduledoc """
  Federation handshake protocol: Follow/Accept between nodes.

  1. Initiator fetches remote's /.well-known/murmuring-federation
  2. Validates protocol compatibility
  3. Sends Follow activity
  4. Remote responds with Accept
  """

  require Logger
  alias Murmuring.Federation
  alias Murmuring.Federation.DeliveryWorker
  alias Murmuring.Federation.ActivityPub

  @doc """
  Initiate federation with a remote node by domain.
  Fetches their well-known, registers the node, sends Follow.
  """
  def initiate(remote_domain) do
    config = Application.get_env(:murmuring, :federation, [])
    local_domain = Keyword.get(config, :domain, "localhost")

    with {:ok, well_known} <- fetch_well_known(remote_domain),
         :ok <- validate_protocol(well_known),
         {:ok, node} <- register_or_update_node(well_known, remote_domain),
         :ok <- send_follow(node, local_domain) do
      {:ok, node}
    end
  end

  @doc "Handle an incoming Follow activity — auto-accept and activate the node."
  def handle_follow(activity, federated_node) do
    config = Application.get_env(:murmuring, :federation, [])
    local_domain = Keyword.get(config, :domain, "localhost")

    # Activate the node
    {:ok, _node} = Federation.activate_node(federated_node)

    # Send Accept back
    accept =
      ActivityPub.wrap_activity(
        "Accept",
        "https://#{local_domain}",
        activity,
        local_domain
      )

    DeliveryWorker.enqueue(federated_node.inbox_url, accept, federated_node.id)

    :ok
  end

  @doc "Handle an incoming Accept activity — activate the node."
  def handle_accept(_activity, federated_node) do
    {:ok, _node} = Federation.activate_node(federated_node)
    :ok
  end

  # ── Private ──

  defp fetch_well_known(domain) do
    url = "https://#{domain}/.well-known/murmuring-federation"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Remote returned HTTP #{status}"}

      {:error, reason} ->
        {:error, "Failed to reach #{domain}: #{inspect(reason)}"}
    end
  end

  defp validate_protocol(%{"protocol_version" => version, "supported_versions" => supported}) do
    if "0.1.0" in supported or version == "0.1.0" do
      :ok
    else
      {:error, "Incompatible protocol version: #{version}"}
    end
  end

  defp validate_protocol(_), do: {:error, "Invalid well-known response"}

  defp register_or_update_node(well_known, domain) do
    case Federation.get_node_by_domain(domain) do
      nil ->
        Federation.register_node(%{
          domain: domain,
          node_id: well_known["node_id"],
          public_key: well_known["public_key"],
          inbox_url: well_known["inbox_url"],
          protocol_version: well_known["protocol_version"],
          privacy_manifest: well_known["privacy_manifest"] || %{},
          status: "pending"
        })

      existing ->
        Federation.update_node(existing, %{
          node_id: well_known["node_id"],
          public_key: well_known["public_key"],
          inbox_url: well_known["inbox_url"],
          protocol_version: well_known["protocol_version"]
        })
    end
  end

  defp send_follow(node, local_domain) do
    follow =
      ActivityPub.wrap_activity(
        "Follow",
        "https://#{local_domain}",
        "https://#{node.domain}",
        local_domain
      )

    case DeliveryWorker.enqueue(node.inbox_url, follow, node.id) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
