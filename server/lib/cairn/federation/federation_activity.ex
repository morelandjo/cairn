defmodule Cairn.Federation.FederationActivity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_directions ~w(inbound outbound)
  @valid_statuses ~w(pending delivered failed)

  schema "federation_activities" do
    field :activity_type, :string
    field :direction, :string
    field :actor_uri, :string
    field :object_uri, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "pending"
    field :error, :string

    belongs_to :federated_node, Cairn.Federation.FederatedNode

    timestamps()
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :activity_type,
      :direction,
      :actor_uri,
      :object_uri,
      :payload,
      :status,
      :error,
      :federated_node_id
    ])
    |> validate_required([:activity_type, :direction, :federated_node_id])
    |> validate_inclusion(:direction, @valid_directions)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:federated_node_id)
  end
end
