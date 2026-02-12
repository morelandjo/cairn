defmodule Cairn.Notifications.PushToken do
  @moduledoc "Ecto schema for push notification tokens (Expo Push)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "push_tokens" do
    field :token, :string
    field :platform, :string
    field :device_id, :string

    belongs_to :user, Cairn.Accounts.User

    timestamps()
  end

  @valid_platforms ~w(ios android expo)

  def changeset(push_token, attrs) do
    push_token
    |> cast(attrs, [:token, :platform, :device_id, :user_id])
    |> validate_required([:token, :platform, :user_id])
    |> validate_inclusion(:platform, @valid_platforms)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token)
  end
end
