defmodule MurmuringWeb.BotControllerTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.{Accounts, Auth, Bots, Servers}

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

    {conn, user}
  end

  setup %{conn: conn} do
    {conn, user} = register_and_auth(conn, "botctrluser")
    {:ok, server} = Servers.create_server(%{name: "Bot Server", creator_id: user.id})
    {:ok, conn: conn, user: user, server: server}
  end

  describe "bot management" do
    test "create bot", %{conn: conn, server: server} do
      conn = post(conn, "/api/v1/servers/#{server.id}/bots")

      assert %{"bot" => %{"id" => _, "user_id" => _, "username" => username, "token" => token}} =
               json_response(conn, 201)

      assert String.starts_with?(username, "bot_")
      assert token != nil
    end

    test "list bots", %{conn: conn, server: server, user: user} do
      {:ok, _} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      conn = get(conn, "/api/v1/servers/#{server.id}/bots")
      assert %{"bots" => bots} = json_response(conn, 200)
      assert length(bots) == 1
    end

    test "delete bot", %{conn: conn, server: server, user: user} do
      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      conn = delete(conn, "/api/v1/servers/#{server.id}/bots/#{result.bot_account.id}")
      assert %{"ok" => true} = json_response(conn, 200)
    end

    test "regenerate bot token", %{conn: conn, server: server, user: user} do
      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      conn =
        post(conn, "/api/v1/servers/#{server.id}/bots/#{result.bot_account.id}/regenerate-token")

      assert %{"token" => new_token} = json_response(conn, 200)
      assert new_token != result.token
    end

    test "bot auth via Bot header", %{server: server, user: user} do
      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      # Use the bot token to authenticate
      conn =
        build_conn()
        |> put_req_header("authorization", "Bot #{result.token}")

      conn = get(conn, "/api/v1/auth/me")
      assert %{"user" => %{"username" => username}} = json_response(conn, 200)
      assert String.starts_with?(username, "bot_")
    end
  end
end
