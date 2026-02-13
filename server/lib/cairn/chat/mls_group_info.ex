defmodule Cairn.Chat.MlsGroupInfo do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mls_group_info" do
    field :data, :binary
    field :epoch, :integer

    belongs_to :channel, Cairn.Chat.Channel

    timestamps()
  end

  def changeset(group_info, attrs) do
    group_info
    |> cast(attrs, [:channel_id, :data, :epoch])
    |> validate_required([:channel_id, :data, :epoch])
    |> unique_constraint(:channel_id)
  end
end
