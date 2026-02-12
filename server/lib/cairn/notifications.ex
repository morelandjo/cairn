defmodule Cairn.Notifications do
  @moduledoc """
  The Notifications context — per-channel/server notification preferences.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Notifications.Preference
  alias Cairn.Notifications.PushToken

  def get_preference(user_id, server_id \\ nil, channel_id \\ nil) do
    from(p in Preference,
      where: p.user_id == ^user_id,
      where:
        ^if(server_id,
          do: dynamic([p], p.server_id == ^server_id),
          else: dynamic([p], is_nil(p.server_id))
        ),
      where:
        ^if(channel_id,
          do: dynamic([p], p.channel_id == ^channel_id),
          else: dynamic([p], is_nil(p.channel_id))
        )
    )
    |> Repo.one()
  end

  def get_preferences(user_id) do
    from(p in Preference, where: p.user_id == ^user_id)
    |> Repo.all()
  end

  def upsert_preference(attrs) do
    user_id = attrs[:user_id] || attrs["user_id"]
    server_id = attrs[:server_id] || attrs["server_id"]
    channel_id = attrs[:channel_id] || attrs["channel_id"]

    case get_preference(user_id, server_id, channel_id) do
      nil ->
        %Preference{}
        |> Preference.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Preference.changeset(attrs)
        |> Repo.update()
    end
  end

  def effective_level(user_id, server_id, channel_id) do
    now = Time.utc_now()

    # Check channel-specific first, then server, then global
    pref =
      get_preference(user_id, server_id, channel_id) ||
        get_preference(user_id, server_id) ||
        get_preference(user_id)

    case pref do
      nil ->
        "all"

      %{dnd_enabled: true} ->
        "nothing"

      %{quiet_hours_start: start_time, quiet_hours_end: end_time} = p
      when not is_nil(start_time) and not is_nil(end_time) ->
        if in_quiet_hours?(now, start_time, end_time), do: "nothing", else: p.level

      p ->
        p.level
    end
  end

  # --- Push Token Management ---

  def register_push_token(attrs) do
    %PushToken{}
    |> PushToken.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:platform, :device_id, :updated_at]},
      conflict_target: :token
    )
  end

  def unregister_push_token(user_id, token) do
    case Repo.one(
           from(pt in PushToken, where: pt.user_id == ^user_id and pt.token == ^token)
         ) do
      nil -> {:error, :not_found}
      push_token -> Repo.delete(push_token) && :ok
    end
  end

  def unregister_all_push_tokens(user_id) do
    from(pt in PushToken, where: pt.user_id == ^user_id)
    |> Repo.delete_all()
  end

  def get_push_tokens_for_channel(channel_id, opts \\ []) do
    exclude_user_id = Keyword.get(opts, :exclude)

    query =
      from pt in PushToken,
        join: m in Cairn.Chat.ChannelMember,
        on: m.user_id == pt.user_id,
        where: m.channel_id == ^channel_id

    query =
      if exclude_user_id do
        from [pt, m] in query, where: pt.user_id != ^exclude_user_id
      else
        query
      end

    Repo.all(query)
  end

  defp in_quiet_hours?(now, start_time, end_time) do
    if Time.compare(start_time, end_time) == :lt do
      # Same day: e.g., 22:00 to 06:00 doesn't cross midnight — but this is start < end
      # e.g., 09:00 to 17:00
      Time.compare(now, start_time) != :lt and Time.compare(now, end_time) == :lt
    else
      # Crosses midnight: e.g., 22:00 to 06:00
      Time.compare(now, start_time) != :lt or Time.compare(now, end_time) == :lt
    end
  end
end
