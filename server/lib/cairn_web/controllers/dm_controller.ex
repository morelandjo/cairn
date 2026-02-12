defmodule CairnWeb.DmController do
  use CairnWeb, :controller

  alias Cairn.Chat
  alias Cairn.Federation
  alias Cairn.Federation.DmHintWorker

  @max_requests_per_hour 10
  @max_pending_per_recipient 5

  @doc """
  POST /api/v1/dm/federated
  Create a federated DM channel with a remote user.
  Params: recipient_did, recipient_instance, initial_message (optional encrypted payload)
  """
  def create_federated_dm(conn, %{
        "recipient_did" => recipient_did,
        "recipient_instance" => recipient_instance
      }) do
    user = conn.assigns.current_user

    with :ok <- validate_did_format(recipient_did),
         :ok <- check_not_self(user, recipient_did),
         :ok <- check_not_blocked(user.id, recipient_did),
         :ok <- check_rate_limit(user.id),
         :ok <- check_pending_limit(recipient_did),
         :ok <- check_no_existing_request(user.id, recipient_did),
         {:ok, federated_user} <- ensure_federated_user(recipient_did, recipient_instance) do
      case Chat.create_federated_dm(user.id, federated_user.id) do
        {:ok, channel} ->
          # Create the DM request record
          {:ok, request} =
            Chat.create_dm_request(%{
              channel_id: channel.id,
              sender_id: user.id,
              recipient_did: recipient_did,
              recipient_instance: recipient_instance,
              status: "pending"
            })

          # Build and enqueue the DM hint activity
          deliver_dm_hint(user, channel, recipient_did, recipient_instance)

          conn
          |> put_status(:created)
          |> json(%{
            channel_id: channel.id,
            request_id: request.id,
            status: "pending"
          })

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to create DM channel: #{inspect(reason)}"})
      end
    else
      {:error, reason} when is_binary(reason) ->
        conn |> put_status(:bad_request) |> json(%{error: reason})

      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "DM request rate limit exceeded (max #{@max_requests_per_hour}/hour)"})

      {:error, :pending_limit} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Recipient has too many pending DM requests"})

      {:error, :already_requested} ->
        conn |> put_status(:conflict) |> json(%{error: "DM request already sent"})

      {:error, :blocked} ->
        conn |> put_status(:forbidden) |> json(%{error: "Cannot send DM to this user"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def create_federated_dm(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "recipient_did and recipient_instance are required"})
  end

  @doc """
  GET /api/v1/dm/requests
  List pending DM requests for the current user (received).
  """
  def list_dm_requests(conn, _params) do
    user = conn.assigns.current_user

    if is_nil(user.did) do
      json(conn, %{requests: []})
    else
      requests = Chat.list_dm_requests_for_did(user.did)
      json(conn, %{requests: requests})
    end
  end

  @doc """
  GET /api/v1/dm/requests/sent
  List DM requests sent by the current user.
  """
  def list_sent_dm_requests(conn, _params) do
    user = conn.assigns.current_user
    requests = Chat.list_sent_dm_requests(user.id)
    json(conn, %{requests: requests})
  end

  @doc """
  POST /api/v1/dm/requests/:id/respond
  Accept or reject a DM request.
  Params: status ("accepted" or "rejected")
  """
  def respond_to_dm_request(conn, %{"id" => request_id, "status" => new_status})
      when new_status in ["accepted", "rejected"] do
    user = conn.assigns.current_user

    case Chat.get_dm_request(request_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "DM request not found"})

      request ->
        # Verify the current user is the intended recipient (by DID)
        if request.recipient_did != user.did do
          conn |> put_status(:forbidden) |> json(%{error: "Not the recipient of this request"})
        else
          if request.status != "pending" do
            conn
            |> put_status(:conflict)
            |> json(%{error: "Request already #{request.status}"})
          else
            case Chat.update_dm_request(request, %{status: new_status}) do
              {:ok, updated} ->
                # Notify the sender via PubSub
                Phoenix.PubSub.broadcast(
                  Cairn.PubSub,
                  "user:#{request.sender_id}",
                  {:dm_request_response, %{
                    request_id: updated.id,
                    status: new_status,
                    channel_id: updated.channel_id
                  }}
                )

                json(conn, %{
                  id: updated.id,
                  status: updated.status,
                  channel_id: updated.channel_id
                })

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{errors: format_errors(changeset)})
            end
          end
        end
    end
  end

  def respond_to_dm_request(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "status must be 'accepted' or 'rejected'"})
  end

  @doc """
  POST /api/v1/dm/requests/:id/block
  Reject and block the sender's DID.
  """
  def block_sender(conn, %{"id" => request_id}) do
    user = conn.assigns.current_user

    case Chat.get_dm_request(request_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "DM request not found"})

      request ->
        if request.recipient_did != user.did do
          conn |> put_status(:forbidden) |> json(%{error: "Not the recipient of this request"})
        else
          # Reject the request
          Chat.update_dm_request(request, %{status: "blocked"})

          # Block the sender's DID
          sender_did = get_sender_did(request.sender_id)

          if sender_did do
            Chat.block_dm_sender(user.id, sender_did)
          end

          json(conn, %{ok: true, blocked: true})
        end
    end
  end

  # ── Private ──

  defp validate_did_format(did) do
    if String.starts_with?(did, "did:cairn:") do
      :ok
    else
      {:error, "Invalid DID format"}
    end
  end

  defp check_not_self(user, recipient_did) do
    if user.did == recipient_did do
      {:error, "Cannot send DM request to yourself"}
    else
      :ok
    end
  end

  defp check_not_blocked(user_id, recipient_did) do
    # Check if the recipient has blocked this user — we can only check
    # locally stored blocks. For cross-instance we rely on the recipient's
    # instance rejecting the hint.
    if Chat.is_dm_blocked?(user_id, recipient_did) do
      {:error, :blocked}
    else
      :ok
    end
  end

  defp check_rate_limit(user_id) do
    if Chat.count_recent_dm_requests(user_id) >= @max_requests_per_hour do
      {:error, :rate_limited}
    else
      :ok
    end
  end

  defp check_pending_limit(recipient_did) do
    if Chat.count_pending_dm_requests_for_did(recipient_did) >= @max_pending_per_recipient do
      {:error, :pending_limit}
    else
      :ok
    end
  end

  defp check_no_existing_request(user_id, recipient_did) do
    case Chat.find_dm_request(user_id, recipient_did) do
      nil -> :ok
      _existing -> {:error, :already_requested}
    end
  end

  defp ensure_federated_user(did, instance) do
    case Federation.get_federated_user_by_did(did) do
      nil ->
        # Create a placeholder federated user (will be updated on first real contact)
        Federation.get_or_create_federated_user(%{
          did: did,
          username: "unknown",
          home_instance: instance,
          public_key: "pending",
          actor_uri: "https://#{instance}/users/unknown",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      user ->
        {:ok, user}
    end
  end

  defp deliver_dm_hint(sender, channel, recipient_did, recipient_instance) do
    config = Application.get_env(:cairn, :federation, [])

    # Only deliver hints when federation is enabled
    if Keyword.get(config, :enabled, false) do
      domain = Keyword.get(config, :domain, "localhost")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Invite",
        "actor" => "https://#{domain}/users/#{sender.username}",
        "object" => %{
          "type" => "cairn:DmHint",
          "cairn:channelId" => channel.id,
          "cairn:senderDid" => sender.did,
          "cairn:senderUsername" => sender.username,
          "cairn:senderDisplayName" => sender.display_name,
          "cairn:recipientDid" => recipient_did
        },
        "target" => "https://#{recipient_instance}/users/#{extract_did_suffix(recipient_did)}"
      }

      DmHintWorker.enqueue(recipient_instance, activity)
    else
      {:ok, :federation_disabled}
    end
  end

  defp extract_did_suffix("did:cairn:" <> suffix), do: suffix
  defp extract_did_suffix(did), do: did

  defp get_sender_did(sender_id) do
    case Cairn.Accounts.get_user(sender_id) do
      nil -> nil
      user -> user.did
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
