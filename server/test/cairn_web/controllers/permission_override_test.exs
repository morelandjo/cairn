defmodule MurmuringWeb.PermissionOverrideTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.{Accounts, Auth, Chat, Servers}

  @valid_password "secure_password_123"

  defp register_and_auth(conn, username) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)
    conn = put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")
    {conn, user}
  end

  setup %{conn: conn} do
    {conn, user} = register_and_auth(conn, "overrideuser")
    {:ok, server} = Servers.create_server(%{name: "OverrideTest", creator_id: user.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})
    {:ok, conn: conn, user: user, server: server, channel: channel}
  end

  describe "channel permission overrides" do
    test "set and list role override", %{conn: conn, server: server, channel: channel} do
      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      conn1 =
        put(
          conn,
          "/api/v1/servers/#{server.id}/channels/#{channel.id}/overrides/role/#{everyone_role.id}",
          %{
            permissions: %{send_messages: "deny"}
          }
        )

      assert %{"override" => %{"role_id" => _, "permissions" => %{"send_messages" => "deny"}}} =
               json_response(conn1, 200)

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> get("/api/v1/servers/#{server.id}/channels/#{channel.id}/overrides")

      assert %{"overrides" => overrides} = json_response(conn2, 200)
      assert length(overrides) == 1
    end

    test "delete role override", %{conn: conn, server: server, channel: channel} do
      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      put(
        conn,
        "/api/v1/servers/#{server.id}/channels/#{channel.id}/overrides/role/#{everyone_role.id}",
        %{
          permissions: %{send_messages: "deny"}
        }
      )

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> delete(
          "/api/v1/servers/#{server.id}/channels/#{channel.id}/overrides/role/#{everyone_role.id}"
        )

      assert %{"ok" => true} = json_response(conn2, 200)
    end

    test "set user override", %{conn: conn, server: server, channel: channel} do
      {_, other_user} = register_and_auth(build_conn(), "otheruser")
      {:ok, _} = Servers.add_member(server.id, other_user.id)

      conn1 =
        put(
          conn,
          "/api/v1/servers/#{server.id}/channels/#{channel.id}/overrides/user/#{other_user.id}",
          %{
            permissions: %{send_messages: "grant"}
          }
        )

      assert %{"override" => %{"user_id" => _, "permissions" => %{"send_messages" => "grant"}}} =
               json_response(conn1, 200)
    end

    test "non-admin cannot set overrides", %{server: server, channel: channel} do
      {other_conn, other_user} = register_and_auth(build_conn(), "nonadmin")
      {:ok, _} = Servers.add_member(server.id, other_user.id)

      everyone_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "@everyone"))

      conn =
        put(
          other_conn,
          "/api/v1/servers/#{server.id}/channels/#{channel.id}/overrides/role/#{everyone_role.id}",
          %{
            permissions: %{send_messages: "deny"}
          }
        )

      assert %{"error" => "insufficient permissions"} = json_response(conn, 403)
    end
  end

  describe "multi-role management" do
    test "add and remove member role", %{conn: conn, server: server} do
      {_, other_user} = register_and_auth(build_conn(), "multirole")
      {:ok, _} = Servers.add_member(server.id, other_user.id)

      mod_role =
        Servers.list_server_roles(server.id) |> Enum.find(&(&1.name == "Moderator"))

      conn1 =
        post(conn, "/api/v1/servers/#{server.id}/members/#{other_user.id}/roles/#{mod_role.id}")

      assert %{"ok" => true} = json_response(conn1, 200)

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> delete("/api/v1/servers/#{server.id}/members/#{other_user.id}/roles/#{mod_role.id}")

      assert %{"ok" => true} = json_response(conn2, 200)
    end
  end
end
