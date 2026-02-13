defmodule Cairn.Moderation.AutoModRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "auto_mod_rules" do
    field :rule_type, :string
    field :enabled, :boolean, default: true
    field :config, :map, default: %{}

    belongs_to :server, Cairn.Servers.Server

    timestamps()
  end

  @valid_types ~w(word_filter regex_filter link_filter mention_spam)

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:rule_type, :enabled, :config, :server_id])
    |> validate_required([:rule_type, :server_id])
    |> validate_inclusion(:rule_type, @valid_types)
    |> foreign_key_constraint(:server_id)
  end
end
