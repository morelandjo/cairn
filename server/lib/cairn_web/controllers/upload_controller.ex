defmodule CairnWeb.UploadController do
  use CairnWeb, :controller

  alias Cairn.Repo
  alias Cairn.Storage
  alias Cairn.Storage.{FileRecord, Thumbnail}

  import Ecto.Query

  @max_file_size 25 * 1024 * 1024
  @max_quota 500 * 1024 * 1024

  @allowed_content_types ~w(
    image/jpeg image/png image/gif image/webp image/svg+xml image/bmp image/tiff
    audio/mpeg audio/ogg audio/wav audio/webm audio/flac audio/aac
    video/mp4 video/webm video/ogg video/quicktime
    application/pdf
    text/plain text/csv text/html text/css text/javascript
    application/json application/xml
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.ms-excel
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-powerpoint
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/zip application/gzip application/x-tar
  )

  def create(conn, %{"file" => upload}) do
    user = conn.assigns.current_user

    with {:ok, data} <- read_upload(upload),
         :ok <- validate_size(data),
         :ok <- validate_content_type(upload.content_type),
         :ok <- validate_quota(user.id, byte_size(data)) do
      storage_key = sha256_key(data)
      :ok = Storage.put(storage_key, data, upload.content_type)

      thumbnail_key = maybe_generate_thumbnail(data, upload.content_type, storage_key)

      {:ok, file_record} =
        %FileRecord{}
        |> FileRecord.changeset(%{
          storage_key: storage_key,
          original_name: upload.filename,
          content_type: upload.content_type,
          size_bytes: byte_size(data),
          uploader_id: user.id,
          thumbnail_key: thumbnail_key
        })
        |> Repo.insert()

      conn
      |> put_status(:created)
      |> json(file_json(file_record))
    else
      {:error, :too_large} ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: "file exceeds 25MB limit"})

      {:error, :invalid_content_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "content type not allowed"})

      {:error, :quota_exceeded} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "storage quota exceeded (500MB)"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "upload failed: #{inspect(reason)}"})
    end
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(FileRecord, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "file not found"})

      file_record ->
        case Storage.get(file_record.storage_key) do
          {:ok, data} ->
            conn
            |> put_resp_content_type(file_record.content_type)
            |> put_resp_header(
              "content-disposition",
              "inline; filename=\"#{file_record.original_name}\""
            )
            |> send_resp(200, data)

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "file data not found"})
        end
    end
  end

  def thumbnail(conn, %{"id" => id}) do
    case Repo.get(FileRecord, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "file not found"})

      %{thumbnail_key: nil} ->
        conn |> put_status(:not_found) |> json(%{error: "no thumbnail available"})

      %{thumbnail_key: thumb_key} ->
        case Storage.get(thumb_key) do
          {:ok, data} ->
            conn
            |> put_resp_content_type("image/jpeg")
            |> send_resp(200, data)

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "thumbnail data not found"})
        end
    end
  end

  defp read_upload(%Plug.Upload{path: path}) do
    File.read(path)
  end

  defp validate_size(data) when byte_size(data) > @max_file_size, do: {:error, :too_large}
  defp validate_size(_data), do: :ok

  defp validate_content_type(content_type) do
    if content_type in @allowed_content_types do
      :ok
    else
      {:error, :invalid_content_type}
    end
  end

  defp validate_quota(user_id, new_size) do
    current_usage =
      from(f in FileRecord,
        where: f.uploader_id == ^user_id,
        select: coalesce(sum(f.size_bytes), 0)
      )
      |> Repo.one()
      |> to_integer()

    if current_usage + new_size > @max_quota do
      {:error, :quota_exceeded}
    else
      :ok
    end
  end

  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(i) when is_integer(i), do: i

  defp sha256_key(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp maybe_generate_thumbnail(data, content_type, storage_key) do
    case Thumbnail.generate(data, content_type) do
      {:ok, thumb_data} ->
        thumb_key = "thumb_" <> storage_key
        :ok = Storage.put(thumb_key, thumb_data, "image/jpeg")
        thumb_key

      {:error, _} ->
        nil
    end
  end

  defp file_json(file_record) do
    %{
      id: file_record.id,
      storage_key: file_record.storage_key,
      original_name: file_record.original_name,
      content_type: file_record.content_type,
      size_bytes: file_record.size_bytes,
      thumbnail_key: file_record.thumbnail_key,
      inserted_at: file_record.inserted_at
    }
  end
end
