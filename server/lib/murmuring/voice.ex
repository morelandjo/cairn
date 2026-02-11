defmodule Murmuring.Voice do
  @moduledoc """
  Voice context — manages voice state for channels.
  """

  import Ecto.Query
  alias Murmuring.Repo
  alias Murmuring.Chat.{Channel, VoiceState}

  @hard_max 100

  def join_voice(channel_id, user_id, server_id \\ nil, opts \\ []) do
    channel = Repo.get!(Channel, channel_id)
    current_count = count_participants(channel_id)
    max = channel.max_participants || 25
    bypass_capacity = Keyword.get(opts, :bypass_capacity, false)

    cond do
      current_count >= @hard_max ->
        {:error, %{reason: "channel_full"}}

      current_count >= max and not bypass_capacity ->
        {:error, %{reason: "channel_full"}}

      true ->
        attrs = %{
          channel_id: channel_id,
          user_id: user_id,
          server_id: server_id,
          joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        %VoiceState{}
        |> VoiceState.changeset(attrs)
        |> Repo.insert(
          on_conflict: {:replace, [:joined_at, :updated_at]},
          conflict_target: [:channel_id, :user_id],
          returning: true
        )
    end
  end

  def leave_voice(channel_id, user_id) do
    case get_voice_state(channel_id, user_id) do
      nil -> {:error, :not_found}
      vs -> Repo.delete(vs)
    end
  end

  def get_voice_state(channel_id, user_id) do
    Repo.one(
      from vs in VoiceState,
        where: vs.channel_id == ^channel_id and vs.user_id == ^user_id
    )
  end

  def list_voice_states(channel_id) do
    Repo.all(
      from vs in VoiceState,
        where: vs.channel_id == ^channel_id,
        order_by: [asc: vs.joined_at]
    )
  end

  def update_voice_state(channel_id, user_id, attrs) do
    case get_voice_state(channel_id, user_id) do
      nil ->
        {:error, :not_found}

      vs ->
        vs
        |> VoiceState.update_changeset(attrs)
        |> Repo.update()
    end
  end

  def count_participants(channel_id) do
    Repo.one(
      from vs in VoiceState,
        where: vs.channel_id == ^channel_id,
        select: count(vs.id)
    )
  end

  def user_voice_state(user_id) do
    Repo.one(
      from vs in VoiceState,
        where: vs.user_id == ^user_id
    )
  end

  def cleanup_user(user_id) do
    from(vs in VoiceState, where: vs.user_id == ^user_id)
    |> Repo.delete_all()
  end
end
