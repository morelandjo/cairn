defmodule Murmuring.Federation.MessageFederator do
  @moduledoc """
  Federates message create/edit/delete events to subscribed remote nodes.
  Enqueues Oban delivery jobs for each active federated node.

  DMs (channels with type "dm" or no server_id) are NEVER federated.
  """

  alias Murmuring.{Chat, Federation}
  alias Murmuring.Federation.ActivityPub
  alias Murmuring.Federation.DeliveryWorker

  @doc "Federate a new message to all active nodes."
  def federate_create(message, channel_id) do
    with_federation(channel_id, fn domain ->
      author = get_author(message)
      object = ActivityPub.serialize_message(message, channel_id, domain, author)

      activity =
        ActivityPub.wrap_activity(
          "Create",
          "https://#{domain}/users/#{message.author_id}",
          object,
          domain
        )

      deliver_to_active_nodes(activity)
    end)
  end

  @doc "Federate a message edit to all active nodes."
  def federate_update(message, channel_id) do
    with_federation(channel_id, fn domain ->
      author = get_author(message)
      object = ActivityPub.serialize_message(message, channel_id, domain, author)

      activity =
        ActivityPub.wrap_activity(
          "Update",
          "https://#{domain}/users/#{message.author_id}",
          object,
          domain
        )

      deliver_to_active_nodes(activity)
    end)
  end

  @doc "Federate a message deletion to all active nodes."
  def federate_delete(message, channel_id) do
    with_federation(channel_id, fn domain ->
      activity =
        ActivityPub.wrap_activity(
          "Delete",
          "https://#{domain}/users/#{message.author_id}",
          "https://#{domain}/channels/#{channel_id}/messages/#{message.id}",
          domain
        )

      deliver_to_active_nodes(activity)
    end)
  end

  # ── Private ──

  defp with_federation(channel_id, fun) do
    config = Application.get_env(:murmuring, :federation, [])

    if Keyword.get(config, :enabled, false) and not dm_channel?(channel_id) do
      domain = Keyword.get(config, :domain, "localhost")
      fun.(domain)
    end

    :ok
  end

  defp dm_channel?(channel_id) do
    case Chat.get_channel(channel_id) do
      nil -> true
      channel -> channel.type == "dm" or is_nil(channel.server_id)
    end
  end

  defp get_author(message) do
    if message.author_id do
      Murmuring.Accounts.get_user(message.author_id)
    end
  end

  defp deliver_to_active_nodes(activity) do
    Federation.list_nodes_by_status("active")
    |> Enum.each(fn node ->
      DeliveryWorker.enqueue(node.inbox_url, activity, node.id)
    end)
  end
end
