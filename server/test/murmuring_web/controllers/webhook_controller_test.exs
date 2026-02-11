defmodule MurmuringWeb.WebhookControllerTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.{Accounts, Auth, Bots, Servers}
  alias Murmuring.Chat

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
    {conn, user} = register_and_auth(conn, "whuser")
    {:ok, server} = Servers.create_server(%{name: "WH Server", creator_id: user.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})
    {:ok, conn: conn, user: user, server: server, channel: channel}
  end

  describe "webhook management" do
    test "create webhook", %{conn: conn, server: server, channel: channel} do
      conn =
        post(conn, "/api/v1/servers/#{server.id}/webhooks", %{
          name: "Test Webhook",
          channel_id: channel.id
        })

      assert %{"webhook" => %{"name" => "Test Webhook", "token" => token}} =
               json_response(conn, 201)

      assert token != nil
    end

    test "list webhooks", %{conn: conn, server: server, channel: channel, user: user} do
      {:ok, _} =
        Bots.create_webhook(%{
          name: "WH1",
          server_id: server.id,
          channel_id: channel.id,
          creator_id: user.id
        })

      conn = get(conn, "/api/v1/servers/#{server.id}/webhooks")
      assert %{"webhooks" => webhooks} = json_response(conn, 200)
      assert length(webhooks) == 1
    end

    test "delete webhook", %{conn: conn, server: server, channel: channel, user: user} do
      {:ok, webhook} =
        Bots.create_webhook(%{
          name: "Delete Me",
          server_id: server.id,
          channel_id: channel.id,
          creator_id: user.id
        })

      conn = delete(conn, "/api/v1/servers/#{server.id}/webhooks/#{webhook.id}")
      assert %{"ok" => true} = json_response(conn, 200)
    end

    test "regenerate webhook token", %{conn: conn, server: server, channel: channel, user: user} do
      {:ok, webhook} =
        Bots.create_webhook(%{
          name: "Regen",
          server_id: server.id,
          channel_id: channel.id,
          creator_id: user.id
        })

      conn = post(conn, "/api/v1/servers/#{server.id}/webhooks/#{webhook.id}/regenerate-token")
      assert %{"webhook" => %{"token" => new_token}} = json_response(conn, 200)
      assert new_token != webhook.token
    end
  end

  describe "webhook execution" do
    test "execute webhook via token (no auth)", %{server: server, channel: channel, user: user} do
      {:ok, webhook} =
        Bots.create_webhook(%{
          name: "Exec",
          server_id: server.id,
          channel_id: channel.id,
          creator_id: user.id
        })

      # Use a fresh conn without auth headers
      conn = build_conn()
      conn = post(conn, "/api/v1/webhooks/#{webhook.token}", %{content: "Hello via webhook"})
      assert %{"message" => %{"id" => _}} = json_response(conn, 201)
    end

    test "execute webhook with invalid token returns 404" do
      conn = build_conn()
      conn = post(conn, "/api/v1/webhooks/invalid_token_here", %{content: "Hello"})
      assert json_response(conn, 404)
    end
  end
end
