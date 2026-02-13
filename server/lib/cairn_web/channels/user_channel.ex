defmodule CairnWeb.UserChannel do
  @moduledoc """
  Personal notification channel for user-scoped events:
  - DM request received
  - DM request accepted/rejected
  - Future: other user-scoped notifications
  """

  use CairnWeb, :channel

  @impl true
  def join("user:" <> user_id, _params, socket) do
    # Only allow local (non-federated) users to join their own user channel
    if socket.assigns[:is_federated] do
      {:error, %{reason: "federated users cannot join user channels"}}
    else
      if socket.assigns.user_id == user_id do
        # Subscribe to PubSub for this user (for cross-process broadcasts)
        Phoenix.PubSub.subscribe(Cairn.PubSub, "user:#{user_id}")
        {:ok, socket}
      else
        {:error, %{reason: "unauthorized"}}
      end
    end
  end

  @impl true
  def handle_info({:dm_request, payload}, socket) do
    push(socket, "dm_request", payload)
    {:noreply, socket}
  end

  def handle_info({:dm_request_response, payload}, socket) do
    push(socket, "dm_request_response", payload)
    {:noreply, socket}
  end

  # Catch-all for future notification types
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
