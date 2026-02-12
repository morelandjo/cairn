defmodule CairnWeb.ActorController do
  use CairnWeb, :controller

  alias Cairn.Accounts
  alias Cairn.Federation.ActivityPub

  @doc "GET /users/:username — returns ActivityPub actor profile."
  def show(conn, %{"username" => username}) do
    config = Application.get_env(:cairn, :federation, [])
    domain = Keyword.get(config, :domain, "localhost")

    case Accounts.get_user_by_username(username) do
      nil ->
        conn
        |> put_status(404)
        |> json(%{error: "User not found"})

      user ->
        actor = ActivityPub.serialize_user(user, domain)

        actor =
          if user.did do
            Map.put(actor, "alsoKnownAs", [user.did])
          else
            actor
          end

        conn
        |> put_resp_header("content-type", "application/activity+json")
        |> json(actor)
    end
  end

  @doc "GET /users/:username/outbox — returns user's outbox."
  def outbox(conn, %{"username" => username}) do
    config = Application.get_env(:cairn, :federation, [])
    domain = Keyword.get(config, :domain, "localhost")

    case Accounts.get_user_by_username(username) do
      nil ->
        conn
        |> put_status(404)
        |> json(%{error: "User not found"})

      _user ->
        conn
        |> put_resp_header("content-type", "application/activity+json")
        |> json(%{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "type" => "OrderedCollection",
          "id" => "https://#{domain}/users/#{username}/outbox",
          "totalItems" => 0,
          "orderedItems" => []
        })
    end
  end
end
