defmodule Cairn.Chat.PinnedMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "pinned_messages" do
    belongs_to :message, Cairn.Chat.Message
    belongs_to :channel, Cairn.Chat.Channel
    belongs_to :pinned_by, Cairn.Accounts.User

    timestamps()
  end

  def changeset(pin, attrs) do
    pin
    |> cast(attrs, [:message_id, :channel_id, :pinned_by_id])
    |> validate_required([:message_id, :channel_id, :pinned_by_id])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:pinned_by_id)
    |> unique_constraint([:channel_id, :message_id])
  end
end
