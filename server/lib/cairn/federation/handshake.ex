defmodule Cairn.Federation.Handshake do
  @moduledoc """
  Federation handshake protocol: Follow/Accept between nodes.

  1. Initiator fetches remote's /.well-known/cairn-federation
  2. Validates protocol compatibility
  3. Sends Follow activity
  4. Remote responds with Accept
  """

  require Logger
  alias Cairn.Federation
  alias Cairn.Federation.DeliveryWorker
  alias Cairn.Federation.ActivityPub

  @doc """
  Initiate federation with a remote node by domain.
  Fetches their well-known, registers the node, sends Follow.
  """
  def initiate(remote_domain) do
    config = Application.get_env(:cairn, :federation, [])
    local_domain = Keyword.get(config, :domain, "localhost")
    allow_insecure = Keyword.get(config, :allow_insecure, false)

    with {:ok, well_known, secure} <- fetch_well_known(remote_domain, allow_insecure),
         :ok <- validate_protocol(well_known),
         {:ok, node} <- register_or_update_node(well_known, remote_domain, secure),
         :ok <- send_follow(node, local_domain) do
      {:ok, node}
    end
  end

  @doc "Handle an incoming Follow activity — auto-accept and activate the node."
  def handle_follow(activity, federated_node) do
    config = Application.get_env(:cairn, :federation, [])
    local_domain = Keyword.get(config, :domain, "localhost")

    # Activate the node
    {:ok, _node} = Federation.activate_node(federated_node)

    # Send Accept back
    accept =
      ActivityPub.wrap_activity(
        "Accept",
        Federation.local_url(),
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

  defp fetch_well_known(domain, allow_insecure) do
    https_url = "https://#{domain}/.well-known/cairn-federation"

    case Req.get(https_url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body, true}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Remote returned HTTP #{status}"}

      {:error, _reason} when allow_insecure ->
        Logger.warning("HTTPS failed for #{domain}, falling back to HTTP (allow_insecure=true)")
        http_url = "http://#{domain}/.well-known/cairn-federation"

        case Req.get(http_url, receive_timeout: 10_000) do
          {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
            {:ok, body, false}

          {:ok, %Req.Response{status: status}} ->
            {:error, "Remote returned HTTP #{status}"}

          {:error, reason} ->
            {:error, "Failed to reach #{domain}: #{inspect(reason)}"}
        end

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

  defp register_or_update_node(well_known, domain, secure) do
    case Federation.get_node_by_domain(domain) do
      nil ->
        Federation.register_node(%{
          domain: domain,
          node_id: well_known["node_id"],
          public_key: well_known["public_key"],
          inbox_url: well_known["inbox_url"],
          protocol_version: well_known["protocol_version"],
          privacy_manifest: well_known["privacy_manifest"] || %{},
          status: "pending",
          secure: secure
        })

      existing ->
        Federation.update_node(existing, %{
          node_id: well_known["node_id"],
          public_key: well_known["public_key"],
          inbox_url: well_known["inbox_url"],
          protocol_version: well_known["protocol_version"],
          secure: secure
        })
    end
  end

  defp send_follow(node, local_domain) do
    follow =
      ActivityPub.wrap_activity(
        "Follow",
        Federation.local_url(),
        Federation.node_url(node),
        local_domain
      )

    case DeliveryWorker.enqueue(node.inbox_url, follow, node.id) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
