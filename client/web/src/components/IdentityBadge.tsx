import { useState } from "react";

interface IdentityBadgeProps {
  did: string;
  homeInstance?: string;
  compact?: boolean;
}

export default function IdentityBadge({
  did,
  homeInstance,
  compact = false,
}: IdentityBadgeProps) {
  const [copied, setCopied] = useState(false);

  const truncated = compact
    ? `${did.slice(0, 16)}...`
    : `${did.slice(0, 20)}...${did.slice(-8)}`;

  function handleCopy() {
    navigator.clipboard.writeText(did);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <span
      className="identity-badge"
      title={`${did}${homeInstance ? ` (${homeInstance})` : ""}\nClick to copy`}
      onClick={handleCopy}
      style={{ cursor: "pointer" }}
    >
      <span className="identity-badge-did" style={{ fontFamily: "monospace", fontSize: "0.8em" }}>
        {truncated}
      </span>
      {homeInstance && (
        <span className="identity-badge-instance" style={{ fontSize: "0.75em", opacity: 0.7 }}>
          @{homeInstance}
        </span>
      )}
      {copied && <span className="identity-badge-copied"> (copied)</span>}
    </span>
  );
}
