defmodule Cairn.ExportTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Export, Servers}
  alias Cairn.Chat

  @valid_password "secure_password_123"

  defp create_user(username) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  test "generate_export creates JSON file with user data" do
    user = create_user("exportuser")
    {:ok, server} = Servers.create_server(%{name: "Export Server", creator_id: user.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    # Create some messages
    {:ok, _} =
      Chat.create_message(%{content: "Hello world", channel_id: channel.id, author_id: user.id})

    {:ok, _} =
      Chat.create_message(%{content: "Second msg", channel_id: channel.id, author_id: user.id})

    {:ok, result} = Export.generate_export(user.id)

    assert result.filename =~ "export_#{user.id}"
    assert result.size > 0

    # Read and verify content
    content = File.read!(result.path) |> Jason.decode!()
    assert content["user"]["username"] == user.username
    assert length(content["messages"]) == 2
    assert length(content["servers"]) == 1

    # Cleanup
    File.rm!(result.path)
  end

  test "get_export_file returns latest export" do
    user = create_user("exportget")

    {:ok, result} = Export.generate_export(user.id)
    {:ok, path} = Export.get_export_file(user.id)
    assert path == result.path

    # Cleanup
    File.rm!(result.path)
  end

  test "get_export_file returns not_found when no export exists" do
    user = create_user("exportnone")
    assert {:error, :not_found} = Export.get_export_file(user.id)
  end

  test "export_portability_data returns user identity data" do
    user = create_user("exportport")

    {:ok, data} = Export.export_portability_data(user.id)
    assert data.version == "1.0"
    assert data.platform == "cairn"
    assert data.user.username == user.username
  end

  test "request_export enqueues an Oban job" do
    user = create_user("exportjob")

    {:ok, job} = Export.request_export(user.id)
    assert job.worker == "Cairn.Export.DataExportWorker"
    assert job.args["user_id"] == user.id
  end
end
