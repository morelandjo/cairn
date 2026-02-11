defmodule Murmuring.Chat.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channels" do
    field :name, :string
    field :type, :string, default: "public"
    field :description, :string
    field :topic, :string
    field :position, :integer, default: 0
    field :slow_mode_seconds, :integer, default: 0
    field :max_participants, :integer, default: 25
    field :bitrate, :integer, default: 64000
    field :history_accessible, :boolean, default: false

    belongs_to :server, Murmuring.Servers.Server
    belongs_to :category, Murmuring.Chat.ChannelCategory
    has_many :members, Murmuring.Chat.ChannelMember
    has_many :messages, Murmuring.Chat.Message

    timestamps()
  end

  @cast_fields [
    :name,
    :type,
    :description,
    :topic,
    :server_id,
    :category_id,
    :position,
    :slow_mode_seconds,
    :max_participants,
    :bitrate,
    :history_accessible
  ]

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :type])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:type, ~w(public dm private voice))
    |> validate_length(:topic, max: 512)
    |> validate_server_id()
    |> validate_history_accessible()
  end

  def update_changeset(channel, attrs) do
    channel
    |> cast(attrs, @cast_fields -- [:history_accessible, :type])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:topic, max: 512)
  end

  defp validate_server_id(changeset) do
    type = get_field(changeset, :type)

    case type do
      "dm" ->
        # DMs must NOT have a server_id
        changeset

      _ ->
        # Non-DM channels require server_id
        validate_required(changeset, [:server_id])
    end
  end

  defp validate_history_accessible(changeset) do
    type = get_field(changeset, :type)
    history = get_field(changeset, :history_accessible)

    if history && type != "private" do
      add_error(changeset, :history_accessible, "only applies to private channels")
    else
      changeset
    end
  end
end
