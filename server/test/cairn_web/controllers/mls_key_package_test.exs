defmodule MurmuringWeb.MlsKeyPackageTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.Accounts
  alias Murmuring.Keys

  @valid_password "secure_password_123"

  setup %{conn: conn} do
    {user, tokens} = register_user("mlsuser")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {:ok, conn: conn, user: user, tokens: tokens}
  end

  describe "POST /api/v1/users/me/key-packages" do
    test "uploads key packages", %{conn: conn} do
      packages = for _i <- 1..5, do: Base.encode64(:crypto.strong_rand_bytes(256))

      conn = post(conn, "/api/v1/users/me/key-packages", %{key_packages: packages})
      assert %{"uploaded" => 5} = json_response(conn, 201)
    end

    test "rejects invalid base64", %{conn: conn} do
      conn =
        post(conn, "/api/v1/users/me/key-packages", %{
          key_packages: ["not-valid-base64!!!"]
        })

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "rejects more than 100 packages", %{conn: conn} do
      packages = for _i <- 1..101, do: Base.encode64(:crypto.strong_rand_bytes(32))

      conn = post(conn, "/api/v1/users/me/key-packages", %{key_packages: packages})
      assert %{"error" => "max 100 key packages per upload"} = json_response(conn, 400)
    end

    test "rejects missing key_packages field", %{conn: conn} do
      conn = post(conn, "/api/v1/users/me/key-packages", %{})
      assert %{"error" => _} = json_response(conn, 400)
    end

    test "rejects unauthenticated request" do
      conn =
        build_conn()
        |> post("/api/v1/users/me/key-packages", %{
          key_packages: [Base.encode64("data")]
        })

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/users/:user_id/key-packages" do
    test "claims one key package", %{conn: conn, user: user} do
      upload_packages(conn, 3)

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/#{user.id}/key-packages")

      response = json_response(conn2, 200)
      assert response["key_package"]
      # base64-encoded binary data
      assert {:ok, _data} = Base.decode64(response["key_package"])
    end

    test "consuming reduces count", %{conn: conn, user: user} do
      upload_packages(conn, 3)
      assert Keys.count_mls_key_packages(user.id) == 3

      _conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/#{user.id}/key-packages")

      assert Keys.count_mls_key_packages(user.id) == 2
    end

    test "returns 404 when no packages available", %{conn: _conn, user: user} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/#{user.id}/key-packages")

      assert %{"error" => "no key packages available"} = json_response(conn, 404)
    end

    test "each claimed package is unique", %{conn: conn, user: user} do
      upload_packages(conn, 3)

      packages =
        for _i <- 1..3 do
          conn2 =
            build_conn()
            |> put_req_header("authorization", "Bearer #{get_token(user)}")
            |> get("/api/v1/users/#{user.id}/key-packages")

          json_response(conn2, 200)["key_package"]
        end

      assert length(Enum.uniq(packages)) == 3
    end
  end

  describe "GET /api/v1/users/me/key-packages/count" do
    test "returns count of remaining key packages", %{conn: conn, user: user} do
      upload_packages(conn, 5)

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/me/key-packages/count")

      assert %{"count" => 5} = json_response(conn2, 200)
    end

    test "returns 0 when no packages uploaded", %{conn: _conn, user: user} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/me/key-packages/count")

      assert %{"count" => 0} = json_response(conn, 200)
    end

    test "count decreases as packages are claimed", %{conn: conn, user: user} do
      upload_packages(conn, 3)
      assert Keys.count_mls_key_packages(user.id) == 3

      {:ok, _} = Keys.consume_mls_key_package(user.id)
      assert Keys.count_mls_key_packages(user.id) == 2

      {:ok, _} = Keys.consume_mls_key_package(user.id)
      assert Keys.count_mls_key_packages(user.id) == 1

      {:ok, _} = Keys.consume_mls_key_package(user.id)
      assert Keys.count_mls_key_packages(user.id) == 0

      assert {:error, :exhausted} = Keys.consume_mls_key_package(user.id)
    end
  end

  defp register_user(username) do
    {:ok, {user, _recovery_codes}} =
      Accounts.register_user(%{
        "username" => username,
        "password" => @valid_password
      })

    {:ok, tokens} = Murmuring.Auth.generate_tokens(user)
    {user, tokens}
  end

  defp get_token(user) do
    {:ok, tokens} = Murmuring.Auth.generate_tokens(user)
    tokens.access_token
  end

  defp upload_packages(conn, count) do
    packages = for _i <- 1..count, do: Base.encode64(:crypto.strong_rand_bytes(256))
    post(conn, "/api/v1/users/me/key-packages", %{key_packages: packages})
  end
end
