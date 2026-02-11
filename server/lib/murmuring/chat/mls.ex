defmodule Murmuring.Chat.Mls do
  @moduledoc """
  MLS delivery service — stores and relays opaque MLS protocol messages.

  The server is untrusted: it stores binary blobs without inspecting them.
  Clients are responsible for MLS state management.
  """

  import Ecto.Query
  alias Murmuring.Repo
  alias Murmuring.Chat.{MlsMessage, MlsGroupInfo}

  # --- Group Info ---

  @doc "Store or update the MLS group info for a channel (upsert)."
  def store_group_info(channel_id, data, epoch) do
    case Repo.get_by(MlsGroupInfo, channel_id: channel_id) do
      nil ->
        %MlsGroupInfo{}
        |> MlsGroupInfo.changeset(%{channel_id: channel_id, data: data, epoch: epoch})
        |> Repo.insert()

      existing ->
        existing
        |> MlsGroupInfo.changeset(%{data: data, epoch: epoch})
        |> Repo.update()
    end
  end

  @doc "Get the latest MLS group info for a channel."
  def get_group_info(channel_id) do
    Repo.get_by(MlsGroupInfo, channel_id: channel_id)
  end

  # --- MLS Protocol Messages ---

  @doc "Store an MLS commit message."
  def store_commit(channel_id, sender_id, data, epoch) do
    store_message(channel_id, sender_id, nil, "commit", data, epoch)
  end

  @doc "Store an MLS proposal message."
  def store_proposal(channel_id, sender_id, data, epoch) do
    store_message(channel_id, sender_id, nil, "proposal", data, epoch)
  end

  @doc "Store an MLS welcome message for a specific recipient."
  def store_welcome(channel_id, sender_id, recipient_id, data) do
    store_message(channel_id, sender_id, recipient_id, "welcome", data, nil)
  end

  @doc """
  Get pending (unprocessed) MLS messages for a channel.
  Optionally filter by recipient_id for Welcome messages.
  Returns messages ordered by insertion time (oldest first).
  """
  def get_pending_messages(channel_id, opts \\ []) do
    recipient_id = Keyword.get(opts, :recipient_id)

    query =
      from(m in MlsMessage,
        where: m.channel_id == ^channel_id and m.processed == false,
        order_by: [asc: m.inserted_at]
      )

    query =
      if recipient_id do
        from(m in query,
          where: is_nil(m.recipient_id) or m.recipient_id == ^recipient_id
        )
      else
        query
      end

    Repo.all(query)
  end

  @doc "Mark an MLS message as processed."
  def mark_processed(message_id) do
    case Repo.get(MlsMessage, message_id) do
      nil ->
        {:error, :not_found}

      message ->
        message
        |> Ecto.Changeset.change(processed: true)
        |> Repo.update()
    end
  end

  @doc "Mark multiple MLS messages as processed."
  def mark_all_processed(message_ids) when is_list(message_ids) do
    from(m in MlsMessage, where: m.id in ^message_ids)
    |> Repo.update_all(set: [processed: true])
  end

  defp store_message(channel_id, sender_id, recipient_id, type, data, epoch) do
    %MlsMessage{}
    |> MlsMessage.changeset(%{
      channel_id: channel_id,
      sender_id: sender_id,
      recipient_id: recipient_id,
      message_type: type,
      data: data,
      epoch: epoch
    })
    |> Repo.insert()
  end
end
