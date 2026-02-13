import { useRef, useState } from "react";
import { uploadFile } from "../api/upload.ts";

interface FileUploadProps {
  onUploaded: (file: { id: string; filename: string; content_type: string; size: number }) => void;
}

export default function FileUpload({ onUploaded }: FileUploadProps) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploading(true);
    setError(null);

    try {
      const result = await uploadFile(file);
      onUploaded(result);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Upload failed";
      setError(message);
    } finally {
      setIsUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  return (
    <div className="file-upload">
      <input
        ref={fileRef}
        type="file"
        onChange={handleFileChange}
        disabled={isUploading}
        hidden
      />
      <button
        className="btn-attach"
        onClick={() => fileRef.current?.click()}
        disabled={isUploading}
        title="Attach file"
      >
        {isUploading ? "..." : "+"}
      </button>
      {error && <span className="file-upload-error">{error}</span>}
    </div>
  );
}
