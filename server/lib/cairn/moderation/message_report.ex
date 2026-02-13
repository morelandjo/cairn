defmodule Cairn.Moderation.MessageReport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "message_reports" do
    field :reason, :string
    field :details, :string
    field :status, :string, default: "pending"
    field :resolution_action, :string

    belongs_to :message, Cairn.Chat.Message
    belongs_to :reporter, Cairn.Accounts.User
    belongs_to :server, Cairn.Servers.Server
    belongs_to :resolved_by, Cairn.Accounts.User

    timestamps()
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :reason,
      :details,
      :status,
      :resolution_action,
      :message_id,
      :reporter_id,
      :server_id,
      :resolved_by_id
    ])
    |> validate_required([:reason, :message_id, :reporter_id, :server_id])
    |> validate_inclusion(:status, ~w(pending dismissed actioned))
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:reporter_id)
    |> foreign_key_constraint(:server_id)
  end
end
