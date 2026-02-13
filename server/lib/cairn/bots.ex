defmodule Cairn.Bots do
  @moduledoc """
  The Bots context — webhooks and bot accounts.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Bots.{Webhook, BotAccount}
  alias Cairn.Accounts
  alias Cairn.Servers
  alias Cairn.Chat

  # Webhooks

  def create_webhook(attrs) do
    token = Webhook.generate_token()

    %Webhook{}
    |> Webhook.changeset(Map.put(attrs, :token, token))
    |> Repo.insert()
    |> case do
      {:ok, webhook} -> {:ok, %{webhook | token: token}}
      error -> error
    end
  end

  def get_webhook_by_token(token) do
    Repo.get_by(Webhook, token: token)
  end

  def list_webhooks(server_id) do
    from(w in Webhook,
      where: w.server_id == ^server_id,
      order_by: [asc: w.name]
    )
    |> Repo.all()
  end

  def delete_webhook(%Webhook{} = webhook) do
    Repo.delete(webhook)
  end

  def regenerate_webhook_token(%Webhook{} = webhook) do
    new_token = Webhook.generate_token()

    webhook
    |> Webhook.changeset(%{token: new_token})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, %{updated | token: new_token}}
      error -> error
    end
  end

  def execute_webhook(token, params) do
    case get_webhook_by_token(token) do
      nil ->
        {:error, :not_found}

      webhook ->
        # Create message as webhook (system message)
        Chat.create_message(%{
          content: params["content"],
          channel_id: webhook.channel_id,
          author_id: webhook.creator_id
        })
    end
  end

  # Bot accounts

  def create_bot(attrs) do
    token = BotAccount.generate_token()
    token_hash = BotAccount.hash_token(token)

    # Create a bot user account
    bot_username = "bot_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

    case Accounts.register_user(%{
           "username" => bot_username,
           "password" => :crypto.strong_rand_bytes(32) |> Base.encode64()
         }) do
      {:ok, {bot_user, _codes}} ->
        # Mark user as a bot
        bot_user =
          bot_user
          |> Ecto.Changeset.change(is_bot: true)
          |> Repo.update!()

        # Add bot to server
        Servers.add_member(attrs.server_id, bot_user.id)

        case %BotAccount{}
             |> BotAccount.changeset(%{
               api_token_hash: token_hash,
               user_id: bot_user.id,
               server_id: attrs.server_id,
               creator_id: attrs.creator_id,
               allowed_channels: attrs[:allowed_channels] || []
             })
             |> Repo.insert() do
          {:ok, bot_account} ->
            {:ok, %{bot_account: bot_account, user: bot_user, token: token}}

          error ->
            error
        end

      error ->
        error
    end
  end

  def get_bot_by_token(token) do
    token_hash = BotAccount.hash_token(token)

    from(b in BotAccount,
      where: b.api_token_hash == ^token_hash,
      preload: [:user]
    )
    |> Repo.one()
  end

  def list_bots(server_id) do
    from(b in BotAccount,
      where: b.server_id == ^server_id,
      join: u in assoc(b, :user),
      select: %{
        id: b.id,
        user_id: b.user_id,
        username: u.username,
        allowed_channels: b.allowed_channels,
        inserted_at: b.inserted_at
      }
    )
    |> Repo.all()
  end

  def delete_bot(%BotAccount{} = bot) do
    Repo.delete(bot)
  end

  def get_bot!(id), do: Repo.get!(BotAccount, id)

  def get_bot_for_user(user_id, server_id) do
    from(b in BotAccount,
      where: b.user_id == ^user_id and b.server_id == ^server_id
    )
    |> Repo.one()
  end

  def update_bot_channels(%BotAccount{} = bot, channels) do
    bot
    |> BotAccount.changeset(%{allowed_channels: channels})
    |> Repo.update()
  end

  def regenerate_bot_token(%BotAccount{} = bot) do
    token = BotAccount.generate_token()
    token_hash = BotAccount.hash_token(token)

    case bot
         |> BotAccount.changeset(%{api_token_hash: token_hash})
         |> Repo.update() do
      {:ok, _updated} -> {:ok, token}
      error -> error
    end
  end
end
