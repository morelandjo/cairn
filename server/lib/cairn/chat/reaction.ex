defmodule Cairn.Chat.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reactions" do
    field :emoji, :string

    belongs_to :message, Cairn.Chat.Message
    belongs_to :user, Cairn.Accounts.User

    timestamps()
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :message_id, :user_id])
    |> validate_required([:emoji, :message_id, :user_id])
    |> validate_length(:emoji, min: 1, max: 64)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:message_id, :user_id, :emoji])
  end
end
