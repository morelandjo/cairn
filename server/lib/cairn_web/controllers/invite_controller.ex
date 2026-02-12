defmodule MurmuringWeb.InviteController do
  use MurmuringWeb, :controller

  alias Murmuring.Chat

  def create(conn, %{"channel_id" => channel_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Chat.is_member?(channel_id, user_id) do
      conn |> put_status(:forbidden) |> json(%{error: "not a member"}) |> halt()
    else
      opts =
        []
        |> then(fn o ->
          if params["max_uses"], do: Keyword.put(o, :max_uses, params["max_uses"]), else: o
        end)
        |> then(fn o ->
          if params["expires_at"] do
            case DateTime.from_iso8601(params["expires_at"]) do
              {:ok, dt, _} -> Keyword.put(o, :expires_at, dt)
              _ -> o
            end
          else
            o
          end
        end)

      case Chat.create_invite(channel_id, user_id, opts) do
        {:ok, invite} ->
          conn
          |> put_status(:created)
          |> json(%{
            invite: %{
              id: invite.id,
              code: invite.code,
              channel_id: invite.channel_id,
              max_uses: invite.max_uses,
              uses: invite.uses,
              expires_at: invite.expires_at
            }
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  def show(conn, %{"code" => code}) do
    case Chat.get_invite_by_code(code) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "invite not found"})

      invite ->
        json(conn, %{
          invite: %{
            code: invite.code,
            channel_name: invite.channel.name,
            channel_id: invite.channel_id
          }
        })
    end
  end

  def use(conn, %{"code" => code}) do
    user_id = conn.assigns.current_user.id

    case Chat.use_invite(code, user_id) do
      {:ok, channel} ->
        json(conn, %{
          channel: %{
            id: channel.id,
            name: channel.name,
            type: channel.type
          }
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "invite not found"})

      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: "invite expired"})

      {:error, :max_uses_reached} ->
        conn |> put_status(:gone) |> json(%{error: "invite has reached maximum uses"})
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
