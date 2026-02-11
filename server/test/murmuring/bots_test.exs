defmodule Murmuring.BotsTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.{Accounts, Bots, Servers}
  alias Murmuring.Chat

  @valid_password "secure_password_123"

  defp create_user(username) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp create_server(user) do
    {:ok, server} = Servers.create_server(%{name: "Test Server", creator_id: user.id})
    server
  end

  describe "webhooks" do
    test "create, list, and delete webhook" do
      user = create_user("webhookuser")
      server = create_server(user)

      {:ok, channel} =
        Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

      {:ok, webhook} =
        Bots.create_webhook(%{
          name: "My Webhook",
          server_id: server.id,
          channel_id: channel.id,
          creator_id: user.id
        })

      assert webhook.name == "My Webhook"
      assert webhook.token != nil

      webhooks = Bots.list_webhooks(server.id)
      assert length(webhooks) == 1

      {:ok, _} = Bots.delete_webhook(webhook)
      assert Bots.list_webhooks(server.id) == []
    end

    test "execute webhook creates a message" do
      user = create_user("webhookexec")
      server = create_server(user)

      {:ok, channel} =
        Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

      {:ok, webhook} =
        Bots.create_webhook(%{
          name: "Poster",
          server_id: server.id,
          channel_id: channel.id,
          creator_id: user.id
        })

      {:ok, message} = Bots.execute_webhook(webhook.token, %{"content" => "Hello from webhook!"})
      assert message.content == "Hello from webhook!"
      assert message.channel_id == channel.id
    end

    test "execute webhook with invalid token returns not_found" do
      assert {:error, :not_found} = Bots.execute_webhook("invalid_token", %{"content" => "hi"})
    end

    test "regenerate webhook token" do
      user = create_user("webhookregen")
      server = create_server(user)

      {:ok, channel} =
        Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

      {:ok, webhook} =
        Bots.create_webhook(%{
          name: "Regen",
          server_id: server.id,
          channel_id: channel.id,
          creator_id: user.id
        })

      old_token = webhook.token
      {:ok, updated} = Bots.regenerate_webhook_token(webhook)
      assert updated.token != old_token
    end
  end

  describe "bot accounts" do
    test "create bot with user account" do
      user = create_user("botcreator")
      server = create_server(user)

      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      assert result.token != nil
      assert result.user.is_bot == true
      assert String.starts_with?(result.user.username, "bot_")
      assert result.bot_account.server_id == server.id
    end

    test "list bots" do
      user = create_user("botlister")
      server = create_server(user)

      {:ok, _} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})
      {:ok, _} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      bots = Bots.list_bots(server.id)
      assert length(bots) == 2
    end

    test "authenticate bot by token" do
      user = create_user("botauth")
      server = create_server(user)

      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      bot = Bots.get_bot_by_token(result.token)
      assert bot != nil
      assert bot.user_id == result.user.id
    end

    test "update bot channels" do
      user = create_user("botchannels")
      server = create_server(user)

      {:ok, channel} =
        Chat.create_channel(%{name: "allowed", type: "public", server_id: server.id})

      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      {:ok, updated} = Bots.update_bot_channels(result.bot_account, [channel.id])
      assert updated.allowed_channels == [channel.id]
    end

    test "regenerate bot token" do
      user = create_user("botregen")
      server = create_server(user)

      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      old_token = result.token
      {:ok, new_token} = Bots.regenerate_bot_token(result.bot_account)
      assert new_token != old_token

      # Old token should no longer work
      assert Bots.get_bot_by_token(old_token) == nil
      # New token should work
      assert Bots.get_bot_by_token(new_token) != nil
    end

    test "delete bot" do
      user = create_user("botdelete")
      server = create_server(user)

      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      {:ok, _} = Bots.delete_bot(result.bot_account)
      assert Bots.list_bots(server.id) == []
    end

    test "get_bot_for_user returns bot for matching user and server" do
      user = create_user("botforuser")
      server = create_server(user)

      {:ok, result} = Bots.create_bot(%{server_id: server.id, creator_id: user.id})

      bot = Bots.get_bot_for_user(result.user.id, server.id)
      assert bot != nil
      assert bot.id == result.bot_account.id
    end
  end
end
