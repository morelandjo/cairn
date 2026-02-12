defmodule Cairn.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Cairn.Types.UUIDv7, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :content, :string
    field :encrypted_content, :binary
    field :nonce, :binary
    field :mls_epoch, :integer
    field :edited_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :hlc_wall, :integer
    field :hlc_counter, :integer, default: 0
    field :hlc_node, :string

    belongs_to :channel, Cairn.Chat.Channel
    belongs_to :author, Cairn.Accounts.User
    belongs_to :federated_author, Cairn.Federation.FederatedUser
    belongs_to :reply_to, Cairn.Chat.Message

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :content,
      :encrypted_content,
      :nonce,
      :mls_epoch,
      :channel_id,
      :author_id,
      :federated_author_id,
      :hlc_wall,
      :hlc_counter,
      :hlc_node,
      :reply_to_id
    ])
    |> validate_required([:channel_id])
    |> validate_author()
    |> validate_content()
    |> validate_length(:content, max: 4000)
  end

  defp validate_author(changeset) do
    author_id = get_field(changeset, :author_id)
    fed_author_id = get_field(changeset, :federated_author_id)

    if is_nil(author_id) and is_nil(fed_author_id) do
      add_error(changeset, :author_id, "either author_id or federated_author_id required")
    else
      changeset
    end
  end

  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :encrypted_content, :nonce])
    |> validate_content()
    |> validate_length(:content, max: 4000)
    |> put_change(:edited_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def delete_changeset(message) do
    message
    |> change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:content, nil)
    |> put_change(:encrypted_content, nil)
    |> put_change(:nonce, nil)
  end

  defp validate_content(changeset) do
    content = get_change(changeset, :content)
    encrypted = get_change(changeset, :encrypted_content)

    if is_nil(content) and is_nil(encrypted) do
      add_error(changeset, :content, "either content or encrypted_content must be provided")
    else
      changeset
    end
  end
end
