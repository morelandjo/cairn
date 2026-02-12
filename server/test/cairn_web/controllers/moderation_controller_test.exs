defmodule CairnWeb.ModerationControllerTest do
  use CairnWeb.ConnCase, async: true

  alias Cairn.{Accounts, Auth, Servers}

  @valid_password "secure_password_123"

  defp register_and_auth(conn, username) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)
    conn = put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")
    {conn, user}
  end

  setup %{conn: conn} do
    {conn, user} = register_and_auth(conn, "modctrl")
    {:ok, server} = Servers.create_server(%{name: "ModCtrlTest", creator_id: user.id})
    {_, target} = register_and_auth(build_conn(), "target")
    {:ok, _} = Servers.add_member(server.id, target.id)
    {:ok, conn: conn, user: user, server: server, target: target}
  end

  describe "mute/unmute" do
    test "mute and unmute a user", %{conn: conn, server: server, target: target} do
      conn1 =
        post(conn, "/api/v1/servers/#{server.id}/mutes", %{user_id: target.id, reason: "spam"})

      assert %{"mute" => %{"user_id" => _}} = json_response(conn1, 201)

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> get("/api/v1/servers/#{server.id}/mutes")

      assert %{"mutes" => mutes} = json_response(conn2, 200)
      assert length(mutes) == 1

      conn3 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> delete("/api/v1/servers/#{server.id}/mutes/#{target.id}")

      assert %{"ok" => true} = json_response(conn3, 200)
    end
  end

  describe "kick" do
    test "kick a user", %{conn: conn, server: server, target: target} do
      conn1 = post(conn, "/api/v1/servers/#{server.id}/kicks/#{target.id}")
      assert %{"ok" => true} = json_response(conn1, 200)
      refute Servers.is_member?(server.id, target.id)
    end
  end

  describe "ban/unban" do
    test "ban and unban a user", %{conn: conn, server: server, target: target} do
      conn1 =
        post(conn, "/api/v1/servers/#{server.id}/bans", %{user_id: target.id, reason: "toxic"})

      assert %{"ban" => %{"user_id" => _}} = json_response(conn1, 201)

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> get("/api/v1/servers/#{server.id}/bans")

      assert %{"bans" => bans} = json_response(conn2, 200)
      assert length(bans) == 1

      conn3 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> delete("/api/v1/servers/#{server.id}/bans/#{target.id}")

      assert %{"ok" => true} = json_response(conn3, 200)
    end
  end

  describe "moderation log" do
    test "view mod log", %{conn: conn, server: server, target: target} do
      post(conn, "/api/v1/servers/#{server.id}/kicks/#{target.id}")

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> get("/api/v1/servers/#{server.id}/moderation-log")

      assert %{"log" => log} = json_response(conn2, 200)
      assert length(log) >= 1
    end
  end

  describe "permission enforcement" do
    test "non-moderator cannot mute", %{server: server, target: target} do
      {other_conn, other_user} = register_and_auth(build_conn(), "noperm")
      {:ok, _} = Servers.add_member(server.id, other_user.id)

      conn = post(other_conn, "/api/v1/servers/#{server.id}/mutes", %{user_id: target.id})
      assert %{"error" => "insufficient permissions"} = json_response(conn, 403)
    end
  end
end
