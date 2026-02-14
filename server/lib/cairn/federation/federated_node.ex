defmodule Cairn.Federation.FederatedNode do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(pending active blocked)

  schema "federated_nodes" do
    field :domain, :string
    field :node_id, :string
    field :public_key, :string
    field :inbox_url, :string
    field :protocol_version, :string
    field :privacy_manifest, :map, default: %{}
    field :status, :string, default: "pending"
    field :secure, :boolean, default: true

    has_many :activities, Cairn.Federation.FederationActivity

    timestamps()
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :domain,
      :node_id,
      :public_key,
      :inbox_url,
      :protocol_version,
      :privacy_manifest,
      :status,
      :secure
    ])
    |> validate_required([:domain, :node_id, :public_key, :inbox_url, :protocol_version])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:domain)
    |> unique_constraint(:node_id)
  end
end
