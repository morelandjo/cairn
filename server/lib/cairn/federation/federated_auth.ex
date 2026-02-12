defmodule Murmuring.Federation.FederatedAuth do
  @moduledoc """
  Issues and verifies federated authentication tokens.

  A federated auth token allows a user on one instance to authenticate
  with a remote instance without re-registering. The token is signed by
  the home node's Ed25519 key and verified by the remote instance against
  the home node's public key from `federated_nodes`.

  Wire format: `base64url(json_payload).base64url(ed25519_signature)`
  """

  alias Murmuring.Federation
  alias Murmuring.Federation.NodeIdentity

  @max_clock_skew 300
  @token_ttl 3600

  @doc """
  Issues a federated auth token for the given user to authenticate with
  the target instance. Signed by the local node's Ed25519 key.
  """
  def issue_token(user, target_instance) do
    config = Application.get_env(:murmuring, :federation, [])
    domain = Keyword.get(config, :domain, "localhost")

    payload = %{
      "type" => "federated_auth",
      "did" => user.did,
      "username" => user.username,
      "display_name" => user.display_name,
      "home_instance" => domain,
      "target_instance" => target_instance,
      "public_key" => Base.encode64(user.identity_public_key || <<>>),
      "iat" => System.system_time(:second),
      "exp" => System.system_time(:second) + @token_ttl,
      "nonce" => Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    }

    payload_json = Jason.encode!(payload)
    payload_b64 = Base.url_encode64(payload_json, padding: false)
    signature = NodeIdentity.sign(payload_json)
    sig_b64 = Base.url_encode64(signature, padding: false)

    {:ok, "#{payload_b64}.#{sig_b64}"}
  end

  @doc """
  Verifies a federated auth token received from a remote user.

  Verification steps:
  1. Decode payload + signature
  2. Look up home_instance in federated_nodes (must be active)
  3. Verify Ed25519 signature against node's public key
  4. Check exp not expired, iat not too old
  5. Check target_instance matches local domain
  """
  def verify_token(token) do
    config = Application.get_env(:murmuring, :federation, [])
    local_domain = Keyword.get(config, :domain, "localhost")

    with {:ok, {payload, signature}} <- decode_token(token),
         {:ok, claims} <- decode_payload(payload),
         :ok <- verify_type(claims),
         :ok <- verify_target(claims, local_domain),
         :ok <- verify_timestamps(claims),
         {:ok, node} <- lookup_home_node(claims["home_instance"]),
         :ok <- verify_signature(payload, signature, node) do
      {:ok, claims}
    end
  end

  # ── Private ──

  defp decode_token(token) when is_binary(token) do
    case String.split(token, ".") do
      [payload_b64, sig_b64] ->
        with {:ok, payload} <- Base.url_decode64(payload_b64, padding: false),
             {:ok, signature} <- Base.url_decode64(sig_b64, padding: false) do
          {:ok, {payload, signature}}
        else
          _ -> {:error, :invalid_token_encoding}
        end

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp decode_payload(payload_json) do
    case Jason.decode(payload_json) do
      {:ok, claims} when is_map(claims) -> {:ok, claims}
      _ -> {:error, :invalid_token_payload}
    end
  end

  defp verify_type(%{"type" => "federated_auth"}), do: :ok
  defp verify_type(_), do: {:error, :invalid_token_type}

  defp verify_target(%{"target_instance" => target}, local_domain) do
    if target == local_domain do
      :ok
    else
      {:error, :wrong_target_instance}
    end
  end

  defp verify_timestamps(%{"iat" => iat, "exp" => exp}) do
    now = System.system_time(:second)

    cond do
      exp < now -> {:error, :token_expired}
      iat > now + @max_clock_skew -> {:error, :token_from_future}
      true -> :ok
    end
  end

  defp verify_timestamps(_), do: {:error, :missing_timestamps}

  defp lookup_home_node(home_instance) do
    case Federation.get_node_by_domain(home_instance) do
      nil ->
        {:error, :unknown_home_instance}

      %{status: "blocked"} ->
        {:error, :blocked_home_instance}

      %{status: "active"} = node ->
        {:ok, node}

      _ ->
        {:error, :inactive_home_instance}
    end
  end

  defp verify_signature(payload_json, signature, node) do
    public_key = node.public_key

    if NodeIdentity.verify(payload_json, signature, public_key) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end
end
