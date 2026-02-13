import { useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useAuthStore } from "../stores/authStore.ts";
import { useConnectionStore } from "../stores/connectionStore.ts";
import {
  requestFederatedToken,
  createRemoteClient,
  useRemoteFederatedInvite,
} from "../api/federation.ts";

/**
 * Handles invite links for remote instances.
 * URL: /federated-invite/:code?instance=remote.example.com
 *
 * Flow:
 * 1. Shows invite confirmation with instance info
 * 2. Requests a federated auth token from home instance
 * 3. Uses the token to accept the invite on the remote instance
 * 4. Establishes a WebSocket connection to the remote instance
 * 5. Navigates to the joined server
 */
export default function FederatedInvitePage() {
  const { code } = useParams<{ code: string }>();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const user = useAuthStore((s) => s.user);
  const accessToken = useAuthStore((s) => s.accessToken);
  const connect = useConnectionStore((s) => s.connect);

  const instance = searchParams.get("instance") || "";

  const [status, setStatus] = useState<"idle" | "joining" | "success" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  if (!user || !accessToken) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <h2>Federated Invite</h2>
          <p>You must be logged in to accept this invite.</p>
          <button className="btn-primary" onClick={() => navigate("/login")}>
            Log In
          </button>
        </div>
      </div>
    );
  }

  if (!code || !instance) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <h2>Invalid Invite</h2>
          <p>This invite link is missing required information.</p>
          <button className="btn-primary" onClick={() => navigate("/")}>
            Go Home
          </button>
        </div>
      </div>
    );
  }

  async function handleJoin() {
    setStatus("joining");
    setError(null);

    try {
      // Step 1: Get federated auth token from home instance
      const { token: federatedToken } = await requestFederatedToken(instance);

      // Step 2: Use the token to accept the invite on the remote instance
      const remoteBaseUrl = `https://${instance}`;
      const remoteClient = createRemoteClient(remoteBaseUrl, federatedToken);
      const result = await useRemoteFederatedInvite(remoteClient, code!);

      // Step 3: Establish WebSocket connection to the remote instance
      const wsUrl = `wss://${instance}/socket`;
      connect(instance, federatedToken, false, wsUrl);

      setStatus("success");

      // Step 4: Navigate to the joined server
      if (result.server_id) {
        setTimeout(() => {
          navigate(`/servers/${result.server_id}`);
        }, 1500);
      }
    } catch (err) {
      setStatus("error");
      setError(err instanceof Error ? err.message : "Failed to join");
    }
  }

  return (
    <div className="invite-page">
      <div className="invite-card">
        <h2>Federated Server Invite</h2>
        <div className="invite-details">
          <div className="invite-info-row">
            <span className="invite-label">Instance</span>
            <span className="invite-value">{instance}</span>
          </div>
          <div className="invite-info-row">
            <span className="invite-label">Invite Code</span>
            <span className="invite-value" style={{ fontFamily: "monospace" }}>
              {code}
            </span>
          </div>
          <div className="invite-info-row">
            <span className="invite-label">Your Identity</span>
            <span className="invite-value">
              {user?.username}
              {user?.did && (
                <span style={{ fontSize: "0.8em", opacity: 0.7, marginLeft: 8 }}>
                  {user.did.slice(0, 16)}...
                </span>
              )}
            </span>
          </div>
        </div>

        {status === "idle" && (
          <>
            <p className="invite-description">
              You&apos;ll join this server on <strong>{instance}</strong> using
              your federated identity. Your DMs and account stay on your home
              instance.
            </p>
            <button className="btn-primary" onClick={handleJoin}>
              Join Server
            </button>
            <button className="btn-secondary" onClick={() => navigate("/")}>
              Cancel
            </button>
          </>
        )}

        {status === "joining" && (
          <div className="invite-status">
            <p>Authenticating with {instance}...</p>
          </div>
        )}

        {status === "success" && (
          <div className="invite-status status-ok">
            <p>Successfully joined! Redirecting...</p>
          </div>
        )}

        {status === "error" && (
          <div className="invite-status status-error">
            <p>Failed to join: {error}</p>
            <button className="btn-primary" onClick={handleJoin}>
              Try Again
            </button>
            <button className="btn-secondary" onClick={() => navigate("/")}>
              Go Home
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
