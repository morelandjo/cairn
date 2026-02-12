defmodule MurmuringWeb.KeyBackupTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.Accounts

  @valid_password "secure_password_123"

  setup %{conn: conn} do
    {user, tokens} = register_user("backupuser")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {:ok, conn: conn, user: user, tokens: tokens}
  end

  describe "POST /api/v1/users/me/key-backup" do
    test "uploads a key backup", %{conn: conn} do
      data = Base.encode64(:crypto.strong_rand_bytes(500))

      conn = post(conn, "/api/v1/users/me/key-backup", %{data: data})

      assert json_response(conn, 201)["size_bytes"] == 500
    end

    test "upserts on second upload", %{conn: conn} do
      data1 = Base.encode64(:crypto.strong_rand_bytes(100))
      data2 = Base.encode64(:crypto.strong_rand_bytes(200))

      post(conn, "/api/v1/users/me/key-backup", %{data: data1})
      conn2 = post(conn, "/api/v1/users/me/key-backup", %{data: data2})

      assert json_response(conn2, 201)["size_bytes"] == 200
    end

    test "rejects missing data field", %{conn: conn} do
      conn = post(conn, "/api/v1/users/me/key-backup", %{})

      assert json_response(conn, 400)["error"] == "data field required"
    end

    test "rejects invalid base64", %{conn: conn} do
      conn = post(conn, "/api/v1/users/me/key-backup", %{data: "not-base64!!!"})

      assert json_response(conn, 400)["error"] == "invalid base64 data"
    end

    test "rejects backup over 10MB", %{conn: conn} do
      # 10MB + 1 byte
      big_data = Base.encode64(:crypto.strong_rand_bytes(10 * 1024 * 1024 + 1))

      conn = post(conn, "/api/v1/users/me/key-backup", %{data: big_data})

      assert json_response(conn, 400)["error"] =~ "10MB"
    end
  end

  describe "GET /api/v1/users/me/key-backup" do
    test "downloads a key backup", %{conn: conn} do
      original_bytes = :crypto.strong_rand_bytes(300)
      data = Base.encode64(original_bytes)

      post(conn, "/api/v1/users/me/key-backup", %{data: data})

      conn2 = get(conn, "/api/v1/users/me/key-backup")
      response = json_response(conn2, 200)

      assert response["data"] == data
      assert response["size_bytes"] == 300
      assert response["updated_at"] != nil
    end

    test "returns 404 when no backup exists", %{conn: conn} do
      conn = get(conn, "/api/v1/users/me/key-backup")

      assert json_response(conn, 404)["error"] == "no backup found"
    end
  end

  describe "DELETE /api/v1/users/me/key-backup" do
    test "deletes a key backup", %{conn: conn} do
      data = Base.encode64(:crypto.strong_rand_bytes(100))
      post(conn, "/api/v1/users/me/key-backup", %{data: data})

      conn2 = delete(conn, "/api/v1/users/me/key-backup")
      assert json_response(conn2, 200)["ok"] == true

      # Verify it's gone
      conn3 = get(conn, "/api/v1/users/me/key-backup")
      assert json_response(conn3, 404)["error"] == "no backup found"
    end

    test "returns 404 when no backup exists", %{conn: conn} do
      conn = delete(conn, "/api/v1/users/me/key-backup")

      assert json_response(conn, 404)["error"] == "no backup found"
    end
  end

  describe "isolation" do
    test "backups are isolated between users", %{conn: conn} do
      data1 = Base.encode64(:crypto.strong_rand_bytes(100))
      post(conn, "/api/v1/users/me/key-backup", %{data: data1})

      # Create a second user
      {_user2, tokens2} = register_user("backupuser2")
      conn2 = build_conn() |> put_req_header("authorization", "Bearer #{tokens2.access_token}")

      # User 2 has no backup
      conn_get = get(conn2, "/api/v1/users/me/key-backup")
      assert json_response(conn_get, 404)["error"] == "no backup found"

      # User 2 uploads their own
      data2 = Base.encode64(:crypto.strong_rand_bytes(200))
      post(conn2, "/api/v1/users/me/key-backup", %{data: data2})

      # Each user sees their own backup
      conn_get1 = get(conn, "/api/v1/users/me/key-backup")
      assert json_response(conn_get1, 200)["size_bytes"] == 100

      conn_get2 = get(conn2, "/api/v1/users/me/key-backup")
      assert json_response(conn_get2, 200)["size_bytes"] == 200
    end
  end

  defp register_user(username) do
    {:ok, {user, _recovery_codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Murmuring.Auth.generate_tokens(user)
    {user, tokens}
  end
end
