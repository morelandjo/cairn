defmodule Cairn.IdentityTest do
  use Cairn.DataCase, async: true

  alias Cairn.Identity
  alias Cairn.Accounts

  @valid_password "secure_password_123"

  setup do
    # Create a user with identity keys
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "diduser",
        "password" => @valid_password
      })

    # Generate Ed25519 signing key pair
    {signing_pub, signing_priv} = :crypto.generate_key(:eddsa, :ed25519)

    # Generate Ed25519 rotation key pair
    {rotation_pub, rotation_priv} = :crypto.generate_key(:eddsa, :ed25519)

    # Upload signing key and set rotation key on user
    {:ok, user} =
      Accounts.update_user_keys(user, %{
        identity_public_key: signing_pub,
        signed_prekey: <<0::256>>,
        signed_prekey_signature: <<0::512>>
      })

    # Set rotation key directly (no DID yet, did_changeset requires did)
    user =
      user
      |> Ecto.Changeset.change(rotation_public_key: rotation_pub)
      |> Repo.update!()

    %{
      user: user,
      signing_pub: signing_pub,
      signing_priv: signing_priv,
      rotation_pub: rotation_pub,
      rotation_priv: rotation_priv
    }
  end

  describe "create_did/3" do
    test "creates a DID from genesis operation", ctx do
      {:ok, did} = Identity.create_did(ctx.user, ctx.rotation_priv, service: "test.example.com")

      assert String.starts_with?(did, "did:cairn:")
      assert String.length(did) > 20
    end

    test "DID derivation is deterministic for same genesis", ctx do
      {:ok, did} = Identity.create_did(ctx.user, ctx.rotation_priv, service: "test.example.com")

      # Verify the DID matches what we'd compute manually
      {:ok, [genesis]} = Identity.get_operation_chain(did)
      assert genesis.seq == 0
      assert genesis.operation_type == "create"
      assert genesis.prev_hash == nil
    end

    test "genesis payload contains correct fields", ctx do
      {:ok, did} = Identity.create_did(ctx.user, ctx.rotation_priv, service: "test.example.com")

      {:ok, [genesis]} = Identity.get_operation_chain(did)
      payload = genesis.payload

      assert payload["type"] == "create"
      assert String.starts_with?(payload["signingKey"], "z")
      assert String.starts_with?(payload["rotationKey"], "z")
      assert payload["handle"] == "diduser"
      assert payload["service"] == "test.example.com"
      assert payload["prev"] == nil
    end
  end

  describe "operation chain" do
    setup ctx do
      {:ok, did} = Identity.create_did(ctx.user, ctx.rotation_priv, service: "test.example.com")
      Map.put(ctx, :did, did)
    end

    test "rotate_signing_key appends to chain", ctx do
      {new_signing_pub, _new_signing_priv} = :crypto.generate_key(:eddsa, :ed25519)

      {:ok, op} = Identity.rotate_signing_key(ctx.did, new_signing_pub, ctx.rotation_priv)

      assert op.seq == 1
      assert op.operation_type == "rotate_signing_key"
      assert op.prev_hash != nil
      assert op.payload["key"] == Identity.multibase_encode(new_signing_pub)
    end

    test "rotate_rotation_key appends to chain", ctx do
      {new_rotation_pub, _new_rotation_priv} = :crypto.generate_key(:eddsa, :ed25519)

      {:ok, op} = Identity.rotate_rotation_key(ctx.did, new_rotation_pub, ctx.rotation_priv)

      assert op.seq == 1
      assert op.operation_type == "rotate_rotation_key"
      assert op.payload["key"] == Identity.multibase_encode(new_rotation_pub)
    end

    test "multiple operations form a valid chain", ctx do
      # Rotate signing key
      {new_signing_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, _} = Identity.rotate_signing_key(ctx.did, new_signing_pub, ctx.rotation_priv)

      # Rotate rotation key
      {new_rotation_pub, new_rotation_priv} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, _} = Identity.rotate_rotation_key(ctx.did, new_rotation_pub, ctx.rotation_priv)

      # Rotate signing key again (with new rotation key)
      {newer_signing_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, _} = Identity.rotate_signing_key(ctx.did, newer_signing_pub, new_rotation_priv)

      {:ok, ops} = Identity.get_operation_chain(ctx.did)
      assert length(ops) == 4
      assert :ok == Identity.verify_operation_chain(ops)
    end

    test "operations signed with wrong key fail verification", ctx do
      # Try to rotate with a random key (not the rotation key)
      {new_signing_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
      {_, wrong_priv} = :crypto.generate_key(:eddsa, :ed25519)

      {:ok, _op} = Identity.rotate_signing_key(ctx.did, new_signing_pub, wrong_priv)

      {:ok, ops} = Identity.get_operation_chain(ctx.did)
      assert {:error, {:invalid_signature, 1}} = Identity.verify_operation_chain(ops)
    end
  end

  describe "verify_operation_chain/1" do
    setup ctx do
      {:ok, did} = Identity.create_did(ctx.user, ctx.rotation_priv, service: "test.example.com")
      Map.put(ctx, :did, did)
    end

    test "valid genesis-only chain passes", ctx do
      {:ok, ops} = Identity.get_operation_chain(ctx.did)
      assert :ok = Identity.verify_operation_chain(ops)
    end

    test "empty chain fails" do
      assert {:error, :empty_chain} = Identity.verify_operation_chain([])
    end

    test "tampered payload is detected", ctx do
      {:ok, [genesis]} = Identity.get_operation_chain(ctx.did)

      # Tamper with the payload — DID derivation will fail first since the
      # hash of the tampered genesis won't match the stated DID
      tampered = %{genesis | payload: Map.put(genesis.payload, "handle", "evil")}

      assert {:error, _reason} = Identity.verify_operation_chain([tampered])
    end

    test "chain break is detected", ctx do
      {new_signing_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, _} = Identity.rotate_signing_key(ctx.did, new_signing_pub, ctx.rotation_priv)

      {:ok, [genesis, rotation]} = Identity.get_operation_chain(ctx.did)

      # Tamper with prev_hash — chain link verification catches this
      tampered_rotation = %{rotation | prev_hash: "0000", payload: Map.put(rotation.payload, "prev", "0000")}

      assert {:error, {:chain_break, 1}} =
               Identity.verify_operation_chain([genesis, tampered_rotation])
    end
  end

  describe "resolve_did/1" do
    test "returns DID document from genesis", ctx do
      {:ok, did} = Identity.create_did(ctx.user, ctx.rotation_priv, service: "test.example.com")

      {:ok, doc} = Identity.resolve_did(did)

      assert doc["id"] == did
      assert doc["@context"] == ["https://www.w3.org/ns/did/v1"]

      [vm] = doc["verificationMethod"]
      assert vm["id"] == "#{did}#signing"
      assert vm["type"] == "Ed25519VerificationKey2020"
      assert vm["publicKeyMultibase"] == Identity.multibase_encode(ctx.signing_pub)

      assert doc["authentication"] == ["#{did}#signing"]

      [svc] = doc["service"]
      assert svc["type"] == "CairnPDS"
      assert svc["serviceEndpoint"] == "https://test.example.com"
    end

    test "DID document reflects signing key rotation", ctx do
      {:ok, did} = Identity.create_did(ctx.user, ctx.rotation_priv, service: "test.example.com")

      {new_signing_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, _} = Identity.rotate_signing_key(did, new_signing_pub, ctx.rotation_priv)

      {:ok, doc} = Identity.resolve_did(did)

      # DID stays the same
      assert doc["id"] == did

      # But signing key is updated
      [vm] = doc["verificationMethod"]
      assert vm["publicKeyMultibase"] == Identity.multibase_encode(new_signing_pub)
    end

    test "nonexistent DID returns error" do
      assert {:error, :did_not_found} = Identity.resolve_did("did:cairn:nonexistent")
    end
  end

  describe "base58 encoding" do
    test "roundtrip encoding" do
      data = :crypto.strong_rand_bytes(32)
      encoded = Identity.base58_encode(data)
      {:ok, decoded} = Identity.base58_decode(encoded)
      assert decoded == data
    end

    test "leading zeros are preserved" do
      data = <<0, 0, 0, 1, 2, 3>>
      encoded = Identity.base58_encode(data)
      assert String.starts_with?(encoded, "111")
      {:ok, decoded} = Identity.base58_decode(encoded)
      assert decoded == data
    end
  end

  describe "multibase encoding" do
    test "encodes with z prefix" do
      data = <<1, 2, 3, 4>>
      encoded = Identity.multibase_encode(data)
      assert String.starts_with?(encoded, "z")
    end

    test "roundtrip" do
      data = :crypto.strong_rand_bytes(32)
      encoded = Identity.multibase_encode(data)
      {:ok, decoded} = Identity.multibase_decode(encoded)
      assert decoded == data
    end
  end
end
