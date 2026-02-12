defmodule MurmuringWeb.KeyControllerTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.Accounts
  alias Murmuring.Keys

  @valid_password "secure_password_123"

  setup %{conn: conn} do
    {user, tokens} = register_user("keyuser")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {:ok, conn: conn, user: user, tokens: tokens}
  end

  describe "POST /api/v1/users/me/keys" do
    test "uploads key bundle with identity key, signed prekey, and OTPs", %{conn: conn} do
      conn =
        post(conn, "/api/v1/users/me/keys", %{
          identity_public_key: Base.encode64("identity_key_32_bytes_padding!!"),
          signed_prekey: Base.encode64("signed_prekey_32_bytes_padding!"),
          signed_prekey_signature: Base.encode64("signature_64_bytes_padding_here!"),
          one_time_prekeys: [
            %{key_id: 1, public_key: Base.encode64("otp_key_1_padding_bytes_needed!")},
            %{key_id: 2, public_key: Base.encode64("otp_key_2_padding_bytes_needed!")},
            %{key_id: 3, public_key: Base.encode64("otp_key_3_padding_bytes_needed!")}
          ]
        })

      assert %{"uploaded_prekeys" => 3} = json_response(conn, 201)
    end

    test "rejects invalid base64", %{conn: conn} do
      conn =
        post(conn, "/api/v1/users/me/keys", %{
          identity_public_key: "not-valid-base64!!!",
          signed_prekey: Base.encode64("signed_prekey_32_bytes_padding!"),
          signed_prekey_signature: Base.encode64("signature"),
          one_time_prekeys: []
        })

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "rejects unauthenticated request", %{conn: _conn} do
      conn =
        build_conn()
        |> post("/api/v1/users/me/keys", %{
          identity_public_key: Base.encode64("key"),
          signed_prekey: Base.encode64("key"),
          signed_prekey_signature: Base.encode64("sig"),
          one_time_prekeys: []
        })

      assert json_response(conn, 401)
    end

    test "uploads with no one-time prekeys", %{conn: conn} do
      conn =
        post(conn, "/api/v1/users/me/keys", %{
          identity_public_key: Base.encode64("identity_key_32_bytes_padding!!"),
          signed_prekey: Base.encode64("signed_prekey_32_bytes_padding!"),
          signed_prekey_signature: Base.encode64("signature_64_bytes_padding_here!"),
          one_time_prekeys: []
        })

      assert %{"uploaded_prekeys" => 0} = json_response(conn, 201)
    end
  end

  describe "GET /api/v1/users/:user_id/keys" do
    test "returns key bundle and consumes one OTP", %{conn: conn, user: user} do
      upload_key_bundle(conn, 3)

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/#{user.id}/keys")

      response = json_response(conn2, 200)
      assert response["identity_public_key"]
      assert response["signed_prekey"]
      assert response["signed_prekey_signature"]
      assert response["one_time_prekey"]["key_id"]
      assert response["one_time_prekey"]["public_key"]

      # Should have consumed one OTP (3 - 1 = 2 remaining)
      assert Keys.count_prekeys(user.id) == 2
    end

    test "returns bundle without OTP when all are consumed", %{conn: conn, user: user} do
      upload_key_bundle(conn, 1)

      # Consume the only OTP
      {:ok, _bundle} = Keys.get_key_bundle(user.id)
      assert Keys.count_prekeys(user.id) == 0

      # Now fetch again — no OTP should be returned
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/#{user.id}/keys")

      response = json_response(conn2, 200)
      assert response["identity_public_key"]
      refute Map.has_key?(response, "one_time_prekey")
    end

    test "returns 404 for nonexistent user", %{conn: _conn, user: user} do
      fake_id = Ecto.UUID.generate()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/#{fake_id}/keys")

      assert %{"error" => "user not found"} = json_response(conn, 404)
    end

    test "returns 404 when user has no keys uploaded", %{conn: _conn, user: user} do
      {other_user, _tokens} = register_user("nokeysuser")

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/#{other_user.id}/keys")

      assert %{"error" => "no keys uploaded"} = json_response(conn, 404)
    end

    test "OTPs are consumed one at a time", %{conn: conn, user: user} do
      upload_key_bundle(conn, 5)

      assert Keys.count_prekeys(user.id) == 5

      # Consume prekeys one at a time
      {:ok, bundle1} = Keys.get_key_bundle(user.id)
      assert bundle1.one_time_prekey != nil
      assert Keys.count_prekeys(user.id) == 4

      {:ok, bundle2} = Keys.get_key_bundle(user.id)
      assert bundle2.one_time_prekey != nil
      assert Keys.count_prekeys(user.id) == 3

      # Each consumed key should be different
      assert bundle1.one_time_prekey.key_id != bundle2.one_time_prekey.key_id

      {:ok, _} = Keys.get_key_bundle(user.id)
      {:ok, _} = Keys.get_key_bundle(user.id)
      {:ok, _} = Keys.get_key_bundle(user.id)
      assert Keys.count_prekeys(user.id) == 0

      # Next request should return nil OTP
      {:ok, bundle_no_otp} = Keys.get_key_bundle(user.id)
      assert bundle_no_otp.one_time_prekey == nil
    end
  end

  describe "GET /api/v1/users/me/keys/prekey-count" do
    test "returns count of remaining prekeys", %{conn: conn, user: user} do
      upload_key_bundle(conn, 5)

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/me/keys/prekey-count")

      assert %{"count" => 5} = json_response(conn2, 200)
    end

    test "returns 0 when no prekeys uploaded", %{conn: _conn, user: user} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{get_token(user)}")
        |> get("/api/v1/users/me/keys/prekey-count")

      assert %{"count" => 0} = json_response(conn, 200)
    end

    test "count decreases as prekeys are consumed", %{conn: conn, user: user} do
      upload_key_bundle(conn, 3)

      assert Keys.count_prekeys(user.id) == 3

      {:ok, _} = Keys.get_key_bundle(user.id)
      assert Keys.count_prekeys(user.id) == 2

      {:ok, _} = Keys.get_key_bundle(user.id)
      assert Keys.count_prekeys(user.id) == 1
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

  defp upload_key_bundle(conn, num_otps) do
    otps =
      for i <- 1..num_otps do
        %{key_id: i, public_key: Base.encode64("otp_key_#{i}_padding_bytes_here!")}
      end

    post(conn, "/api/v1/users/me/keys", %{
      identity_public_key: Base.encode64("identity_key_32_bytes_padding!!"),
      signed_prekey: Base.encode64("signed_prekey_32_bytes_padding!"),
      signed_prekey_signature: Base.encode64("signature_64_bytes_padding_here!"),
      one_time_prekeys: otps
    })
  end
end
