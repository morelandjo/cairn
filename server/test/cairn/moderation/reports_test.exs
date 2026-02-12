defmodule Cairn.Moderation.ReportsTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Chat, Moderation, Servers}

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "report_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup do
    owner = create_user("owner")
    reporter = create_user("reporter")
    {:ok, server} = Servers.create_server(%{name: "ReportTest", creator_id: owner.id})
    {:ok, _} = Servers.add_member(server.id, reporter.id)
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    {:ok, msg} =
      Chat.create_message(%{
        content: "Bad message",
        channel_id: channel.id,
        author_id: reporter.id
      })

    %{owner: owner, reporter: reporter, server: server, channel: channel, message: msg}
  end

  describe "reports" do
    test "create and list reports" do
      %{reporter: reporter, server: server, message: msg} = setup()

      {:ok, report} =
        Moderation.create_report(%{
          message_id: msg.id,
          reporter_id: reporter.id,
          server_id: server.id,
          reason: "spam"
        })

      assert report.status == "pending"

      reports = Moderation.list_reports(server.id)
      assert length(reports) == 1
      assert hd(reports).reason == "spam"
    end

    test "resolve a report" do
      %{owner: owner, reporter: reporter, server: server, message: msg} = setup()

      {:ok, report} =
        Moderation.create_report(%{
          message_id: msg.id,
          reporter_id: reporter.id,
          server_id: server.id,
          reason: "harassment"
        })

      {:ok, resolved} =
        Moderation.resolve_report(report.id, owner.id, %{
          "status" => "actioned",
          "action" => "user_warned"
        })

      assert resolved.status == "actioned"
      assert resolved.resolution_action == "user_warned"
    end
  end
end
