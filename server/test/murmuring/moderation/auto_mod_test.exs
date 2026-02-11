defmodule Murmuring.Moderation.AutoModTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.{Accounts, Moderation, Servers}
  alias Murmuring.Moderation.AutoMod

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "automod_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_server do
    owner = create_user("owner")
    {:ok, server} = Servers.create_server(%{name: "AutoModTest", creator_id: owner.id})
    %{owner: owner, server: server}
  end

  describe "word_filter" do
    test "blocks messages containing blocked words" do
      %{server: server} = setup_server()

      {:ok, _} =
        Moderation.create_auto_mod_rule(%{
          server_id: server.id,
          rule_type: "word_filter",
          config: %{"words" => ["badword", "spam"], "action" => "delete"}
        })

      assert {:violation, "delete", "word_filter"} =
               AutoMod.check_message(server.id, "This contains badword in it")

      assert :ok = AutoMod.check_message(server.id, "This is a clean message")
    end

    test "case insensitive matching" do
      %{server: server} = setup_server()

      {:ok, _} =
        Moderation.create_auto_mod_rule(%{
          server_id: server.id,
          rule_type: "word_filter",
          config: %{"words" => ["BadWord"], "action" => "delete"}
        })

      assert {:violation, _, _} = AutoMod.check_message(server.id, "BADWORD here")
    end
  end

  describe "regex_filter" do
    test "blocks messages matching regex patterns" do
      %{server: server} = setup_server()

      {:ok, _} =
        Moderation.create_auto_mod_rule(%{
          server_id: server.id,
          rule_type: "regex_filter",
          config: %{"patterns" => ["\\d{4}-\\d{4}-\\d{4}-\\d{4}"], "action" => "delete"}
        })

      assert {:violation, "delete", "regex_filter"} =
               AutoMod.check_message(server.id, "My card is 1234-5678-9012-3456")

      assert :ok = AutoMod.check_message(server.id, "No numbers here")
    end
  end

  describe "link_filter" do
    test "blocks all links when no allowed domains" do
      %{server: server} = setup_server()

      {:ok, _} =
        Moderation.create_auto_mod_rule(%{
          server_id: server.id,
          rule_type: "link_filter",
          config: %{"action" => "delete"}
        })

      assert {:violation, "delete", "link_filter"} =
               AutoMod.check_message(server.id, "Check out https://example.com")

      assert :ok = AutoMod.check_message(server.id, "No links here")
    end

    test "allows specified domains" do
      %{server: server} = setup_server()

      {:ok, _} =
        Moderation.create_auto_mod_rule(%{
          server_id: server.id,
          rule_type: "link_filter",
          config: %{"allowed_domains" => ["example.com"], "action" => "delete"}
        })

      assert :ok = AutoMod.check_message(server.id, "Check https://example.com/page")
      assert {:violation, _, _} = AutoMod.check_message(server.id, "Check https://evil.com/page")
    end
  end

  describe "mention_spam" do
    test "blocks messages with too many mentions" do
      %{server: server} = setup_server()

      {:ok, _} =
        Moderation.create_auto_mod_rule(%{
          server_id: server.id,
          rule_type: "mention_spam",
          config: %{"max_mentions" => 3, "action" => "mute"}
        })

      assert {:violation, "mute", "mention_spam"} =
               AutoMod.check_message(server.id, "@user1 @user2 @user3 @user4 hey")

      assert :ok = AutoMod.check_message(server.id, "@user1 @user2 hello")
    end
  end

  describe "disabled rules" do
    test "disabled rules are skipped" do
      %{server: server} = setup_server()

      {:ok, rule} =
        Moderation.create_auto_mod_rule(%{
          server_id: server.id,
          rule_type: "word_filter",
          config: %{"words" => ["blocked"], "action" => "delete"}
        })

      assert {:violation, _, _} = AutoMod.check_message(server.id, "blocked content")

      {:ok, _} = Moderation.update_auto_mod_rule(rule, %{enabled: false})
      assert :ok = AutoMod.check_message(server.id, "blocked content")
    end
  end
end
