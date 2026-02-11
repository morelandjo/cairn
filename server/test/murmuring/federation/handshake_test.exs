defmodule Murmuring.Federation.HandshakeTest do
  use Murmuring.DataCase, async: false

  alias Murmuring.Federation
  alias Murmuring.Federation.Handshake
  alias Murmuring.Federation.NodeIdentity

  setup do
    # Start NodeIdentity for signing — stop any existing instance first
    tmp_dir = Path.join(System.tmp_dir!(), "murmuring_hs_test")
    File.mkdir_p!(tmp_dir)
    key_path = Path.join(tmp_dir, "test_#{:erlang.unique_integer([:positive, :monotonic])}.key")

    # Stop any running NodeIdentity (may be left over from app supervisor or prior test)
    try do
      GenServer.stop(NodeIdentity, :normal, 5_000)
    catch
      :exit, {:noproc, _} -> :ok
    end

    # Brief sleep to let the name deregister
    Process.sleep(10)

    {:ok, _} = NodeIdentity.start_link(key_path: key_path)

    original_config = Application.get_env(:murmuring, :federation, [])

    Application.put_env(:murmuring, :federation,
      enabled: true,
      domain: "local.example.com"
    )

    on_exit(fn ->
      try do
        GenServer.stop(NodeIdentity, :normal, 5_000)
      catch
        :exit, {:noproc, _} -> :ok
      end

      Application.put_env(:murmuring, :federation, original_config)
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  describe "handle_follow/2" do
    test "activates the node and enqueues Accept" do
      {:ok, node} =
        Federation.register_node(%{
          domain: "handshake.example.com",
          node_id: "hs1",
          public_key: "key",
          inbox_url: "https://handshake.example.com/inbox",
          protocol_version: "0.1.0",
          status: "pending"
        })

      activity = %{
        "type" => "Follow",
        "actor" => "https://handshake.example.com",
        "object" => "https://local.example.com"
      }

      assert :ok = Handshake.handle_follow(activity, node)

      # Node should be activated
      updated = Federation.get_node(node.id)
      assert updated.status == "active"
    end
  end

  describe "handle_accept/2" do
    test "activates the pending node" do
      {:ok, node} =
        Federation.register_node(%{
          domain: "accept.example.com",
          node_id: "ac1",
          public_key: "key",
          inbox_url: "https://accept.example.com/inbox",
          protocol_version: "0.1.0",
          status: "pending"
        })

      activity = %{
        "type" => "Accept",
        "actor" => "https://accept.example.com",
        "object" => %{"type" => "Follow"}
      }

      assert :ok = Handshake.handle_accept(activity, node)

      updated = Federation.get_node(node.id)
      assert updated.status == "active"
    end
  end
end
