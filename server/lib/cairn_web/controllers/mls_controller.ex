defmodule MurmuringWeb.MlsController do
  use MurmuringWeb, :controller

  alias Murmuring.Chat
  alias Murmuring.Chat.Mls

  @doc "POST /api/v1/channels/:id/mls/group-info — Store MLS group info"
  def store_group_info(conn, %{"id" => channel_id} = params) do
    user_id = conn.assigns.current_user.id

    with :ok <- require_member(channel_id, user_id),
         {:ok, data} <- decode_required(params, "data"),
         epoch when is_integer(epoch) <- params["epoch"] || {:error, "epoch required"} do
      case Mls.store_group_info(channel_id, data, epoch) do
        {:ok, _} ->
          conn |> put_status(:created) |> json(%{ok: true})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
      :forbidden -> conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  @doc "POST /api/v1/channels/:id/mls/commit — Store MLS commit"
  def store_commit(conn, %{"id" => channel_id} = params) do
    user_id = conn.assigns.current_user.id

    with :ok <- require_member(channel_id, user_id),
         {:ok, data} <- decode_required(params, "data") do
      epoch = params["epoch"]

      case Mls.store_commit(channel_id, user_id, data, epoch) do
        {:ok, msg} ->
          conn |> put_status(:created) |> json(%{id: msg.id})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
      :forbidden -> conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  @doc "POST /api/v1/channels/:id/mls/proposal — Store MLS proposal"
  def store_proposal(conn, %{"id" => channel_id} = params) do
    user_id = conn.assigns.current_user.id

    with :ok <- require_member(channel_id, user_id),
         {:ok, data} <- decode_required(params, "data") do
      epoch = params["epoch"]

      case Mls.store_proposal(channel_id, user_id, data, epoch) do
        {:ok, msg} ->
          conn |> put_status(:created) |> json(%{id: msg.id})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
      :forbidden -> conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  @doc "POST /api/v1/channels/:id/mls/welcome — Store MLS welcome for a recipient"
  def store_welcome(conn, %{"id" => channel_id} = params) do
    user_id = conn.assigns.current_user.id

    with :ok <- require_member(channel_id, user_id),
         {:ok, data} <- decode_required(params, "data"),
         recipient_id when is_binary(recipient_id) <-
           params["recipient_id"] || {:error, "recipient_id required"} do
      case Mls.store_welcome(channel_id, user_id, recipient_id, data) do
        {:ok, msg} ->
          conn |> put_status(:created) |> json(%{id: msg.id})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
      :forbidden -> conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  @doc "GET /api/v1/channels/:id/mls/messages — Get pending MLS messages"
  def pending_messages(conn, %{"id" => channel_id}) do
    user_id = conn.assigns.current_user.id

    with :ok <- require_member(channel_id, user_id) do
      messages = Mls.get_pending_messages(channel_id, recipient_id: user_id)

      json(conn, %{
        messages:
          Enum.map(messages, fn m ->
            %{
              id: m.id,
              message_type: m.message_type,
              data: Base.encode64(m.data),
              epoch: m.epoch,
              sender_id: m.sender_id,
              inserted_at: m.inserted_at
            }
          end)
      })
    else
      :forbidden -> conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  @doc "POST /api/v1/channels/:id/mls/ack — Mark MLS messages as processed"
  def ack_messages(conn, %{"id" => channel_id} = params) do
    user_id = conn.assigns.current_user.id

    with :ok <- require_member(channel_id, user_id),
         message_ids when is_list(message_ids) <-
           params["message_ids"] || {:error, "message_ids required"} do
      {count, _} = Mls.mark_all_processed(message_ids)
      json(conn, %{acknowledged: count})
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
      :forbidden -> conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  @doc "GET /api/v1/channels/:id/mls/group-info — Get latest MLS group info"
  def get_group_info(conn, %{"id" => channel_id}) do
    user_id = conn.assigns.current_user.id

    with :ok <- require_member(channel_id, user_id) do
      case Mls.get_group_info(channel_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "no group info"})

        info ->
          json(conn, %{
            data: Base.encode64(info.data),
            epoch: info.epoch
          })
      end
    else
      :forbidden -> conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    end
  end

  # --- Helpers ---

  defp require_member(channel_id, user_id) do
    if Chat.is_member?(channel_id, user_id), do: :ok, else: :forbidden
  end

  defp decode_required(params, field) do
    case params[field] do
      nil ->
        {:error, "#{field} required"}

      value when is_binary(value) ->
        case Base.decode64(value) do
          {:ok, data} -> {:ok, data}
          :error -> {:error, "invalid base64 for #{field}"}
        end

      _ ->
        {:error, "#{field} must be a base64 string"}
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
