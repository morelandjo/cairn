defmodule MurmuringWeb.WebauthnController do
  use MurmuringWeb, :controller

  @rp_id "localhost"

  def register(conn, _params) do
    user = conn.assigns.current_user

    challenge =
      Wax.new_registration_challenge(
        rp_id: @rp_id,
        origin: "http://localhost:5173"
      )

    conn
    |> put_session(:webauthn_challenge, challenge)
    |> json(%{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{id: @rp_id, name: "Murmuring"},
      user: %{
        id: Base.url_encode64(user.id, padding: false),
        name: user.username,
        displayName: user.display_name || user.username
      }
    })
  end

  def register_complete(conn, %{
        "attestation_object" => attestation_object_b64,
        "client_data_json" => client_data_json
      }) do
    challenge = get_session(conn, :webauthn_challenge)

    if is_nil(challenge) do
      conn |> put_status(:bad_request) |> json(%{error: "no registration challenge"})
    else
      attestation_object = Base.url_decode64!(attestation_object_b64, padding: false)

      case Wax.register(attestation_object, client_data_json, challenge) do
        {:ok, {auth_data, _attestation_result}} ->
          _credential_id = auth_data.attested_credential_data.credential_id
          _cose_key = auth_data.attested_credential_data.credential_public_key

          conn
          |> delete_session(:webauthn_challenge)
          |> json(%{status: "registered"})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
      end
    end
  end

  def authenticate(conn, _params) do
    challenge =
      Wax.new_authentication_challenge(
        rp_id: @rp_id,
        origin: "http://localhost:5173"
      )

    conn
    |> put_session(:webauthn_challenge, challenge)
    |> json(%{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp_id: @rp_id
    })
  end

  def authenticate_complete(
        conn,
        %{
          "credential_id" => credential_id_b64,
          "authenticator_data" => auth_data_b64,
          "signature" => sig_b64,
          "client_data_json" => client_data_json
        }
      ) do
    challenge = get_session(conn, :webauthn_challenge)

    if is_nil(challenge) do
      conn |> put_status(:bad_request) |> json(%{error: "no authentication challenge"})
    else
      credential_id = Base.url_decode64!(credential_id_b64, padding: false)
      auth_data_bin = Base.url_decode64!(auth_data_b64, padding: false)
      sig = Base.url_decode64!(sig_b64, padding: false)

      case Wax.authenticate(credential_id, auth_data_bin, sig, client_data_json, challenge) do
        {:ok, _auth_data} ->
          conn
          |> delete_session(:webauthn_challenge)
          |> json(%{status: "authenticated"})

        {:error, reason} ->
          conn |> put_status(:unauthorized) |> json(%{error: inspect(reason)})
      end
    end
  end
end
