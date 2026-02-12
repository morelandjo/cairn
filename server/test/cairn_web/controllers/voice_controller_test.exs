defmodule MurmuringWeb.VoiceControllerTest do
  use MurmuringWeb.ConnCase, async: true

  alias Murmuring.{Accounts, Auth}

  @valid_password "secure_password_123"

  setup %{conn: conn} do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "voicectrl_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {:ok, conn: conn, user: user}
  end

  describe "GET /api/v1/voice/turn-credentials" do
    test "returns empty ice servers when no TURN configured", %{conn: conn} do
      conn = get(conn, "/api/v1/voice/turn-credentials")
      assert %{"iceServers" => []} = json_response(conn, 200)
    end

    test "returns TURN credentials when configured", %{conn: conn} do
      Application.put_env(:murmuring, :turn_urls, ["turn:turn.example.com:3478"])

      on_exit(fn ->
        Application.put_env(:murmuring, :turn_urls, [])
      end)

      conn = get(conn, "/api/v1/voice/turn-credentials")
      assert %{"iceServers" => [server]} = json_response(conn, 200)
      assert server["urls"] == ["turn:turn.example.com:3478"]
      assert is_binary(server["username"])
      assert is_binary(server["credential"])
    end
  end

  describe "GET /api/v1/voice/ice-servers" do
    test "returns at least STUN servers", %{conn: conn} do
      conn = get(conn, "/api/v1/voice/ice-servers")
      assert %{"iceServers" => servers} = json_response(conn, 200)
      assert length(servers) >= 1
      assert hd(servers)["urls"] == ["stun:stun.l.google.com:19302"]
    end

    test "includes TURN when configured", %{conn: conn} do
      Application.put_env(:murmuring, :turn_urls, ["turn:turn.example.com:3478"])

      on_exit(fn ->
        Application.put_env(:murmuring, :turn_urls, [])
      end)

      conn = get(conn, "/api/v1/voice/ice-servers")
      assert %{"iceServers" => servers} = json_response(conn, 200)
      assert length(servers) == 2
    end
  end
end
