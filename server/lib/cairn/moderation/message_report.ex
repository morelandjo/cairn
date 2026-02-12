defmodule Murmuring.Moderation.MessageReport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "message_reports" do
    field :reason, :string
    field :details, :string
    field :status, :string, default: "pending"
    field :resolution_action, :string

    belongs_to :message, Murmuring.Chat.Message
    belongs_to :reporter, Murmuring.Accounts.User
    belongs_to :server, Murmuring.Servers.Server
    belongs_to :resolved_by, Murmuring.Accounts.User

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
