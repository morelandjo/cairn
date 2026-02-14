defmodule CairnWeb.FederationController do
  use CairnWeb, :controller

  alias Cairn.Federation
  alias Cairn.Federation.NodeIdentity

  @protocol_version "0.1.0"
  @supported_versions ["0.1.0"]

  @doc """
  GET /.well-known/cairn-federation

  Returns the node's federation metadata: node_id, domain, public_key,
  protocol version, inbox URL, and privacy manifest reference.
  """
  def federation_info(conn, _params) do
    config = Application.get_env(:cairn, :federation, [])
    domain = Keyword.get(config, :domain, "localhost")

    if Keyword.get(config, :enabled, false) do
      base = %{
        node_id: NodeIdentity.node_id(),
        domain: domain,
        public_key: NodeIdentity.public_key_base64(),
        protocol_version: @protocol_version,
        supported_versions: @supported_versions,
        inbox_url: Federation.local_url("/inbox"),
        privacy_manifest: Federation.local_url("/.well-known/privacy-manifest"),
        secure: Application.get_env(:cairn, :force_ssl, true)
      }

      response =
        case NodeIdentity.previous_public_key_base64() do
          nil -> base
          prev -> Map.put(base, :previous_public_key, prev)
        end

      json(conn, response)
    else
      conn
      |> put_status(404)
      |> json(%{error: "Federation is not enabled on this node"})
    end
  end

  @doc """
  GET /.well-known/privacy-manifest

  Returns configurable privacy practices: logging, retention,
  federation policies. Operators can customize via config.
  """
  def privacy_manifest(conn, _params) do
    config = Application.get_env(:cairn, :federation, [])

    if Keyword.get(config, :enabled, false) do
      privacy = Keyword.get(config, :privacy_manifest, %{})

      json(conn, %{
        version: "1.0",
        data_collection: %{
          ip_logging: Map.get(privacy, :ip_logging, false),
          message_retention_days: Map.get(privacy, :message_retention_days, nil),
          metadata_retention_days: Map.get(privacy, :metadata_retention_days, 30),
          analytics: Map.get(privacy, :analytics, false)
        },
        federation: %{
          strips_metadata: true,
          forwards_to_third_parties: false,
          e2ee_supported: true
        }
      })
    else
      conn
      |> put_status(404)
      |> json(%{error: "Federation is not enabled on this node"})
    end
  end

  @doc """
  GET /.well-known/webfinger?resource=acct:user@domain

  Returns a JRD (JSON Resource Descriptor) with the user's
  ActivityPub actor URI. 404 for unknown users.
  """
  def webfinger(conn, %{"resource" => resource}) do
    config = Application.get_env(:cairn, :federation, [])

    if Keyword.get(config, :enabled, false) do
      domain = Keyword.get(config, :domain, "localhost")

      case parse_resource(resource, domain) do
        {:ok, :acct, username} ->
          case Cairn.Accounts.get_user_by_username(username) do
            nil ->
              conn
              |> put_status(404)
              |> json(%{error: "User not found"})

            _user ->
              conn
              |> put_resp_header("content-type", "application/jrd+json")
              |> json(%{
                subject: resource,
                links: [
                  %{
                    rel: "self",
                    type: "application/activity+json",
                    href: Federation.local_url("/users/#{username}")
                  }
                ]
              })
          end

        {:ok, :did, did} ->
          case Cairn.Accounts.get_user_by_did(did) do
            nil ->
              conn
              |> put_status(404)
              |> json(%{error: "DID not found"})

            user ->
              conn
              |> put_resp_header("content-type", "application/jrd+json")
              |> json(%{
                subject: resource,
                links: [
                  %{
                    rel: "self",
                    type: "application/activity+json",
                    href: Federation.local_url("/users/#{user.username}")
                  },
                  %{
                    rel: "https://cairn.chat/ns/did",
                    type: "application/json",
                    href: Federation.local_url("/.well-known/did/#{did}")
                  }
                ]
              })
          end

        {:error, :invalid_resource} ->
          conn
          |> put_status(400)
          |> json(%{error: "Invalid resource format. Expected acct:user@domain or did:cairn:..."})

        {:error, :wrong_domain} ->
          conn
          |> put_status(404)
          |> json(%{error: "Resource not found on this domain"})
      end
    else
      conn
      |> put_status(404)
      |> json(%{error: "Federation is not enabled on this node"})
    end
  end

  def webfinger(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing required 'resource' parameter"})
  end

  @doc """
  GET /.well-known/did/:did — Resolves a DID to its DID document.
  """
  def resolve_did(conn, %{"did" => did_suffix}) do
    did = "did:cairn:" <> did_suffix

    case Cairn.Identity.resolve_did(did) do
      {:ok, document} ->
        conn
        |> put_resp_header("content-type", "application/did+json")
        |> json(document)

      {:error, :did_not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "DID not found"})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: "DID resolution failed: #{inspect(reason)}"})
    end
  end

  @doc """
  GET /.well-known/did/:did/operations — Returns the raw operation chain for a DID.
  """
  def did_operations(conn, %{"did" => did_suffix}) do
    did = "did:cairn:" <> did_suffix

    case Cairn.Identity.get_operations_for_api(did) do
      [] ->
        conn
        |> put_status(404)
        |> json(%{error: "DID not found"})

      ops ->
        json(conn, %{
          did: did,
          operations:
            Enum.map(ops, fn op ->
              %{
                seq: op.seq,
                operation_type: op.operation_type,
                payload: op.payload,
                signature: Base.encode64(op.signature),
                prev_hash: op.prev_hash,
                inserted_at: op.inserted_at
              }
            end)
        })
    end
  end

  @doc """
  GET /api/v1/federation/users/:did/keys

  Returns the X3DH key bundle for a user identified by DID.
  Used for cross-instance DM key exchange (node-to-node).
  """
  def user_keys_by_did(conn, %{"did" => did_suffix}) do
    did = "did:cairn:" <> did_suffix

    case Cairn.Accounts.get_user_by_did(did) do
      nil ->
        conn
        |> put_status(404)
        |> json(%{error: "User not found for DID"})

      user ->
        case Cairn.Keys.get_key_bundle(user.id) do
          {:ok, bundle} ->
            response = %{
              did: did,
              identity_public_key: Base.encode64(bundle.identity_public_key),
              signed_prekey: Base.encode64(bundle.signed_prekey),
              signed_prekey_signature: Base.encode64(bundle.signed_prekey_signature)
            }

            response =
              if bundle.one_time_prekey do
                Map.put(response, :one_time_prekey, %{
                  key_id: bundle.one_time_prekey.key_id,
                  public_key: Base.encode64(bundle.one_time_prekey.public_key)
                })
              else
                response
              end

            json(conn, response)

          {:error, :no_keys} ->
            conn
            |> put_status(404)
            |> json(%{error: "No keys uploaded for this user"})

          {:error, :not_found} ->
            conn
            |> put_status(404)
            |> json(%{error: "User not found"})
        end
    end
  end

  # ── Private ──

  defp parse_resource(resource, expected_domain) do
    cond do
      String.starts_with?(resource, "acct:") ->
        case Regex.run(~r/^acct:([^@]+)@(.+)$/, resource) do
          [_, username, domain] ->
            if domain == expected_domain do
              {:ok, :acct, username}
            else
              {:error, :wrong_domain}
            end

          _ ->
            {:error, :invalid_resource}
        end

      String.starts_with?(resource, "did:cairn:") ->
        {:ok, :did, resource}

      true ->
        {:error, :invalid_resource}
    end
  end
end
