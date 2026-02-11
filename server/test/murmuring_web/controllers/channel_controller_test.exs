defmodule MurmuringWeb.ChannelControllerTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.{Accounts, Auth, Chat, Servers}

  @valid_password "secure_password_123"

  setup %{conn: conn} do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "channeluser_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)
    {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: user.id})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {:ok, conn: conn, user: user, server: server}
  end

  describe "GET /api/v1/channels" do
    test "lists public channels", %{conn: conn, server: server} do
      {:ok, _channel} =
        Chat.create_channel(%{name: "test-channel", type: "public", server_id: server.id})

      conn = get(conn, "/api/v1/channels")
      assert %{"channels" => channels} = json_response(conn, 200)
      assert length(channels) >= 1
    end
  end

  describe "POST /api/v1/channels" do
    test "creates a channel", %{conn: conn, user: user, server: server} do
      conn =
        post(conn, "/api/v1/channels", %{
          name: "new-channel",
          type: "public",
          description: "A test channel",
          server_id: server.id
        })

      assert %{"channel" => %{"name" => "new-channel", "type" => "public"}} =
               json_response(conn, 201)

      # Creator should be owner
      channels = Chat.list_user_channels(user.id)
      assert Enum.any?(channels, &(&1.name == "new-channel"))
    end

    test "rejects invalid channel", %{conn: conn, server: server} do
      conn = post(conn, "/api/v1/channels", %{name: "", type: "public", server_id: server.id})
      assert %{"errors" => _} = json_response(conn, 422)
    end
  end

  describe "GET /api/v1/channels/:id/messages" do
    test "lists messages for a public channel", %{conn: conn, user: user, server: server} do
      {:ok, channel} =
        Chat.create_channel(%{name: "msg-channel", type: "public", server_id: server.id})

      Chat.add_member(channel.id, user.id)

      {:ok, _msg} =
        Chat.create_message(%{
          content: "Hello world",
          channel_id: channel.id,
          author_id: user.id
        })

      conn = get(conn, "/api/v1/channels/#{channel.id}/messages")
      assert %{"messages" => messages} = json_response(conn, 200)
      assert length(messages) == 1
      assert hd(messages)["content"] == "Hello world"
    end
  end

  describe "history_accessible setting" do
    test "creates private channel with history_accessible", %{conn: conn, server: server} do
      conn =
        post(conn, "/api/v1/channels", %{
          name: "history-channel",
          type: "private",
          server_id: server.id,
          history_accessible: true
        })

      assert %{"channel" => channel} = json_response(conn, 201)
      assert channel["type"] == "private"
      assert channel["history_accessible"] == true
    end

    test "private channel defaults to history_accessible false", %{conn: conn, server: server} do
      conn =
        post(conn, "/api/v1/channels", %{
          name: "private-default",
          type: "private",
          server_id: server.id
        })

      assert %{"channel" => channel} = json_response(conn, 201)
      assert channel["history_accessible"] == false
    end

    test "rejects history_accessible on public channels", %{conn: conn, server: server} do
      conn =
        post(conn, "/api/v1/channels", %{
          name: "public-history",
          type: "public",
          server_id: server.id,
          history_accessible: true
        })

      assert %{"errors" => %{"history_accessible" => _}} = json_response(conn, 422)
    end

    test "history_accessible is immutable on update", %{conn: _conn, server: server} do
      {:ok, channel} =
        Chat.create_channel(%{
          name: "immutable-test",
          type: "private",
          server_id: server.id,
          history_accessible: false
        })

      # update_channel should not change history_accessible
      {:ok, updated} = Chat.update_channel(channel, %{history_accessible: true, name: "renamed"})
      assert updated.name == "renamed"
      assert updated.history_accessible == false
    end

    test "returns history_accessible in channel JSON", %{conn: conn, server: server} do
      {:ok, channel} =
        Chat.create_channel(%{name: "json-test", type: "public", server_id: server.id})

      conn = get(conn, "/api/v1/channels/#{channel.id}")
      assert %{"channel" => ch} = json_response(conn, 200)
      assert Map.has_key?(ch, "history_accessible")
    end
  end

  describe "GET /api/v1/channels/:id/members" do
    test "lists channel members", %{conn: conn, user: user, server: server} do
      {:ok, channel} =
        Chat.create_channel(%{name: "member-channel", type: "public", server_id: server.id})

      Chat.add_member(channel.id, user.id, "owner")

      conn = get(conn, "/api/v1/channels/#{channel.id}/members")
      assert %{"members" => members} = json_response(conn, 200)
      assert length(members) == 1
      assert hd(members)["role"] == "owner"
    end
  end
end
