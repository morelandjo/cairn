defmodule Cairn.Servers.ChannelPermissionOverride do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_permission_overrides" do
    field :permissions, :map, default: %{}

    belongs_to :channel, Cairn.Chat.Channel
    belongs_to :role, Cairn.Accounts.Role
    belongs_to :user, Cairn.Accounts.User

    timestamps()
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [:channel_id, :role_id, :user_id, :permissions])
    |> validate_required([:channel_id, :permissions])
    |> validate_role_or_user()
    |> validate_permissions()
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:channel_id, :role_id],
      name: :channel_permission_overrides_channel_role_idx
    )
    |> unique_constraint([:channel_id, :user_id],
      name: :channel_permission_overrides_channel_user_idx
    )
    |> check_constraint(:role_id,
      name: :role_or_user_required,
      message: "exactly one of role_id or user_id must be set"
    )
  end

  @valid_values ~w(grant deny inherit)

  defp validate_permissions(changeset) do
    case get_field(changeset, :permissions) do
      nil ->
        changeset

      perms when is_map(perms) ->
        permission_keys = Cairn.Servers.Permissions.permission_keys()
        invalid = Enum.reject(perms, fn {k, v} -> k in permission_keys and v in @valid_values end)

        if invalid == [] do
          changeset
        else
          add_error(changeset, :permissions, "contains invalid keys or values")
        end

      _ ->
        add_error(changeset, :permissions, "must be a map")
    end
  end

  defp validate_role_or_user(changeset) do
    role_id = get_field(changeset, :role_id)
    user_id = get_field(changeset, :user_id)

    cond do
      is_nil(role_id) and is_nil(user_id) ->
        add_error(changeset, :role_id, "either role_id or user_id must be set")

      not is_nil(role_id) and not is_nil(user_id) ->
        add_error(changeset, :role_id, "only one of role_id or user_id can be set")

      true ->
        changeset
    end
  end
end
