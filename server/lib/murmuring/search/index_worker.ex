defmodule Murmuring.Search.IndexWorker do
  use Oban.Worker, queue: :search, max_attempts: 3

  alias Murmuring.Chat
  alias Murmuring.Search

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    case Chat.get_message(message_id) do
      nil ->
        :ok

      message ->
        # Only index public, non-encrypted, non-deleted messages
        message = Murmuring.Repo.preload(message, [:channel])

        if message.channel.type == "public" and
             is_nil(message.encrypted_content) and
             is_nil(message.deleted_at) and
             message.content do
          Search.index_message(message)
        end

        :ok
    end
  end
end
