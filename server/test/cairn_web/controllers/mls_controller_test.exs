defmodule CairnWeb.MlsControllerTest do
  use CairnWeb.ConnCase, async: true

  alias Cairn.{Accounts, Auth, Chat, Servers}
  alias Cairn.Chat.Mls

  @valid_password "secure_password_123"

  setup %{conn: conn} do
    {user, tokens} = register_user("mlsuser")
    {user2, tokens2} = register_user("mlsuser2")

    # Create a server and private channel, add both users
    {:ok, server} = Servers.create_server(%{name: "MLS Test Server", creator_id: user.id})

    {:ok, channel} =
      Chat.create_channel(%{name: "private-test", type: "private", server_id: server.id})

    Chat.add_member(channel.id, user.id, "owner")
    Chat.add_member(channel.id, user2.id)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {:ok,
     conn: conn, user: user, user2: user2, tokens2: tokens2, channel: channel, server: server}
  end

  # --- Store Group Info ---

  describe "POST /api/v1/channels/:id/mls/group-info" do
    test "stores group info", %{conn: conn, channel: channel} do
      data = Base.encode64(:crypto.strong_rand_bytes(128))

      conn =
        post(conn, "/api/v1/channels/#{channel.id}/mls/group-info", %{
          data: data,
          epoch: 0
        })

      assert %{"ok" => true} = json_response(conn, 201)
    end

    test "upserts group info on same channel", %{conn: conn, channel: channel} do
      data1 = Base.encode64(:crypto.strong_rand_bytes(64))
      data2 = Base.encode64(:crypto.strong_rand_bytes(64))

      post(conn, "/api/v1/channels/#{channel.id}/mls/group-info", %{data: data1, epoch: 0})

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> post("/api/v1/channels/#{channel.id}/mls/group-info", %{data: data2, epoch: 1})

      assert %{"ok" => true} = json_response(conn2, 201)

      info = Mls.get_group_info(channel.id)
      assert info.epoch == 1
    end

    test "rejects missing data", %{conn: conn, channel: channel} do
      conn = post(conn, "/api/v1/channels/#{channel.id}/mls/group-info", %{epoch: 0})
      assert %{"error" => "data required"} = json_response(conn, 400)
    end

    test "rejects non-member", %{channel: channel} do
      {_outsider, outsider_tokens} = register_user("outsider")

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{outsider_tokens.access_token}")
        |> post("/api/v1/channels/#{channel.id}/mls/group-info", %{
          data: Base.encode64("data"),
          epoch: 0
        })

      assert %{"error" => "not a member"} = json_response(conn, 403)
    end
  end

  # --- Get Group Info ---

  describe "GET /api/v1/channels/:id/mls/group-info" do
    test "returns group info", %{conn: conn, channel: channel} do
      raw = :crypto.strong_rand_bytes(64)
      Mls.store_group_info(channel.id, raw, 3)

      conn = get(conn, "/api/v1/channels/#{channel.id}/mls/group-info")
      response = json_response(conn, 200)

      assert response["epoch"] == 3
      assert {:ok, ^raw} = Base.decode64(response["data"])
    end

    test "returns 404 when no group info", %{conn: conn, channel: channel} do
      conn = get(conn, "/api/v1/channels/#{channel.id}/mls/group-info")
      assert %{"error" => "no group info"} = json_response(conn, 404)
    end
  end

  # --- Store Commit ---

  describe "POST /api/v1/channels/:id/mls/commit" do
    test "stores a commit", %{conn: conn, channel: channel} do
      data = Base.encode64(:crypto.strong_rand_bytes(256))

      conn =
        post(conn, "/api/v1/channels/#{channel.id}/mls/commit", %{
          data: data,
          epoch: 1
        })

      assert %{"id" => id} = json_response(conn, 201)
      assert is_binary(id)
    end

    test "commit appears in pending messages", %{
      conn: conn,
      tokens2: tokens2,
      channel: channel
    } do
      data = Base.encode64(:crypto.strong_rand_bytes(64))
      post(conn, "/api/v1/channels/#{channel.id}/mls/commit", %{data: data, epoch: 1})

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens2.access_token}")
        |> get("/api/v1/channels/#{channel.id}/mls/messages")

      response = json_response(conn2, 200)
      assert length(response["messages"]) == 1
      assert hd(response["messages"])["message_type"] == "commit"
    end
  end

  # --- Store Proposal ---

  describe "POST /api/v1/channels/:id/mls/proposal" do
    test "stores a proposal", %{conn: conn, channel: channel} do
      data = Base.encode64(:crypto.strong_rand_bytes(128))

      conn =
        post(conn, "/api/v1/channels/#{channel.id}/mls/proposal", %{
          data: data,
          epoch: 0
        })

      assert %{"id" => _} = json_response(conn, 201)
    end
  end

  # --- Store Welcome ---

  describe "POST /api/v1/channels/:id/mls/welcome" do
    test "stores a welcome for a recipient", %{conn: conn, user2: user2, channel: channel} do
      data = Base.encode64(:crypto.strong_rand_bytes(512))

      conn =
        post(conn, "/api/v1/channels/#{channel.id}/mls/welcome", %{
          data: data,
          recipient_id: user2.id
        })

      assert %{"id" => _} = json_response(conn, 201)
    end

    test "welcome only visible to recipient", %{
      conn: conn,
      user2: user2,
      tokens2: tokens2,
      channel: channel
    } do
      data = Base.encode64(:crypto.strong_rand_bytes(128))

      post(conn, "/api/v1/channels/#{channel.id}/mls/welcome", %{
        data: data,
        recipient_id: user2.id
      })

      # User2 sees the welcome
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens2.access_token}")
        |> get("/api/v1/channels/#{channel.id}/mls/messages")

      msgs2 = json_response(conn2, 200)["messages"]
      assert length(msgs2) == 1
      assert hd(msgs2)["message_type"] == "welcome"

      # User1 (sender, not recipient) should also see it if no recipient filter
      # Actually, the endpoint filters by recipient_id: current user
      # Commits have nil recipient, so user1 sees commits but not user2's welcome
      conn1 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> get("/api/v1/channels/#{channel.id}/mls/messages")

      msgs1 = json_response(conn1, 200)["messages"]
      # Welcome has recipient_id=user2, so user1 should NOT see it
      # (query filters: recipient_id is nil OR recipient_id == current_user)
      assert length(msgs1) == 0
    end

    test "rejects missing recipient_id", %{conn: conn, channel: channel} do
      conn =
        post(conn, "/api/v1/channels/#{channel.id}/mls/welcome", %{
          data: Base.encode64("data")
        })

      assert %{"error" => "recipient_id required"} = json_response(conn, 400)
    end
  end

  # --- Pending Messages ---

  describe "GET /api/v1/channels/:id/mls/messages" do
    test "returns pending messages ordered by time", %{
      conn: conn,
      tokens2: tokens2,
      channel: channel
    } do
      for i <- 1..3 do
        post(conn, "/api/v1/channels/#{channel.id}/mls/commit", %{
          data: Base.encode64(:crypto.strong_rand_bytes(32)),
          epoch: i
        })
      end

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens2.access_token}")
        |> get("/api/v1/channels/#{channel.id}/mls/messages")

      response = json_response(conn2, 200)
      assert length(response["messages"]) == 3

      epochs = Enum.map(response["messages"], & &1["epoch"])
      assert epochs == [1, 2, 3]
    end
  end

  # --- Ack Messages ---

  describe "POST /api/v1/channels/:id/mls/ack" do
    test "marks messages as processed", %{conn: conn, tokens2: tokens2, channel: channel} do
      # Store a commit
      resp =
        conn
        |> post("/api/v1/channels/#{channel.id}/mls/commit", %{
          data: Base.encode64(:crypto.strong_rand_bytes(32)),
          epoch: 1
        })
        |> json_response(201)

      msg_id = resp["id"]

      # Ack it
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens2.access_token}")
        |> post("/api/v1/channels/#{channel.id}/mls/ack", %{
          message_ids: [msg_id]
        })

      assert %{"acknowledged" => 1} = json_response(conn2, 200)

      # Should no longer appear in pending
      conn3 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens2.access_token}")
        |> get("/api/v1/channels/#{channel.id}/mls/messages")

      assert json_response(conn3, 200)["messages"] == []
    end
  end

  # --- Private Channel Type ---

  describe "private channel type" do
    test "can create a private channel", %{conn: conn, server: server} do
      conn =
        post(conn, "/api/v1/channels", %{
          name: "secret-room",
          type: "private",
          server_id: server.id
        })

      assert %{"channel" => %{"type" => "private"}} = json_response(conn, 201)
    end

    test "private channels don't appear in public listing", %{conn: conn, channel: _channel} do
      conn = get(conn, "/api/v1/channels")
      channels = json_response(conn, 200)["channels"]

      # Public listing only shows type=public
      types = Enum.map(channels, & &1["type"])
      refute "private" in types
    end
  end

  # --- Helpers ---

  defp register_user(username) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)
    {user, tokens}
  end
end
