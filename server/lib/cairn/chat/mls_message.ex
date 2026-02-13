defmodule Cairn.Chat.MlsMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(commit proposal welcome)

  schema "mls_messages" do
    field :message_type, :string
    field :data, :binary
    field :epoch, :integer
    field :processed, :boolean, default: false

    belongs_to :channel, Cairn.Chat.Channel
    belongs_to :sender, Cairn.Accounts.User
    belongs_to :recipient, Cairn.Accounts.User

    timestamps()
  end

  def changeset(mls_message, attrs) do
    mls_message
    |> cast(attrs, [:channel_id, :sender_id, :recipient_id, :message_type, :data, :epoch])
    |> validate_required([:channel_id, :sender_id, :message_type, :data])
    |> validate_inclusion(:message_type, @valid_types)
  end
end
