defmodule CairnWeb.UploadControllerTest do
  use CairnWeb.ConnCase, async: true

  alias Cairn.Accounts

  @valid_password "secure_password_123"

  setup do
    root = Application.get_env(:cairn, Cairn.Storage.LocalBackend)[:root]

    tmp_dir =
      Path.join(System.tmp_dir!(), "cairn_upload_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(root)
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "POST /api/v1/upload" do
    test "uploads a text file successfully", %{conn: conn} do
      {_user, tokens} = register_user("uploader")

      upload = %Plug.Upload{
        path: create_tmp_file("hello world"),
        filename: "test.txt",
        content_type: "text/plain"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> post("/api/v1/upload", %{"file" => upload})

      assert %{
               "id" => id,
               "original_name" => "test.txt",
               "content_type" => "text/plain",
               "size_bytes" => 11,
               "storage_key" => _key
             } = json_response(conn, 201)

      assert is_binary(id)
    end

    test "rejects unauthenticated upload", %{conn: conn} do
      upload = %Plug.Upload{
        path: create_tmp_file("data"),
        filename: "test.txt",
        content_type: "text/plain"
      }

      conn = post(conn, "/api/v1/upload", %{"file" => upload})
      assert json_response(conn, 401)
    end

    test "rejects disallowed content type", %{conn: conn} do
      {_user, tokens} = register_user("uploader2")

      upload = %Plug.Upload{
        path: create_tmp_file("evil"),
        filename: "test.exe",
        content_type: "application/x-msdownload"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> post("/api/v1/upload", %{"file" => upload})

      assert %{"error" => "content type not allowed"} = json_response(conn, 422)
    end

    test "rejects file over 25MB", %{conn: conn, tmp_dir: tmp_dir} do
      {_user, tokens} = register_user("uploader3")

      # Create a file just over 25MB (in test-specific tmp_dir for cleanup)
      big_data = :binary.copy(<<0>>, 25 * 1024 * 1024 + 1)

      upload = %Plug.Upload{
        path: create_tmp_file(big_data, tmp_dir),
        filename: "big.bin",
        content_type: "application/pdf"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> post("/api/v1/upload", %{"file" => upload})

      assert %{"error" => "file exceeds 25MB limit"} = json_response(conn, 413)
    end
  end

  describe "GET /api/v1/files/:id" do
    test "downloads an uploaded file", %{conn: conn} do
      {_user, tokens} = register_user("downloader")

      upload = %Plug.Upload{
        path: create_tmp_file("file content here"),
        filename: "readme.txt",
        content_type: "text/plain"
      }

      create_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> post("/api/v1/upload", %{"file" => upload})

      %{"id" => id} = json_response(create_conn, 201)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get("/api/v1/files/#{id}")

      assert response(conn, 200) == "file content here"
      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/plain"
    end

    test "returns 404 for nonexistent file", %{conn: conn} do
      {_user, tokens} = register_user("downloader2")
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get("/api/v1/files/#{fake_id}")

      assert %{"error" => "file not found"} = json_response(conn, 404)
    end
  end

  describe "GET /api/v1/files/:id/thumbnail" do
    test "returns 404 when no thumbnail exists", %{conn: conn} do
      {_user, tokens} = register_user("thumbuser")

      upload = %Plug.Upload{
        path: create_tmp_file("just text"),
        filename: "plain.txt",
        content_type: "text/plain"
      }

      create_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> post("/api/v1/upload", %{"file" => upload})

      %{"id" => id} = json_response(create_conn, 201)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get("/api/v1/files/#{id}/thumbnail")

      assert %{"error" => "no thumbnail available"} = json_response(conn, 404)
    end

    test "returns thumbnail for uploaded image", %{conn: conn} do
      {_user, tokens} = register_user("thumbuser2")

      # Create a minimal valid JPEG — 1x1 white pixel
      jpeg_data = create_minimal_jpeg()

      upload = %Plug.Upload{
        path: create_tmp_file(jpeg_data),
        filename: "photo.jpg",
        content_type: "image/jpeg"
      }

      create_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> post("/api/v1/upload", %{"file" => upload})

      resp = json_response(create_conn, 201)
      assert resp["thumbnail_key"] != nil

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get("/api/v1/files/#{resp["id"]}/thumbnail")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> List.first() =~ "image/jpeg"
    end
  end

  defp register_user(username) do
    {:ok, {user, _recovery_codes}} =
      Accounts.register_user(%{
        "username" => username,
        "password" => @valid_password
      })

    {:ok, tokens} = Cairn.Auth.generate_tokens(user)
    {user, tokens}
  end

  defp create_tmp_file(content, dir \\ nil) do
    base = dir || System.tmp_dir!()
    path = Path.join(base, "cairn_test_#{:erlang.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp create_minimal_jpeg do
    # Use Image library to create a small valid JPEG in memory
    {:ok, image} = Image.new(10, 10, color: :white)
    {:ok, data} = Image.write(image, :memory, suffix: ".jpg", quality: 80)
    data
  end
end
