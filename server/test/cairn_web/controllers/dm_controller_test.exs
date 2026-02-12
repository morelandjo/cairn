defmodule CairnWeb.DmControllerTest do
  use CairnWeb.ConnCase, async: true

  alias Cairn.{Accounts, Auth, Chat, Federation}

  @valid_password "secure_password_123"

  setup %{conn: conn} do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "dm_user_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    # Give user a DID (did_changeset requires rotation_public_key)
    {:ok, user} =
      Accounts.update_user_did(user, %{
        did: "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}",
        rotation_public_key: :crypto.strong_rand_bytes(32)
      })

    {:ok, tokens} = Auth.generate_tokens(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {:ok, conn: conn, user: user}
  end

  describe "POST /api/v1/dm/federated" do
    test "creates a federated DM request", %{conn: conn} do
      recipient_did =
        "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"

      conn =
        post(conn, "/api/v1/dm/federated", %{
          recipient_did: recipient_did,
          recipient_instance: "remote.example.com"
        })

      body = json_response(conn, 201)
      assert body["channel_id"]
      assert body["request_id"]
      assert body["status"] == "pending"
    end

    test "rejects invalid DID format", %{conn: conn} do
      conn =
        post(conn, "/api/v1/dm/federated", %{
          recipient_did: "not-a-did",
          recipient_instance: "remote.example.com"
        })

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "rejects self DM", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v1/dm/federated", %{
          recipient_did: user.did,
          recipient_instance: "remote.example.com"
        })

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "yourself"
    end

    test "rejects duplicate request", %{conn: conn} do
      recipient_did =
        "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"

      conn1 =
        post(conn, "/api/v1/dm/federated", %{
          recipient_did: recipient_did,
          recipient_instance: "remote.example.com"
        })

      assert json_response(conn1, 201)

      conn2 =
        build_conn()
        |> put_req_header("authorization", get_req_header(conn, "authorization") |> hd())
        |> post("/api/v1/dm/federated", %{
          recipient_did: recipient_did,
          recipient_instance: "remote.example.com"
        })

      assert %{"error" => _} = json_response(conn2, 409)
    end

    test "enforces rate limit", %{conn: conn, user: user} do
      # Create 10 requests (the max)
      for i <- 1..10 do
        did = "did:cairn:ratelimit#{i}#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

        {:ok, fu} =
          Federation.get_or_create_federated_user(%{
            did: did,
            username: "user#{i}",
            home_instance: "remote.example.com",
            public_key: "pending",
            actor_uri: "https://remote.example.com/users/user#{i}",
            last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
          })

        {:ok, channel} = Chat.create_federated_dm(user.id, fu.id)

        Chat.create_dm_request(%{
          channel_id: channel.id,
          sender_id: user.id,
          recipient_did: did,
          recipient_instance: "remote.example.com",
          status: "pending"
        })
      end

      # 11th should fail
      conn =
        post(conn, "/api/v1/dm/federated", %{
          recipient_did:
            "did:cairn:overflow#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
          recipient_instance: "remote.example.com"
        })

      assert %{"error" => error} = json_response(conn, 429)
      assert error =~ "rate limit"
    end

    test "rejects when recipient is blocked", %{conn: conn, user: user} do
      blocked_did =
        "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"

      Chat.block_dm_sender(user.id, blocked_did)

      conn =
        post(conn, "/api/v1/dm/federated", %{
          recipient_did: blocked_did,
          recipient_instance: "remote.example.com"
        })

      assert %{"error" => _} = json_response(conn, 403)
    end

    test "rejects missing params", %{conn: conn} do
      conn = post(conn, "/api/v1/dm/federated", %{})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "GET /api/v1/dm/requests" do
    test "lists received DM requests", %{conn: conn, user: user} do
      # Create a request targeting this user's DID
      {:ok, {sender, _codes}} =
        Accounts.register_user(%{
          "username" => "sender_#{System.unique_integer([:positive])}",
          "password" => @valid_password
        })

      {:ok, fu} =
        Federation.get_or_create_federated_user(%{
          did: user.did,
          username: user.username,
          home_instance: "remote.example.com",
          public_key: "pending",
          actor_uri: "https://remote.example.com/users/#{user.username}",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      {:ok, channel} = Chat.create_federated_dm(sender.id, fu.id)

      {:ok, _request} =
        Chat.create_dm_request(%{
          channel_id: channel.id,
          sender_id: sender.id,
          recipient_did: user.did,
          recipient_instance: "localhost",
          status: "pending"
        })

      conn = get(conn, "/api/v1/dm/requests")
      body = json_response(conn, 200)
      assert length(body["requests"]) == 1
    end
  end

  describe "GET /api/v1/dm/requests/sent" do
    test "lists sent DM requests", %{conn: conn, user: user} do
      did = "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"

      {:ok, fu} =
        Federation.get_or_create_federated_user(%{
          did: did,
          username: "remote_user",
          home_instance: "remote.example.com",
          public_key: "pending",
          actor_uri: "https://remote.example.com/users/remote_user",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      {:ok, channel} = Chat.create_federated_dm(user.id, fu.id)

      Chat.create_dm_request(%{
        channel_id: channel.id,
        sender_id: user.id,
        recipient_did: did,
        recipient_instance: "remote.example.com",
        status: "pending"
      })

      conn = get(conn, "/api/v1/dm/requests/sent")
      body = json_response(conn, 200)
      assert length(body["requests"]) == 1
    end
  end

  describe "POST /api/v1/dm/requests/:id/respond" do
    setup %{user: user} do
      {:ok, {sender, _codes}} =
        Accounts.register_user(%{
          "username" => "respond_sender_#{System.unique_integer([:positive])}",
          "password" => @valid_password
        })

      {:ok, fu} =
        Federation.get_or_create_federated_user(%{
          did: user.did,
          username: user.username,
          home_instance: "localhost",
          public_key: "pending",
          actor_uri: "https://localhost/users/#{user.username}",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      {:ok, channel} = Chat.create_federated_dm(sender.id, fu.id)

      {:ok, request} =
        Chat.create_dm_request(%{
          channel_id: channel.id,
          sender_id: sender.id,
          recipient_did: user.did,
          recipient_instance: "localhost",
          status: "pending"
        })

      {:ok, request: request, sender: sender}
    end

    test "accepts a DM request", %{conn: conn, request: request} do
      conn =
        post(conn, "/api/v1/dm/requests/#{request.id}/respond", %{status: "accepted"})

      body = json_response(conn, 200)
      assert body["status"] == "accepted"
      assert body["channel_id"]
    end

    test "rejects a DM request", %{conn: conn, request: request} do
      conn =
        post(conn, "/api/v1/dm/requests/#{request.id}/respond", %{status: "rejected"})

      body = json_response(conn, 200)
      assert body["status"] == "rejected"
    end

    test "returns 404 for unknown request", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn =
        post(conn, "/api/v1/dm/requests/#{fake_id}/respond", %{status: "accepted"})

      assert json_response(conn, 404)
    end

    test "rejects invalid status", %{conn: conn, request: request} do
      conn =
        post(conn, "/api/v1/dm/requests/#{request.id}/respond", %{status: "invalid"})

      assert json_response(conn, 400)
    end
  end

  describe "POST /api/v1/dm/requests/:id/block" do
    test "blocks a DM sender", %{conn: conn, user: user} do
      {:ok, {sender, _codes}} =
        Accounts.register_user(%{
          "username" => "block_sender_#{System.unique_integer([:positive])}",
          "password" => @valid_password
        })

      {:ok, sender} =
        Accounts.update_user_did(sender, %{
          did: "did:cairn:#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}",
          rotation_public_key: :crypto.strong_rand_bytes(32)
        })

      {:ok, fu} =
        Federation.get_or_create_federated_user(%{
          did: user.did,
          username: user.username,
          home_instance: "localhost",
          public_key: "pending",
          actor_uri: "https://localhost/users/#{user.username}",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      {:ok, channel} = Chat.create_federated_dm(sender.id, fu.id)

      {:ok, request} =
        Chat.create_dm_request(%{
          channel_id: channel.id,
          sender_id: sender.id,
          recipient_did: user.did,
          recipient_instance: "localhost",
          status: "pending"
        })

      conn = post(conn, "/api/v1/dm/requests/#{request.id}/block")
      body = json_response(conn, 200)
      assert body["ok"] == true
      assert body["blocked"] == true

      # Verify the sender's DID is now blocked
      assert Chat.is_dm_blocked?(user.id, sender.did)
    end
  end
end
