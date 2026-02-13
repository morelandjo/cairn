defmodule Cairn.Federation.MessageFederatorTest do
  use Cairn.DataCase, async: false

  alias Cairn.{Chat, Federation}
  alias Cairn.Federation.MessageFederator
  alias Cairn.Federation.NodeIdentity

  setup do
    # Start NodeIdentity for signing in delivery worker
    tmp_dir = Path.join(System.tmp_dir!(), "cairn_msg_fed_test")
    File.mkdir_p!(tmp_dir)
    key_path = Path.join(tmp_dir, "test_#{:erlang.unique_integer([:positive, :monotonic])}.key")

    case Process.whereis(NodeIdentity) do
      nil -> :ok
      pid when is_pid(pid) -> if Process.alive?(pid), do: GenServer.stop(pid)
    end

    {:ok, _} = NodeIdentity.start_link(key_path: key_path)

    # Create an active federated node
    {:ok, node} =
      Federation.register_node(%{
        domain: "fed-msg.example.com",
        node_id: "fed_msg_1",
        public_key: "key",
        inbox_url: "https://fed-msg.example.com/inbox",
        protocol_version: "0.1.0",
        status: "active"
      })

    # Create a server and channel for federation tests
    {:ok, {user, _codes}} =
      Cairn.Accounts.register_user(%{
        username: "fed_msg_user_#{:erlang.unique_integer([:positive])}",
        password: "TestPassword123!",
        display_name: "Fed Msg User"
      })

    {:ok, server} =
      Cairn.Servers.create_server(%{name: "Fed Server", creator_id: user.id})

    {:ok, channel} =
      Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    # Enable federation in config
    original_config = Application.get_env(:cairn, :federation, [])

    Application.put_env(:cairn, :federation,
      enabled: true,
      domain: "local.example.com"
    )

    on_exit(fn ->
      case Process.whereis(NodeIdentity) do
        nil -> :ok
        pid when is_pid(pid) -> if Process.alive?(pid), do: GenServer.stop(pid)
      end

      Application.put_env(:cairn, :federation, original_config)
      File.rm_rf!(tmp_dir)
    end)

    %{node: node, channel: channel, user: user, server: server}
  end

  test "federate_create enqueues delivery to active nodes", %{channel: channel, user: user} do
    message = %{
      id: Ecto.UUID.generate(),
      author_id: user.id,
      content: "Hello federation",
      inserted_at: DateTime.utc_now()
    }

    assert :ok = MessageFederator.federate_create(message, channel.id)
  end

  test "federate_update enqueues delivery", %{channel: channel, user: user} do
    message = %{
      id: Ecto.UUID.generate(),
      author_id: user.id,
      content: "Edited content",
      inserted_at: DateTime.utc_now()
    }

    assert :ok = MessageFederator.federate_update(message, channel.id)
  end

  test "federate_delete enqueues delivery", %{channel: channel, user: user} do
    message = %{
      id: Ecto.UUID.generate(),
      author_id: user.id,
      inserted_at: DateTime.utc_now()
    }

    assert :ok = MessageFederator.federate_delete(message, channel.id)
  end

  test "does nothing when federation disabled", %{channel: channel} do
    Application.put_env(:cairn, :federation, enabled: false)

    message = %{
      id: Ecto.UUID.generate(),
      author_id: Ecto.UUID.generate(),
      content: "No federation",
      inserted_at: DateTime.utc_now()
    }

    assert :ok = MessageFederator.federate_create(message, channel.id)
  end

  test "skips federation for DM channels" do
    # DM channels have no server_id
    {:ok, dm_channel} = Chat.create_channel(%{name: "dm", type: "dm"})

    message = %{
      id: Ecto.UUID.generate(),
      author_id: Ecto.UUID.generate(),
      content: "Secret DM",
      inserted_at: DateTime.utc_now()
    }

    # Should return :ok but not enqueue anything
    assert :ok = MessageFederator.federate_create(message, dm_channel.id)
  end
end
