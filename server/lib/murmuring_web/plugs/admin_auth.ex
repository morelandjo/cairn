defmodule MurmuringWeb.Plugs.AdminAuth do
  @moduledoc """
  Plug that verifies the current user has admin privileges.

  Must run after the Auth plug (requires `current_user` in assigns).

  Admin is determined by:
  1. A configured admin_user_id in the federation config, OR
  2. The user being the creator of the first (default) server
  """

  import Plug.Conn
  alias Murmuring.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && is_admin?(user.id) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "admin access required"})
      |> halt()
    end
  end

  defp is_admin?(user_id) do
    # Check configured admin user ID first
    config = Application.get_env(:murmuring, :federation, [])

    case Keyword.get(config, :admin_user_id) do
      nil ->
        # Fall back to: creator of the first server is admin
        import Ecto.Query

        Repo.exists?(
          from s in Murmuring.Servers.Server,
            where: s.creator_id == ^user_id,
            order_by: [asc: s.inserted_at],
            limit: 1
        )

      admin_id ->
        user_id == admin_id
    end
  end
end
