defmodule CairnWeb.AuthControllerTest do
  use CairnWeb.ConnCase, async: true

  alias Cairn.Accounts

  @valid_password "secure_password_123"

  describe "POST /api/v1/auth/register" do
    test "registers a new user and returns tokens", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "testuser",
          password: @valid_password,
          display_name: "Test User"
        })

      assert %{
               "user" => %{"username" => "testuser", "display_name" => "Test User"},
               "access_token" => access_token,
               "refresh_token" => refresh_token,
               "recovery_codes" => recovery_codes
             } = json_response(conn, 201)

      assert is_binary(access_token)
      assert is_binary(refresh_token)
      assert length(recovery_codes) == 12
    end

    test "rejects short password", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "testuser",
          password: "short"
        })

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "rejects duplicate username", %{conn: conn} do
      register_user("taken_user")

      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "taken_user",
          password: @valid_password
        })

      assert %{"errors" => %{"username" => _}} = json_response(conn, 422)
    end
  end

  describe "POST /api/v1/auth/login" do
    test "logs in with valid credentials", %{conn: conn} do
      register_user("loginuser")

      conn =
        post(conn, "/api/v1/auth/login", %{
          username: "loginuser",
          password: @valid_password
        })

      assert %{
               "user" => %{"username" => "loginuser"},
               "access_token" => _,
               "refresh_token" => _
             } = json_response(conn, 200)
    end

    test "rejects invalid password", %{conn: conn} do
      register_user("loginuser2")

      conn =
        post(conn, "/api/v1/auth/login", %{
          username: "loginuser2",
          password: "wrong_password_here"
        })

      assert %{"error" => "invalid credentials"} = json_response(conn, 401)
    end

    test "rejects nonexistent user", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/login", %{
          username: "nobody",
          password: @valid_password
        })

      assert %{"error" => "invalid credentials"} = json_response(conn, 401)
    end
  end

  describe "POST /api/v1/auth/refresh" do
    test "rotates refresh token", %{conn: conn} do
      {_user, tokens} = register_user("refreshuser")

      conn =
        post(conn, "/api/v1/auth/refresh", %{
          refresh_token: tokens.refresh_token
        })

      assert %{
               "access_token" => new_access,
               "refresh_token" => new_refresh
             } = json_response(conn, 200)

      assert new_access != tokens.access_token
      assert new_refresh != tokens.refresh_token

      # Old token should no longer work
      conn2 =
        build_conn()
        |> post("/api/v1/auth/refresh", %{refresh_token: tokens.refresh_token})

      assert %{"error" => _} = json_response(conn2, 401)
    end

    test "rejects invalid refresh token", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/refresh", %{refresh_token: "bogus_token"})
      assert %{"error" => _} = json_response(conn, 401)
    end
  end

  describe "GET /api/v1/auth/me" do
    test "returns current user with valid token", %{conn: conn} do
      {_user, tokens} = register_user("meuser")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get("/api/v1/auth/me")

      assert %{"user" => %{"username" => "meuser"}} = json_response(conn, 200)
    end

    test "rejects unauthenticated request", %{conn: conn} do
      conn = get(conn, "/api/v1/auth/me")
      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/auth/recover" do
    test "recovers account with valid recovery code", %{conn: conn} do
      {_user, tokens} = register_user("recoveruser")
      [first_code | _] = tokens.recovery_codes

      conn =
        post(conn, "/api/v1/auth/recover", %{
          username: "recoveruser",
          recovery_code: first_code,
          new_password: "new_secure_password_456"
        })

      assert %{
               "user" => %{"username" => "recoveruser"},
               "access_token" => _,
               "refresh_token" => _
             } = json_response(conn, 200)

      # Old password should no longer work
      conn2 =
        build_conn()
        |> post("/api/v1/auth/login", %{
          username: "recoveruser",
          password: @valid_password
        })

      assert %{"error" => "invalid credentials"} = json_response(conn2, 401)

      # New password should work
      conn3 =
        build_conn()
        |> post("/api/v1/auth/login", %{
          username: "recoveruser",
          password: "new_secure_password_456"
        })

      assert %{"access_token" => _} = json_response(conn3, 200)
    end

    test "rejects invalid recovery code", %{conn: conn} do
      register_user("recoveruser2")

      conn =
        post(conn, "/api/v1/auth/recover", %{
          username: "recoveruser2",
          recovery_code: "invalid_code",
          new_password: "new_secure_password_456"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end
  end

  describe "GET /api/v1/auth/challenge" do
    test "returns a valid ALTCHA challenge", %{conn: conn} do
      conn = get(conn, "/api/v1/auth/challenge")

      assert %{
               "algorithm" => "SHA-256",
               "challenge" => challenge,
               "maxnumber" => maxnumber,
               "salt" => salt,
               "signature" => signature
             } = json_response(conn, 200)

      assert is_binary(challenge)
      assert is_integer(maxnumber)
      assert is_binary(salt)
      assert is_binary(signature)
    end
  end

  describe "honeypot and PoW" do
    test "rejects registration when honeypot field is filled", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "honeypotuser",
          password: @valid_password,
          website: "http://spam.example.com"
        })

      assert %{"error" => "invalid request"} = json_response(conn, 422)
    end

    test "allows registration when honeypot field is empty", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "cleanuser",
          password: @valid_password,
          website: ""
        })

      assert %{"user" => %{"username" => "cleanuser"}} = json_response(conn, 201)
    end

    test "rejects registration when PoW is required but missing", %{conn: conn} do
      original = Application.get_env(:cairn, :require_pow)
      Application.put_env(:cairn, :require_pow, true)

      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "powuser",
          password: @valid_password
        })

      assert %{"error" => "proof of work required"} = json_response(conn, 422)

      Application.put_env(:cairn, :require_pow, original || false)
    end

    test "accepts registration with valid PoW solution", %{conn: conn} do
      original = Application.get_env(:cairn, :require_pow)
      Application.put_env(:cairn, :require_pow, true)

      hmac_key = Application.fetch_env!(:cairn, :altcha_hmac_key)

      challenge =
        Altcha.create_challenge(%Altcha.ChallengeOptions{
          hmac_key: hmac_key,
          max_number: 1_000
        })

      solution =
        Altcha.solve_challenge(
          challenge.challenge,
          challenge.salt,
          challenge.algorithm,
          challenge.maxnumber
        )

      payload =
        Base.encode64(
          Jason.encode!(%{
            algorithm: "SHA-256",
            challenge: challenge.challenge,
            number: solution.number,
            salt: challenge.salt,
            signature: challenge.signature
          })
        )

      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "powvaliduser",
          password: @valid_password,
          altcha: payload
        })

      assert %{"user" => %{"username" => "powvaliduser"}} = json_response(conn, 201)

      Application.put_env(:cairn, :require_pow, original || false)
    end

    test "rejects registration with invalid PoW solution", %{conn: conn} do
      original = Application.get_env(:cairn, :require_pow)
      Application.put_env(:cairn, :require_pow, true)

      payload =
        Base.encode64(
          Jason.encode!(%{
            algorithm: "SHA-256",
            challenge: "bogus",
            number: 42,
            salt: "fakesalt",
            signature: "badsig"
          })
        )

      conn =
        post(conn, "/api/v1/auth/register", %{
          username: "powbaduser",
          password: @valid_password,
          altcha: payload
        })

      assert %{"error" => "invalid proof of work"} = json_response(conn, 422)

      Application.put_env(:cairn, :require_pow, original || false)
    end
  end

  defp register_user(username) do
    {:ok, {user, recovery_codes}} =
      Accounts.register_user(%{
        "username" => username,
        "password" => @valid_password
      })

    {:ok, tokens} = Cairn.Auth.generate_tokens(user)
    {user, Map.put(tokens, :recovery_codes, recovery_codes)}
  end
end
