defmodule Cairn.Chat.DmRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dm_requests" do
    field :recipient_did, :string
    field :recipient_instance, :string
    field :status, :string, default: "pending"

    belongs_to :channel, Cairn.Chat.Channel
    belongs_to :sender, Cairn.Accounts.User, foreign_key: :sender_id

    timestamps()
  end

  def changeset(dm_request, attrs) do
    dm_request
    |> cast(attrs, [:channel_id, :sender_id, :recipient_did, :recipient_instance, :status])
    |> validate_required([:channel_id, :sender_id, :recipient_did, :recipient_instance, :status])
    |> validate_inclusion(:status, ~w(pending accepted rejected blocked))
    |> validate_format(:recipient_did, ~r/^did:cairn:/)
    |> unique_constraint([:sender_id, :recipient_did])
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:sender_id)
  end
end
