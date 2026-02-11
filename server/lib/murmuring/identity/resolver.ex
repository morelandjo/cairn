defmodule Murmuring.Identity.Resolver do
  @moduledoc """
  Resolves remote actor URIs to federated users by fetching their profile
  and DID operation chain, verifying the chain, and caching the result.
  """

  alias Murmuring.Federation
  alias Murmuring.Identity

  @doc """
  Resolves a remote actor URI, fetching the actor profile and verifying
  its DID operation chain. Returns the local federated user record.

  Steps:
  1. Fetch actor profile from remote instance
  2. Extract DID from `alsoKnownAs`
  3. Fetch and verify the DID operation chain
  4. Upsert the federated user cache
  """
  def resolve_actor_uri(actor_uri) do
    with {:ok, actor} <- fetch_remote_actor(actor_uri),
         {:ok, did} <- extract_did(actor),
         {:ok, _ops} <- verify_remote_did(did, actor),
         {:ok, federated_user} <- upsert_federated_user(actor, did) do
      {:ok, federated_user}
    end
  end

  @doc """
  Verify a DID by fetching and replaying its operation chain from the
  home instance. Used for anti-impersonation verification.
  """
  def verify_did(did, home_instance) do
    url = "https://#{home_instance}/.well-known/did/#{did_suffix(did)}/operations"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"operations" => ops}}} ->
        operations = Enum.map(ops, &parse_operation/1)
        Identity.verify_operation_chain(operations)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_error, reason}}
    end
  end

  # ── Private ──

  defp fetch_remote_actor(actor_uri) do
    case Req.get(actor_uri,
           headers: [{"accept", "application/activity+json"}],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_error, reason}}
    end
  end

  defp extract_did(actor) do
    also_known_as = Map.get(actor, "alsoKnownAs", [])

    case Enum.find(also_known_as, &String.starts_with?(&1, "did:murmuring:")) do
      nil -> {:error, :no_did}
      did -> {:ok, did}
    end
  end

  defp verify_remote_did(did, actor) do
    # Extract the home instance from the actor's ID
    uri = URI.parse(actor["id"] || "")
    home_instance = uri.host

    if home_instance do
      case verify_did(did, home_instance) do
        :ok -> {:ok, :verified}
        error -> error
      end
    else
      {:error, :no_home_instance}
    end
  end

  defp upsert_federated_user(actor, did) do
    uri = URI.parse(actor["id"] || "")
    home_instance = uri.host || "unknown"

    # Extract the public key from the actor
    public_key =
      case deep_get(actor, ["publicKey", "publicKeyPem"]) do
        nil -> <<>>
        key when is_binary(key) -> key
      end

    attrs = %{
      did: did,
      username: actor["preferredUsername"] || "unknown",
      display_name: actor["name"],
      home_instance: home_instance,
      public_key: public_key,
      avatar_url: deep_get(actor, ["icon", "url"]),
      actor_uri: actor["id"],
      last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }

    Federation.get_or_create_federated_user(attrs)
  end

  defp did_suffix("did:murmuring:" <> suffix), do: suffix
  defp did_suffix(did), do: did

  defp parse_operation(op) do
    %Identity.Operation{
      seq: op["seq"],
      operation_type: op["operation_type"],
      payload: op["payload"],
      signature: Base.decode64!(op["signature"]),
      prev_hash: op["prev_hash"],
      did: nil
    }
  end

  defp deep_get(map, []), do: map

  defp deep_get(map, [key | rest]) when is_map(map) do
    deep_get(Map.get(map, key), rest)
  end

  defp deep_get(_, _), do: nil
end
