defmodule CairnWeb.ServerControllerTest do
  use CairnWeb.ConnCase, async: true

  alias Cairn.{Accounts, Auth, Servers}

  @valid_password "secure_password_123"

  defp register_and_auth(conn, username) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {conn, user, tokens}
  end

  setup %{conn: conn} do
    {conn, user, _tokens} = register_and_auth(conn, "srvuser")
    {:ok, conn: conn, user: user}
  end

  describe "POST /api/v1/servers" do
    test "creates a server", %{conn: conn} do
      conn = post(conn, "/api/v1/servers", %{name: "My Server", description: "A cool server"})

      assert %{"server" => %{"name" => "My Server", "description" => "A cool server"}} =
               json_response(conn, 201)
    end

    test "rejects missing name", %{conn: conn} do
      conn = post(conn, "/api/v1/servers", %{description: "No name"})
      assert %{"errors" => _} = json_response(conn, 422)
    end
  end

  describe "GET /api/v1/servers" do
    test "lists user's servers", %{conn: conn, user: user} do
      {:ok, _} = Servers.create_server(%{name: "Server1", creator_id: user.id})
      {:ok, _} = Servers.create_server(%{name: "Server2", creator_id: user.id})

      conn = get(conn, "/api/v1/servers")
      assert %{"servers" => servers} = json_response(conn, 200)
      assert length(servers) == 2
    end
  end

  describe "GET /api/v1/servers/:id" do
    test "shows a server", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "ShowMe", creator_id: user.id})

      conn = get(conn, "/api/v1/servers/#{server.id}")
      assert %{"server" => %{"name" => "ShowMe"}} = json_response(conn, 200)
    end

    test "returns 404 for missing server", %{conn: conn} do
      conn = get(conn, "/api/v1/servers/#{Ecto.UUID.generate()}")
      assert %{"error" => "server not found"} = json_response(conn, 404)
    end
  end

  describe "PUT /api/v1/servers/:id" do
    test "updates a server as owner", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "Old Name", creator_id: user.id})

      conn = put(conn, "/api/v1/servers/#{server.id}", %{name: "New Name"})
      assert %{"server" => %{"name" => "New Name"}} = json_response(conn, 200)
    end

    test "rejects update from non-owner", %{conn: _conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "Protected", creator_id: user.id})

      # Create another user
      {other_conn, _other_user, _} = register_and_auth(build_conn(), "other")
      conn = put(other_conn, "/api/v1/servers/#{server.id}", %{name: "Hacked"})
      assert %{"error" => "insufficient permissions"} = json_response(conn, 403)
    end
  end

  describe "DELETE /api/v1/servers/:id" do
    test "deletes a server as owner", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "ToDelete", creator_id: user.id})

      conn = delete(conn, "/api/v1/servers/#{server.id}")
      assert %{"ok" => true} = json_response(conn, 200)
    end
  end

  describe "POST /api/v1/servers/:server_id/join" do
    test "joins a server", %{conn: _conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "Joinable", creator_id: user.id})

      {other_conn, other_user, _} = register_and_auth(build_conn(), "joiner")
      refute Servers.is_member?(server.id, other_user.id)

      conn = post(other_conn, "/api/v1/servers/#{server.id}/join")
      assert %{"ok" => true} = json_response(conn, 200)
      assert Servers.is_member?(server.id, other_user.id)
    end
  end

  describe "POST /api/v1/servers/:server_id/leave" do
    test "leaves a server", %{conn: _conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "Leavable", creator_id: user.id})

      {other_conn, other_user, _} = register_and_auth(build_conn(), "leaver")
      {:ok, _} = Servers.add_member(server.id, other_user.id)
      assert Servers.is_member?(server.id, other_user.id)

      conn = post(other_conn, "/api/v1/servers/#{server.id}/leave")
      assert %{"ok" => true} = json_response(conn, 200)
      refute Servers.is_member?(server.id, other_user.id)
    end
  end

  describe "GET /api/v1/servers/:server_id/members" do
    test "lists server members", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "MemberTest", creator_id: user.id})

      conn = get(conn, "/api/v1/servers/#{server.id}/members")
      assert %{"members" => members} = json_response(conn, 200)
      assert length(members) == 1
      assert hd(members)["role_name"] == "Owner"
    end
  end

  describe "GET /api/v1/servers/:server_id/channels" do
    test "lists server channels", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "ChanTest", creator_id: user.id})

      {:ok, _} =
        Cairn.Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

      {:ok, _} =
        Cairn.Chat.create_channel(%{name: "random", type: "public", server_id: server.id})

      conn = get(conn, "/api/v1/servers/#{server.id}/channels")
      assert %{"channels" => channels} = json_response(conn, 200)
      assert length(channels) == 2
    end
  end

  describe "POST /api/v1/servers/:server_id/channels" do
    test "creates a channel in a server", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "ChanCreate", creator_id: user.id})

      conn =
        post(conn, "/api/v1/servers/#{server.id}/channels", %{
          name: "new-channel",
          type: "public"
        })

      assert %{"channel" => %{"name" => "new-channel", "server_id" => sid}} =
               json_response(conn, 201)

      assert sid == server.id
    end
  end

  describe "role CRUD" do
    test "lists, creates, updates, deletes roles", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(%{name: "RoleTest", creator_id: user.id})

      # List default roles
      conn1 = get(conn, "/api/v1/servers/#{server.id}/roles")
      assert %{"roles" => roles} = json_response(conn1, 200)
      assert length(roles) == 4

      # Create a custom role
      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> post("/api/v1/servers/#{server.id}/roles", %{
          name: "VIP",
          permissions: %{send_messages: true},
          priority: 25
        })

      assert %{"role" => %{"name" => "VIP"}} = json_response(conn2, 201)
      role_id = json_response(conn2, 201)["role"]["id"]

      # Update role
      conn3 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> put("/api/v1/servers/#{server.id}/roles/#{role_id}", %{color: "#ff0000"})

      assert %{"role" => %{"color" => "#ff0000"}} = json_response(conn3, 200)

      # Delete role
      conn4 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> delete("/api/v1/servers/#{server.id}/roles/#{role_id}")

      assert %{"ok" => true} = json_response(conn4, 200)
    end
  end
end
