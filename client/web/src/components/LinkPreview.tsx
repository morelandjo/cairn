interface Props {
  url: string;
  title?: string;
  description?: string;
  image_url?: string;
  site_name?: string;
}

export default function LinkPreview({
  url,
  title,
  description,
  image_url,
  site_name,
}: Props) {
  if (!title && !description) return null;

  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      className="link-preview"
    >
      {image_url && (
        <img
          src={image_url}
          alt={title || "Preview"}
          className="link-preview-image"
        />
      )}
      <div className="link-preview-text">
        {site_name && (
          <span className="link-preview-site">{site_name}</span>
        )}
        {title && <span className="link-preview-title">{title}</span>}
        {description && (
          <span className="link-preview-desc">{description}</span>
        )}
      </div>
    </a>
  );
}
