defmodule CairnWeb.FederationControllerTest do
  use CairnWeb.ConnCase

  alias Cairn.Federation.NodeIdentity

  setup do
    # Start NodeIdentity with a temp key for these tests
    tmp_dir = Path.join(System.tmp_dir!(), "cairn_fed_ctrl_test")
    File.mkdir_p!(tmp_dir)
    key_path = Path.join(tmp_dir, "test_#{:erlang.unique_integer([:positive, :monotonic])}.key")

    # Enable federation in config for tests
    original_config = Application.get_env(:cairn, :federation, [])

    Application.put_env(:cairn, :federation,
      enabled: true,
      domain: "test.example.com"
    )

    # Stop any existing NodeIdentity process before starting a new one
    case Process.whereis(NodeIdentity) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        if Process.alive?(pid), do: GenServer.stop(pid)
    end

    {:ok, _pid} = NodeIdentity.start_link(key_path: key_path)

    on_exit(fn ->
      case Process.whereis(NodeIdentity) do
        nil ->
          :ok

        pid when is_pid(pid) ->
          if Process.alive?(pid), do: GenServer.stop(pid)
      end

      Application.put_env(:cairn, :federation, original_config)
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  describe "GET /.well-known/cairn-federation" do
    test "returns federation metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/cairn-federation")
      body = json_response(conn, 200)

      assert body["node_id"]
      assert String.length(body["node_id"]) == 64
      assert body["domain"] == "test.example.com"
      assert body["public_key"]
      assert body["protocol_version"] == "0.1.0"
      assert body["supported_versions"] == ["0.1.0"]
      assert body["inbox_url"] == "http://test.example.com/inbox"
      assert body["privacy_manifest"] == "http://test.example.com/.well-known/privacy-manifest"
      assert body["secure"] == false
    end

    test "returns 404 when federation disabled", %{conn: conn} do
      Application.put_env(:cairn, :federation, enabled: false, domain: "test.example.com")

      conn = get(conn, "/.well-known/cairn-federation")
      body = json_response(conn, 404)
      assert body["error"] =~ "not enabled"
    end
  end

  describe "GET /.well-known/privacy-manifest" do
    test "returns privacy manifest with defaults", %{conn: conn} do
      conn = get(conn, "/.well-known/privacy-manifest")
      body = json_response(conn, 200)

      assert body["version"] == "1.0"
      assert body["data_collection"]["ip_logging"] == false
      assert body["data_collection"]["analytics"] == false
      assert body["data_collection"]["metadata_retention_days"] == 30
      assert body["federation"]["strips_metadata"] == true
      assert body["federation"]["e2ee_supported"] == true
    end

    test "returns 404 when federation disabled", %{conn: conn} do
      Application.put_env(:cairn, :federation, enabled: false)

      conn = get(conn, "/.well-known/privacy-manifest")
      assert json_response(conn, 404)
    end
  end

  describe "GET /.well-known/webfinger" do
    test "resolves existing user", %{conn: conn} do
      # Create a user
      {:ok, {user, _recovery_codes}} =
        Cairn.Accounts.register_user(%{
          username: "feduser",
          password: "TestPassword123!",
          display_name: "Fed User"
        })

      conn =
        get(conn, "/.well-known/webfinger", %{
          "resource" => "acct:#{user.username}@test.example.com"
        })

      body = json_response(conn, 200)
      assert body["subject"] == "acct:feduser@test.example.com"
      assert [link] = body["links"]
      assert link["rel"] == "self"
      assert link["type"] == "application/activity+json"
      assert link["href"] == "http://test.example.com/users/feduser"
    end

    test "returns 404 for unknown user", %{conn: conn} do
      conn =
        get(conn, "/.well-known/webfinger", %{
          "resource" => "acct:nonexistent@test.example.com"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 404 for wrong domain", %{conn: conn} do
      conn =
        get(conn, "/.well-known/webfinger", %{
          "resource" => "acct:user@other.example.com"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 400 for invalid resource format", %{conn: conn} do
      conn =
        get(conn, "/.well-known/webfinger", %{
          "resource" => "invalid-format"
        })

      assert json_response(conn, 400)["error"] =~ "Invalid resource"
    end

    test "returns 400 when resource param missing", %{conn: conn} do
      conn = get(conn, "/.well-known/webfinger")
      assert json_response(conn, 400)["error"] =~ "Missing"
    end

    test "returns 404 when federation disabled", %{conn: conn} do
      Application.put_env(:cairn, :federation, enabled: false)

      conn =
        get(conn, "/.well-known/webfinger", %{
          "resource" => "acct:user@test.example.com"
        })

      assert json_response(conn, 404)
    end
  end
end
