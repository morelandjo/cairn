defmodule Murmuring.Chat do
  @moduledoc """
  The Chat context — channels, messages, and membership management.
  """

  import Ecto.Query
  alias Murmuring.Repo

  alias Murmuring.Chat.{
    Channel,
    ChannelMember,
    ChannelCategory,
    CustomEmoji,
    DmBlock,
    DmRequest,
    Message,
    PinnedMessage,
    Reaction
  }

  alias Murmuring.Accounts.InviteLink

  # Channels

  def create_channel(attrs) do
    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
  end

  def get_channel!(id), do: Repo.get!(Channel, id)

  def get_channel(id), do: Repo.get(Channel, id)

  def list_channels do
    Repo.all(from c in Channel, where: c.type == "public", order_by: [asc: c.name])
  end

  def list_server_channels(server_id) do
    from(c in Channel,
      where: c.server_id == ^server_id,
      order_by: [asc: c.name]
    )
    |> Repo.all()
  end

  def list_user_server_channels(server_id, user_id) do
    # Public channels in the server + private channels the user is a member of
    public_q =
      from(c in Channel,
        where: c.server_id == ^server_id and c.type == "public"
      )

    private_q =
      from(c in Channel,
        where: c.server_id == ^server_id and c.type == "private",
        join: cm in ChannelMember,
        on: cm.channel_id == c.id and cm.user_id == ^user_id
      )

    from(c in Channel,
      where: c.id in subquery(from(c in subquery(union_all(public_q, ^private_q)), select: c.id)),
      order_by: [asc: c.name]
    )
    |> Repo.all()
  end

  def list_user_channels(user_id) do
    from(c in Channel,
      join: cm in ChannelMember,
      on: cm.channel_id == c.id,
      where: cm.user_id == ^user_id,
      order_by: [asc: c.name],
      select: c
    )
    |> Repo.all()
  end

  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_channel(%Channel{} = channel) do
    Repo.delete(channel)
  end

  # Membership

  def add_member(channel_id, user_id, role \\ "member") do
    %ChannelMember{}
    |> ChannelMember.changeset(%{channel_id: channel_id, user_id: user_id, role: role})
    |> Repo.insert()
  end

  def remove_member(channel_id, user_id) do
    from(cm in ChannelMember,
      where: cm.channel_id == ^channel_id and cm.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  def get_member(channel_id, user_id) do
    Repo.get_by(ChannelMember, channel_id: channel_id, user_id: user_id)
  end

  def is_member?(channel_id, user_id) do
    get_member(channel_id, user_id) != nil
  end

  def list_members(channel_id) do
    from(cm in ChannelMember,
      where: cm.channel_id == ^channel_id,
      join: u in assoc(cm, :user),
      select: %{
        id: u.id,
        username: u.username,
        display_name: u.display_name,
        role: cm.role
      }
    )
    |> Repo.all()
  end

  # Messages

  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  def edit_message(%Message{} = message, attrs) do
    message
    |> Message.edit_changeset(attrs)
    |> Repo.update()
  end

  def delete_message(%Message{} = message) do
    message
    |> Message.delete_changeset()
    |> Repo.update()
  end

  def get_message!(id), do: Repo.get!(Message, id)

  def get_message(id), do: Repo.get(Message, id)

  def list_messages(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before = Keyword.get(opts, :before)

    query =
      from m in Message,
        where: m.channel_id == ^channel_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        left_join: u in assoc(m, :author),
        left_join: fu in assoc(m, :federated_author),
        left_join: reply in assoc(m, :reply_to),
        left_join: reply_author in assoc(reply, :author),
        select: %{
          id: m.id,
          content: m.content,
          encrypted_content: m.encrypted_content,
          nonce: m.nonce,
          author_id: m.author_id,
          federated_author_id: m.federated_author_id,
          author_username: coalesce(u.username, fu.username),
          author_display_name: coalesce(u.display_name, fu.display_name),
          home_instance: fu.home_instance,
          is_federated: not is_nil(m.federated_author_id),
          channel_id: m.channel_id,
          reply_to_id: m.reply_to_id,
          reply_to_content: reply.content,
          reply_to_author_username: reply_author.username,
          edited_at: m.edited_at,
          deleted_at: m.deleted_at,
          inserted_at: m.inserted_at
        }

    query =
      if before do
        from m in query, where: m.inserted_at < ^before
      else
        query
      end

    messages = Repo.all(query) |> Enum.reverse()

    # Attach reaction summaries
    message_ids = Enum.map(messages, & &1.id)

    reactions =
      if message_ids != [] do
        from(r in Reaction,
          where: r.message_id in ^message_ids,
          group_by: [r.message_id, r.emoji],
          select: %{message_id: r.message_id, emoji: r.emoji, count: count(r.id)}
        )
        |> Repo.all()
        |> Enum.group_by(& &1.message_id)
      else
        %{}
      end

    Enum.map(messages, fn msg ->
      msg_reactions =
        reactions
        |> Map.get(msg.id, [])
        |> Enum.map(fn r -> %{emoji: r.emoji, count: r.count} end)

      Map.put(msg, :reactions, msg_reactions)
    end)
  end

  # Invites

  def create_invite(channel_id, creator_id, opts \\ []) do
    %InviteLink{}
    |> InviteLink.changeset(%{
      code: InviteLink.generate_code(),
      channel_id: channel_id,
      creator_id: creator_id,
      server_id: Keyword.get(opts, :server_id),
      max_uses: Keyword.get(opts, :max_uses),
      expires_at: Keyword.get(opts, :expires_at)
    })
    |> Repo.insert()
  end

  def create_server_invite(server_id, creator_id, opts \\ []) do
    %InviteLink{}
    |> InviteLink.changeset(%{
      code: InviteLink.generate_code(),
      server_id: server_id,
      creator_id: creator_id,
      max_uses: Keyword.get(opts, :max_uses),
      expires_at: Keyword.get(opts, :expires_at)
    })
    |> Repo.insert()
  end

  def get_invite_by_code(code) do
    Repo.get_by(InviteLink, code: code)
    |> Repo.preload(:channel)
  end

  def use_invite(code, user_id) do
    case get_invite_by_code(code) do
      nil ->
        {:error, :not_found}

      invite ->
        cond do
          invite.expires_at && DateTime.compare(invite.expires_at, DateTime.utc_now()) == :lt ->
            {:error, :expired}

          invite.max_uses && invite.uses >= invite.max_uses ->
            {:error, :max_uses_reached}

          is_member?(invite.channel_id, user_id) ->
            {:ok, invite.channel}

          true ->
            Repo.transaction(fn ->
              {:ok, _} = add_member(invite.channel_id, user_id)

              invite
              |> Ecto.Changeset.change(uses: invite.uses + 1)
              |> Repo.update!()

              invite.channel
            end)
        end
    end
  end

  # DM channels

  def find_or_create_dm(user_id_1, user_id_2) do
    # Find existing DM between the two users
    existing =
      from(c in Channel,
        where: c.type == "dm",
        join: cm1 in ChannelMember,
        on: cm1.channel_id == c.id and cm1.user_id == ^user_id_1,
        join: cm2 in ChannelMember,
        on: cm2.channel_id == c.id and cm2.user_id == ^user_id_2,
        select: c
      )
      |> Repo.one()

    case existing do
      nil ->
        Repo.transaction(fn ->
          {:ok, channel} = create_channel(%{name: "dm", type: "dm"})
          {:ok, _} = add_member(channel.id, user_id_1)
          {:ok, _} = add_member(channel.id, user_id_2)
          channel
        end)

      channel ->
        {:ok, channel}
    end
  end

  # Categories

  def create_category(attrs) do
    %ChannelCategory{}
    |> ChannelCategory.changeset(attrs)
    |> Repo.insert()
  end

  def get_category!(id), do: Repo.get!(ChannelCategory, id)

  def update_category(%ChannelCategory{} = category, attrs) do
    category
    |> ChannelCategory.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%ChannelCategory{} = category) do
    Repo.delete(category)
  end

  def list_categories(server_id) do
    from(c in ChannelCategory,
      where: c.server_id == ^server_id,
      order_by: [asc: c.position]
    )
    |> Repo.all()
  end

  # Channel reordering

  def reorder_channels(channel_positions) do
    Repo.transaction(fn ->
      Enum.each(channel_positions, fn %{"id" => id, "position" => position} = item ->
        category_id = item["category_id"]

        from(c in Channel, where: c.id == ^id)
        |> Repo.update_all(set: [position: position, category_id: category_id])
      end)
    end)
  end

  def list_server_channels_ordered(server_id) do
    from(c in Channel,
      where: c.server_id == ^server_id,
      order_by: [asc: c.position, asc: c.name]
    )
    |> Repo.all()
  end

  # Pinned messages

  @max_pins 50

  def pin_message(channel_id, message_id, pinned_by_id) do
    pin_count =
      from(p in PinnedMessage, where: p.channel_id == ^channel_id)
      |> Repo.aggregate(:count)

    if pin_count >= @max_pins do
      {:error, :max_pins_reached}
    else
      %PinnedMessage{}
      |> PinnedMessage.changeset(%{
        channel_id: channel_id,
        message_id: message_id,
        pinned_by_id: pinned_by_id
      })
      |> Repo.insert()
    end
  end

  def unpin_message(channel_id, message_id) do
    from(p in PinnedMessage,
      where: p.channel_id == ^channel_id and p.message_id == ^message_id
    )
    |> Repo.delete_all()

    :ok
  end

  def list_pins(channel_id) do
    from(p in PinnedMessage,
      where: p.channel_id == ^channel_id,
      join: m in Message,
      on: m.id == p.message_id,
      join: u in assoc(m, :author),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        message_id: m.id,
        content: m.content,
        author_id: m.author_id,
        author_username: u.username,
        pinned_by_id: p.pinned_by_id,
        pinned_at: p.inserted_at
      }
    )
    |> Repo.all()
  end

  # Reactions

  def add_reaction(message_id, user_id, emoji) do
    %Reaction{}
    |> Reaction.changeset(%{message_id: message_id, user_id: user_id, emoji: emoji})
    |> Repo.insert()
  end

  def remove_reaction(message_id, user_id, emoji) do
    from(r in Reaction,
      where: r.message_id == ^message_id and r.user_id == ^user_id and r.emoji == ^emoji
    )
    |> Repo.delete_all()

    :ok
  end

  def list_reactions(message_id) do
    from(r in Reaction,
      where: r.message_id == ^message_id,
      group_by: r.emoji,
      select: %{emoji: r.emoji, count: count(r.id)}
    )
    |> Repo.all()
  end

  def list_reactions_with_users(message_id) do
    from(r in Reaction,
      where: r.message_id == ^message_id,
      join: u in assoc(r, :user),
      select: %{emoji: r.emoji, user_id: r.user_id, username: u.username}
    )
    |> Repo.all()
  end

  # Threading

  def get_thread(message_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(m in Message,
      where: m.reply_to_id == ^message_id,
      order_by: [asc: m.id],
      limit: ^limit,
      left_join: u in assoc(m, :author),
      left_join: fu in assoc(m, :federated_author),
      select: %{
        id: m.id,
        content: m.content,
        encrypted_content: m.encrypted_content,
        nonce: m.nonce,
        author_id: m.author_id,
        federated_author_id: m.federated_author_id,
        author_username: coalesce(u.username, fu.username),
        author_display_name: coalesce(u.display_name, fu.display_name),
        home_instance: fu.home_instance,
        is_federated: not is_nil(m.federated_author_id),
        channel_id: m.channel_id,
        reply_to_id: m.reply_to_id,
        edited_at: m.edited_at,
        deleted_at: m.deleted_at,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
  end

  # Custom emojis

  @max_emojis_per_server 50

  def create_emoji(attrs) do
    server_id = attrs[:server_id] || attrs["server_id"]

    emoji_count =
      from(e in CustomEmoji, where: e.server_id == ^server_id)
      |> Repo.aggregate(:count)

    if emoji_count >= @max_emojis_per_server do
      {:error, :max_emojis_reached}
    else
      %CustomEmoji{}
      |> CustomEmoji.changeset(attrs)
      |> Repo.insert()
    end
  end

  def list_emojis(server_id) do
    from(e in CustomEmoji,
      where: e.server_id == ^server_id,
      order_by: [asc: e.name]
    )
    |> Repo.all()
  end

  def get_emoji!(id), do: Repo.get!(CustomEmoji, id)

  def delete_emoji(%CustomEmoji{} = emoji) do
    Repo.delete(emoji)
  end

  # ── Federated DM Channels ──

  @doc "Add a federated user as a channel member (for cross-instance DMs)."
  def add_federated_member(channel_id, federated_user_id, role \\ "member") do
    %ChannelMember{}
    |> ChannelMember.federated_changeset(%{
      channel_id: channel_id,
      federated_user_id: federated_user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc "Check if a federated user is a member of a channel."
  def is_federated_channel_member?(channel_id, federated_user_id) do
    from(cm in ChannelMember,
      where: cm.channel_id == ^channel_id and cm.federated_user_id == ^federated_user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Create a DM channel with a local user and a federated user.
  Returns `{:ok, channel}` or `{:error, reason}`.
  """
  def create_federated_dm(user_id, federated_user_id) do
    # Check for existing federated DM between these two
    existing =
      from(c in Channel,
        where: c.type == "dm",
        join: cm1 in ChannelMember,
        on: cm1.channel_id == c.id and cm1.user_id == ^user_id,
        join: cm2 in ChannelMember,
        on: cm2.channel_id == c.id and cm2.federated_user_id == ^federated_user_id,
        select: c
      )
      |> Repo.one()

    case existing do
      nil ->
        Repo.transaction(fn ->
          {:ok, channel} = create_channel(%{name: "dm", type: "dm"})
          {:ok, _} = add_member(channel.id, user_id)
          {:ok, _} = add_federated_member(channel.id, federated_user_id)
          channel
        end)

      channel ->
        {:ok, channel}
    end
  end

  @doc "Find an existing federated DM between a local user and a federated user."
  def find_federated_dm(user_id, federated_user_id) do
    from(c in Channel,
      where: c.type == "dm",
      join: cm1 in ChannelMember,
      on: cm1.channel_id == c.id and cm1.user_id == ^user_id,
      join: cm2 in ChannelMember,
      on: cm2.channel_id == c.id and cm2.federated_user_id == ^federated_user_id,
      select: c
    )
    |> Repo.one()
  end

  # ── DM Requests ──

  @doc "Create a DM request from a local user to a remote DID."
  def create_dm_request(attrs) do
    %DmRequest{}
    |> DmRequest.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get a DM request by ID."
  def get_dm_request(id), do: Repo.get(DmRequest, id)

  @doc "Get a DM request by ID, preloading the channel."
  def get_dm_request_with_channel(id) do
    Repo.get(DmRequest, id) |> Repo.preload(:channel)
  end

  @doc "List pending DM requests sent to a given DID."
  def list_dm_requests_for_did(recipient_did) do
    from(r in DmRequest,
      where: r.recipient_did == ^recipient_did and r.status == "pending",
      order_by: [desc: r.inserted_at],
      join: u in assoc(r, :sender),
      select: %{
        id: r.id,
        channel_id: r.channel_id,
        sender_id: r.sender_id,
        sender_username: u.username,
        sender_display_name: u.display_name,
        recipient_did: r.recipient_did,
        recipient_instance: r.recipient_instance,
        status: r.status,
        inserted_at: r.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc "List DM requests sent by a user."
  def list_sent_dm_requests(user_id) do
    from(r in DmRequest,
      where: r.sender_id == ^user_id,
      order_by: [desc: r.inserted_at],
      select: %{
        id: r.id,
        channel_id: r.channel_id,
        recipient_did: r.recipient_did,
        recipient_instance: r.recipient_instance,
        status: r.status,
        inserted_at: r.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc "Update a DM request's status."
  def update_dm_request(%DmRequest{} = request, attrs) do
    request
    |> DmRequest.changeset(attrs)
    |> Repo.update()
  end

  @doc "Count pending DM requests sent by a user in the last hour (for rate limiting)."
  def count_recent_dm_requests(user_id) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    from(r in DmRequest,
      where: r.sender_id == ^user_id and r.inserted_at > ^one_hour_ago
    )
    |> Repo.aggregate(:count)
  end

  @doc "Count pending DM requests targeting a specific DID (for flood prevention)."
  def count_pending_dm_requests_for_did(recipient_did) do
    from(r in DmRequest,
      where: r.recipient_did == ^recipient_did and r.status == "pending"
    )
    |> Repo.aggregate(:count)
  end

  @doc "Find existing DM request between a sender and recipient DID."
  def find_dm_request(sender_id, recipient_did) do
    Repo.get_by(DmRequest, sender_id: sender_id, recipient_did: recipient_did)
  end

  # ── DM Blocks ──

  @doc "Block a DID from sending DM requests to a user."
  def block_dm_sender(user_id, blocked_did) do
    %DmBlock{}
    |> DmBlock.changeset(%{user_id: user_id, blocked_did: blocked_did})
    |> Repo.insert()
  end

  @doc "Unblock a DID."
  def unblock_dm_sender(user_id, blocked_did) do
    from(b in DmBlock,
      where: b.user_id == ^user_id and b.blocked_did == ^blocked_did
    )
    |> Repo.delete_all()

    :ok
  end

  @doc "Check if a DID is blocked by a user."
  def is_dm_blocked?(user_id, did) do
    from(b in DmBlock,
      where: b.user_id == ^user_id and b.blocked_did == ^did
    )
    |> Repo.exists?()
  end

  @doc "List all DIDs blocked by a user."
  def list_dm_blocks(user_id) do
    from(b in DmBlock,
      where: b.user_id == ^user_id,
      order_by: [desc: b.inserted_at],
      select: %{id: b.id, blocked_did: b.blocked_did, inserted_at: b.inserted_at}
    )
    |> Repo.all()
  end
end
