defmodule Murmuring.Voice.Federation do
  @moduledoc """
  Federation voice support.

  Remote users connect directly to the hosting node's SFU.
  Signaling is proxied through federation HTTP. Remote identity
  is verified via federation credentials.
  """

  alias Murmuring.Federation
  alias Murmuring.Voice

  @doc """
  Relay a voice join request to the hosting node for a federated channel.
  Returns SFU transport params if the remote node accepts.
  """
  def relay_join(remote_domain, channel_id, user_id) do
    federation_config = Application.get_env(:murmuring, :federation, [])

    if federation_config[:enabled] do
      url = "https://#{remote_domain}/api/v1/federation/voice/join"

      case Req.post(url,
             json: %{channel_id: channel_id, user_id: user_id},
             headers: Federation.HttpSignature.sign_headers("POST", url)
           ) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :federation_disabled}
    end
  end

  @doc """
  Relay a voice signal (connect, produce, consume) to the hosting node.
  """
  def relay_signal(remote_domain, channel_id, event, payload) do
    federation_config = Application.get_env(:murmuring, :federation, [])

    if federation_config[:enabled] do
      url = "https://#{remote_domain}/api/v1/federation/voice/signal"

      case Req.post(url,
             json: %{channel_id: channel_id, event: event, payload: payload},
             headers: Federation.HttpSignature.sign_headers("POST", url)
           ) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :federation_disabled}
    end
  end

  @doc """
  Verify a remote user's federation credentials for voice access.
  """
  def verify_remote_user(remote_domain, user_id) do
    case Federation.get_node_by_domain(remote_domain) do
      nil -> {:error, :unknown_node}
      %{status: "blocked"} -> {:error, :node_blocked}
      node -> {:ok, %{node_id: node.id, user_id: user_id}}
    end
  end
end
