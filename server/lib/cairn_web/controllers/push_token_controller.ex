defmodule MurmuringWeb.PushTokenController do
  use MurmuringWeb, :controller

  alias Murmuring.Notifications

  @doc "Register a push notification token for the current user."
  def create(conn, %{"token" => token, "platform" => platform} = params) do
    user_id = conn.assigns.current_user.id

    case Notifications.register_push_token(%{
           user_id: user_id,
           token: token,
           platform: platform,
           device_id: params["device_id"]
         }) do
      {:ok, push_token} ->
        conn
        |> put_status(:created)
        |> json(%{
          push_token: %{
            id: push_token.id,
            token: push_token.token,
            platform: push_token.platform,
            device_id: push_token.device_id
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "Unregister a push notification token."
  def delete(conn, %{"token" => token}) do
    user_id = conn.assigns.current_user.id

    case Notifications.unregister_push_token(user_id, token) do
      :ok ->
        conn |> put_status(:no_content) |> text("")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Token not found"})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
