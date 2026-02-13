defmodule CairnWeb.KeyController do
  use CairnWeb, :controller

  alias Cairn.Keys

  @doc "POST /api/v1/users/me/keys — Upload key bundle"
  def upload(conn, params) do
    user = conn.assigns.current_user

    with {:ok, identity_key} <-
           decode_base64(params["identity_public_key"], "identity_public_key"),
         {:ok, signed_prekey} <- decode_base64(params["signed_prekey"], "signed_prekey"),
         {:ok, signature} <-
           decode_base64(params["signed_prekey_signature"], "signed_prekey_signature"),
         {:ok, otps} <- decode_prekeys(params["one_time_prekeys"]) do
      bundle = %{
        identity_public_key: identity_key,
        signed_prekey: signed_prekey,
        signed_prekey_signature: signature,
        one_time_prekeys: otps
      }

      case Keys.upload_key_bundle(user, bundle) do
        {:ok, {_user, prekeys}} ->
          conn
          |> put_status(:created)
          |> json(%{uploaded_prekeys: length(prekeys)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    else
      {:error, field, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid base64 for #{field}: #{reason}"})
    end
  end

  @doc "GET /api/v1/users/:user_id/keys — Get a user's key bundle (consumes one OTP)"
  def show(conn, %{"user_id" => user_id}) do
    case Keys.get_key_bundle(user_id) do
      {:ok, bundle} ->
        response = %{
          identity_public_key: Base.encode64(bundle.identity_public_key),
          signed_prekey: Base.encode64(bundle.signed_prekey),
          signed_prekey_signature: Base.encode64(bundle.signed_prekey_signature)
        }

        response =
          if bundle.one_time_prekey do
            Map.put(response, :one_time_prekey, %{
              key_id: bundle.one_time_prekey.key_id,
              public_key: Base.encode64(bundle.one_time_prekey.public_key)
            })
          else
            response
          end

        conn |> json(response)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "user not found"})

      {:error, :no_keys} ->
        conn |> put_status(:not_found) |> json(%{error: "no keys uploaded"})
    end
  end

  @doc "GET /api/v1/users/me/keys/prekey-count — Get count of remaining prekeys"
  def prekey_count(conn, _params) do
    user = conn.assigns.current_user
    count = Keys.count_prekeys(user.id)
    conn |> json(%{count: count})
  end

  # --- MLS KeyPackage endpoints ---

  @doc "POST /api/v1/users/me/key-packages — Upload MLS key packages"
  def upload_key_packages(conn, %{"key_packages" => packages}) when is_list(packages) do
    user = conn.assigns.current_user

    decoded =
      Enum.reduce_while(packages, {:ok, []}, fn pkg, {:ok, acc} ->
        case Base.decode64(pkg) do
          {:ok, data} -> {:cont, {:ok, [data | acc]}}
          :error -> {:halt, {:error, "invalid base64 in key_packages"}}
        end
      end)

    case decoded do
      {:ok, data_list} ->
        case Keys.upload_mls_key_packages(user.id, Enum.reverse(data_list)) do
          {:ok, inserted} ->
            conn
            |> put_status(:created)
            |> json(%{uploaded: length(inserted)})

          {:error, :too_many_packages} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "max 100 key packages per upload"})
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  def upload_key_packages(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "key_packages must be a list of base64-encoded strings"})
  end

  @doc "GET /api/v1/users/:user_id/key-packages — Claim one MLS key package"
  def claim_key_package(conn, %{"user_id" => user_id}) do
    case Keys.consume_mls_key_package(user_id) do
      {:ok, key_package} ->
        conn |> json(%{key_package: Base.encode64(key_package.data)})

      {:error, :exhausted} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "no key packages available"})
    end
  end

  @doc "GET /api/v1/users/me/key-packages/count — Count remaining MLS key packages"
  def key_package_count(conn, _params) do
    user = conn.assigns.current_user
    count = Keys.count_mls_key_packages(user.id)
    conn |> json(%{count: count})
  end

  # --- Key Backup endpoints ---

  @max_backup_size 10 * 1024 * 1024

  @doc "POST /api/v1/users/me/key-backup — Upload encrypted key backup"
  def upload_backup(conn, %{"data" => data}) when is_binary(data) do
    user = conn.assigns.current_user

    case Base.decode64(data) do
      {:ok, decoded} ->
        if byte_size(decoded) > @max_backup_size do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "backup exceeds 10MB limit"})
        else
          case Keys.upsert_key_backup(user.id, decoded) do
            {:ok, backup} ->
              conn
              |> put_status(:created)
              |> json(%{size_bytes: backup.size_bytes})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{errors: format_errors(changeset)})
          end
        end

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid base64 data"})
    end
  end

  def upload_backup(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "data field required"})
  end

  @doc "GET /api/v1/users/me/key-backup — Download encrypted key backup"
  def download_backup(conn, _params) do
    user = conn.assigns.current_user

    case Keys.get_key_backup(user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "no backup found"})

      backup ->
        json(conn, %{
          data: Base.encode64(backup.data),
          size_bytes: backup.size_bytes,
          updated_at: backup.updated_at
        })
    end
  end

  @doc "DELETE /api/v1/users/me/key-backup — Delete encrypted key backup"
  def delete_backup(conn, _params) do
    user = conn.assigns.current_user

    case Keys.delete_key_backup(user.id) do
      {:ok, _} ->
        json(conn, %{ok: true})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "no backup found"})
    end
  end

  @doc "POST /api/v1/users/me/did/rotate-signing-key — Rotate the user's signing key"
  def rotate_signing_key(conn, params) do
    user = conn.assigns.current_user

    with {:ok, new_signing_key} <-
           decode_base64(params["new_signing_key"], "new_signing_key"),
         {:ok, rotation_private_key} <-
           decode_base64(params["rotation_private_key"], "rotation_private_key") do
      if is_nil(user.did) do
        conn
        |> put_status(:bad_request)
        |> json(%{error: "user does not have a DID"})
      else
        case Cairn.Identity.rotate_signing_key(
               user.did,
               new_signing_key,
               rotation_private_key
             ) do
          {:ok, _op} ->
            # Also update the user's identity_public_key
            {:ok, _user} =
              Cairn.Accounts.update_user_keys(user, %{identity_public_key: new_signing_key})

            json(conn, %{ok: true, did: user.did})

          {:error, {:invalid_signature, _seq}} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "invalid rotation key signature"})

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "rotation failed: #{inspect(reason)}"})
        end
      end
    else
      {:error, field, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid base64 for #{field}: #{reason}"})
    end
  end

  defp decode_base64(nil, field), do: {:error, field, "missing"}

  defp decode_base64(value, field) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, field, "invalid encoding"}
    end
  end

  defp decode_base64(_, field), do: {:error, field, "must be a string"}

  defp decode_prekeys(nil), do: {:ok, []}

  defp decode_prekeys(prekeys) when is_list(prekeys) do
    results =
      Enum.reduce_while(prekeys, {:ok, []}, fn pk, {:ok, acc} ->
        with {:ok, key_id} <- validate_key_id(pk["key_id"]),
             {:ok, public_key} <- decode_base64(pk["public_key"], "one_time_prekey.public_key") do
          {:cont, {:ok, [%{key_id: key_id, public_key: public_key} | acc]}}
        else
          {:error, field, reason} ->
            {:halt, {:error, field, reason}}
        end
      end)

    case results do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp decode_prekeys(_), do: {:error, "one_time_prekeys", "must be a list"}

  defp validate_key_id(nil), do: {:error, "one_time_prekey.key_id", "missing"}
  defp validate_key_id(id) when is_integer(id), do: {:ok, id}
  defp validate_key_id(_), do: {:error, "one_time_prekey.key_id", "must be an integer"}

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
