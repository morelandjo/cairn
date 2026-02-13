defmodule Cairn.Identity do
  @moduledoc """
  The Identity context — `did:cairn` self-certifying identity with
  hash-chained operation log, rotation key support, and DID document resolution.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Identity.Operation

  @doc """
  Creates a DID for a user given their signing and rotation public keys.

  Generates the genesis operation, signs it with the rotation private key,
  computes the DID from the hash of the signed genesis, and stores everything.

  Returns `{:ok, did}` or `{:error, reason}`.
  """
  def create_did(user, rotation_private_key, opts \\ []) do
    handle = Keyword.get(opts, :handle, user.username)
    config = Application.get_env(:cairn, :federation, [])
    service = Keyword.get(opts, :service, Keyword.get(config, :domain, "localhost"))

    signing_key_mb = multibase_encode(user.identity_public_key)
    rotation_key_mb = multibase_encode(user.rotation_public_key)

    payload = %{
      "type" => "create",
      "signingKey" => signing_key_mb,
      "rotationKey" => rotation_key_mb,
      "handle" => handle,
      "service" => service,
      "prev" => nil
    }

    canonical = Operation.canonical_json(payload)
    signature = :crypto.sign(:eddsa, :none, canonical, [rotation_private_key, :ed25519])

    # DID = did:cairn:<base58(SHA-256(canonical_json(signed_genesis_op)))>
    signed_data = canonical <> signature
    hash = :crypto.hash(:sha256, signed_data)
    did = "did:cairn:" <> base58_encode(hash)

    attrs = %{
      did: did,
      seq: 0,
      operation_type: "create",
      payload: payload,
      signature: signature,
      prev_hash: nil,
      user_id: user.id
    }

    case %Operation{} |> Operation.changeset(attrs) |> Repo.insert() do
      {:ok, _op} -> {:ok, did}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Rotates the user's signing key. Creates a new operation in the chain
  signed by the current rotation key.

  Returns `{:ok, operation}` or `{:error, reason}`.
  """
  def rotate_signing_key(did, new_signing_key_bytes, rotation_private_key) do
    with {:ok, ops} <- get_operation_chain(did),
         {:ok, prev_op} <- last_operation(ops) do
      prev_hash = hash_operation(prev_op)
      new_seq = prev_op.seq + 1

      payload = %{
        "type" => "rotate_signing_key",
        "key" => multibase_encode(new_signing_key_bytes),
        "prev" => prev_hash
      }

      canonical = Operation.canonical_json(payload)
      signature = :crypto.sign(:eddsa, :none, canonical, [rotation_private_key, :ed25519])

      attrs = %{
        did: did,
        seq: new_seq,
        operation_type: "rotate_signing_key",
        payload: payload,
        signature: signature,
        prev_hash: prev_hash,
        user_id: prev_op.user_id
      }

      %Operation{} |> Operation.changeset(attrs) |> Repo.insert()
    end
  end

  @doc """
  Rotates the rotation key itself. The operation is signed by the
  **current** rotation key before it gets replaced.

  Returns `{:ok, operation}` or `{:error, reason}`.
  """
  def rotate_rotation_key(did, new_rotation_key_bytes, current_rotation_private_key) do
    with {:ok, ops} <- get_operation_chain(did),
         {:ok, prev_op} <- last_operation(ops) do
      prev_hash = hash_operation(prev_op)
      new_seq = prev_op.seq + 1

      payload = %{
        "type" => "rotate_rotation_key",
        "key" => multibase_encode(new_rotation_key_bytes),
        "prev" => prev_hash
      }

      canonical = Operation.canonical_json(payload)

      signature =
        :crypto.sign(:eddsa, :none, canonical, [current_rotation_private_key, :ed25519])

      attrs = %{
        did: did,
        seq: new_seq,
        operation_type: "rotate_rotation_key",
        payload: payload,
        signature: signature,
        prev_hash: prev_hash,
        user_id: prev_op.user_id
      }

      %Operation{} |> Operation.changeset(attrs) |> Repo.insert()
    end
  end

  @doc """
  Resolves a DID to a DID document by replaying the operation chain.

  Returns `{:ok, did_document}` or `{:error, reason}`.
  """
  def resolve_did(did) do
    with {:ok, ops} <- get_operation_chain(did),
         :ok <- verify_operation_chain(ops) do
      {:ok, build_did_document(did, ops)}
    end
  end

  @doc """
  Verifies the integrity of an operation chain.

  Checks:
  1. Genesis operation has `prev: null` and `seq: 0`
  2. Each subsequent operation's `prev_hash` matches the hash of the prior operation
  3. Each operation's signature is valid against the rotation key active at that point
  4. DID derivation from genesis matches the stated DID

  Returns `:ok` or `{:error, reason}`.
  """
  def verify_operation_chain([]), do: {:error, :empty_chain}

  def verify_operation_chain([genesis | _rest] = ops) do
    with :ok <- verify_genesis(genesis),
         :ok <- verify_did_derivation(genesis),
         :ok <- verify_chain_links(ops),
         :ok <- verify_signatures(ops) do
      :ok
    end
  end

  @doc """
  Returns the full operation chain for a DID, ordered by sequence number.
  """
  def get_operation_chain(did) do
    ops =
      from(o in Operation,
        where: o.did == ^did,
        order_by: [asc: o.seq]
      )
      |> Repo.all()

    if ops == [] do
      {:error, :did_not_found}
    else
      {:ok, ops}
    end
  end

  @doc """
  Returns the operations chain as a list of maps (for API serialization).
  """
  def get_operations_for_api(did) do
    from(o in Operation,
      where: o.did == ^did,
      order_by: [asc: o.seq],
      select: %{
        seq: o.seq,
        operation_type: o.operation_type,
        payload: o.payload,
        signature: o.signature,
        prev_hash: o.prev_hash,
        inserted_at: o.inserted_at
      }
    )
    |> Repo.all()
  end

  # ── DID Document Construction ──

  defp build_did_document(did, ops) do
    state = replay_operations(ops)

    doc = %{
      "@context" => ["https://www.w3.org/ns/did/v1"],
      "id" => did,
      "verificationMethod" => [
        %{
          "id" => "#{did}#signing",
          "type" => "Ed25519VerificationKey2020",
          "controller" => did,
          "publicKeyMultibase" => state.signing_key
        }
      ],
      "authentication" => ["#{did}#signing"],
      "service" => [
        %{
          "id" => "#{did}#home",
          "type" => "CairnPDS",
          "serviceEndpoint" => "https://#{state.service}"
        }
      ]
    }

    if state.handle do
      Map.put(doc, "alsoKnownAs", ["at://#{state.handle}@#{state.service}"])
    else
      doc
    end
  end

  defp replay_operations(ops) do
    Enum.reduce(ops, %{signing_key: nil, rotation_key: nil, handle: nil, service: nil}, fn op,
                                                                                           state ->
      case op.operation_type do
        "create" ->
          %{
            state
            | signing_key: op.payload["signingKey"],
              rotation_key: op.payload["rotationKey"],
              handle: op.payload["handle"],
              service: op.payload["service"]
          }

        "rotate_signing_key" ->
          %{state | signing_key: op.payload["key"]}

        "rotate_rotation_key" ->
          %{state | rotation_key: op.payload["key"]}

        "update_handle" ->
          %{state | handle: op.payload["handle"]}

        _ ->
          state
      end
    end)
  end

  # ── Chain Verification ──

  defp verify_genesis(%Operation{seq: 0, prev_hash: nil, operation_type: "create"} = op) do
    if op.payload["prev"] == nil do
      :ok
    else
      {:error, :invalid_genesis_prev}
    end
  end

  defp verify_genesis(_), do: {:error, :invalid_genesis}

  defp verify_did_derivation(%Operation{did: did} = genesis) do
    canonical = Operation.canonical_json(genesis.payload)
    signed_data = canonical <> genesis.signature
    hash = :crypto.hash(:sha256, signed_data)
    expected_did = "did:cairn:" <> base58_encode(hash)

    if did == expected_did do
      :ok
    else
      {:error, :did_mismatch}
    end
  end

  defp verify_chain_links([_genesis]), do: :ok

  defp verify_chain_links([prev, next | rest]) do
    expected_hash = hash_operation(prev)

    if next.prev_hash == expected_hash and next.payload["prev"] == expected_hash do
      verify_chain_links([next | rest])
    else
      {:error, {:chain_break, next.seq}}
    end
  end

  defp verify_signatures(ops) do
    verify_signatures_with_state(ops, nil)
  end

  defp verify_signatures_with_state([], _rotation_key), do: :ok

  defp verify_signatures_with_state([op | rest], rotation_key) do
    # For genesis, the rotation key is in the payload itself
    key_to_verify =
      if op.seq == 0 do
        multibase_decode!(op.payload["rotationKey"])
      else
        rotation_key
      end

    canonical = Operation.canonical_json(op.payload)

    case :crypto.verify(:eddsa, :none, canonical, op.signature, [key_to_verify, :ed25519]) do
      true ->
        # Track rotation key changes
        new_rotation_key =
          if op.operation_type == "rotate_rotation_key" do
            multibase_decode!(op.payload["key"])
          else
            key_to_verify
          end

        verify_signatures_with_state(rest, new_rotation_key)

      false ->
        {:error, {:invalid_signature, op.seq}}
    end
  end

  # ── Helpers ──

  defp last_operation([]), do: {:error, :empty_chain}
  defp last_operation(ops), do: {:ok, List.last(ops)}

  @doc false
  def hash_operation(%Operation{} = op) do
    canonical = Operation.canonical_json(op.payload)
    signed_data = canonical <> op.signature
    hash = :crypto.hash(:sha256, signed_data)
    Base.encode16(hash, case: :lower)
  end

  @doc """
  Encodes bytes as multibase (base58btc prefix 'z').
  """
  def multibase_encode(bytes) when is_binary(bytes) do
    "z" <> base58_encode(bytes)
  end

  @doc """
  Decodes a multibase-encoded string (base58btc prefix 'z').
  """
  def multibase_decode("z" <> encoded) do
    base58_decode(encoded)
  end

  def multibase_decode(_), do: {:error, :unsupported_multibase}

  defp multibase_decode!(str) do
    {:ok, bytes} = multibase_decode(str)
    bytes
  end

  # ── Base58 (Bitcoin alphabet) ──

  @base58_alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  @doc false
  def base58_encode(<<>>), do: ""

  def base58_encode(bytes) when is_binary(bytes) do
    # Count leading zero bytes
    leading_zeros = count_leading_zeros(bytes, 0)

    # Convert binary to integer
    num = :binary.decode_unsigned(bytes)

    # Encode the non-zero part to base58
    encoded =
      if num == 0 do
        ""
      else
        base58_encode_int(num, []) |> to_string()
      end

    # Prepend '1' for each leading zero byte
    String.duplicate("1", leading_zeros) <> encoded
  end

  defp base58_encode_int(0, acc), do: acc

  defp base58_encode_int(num, acc) do
    char = Enum.at(@base58_alphabet, rem(num, 58))
    base58_encode_int(div(num, 58), [char | acc])
  end

  defp count_leading_zeros(<<0, rest::binary>>, count),
    do: count_leading_zeros(rest, count + 1)

  defp count_leading_zeros(_, count), do: count

  @doc false
  def base58_decode(str) when is_binary(str) do
    chars = String.to_charlist(str)

    # Count leading '1's (representing zero bytes)
    leading_ones = count_leading_ones(chars, 0)

    # Build the integer from base58
    result =
      Enum.reduce_while(chars, 0, fn char, acc ->
        case Enum.find_index(@base58_alphabet, &(&1 == char)) do
          nil -> {:halt, {:error, :invalid_base58}}
          idx -> {:cont, acc * 58 + idx}
        end
      end)

    case result do
      {:error, _} = err ->
        err

      num ->
        bytes =
          if num == 0 do
            <<>>
          else
            :binary.encode_unsigned(num)
          end

        {:ok, String.duplicate(<<0>>, leading_ones) <> bytes}
    end
  end

  defp count_leading_ones([?1 | rest], count), do: count_leading_ones(rest, count + 1)
  defp count_leading_ones(_, count), do: count
end
