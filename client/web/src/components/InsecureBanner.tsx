import { useState } from "react";

export default function InsecureBanner() {
  const [dismissed, setDismissed] = useState(false);

  if (dismissed || window.location.protocol === "https:") {
    return null;
  }

  return (
    <div className="insecure-banner" role="alert">
      <span className="insecure-banner-icon">&#x26A0;</span>
      <span className="insecure-banner-text">
        This server is not using HTTPS. Your connection is not encrypted.
        Passwords, messages, and files are sent in plain text.
      </span>
      <button
        className="insecure-banner-dismiss"
        onClick={() => setDismissed(true)}
        aria-label="Dismiss warning"
      >
        &times;
      </button>
    </div>
  );
}
