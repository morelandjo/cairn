defmodule Murmuring.Storage.Thumbnail do
  @moduledoc """
  Thumbnail generation for uploaded images using the Image library (libvips).

  Generates 400x400 JPEG thumbnails at 80% quality. Only processes image/*
  content types.
  """

  @thumbnail_size 400
  @jpeg_quality 80

  @doc """
  Generate a 400x400 JPEG thumbnail from the given binary data.

  Returns `{:ok, thumbnail_binary}` on success, or `{:error, reason}` on failure.
  Only processes image/* content types; returns an error for other types.
  """
  def generate(data, content_type) do
    if image_content_type?(content_type) do
      do_generate(data)
    else
      {:error, :not_an_image}
    end
  end

  defp do_generate(data) do
    with {:ok, image} <- Image.from_binary(data),
         {:ok, thumbnail} <- Image.thumbnail(image, @thumbnail_size, crop: :center),
         {:ok, binary} <- Image.write(thumbnail, :memory, suffix: ".jpg", quality: @jpeg_quality) do
      {:ok, binary}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp image_content_type?("image/" <> _), do: true
  defp image_content_type?(_), do: false
end
