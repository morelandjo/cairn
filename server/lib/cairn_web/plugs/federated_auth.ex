defmodule CairnWeb.Plugs.FederatedAuth do
  @moduledoc """
  Plug that extracts and verifies a FederatedToken from the Authorization header.

  On success, assigns:
  - `conn.assigns.federated_claims` — the decoded token claims map
  - `conn.assigns.federated_user` — the local FederatedUser record (upserted)
  - `conn.assigns.is_federated` — true
  """

  import Plug.Conn
  alias Cairn.Federation.FederatedAuth
  alias Cairn.Federation

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- FederatedAuth.verify_token(token),
         {:ok, federated_user} <- ensure_federated_user(claims) do
      conn
      |> assign(:federated_claims, claims)
      |> assign(:federated_user, federated_user)
      |> assign(:is_federated, true)
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Federated auth failed: #{inspect(reason)}"})
        |> halt()
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["FederatedToken " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :missing_federated_token}
    end
  end

  defp ensure_federated_user(claims) do
    attrs = %{
      did: claims["did"],
      username: claims["username"],
      display_name: claims["display_name"],
      home_instance: claims["home_instance"],
      public_key: Base.decode64!(claims["public_key"]),
      actor_uri: "https://#{claims["home_instance"]}/users/#{claims["username"]}",
      last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }

    Federation.get_or_create_federated_user(attrs)
  end
end
