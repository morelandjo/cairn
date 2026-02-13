defmodule Cairn.Chat.DmBlock do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dm_blocks" do
    field :blocked_did, :string

    belongs_to :user, Cairn.Accounts.User

    timestamps()
  end

  def changeset(dm_block, attrs) do
    dm_block
    |> cast(attrs, [:user_id, :blocked_did])
    |> validate_required([:user_id, :blocked_did])
    |> validate_format(:blocked_did, ~r/^did:cairn:/)
    |> unique_constraint([:user_id, :blocked_did])
  end
end
