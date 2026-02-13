defmodule Cairn.Federation.NodeIdentityTest do
  use ExUnit.Case, async: false

  alias Cairn.Federation.NodeIdentity

  setup do
    # Stop any existing NodeIdentity from other tests
    case Process.whereis(NodeIdentity) do
      nil -> :ok
      pid when is_pid(pid) -> if Process.alive?(pid), do: GenServer.stop(pid)
    end

    # Use a unique subdirectory under the project's tmp for isolation
    base = Path.join(System.tmp_dir!(), "cairn_node_identity_test")
    File.mkdir_p!(base)
    tmp_dir = Path.join(base, "#{:erlang.unique_integer([:positive, :monotonic])}")
    File.mkdir_p!(tmp_dir)
    key_path = Path.join(tmp_dir, "test_node.key")

    on_exit(fn ->
      case Process.whereis(NodeIdentity) do
        nil -> :ok
        pid when is_pid(pid) -> if Process.alive?(pid), do: GenServer.stop(pid)
      end

      File.rm_rf!(tmp_dir)
    end)

    %{key_path: key_path, tmp_dir: tmp_dir}
  end

  describe "key generation" do
    test "generates a new key pair on first start", %{key_path: key_path} do
      refute File.exists?(key_path)

      {:ok, pid} = NodeIdentity.start_link(key_path: key_path)

      assert File.exists?(key_path)
      assert %File.Stat{mode: mode} = File.stat!(key_path)
      # Check owner-only read/write (0600)
      assert Bitwise.band(mode, 0o777) == 0o600

      GenServer.stop(pid)
    end

    test "loads existing key on restart", %{key_path: key_path} do
      {:ok, pid1} = NodeIdentity.start_link(key_path: key_path)
      pub1 = GenServer.call(pid1, :public_key)
      node_id1 = GenServer.call(pid1, :node_id)
      GenServer.stop(pid1)

      # Start again — should load same key
      {:ok, pid2} = NodeIdentity.start_link(key_path: key_path)
      pub2 = GenServer.call(pid2, :public_key)
      node_id2 = GenServer.call(pid2, :node_id)
      GenServer.stop(pid2)

      assert pub1 == pub2
      assert node_id1 == node_id2
    end
  end

  describe "public_key/0" do
    test "returns a 32-byte binary", %{key_path: key_path} do
      {:ok, pid} = NodeIdentity.start_link(key_path: key_path)

      pub = GenServer.call(pid, :public_key)
      assert is_binary(pub)
      assert byte_size(pub) == 32

      GenServer.stop(pid)
    end
  end

  describe "node_id/0" do
    test "returns hex-encoded SHA-256 of public key", %{key_path: key_path} do
      {:ok, pid} = NodeIdentity.start_link(key_path: key_path)

      node_id = GenServer.call(pid, :node_id)
      pub = GenServer.call(pid, :public_key)

      expected = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)
      assert node_id == expected
      assert String.length(node_id) == 64

      GenServer.stop(pid)
    end
  end

  describe "sign/1 and verify/3" do
    test "sign and verify roundtrip succeeds", %{key_path: key_path} do
      {:ok, pid} = NodeIdentity.start_link(key_path: key_path)

      message = "hello federation"
      signature = GenServer.call(pid, {:sign, message})
      pub = GenServer.call(pid, :public_key)

      assert is_binary(signature)
      assert NodeIdentity.verify(message, signature, pub)

      GenServer.stop(pid)
    end

    test "verify rejects tampered message", %{key_path: key_path} do
      {:ok, pid} = NodeIdentity.start_link(key_path: key_path)

      message = "hello federation"
      signature = GenServer.call(pid, {:sign, message})
      pub = GenServer.call(pid, :public_key)

      refute NodeIdentity.verify("tampered message", signature, pub)

      GenServer.stop(pid)
    end

    test "verify rejects wrong public key", %{key_path: key_path} do
      {:ok, pid} = NodeIdentity.start_link(key_path: key_path)

      message = "hello federation"
      signature = GenServer.call(pid, {:sign, message})

      # Generate a different key pair
      {other_pub, _other_priv} = :crypto.generate_key(:eddsa, :ed25519)

      refute NodeIdentity.verify(message, signature, other_pub)

      GenServer.stop(pid)
    end

    test "verify handles invalid inputs gracefully", %{key_path: _key_path} do
      refute NodeIdentity.verify("msg", "bad_sig", "bad_key")
    end
  end

  describe "error handling" do
    test "fails with invalid key file", %{tmp_dir: tmp_dir} do
      bad_path = Path.join(tmp_dir, "bad.key")
      File.write!(bad_path, "not a valid erlang term")

      Process.flag(:trap_exit, true)
      result = NodeIdentity.start_link(key_path: bad_path)
      assert {:error, {:key_init_failed, :invalid_key_format}} = result
    end
  end
end
