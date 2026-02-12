defmodule CairnWeb.ExportController do
  use CairnWeb, :controller

  alias Cairn.Export

  # POST /api/v1/users/me/export
  def create(conn, _params) do
    user_id = conn.assigns.current_user.id

    case Export.request_export(user_id) do
      {:ok, _job} ->
        conn |> put_status(:accepted) |> json(%{status: "processing"})

      {:error, _} ->
        conn |> put_status(:internal_server_error) |> json(%{error: "failed to start export"})
    end
  end

  # GET /api/v1/users/me/export/download
  def download(conn, _params) do
    user_id = conn.assigns.current_user.id

    case Export.get_export_file(user_id) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"cairn_export.json\""
        )
        |> send_file(200, path)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "no export available"})
    end
  end

  # POST /api/v1/users/me/export/portability
  def portability(conn, _params) do
    user_id = conn.assigns.current_user.id

    case Export.export_portability_data(user_id) do
      {:ok, data} ->
        json(conn, %{export: data})

      {:error, _} ->
        conn |> put_status(:internal_server_error) |> json(%{error: "export failed"})
    end
  end
end
