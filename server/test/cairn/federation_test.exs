defmodule Murmuring.FederationTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.Federation

  describe "register_node/1" do
    test "creates a federated node" do
      attrs = %{
        domain: "remote.example.com",
        node_id: "abc123",
        public_key: "base64key==",
        inbox_url: "https://remote.example.com/inbox",
        protocol_version: "0.1.0"
      }

      assert {:ok, node} = Federation.register_node(attrs)
      assert node.domain == "remote.example.com"
      assert node.status == "pending"
    end

    test "rejects duplicate domain" do
      attrs = %{
        domain: "dup.example.com",
        node_id: "dup1",
        public_key: "key1",
        inbox_url: "https://dup.example.com/inbox",
        protocol_version: "0.1.0"
      }

      assert {:ok, _} = Federation.register_node(attrs)

      assert {:error, changeset} =
               Federation.register_node(%{attrs | node_id: "dup2", public_key: "key2"})

      assert {"has already been taken", _} = changeset.errors[:domain]
    end
  end

  describe "node status management" do
    setup do
      {:ok, node} =
        Federation.register_node(%{
          domain: "status.example.com",
          node_id: "status1",
          public_key: "key",
          inbox_url: "https://status.example.com/inbox",
          protocol_version: "0.1.0"
        })

      %{node: node}
    end

    test "activate_node/1", %{node: node} do
      assert {:ok, activated} = Federation.activate_node(node)
      assert activated.status == "active"
    end

    test "block_node/1", %{node: node} do
      assert {:ok, blocked} = Federation.block_node(node)
      assert blocked.status == "blocked"
    end

    test "unblock_node/1", %{node: node} do
      {:ok, blocked} = Federation.block_node(node)
      assert {:ok, unblocked} = Federation.unblock_node(blocked)
      assert unblocked.status == "active"
    end

    test "active_node?/1 and blocked_node?/1", %{node: node} do
      refute Federation.active_node?(node.domain)
      refute Federation.blocked_node?(node.domain)

      {:ok, _} = Federation.activate_node(node)
      assert Federation.active_node?(node.domain)

      # Re-fetch to avoid stale struct
      node = Federation.get_node_by_domain(node.domain)
      {:ok, _} = Federation.block_node(node)
      assert Federation.blocked_node?(node.domain)
      refute Federation.active_node?(node.domain)
    end
  end

  describe "list_nodes/0" do
    test "returns nodes sorted by domain" do
      for domain <- ["z.example.com", "a.example.com", "m.example.com"] do
        Federation.register_node(%{
          domain: domain,
          node_id: "id_#{domain}",
          public_key: "key",
          inbox_url: "https://#{domain}/inbox",
          protocol_version: "0.1.0"
        })
      end

      nodes = Federation.list_nodes()
      domains = Enum.map(nodes, & &1.domain)
      assert domains == Enum.sort(domains)
    end
  end

  describe "log_activity/1" do
    test "creates an activity record" do
      {:ok, node} =
        Federation.register_node(%{
          domain: "activity.example.com",
          node_id: "act1",
          public_key: "key",
          inbox_url: "https://activity.example.com/inbox",
          protocol_version: "0.1.0"
        })

      assert {:ok, activity} =
               Federation.log_activity(%{
                 federated_node_id: node.id,
                 activity_type: "Create",
                 direction: "inbound",
                 actor_uri: "https://activity.example.com/users/alice",
                 payload: %{"type" => "Create"}
               })

      assert activity.activity_type == "Create"
      assert activity.direction == "inbound"
      assert activity.status == "pending"
    end
  end

  describe "list_activities/1" do
    test "filters by node_id and direction" do
      {:ok, node} =
        Federation.register_node(%{
          domain: "list.example.com",
          node_id: "list1",
          public_key: "key",
          inbox_url: "https://list.example.com/inbox",
          protocol_version: "0.1.0"
        })

      Federation.log_activity(%{
        federated_node_id: node.id,
        activity_type: "Create",
        direction: "inbound"
      })

      Federation.log_activity(%{
        federated_node_id: node.id,
        activity_type: "Follow",
        direction: "outbound"
      })

      inbound = Federation.list_activities(node_id: node.id, direction: "inbound")
      assert length(inbound) == 1
      assert hd(inbound).direction == "inbound"

      all = Federation.list_activities(node_id: node.id)
      assert length(all) == 2
    end
  end
end
