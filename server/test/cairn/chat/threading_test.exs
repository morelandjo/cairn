defmodule Cairn.Chat.ThreadingTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Chat, Servers}

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "threaduser_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_channel do
    owner = create_user("owner")
    {:ok, server} = Servers.create_server(%{name: "ThreadTest", creator_id: owner.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})
    %{owner: owner, channel: channel}
  end

  describe "threading" do
    test "create message with reply_to_id" do
      %{owner: owner, channel: channel} = setup_channel()

      {:ok, parent} =
        Chat.create_message(%{content: "Parent msg", channel_id: channel.id, author_id: owner.id})

      {:ok, reply} =
        Chat.create_message(%{
          content: "Reply!",
          channel_id: channel.id,
          author_id: owner.id,
          reply_to_id: parent.id
        })

      assert reply.reply_to_id == parent.id
    end

    test "get_thread returns replies to a message" do
      %{owner: owner, channel: channel} = setup_channel()

      {:ok, parent} =
        Chat.create_message(%{content: "Parent", channel_id: channel.id, author_id: owner.id})

      {:ok, _reply1} =
        Chat.create_message(%{
          content: "Reply 1",
          channel_id: channel.id,
          author_id: owner.id,
          reply_to_id: parent.id
        })

      {:ok, _reply2} =
        Chat.create_message(%{
          content: "Reply 2",
          channel_id: channel.id,
          author_id: owner.id,
          reply_to_id: parent.id
        })

      {:ok, _unrelated} =
        Chat.create_message(%{content: "Unrelated", channel_id: channel.id, author_id: owner.id})

      thread = Chat.get_thread(parent.id)
      assert length(thread) == 2
      assert Enum.all?(thread, fn m -> m.reply_to_id == parent.id end)
    end

    test "thread replies are ordered by insertion time" do
      %{owner: owner, channel: channel} = setup_channel()

      {:ok, parent} =
        Chat.create_message(%{content: "Parent", channel_id: channel.id, author_id: owner.id})

      {:ok, r1} =
        Chat.create_message(%{
          content: "First",
          channel_id: channel.id,
          author_id: owner.id,
          reply_to_id: parent.id
        })

      {:ok, r2} =
        Chat.create_message(%{
          content: "Second",
          channel_id: channel.id,
          author_id: owner.id,
          reply_to_id: parent.id
        })

      thread = Chat.get_thread(parent.id)
      assert hd(thread).id == r1.id
      assert List.last(thread).id == r2.id
    end
  end
end
