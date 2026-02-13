defmodule Cairn.StorageTest do
  use Cairn.DataCase, async: true

  alias Cairn.Storage.LocalBackend

  @test_data "hello, world!"
  @test_key "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e"

  setup do
    root = Application.get_env(:cairn, Cairn.Storage.LocalBackend)[:root]

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    :ok
  end

  describe "LocalBackend.put/3" do
    test "stores data and returns :ok" do
      assert :ok = LocalBackend.put(@test_key, @test_data, "text/plain")
    end

    test "creates sharded directory structure" do
      :ok = LocalBackend.put(@test_key, @test_data, "text/plain")
      root = Application.get_env(:cairn, Cairn.Storage.LocalBackend)[:root]
      shard = String.slice(@test_key, 0, 2)
      assert File.exists?(Path.join([root, shard, @test_key]))
    end
  end

  describe "LocalBackend.get/1" do
    test "retrieves stored data" do
      :ok = LocalBackend.put(@test_key, @test_data, "text/plain")
      assert {:ok, @test_data} = LocalBackend.get(@test_key)
    end

    test "returns :not_found for missing key" do
      assert {:error, :not_found} = LocalBackend.get("nonexistent_key")
    end
  end

  describe "LocalBackend.delete/1" do
    test "removes stored file" do
      :ok = LocalBackend.put(@test_key, @test_data, "text/plain")
      assert :ok = LocalBackend.delete(@test_key)
      assert {:error, :not_found} = LocalBackend.get(@test_key)
    end

    test "returns :ok for already missing key" do
      assert :ok = LocalBackend.delete("nonexistent_key")
    end
  end

  describe "LocalBackend.exists?/1" do
    test "returns true for stored file" do
      :ok = LocalBackend.put(@test_key, @test_data, "text/plain")
      assert LocalBackend.exists?(@test_key)
    end

    test "returns false for missing file" do
      refute LocalBackend.exists?("nonexistent_key")
    end
  end
end
