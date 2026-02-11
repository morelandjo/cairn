import { useEffect, useState } from "react";
import { useParams, useNavigate, Link } from "react-router-dom";
import { useAuthStore } from "../stores/authStore.ts";
import { getInvite, useInvite } from "../api/invites.ts";
import type { InviteInfo } from "../api/invites.ts";

export default function InvitePage() {
  const { code } = useParams<{ code: string }>();
  const navigate = useNavigate();
  const user = useAuthStore((s) => s.user);
  const accessToken = useAuthStore((s) => s.accessToken);

  const [invite, setInvite] = useState<InviteInfo | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isJoining, setIsJoining] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    if (!code) return;
    getInvite(code)
      .then((data) => {
        setInvite(data.invite);
        setIsLoading(false);
      })
      .catch((err) => {
        const message = err instanceof Error ? err.message : "Invite not found";
        setError(message);
        setIsLoading(false);
      });
  }, [code]);

  async function handleJoin() {
    if (!code) return;
    setIsJoining(true);
    setError(null);
    try {
      const data = await useInvite(code);
      navigate(`/channels/${data.channel.id}`);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Failed to join";
      setError(message);
      setIsJoining(false);
    }
  }

  if (isLoading) {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <h2>Loading invite...</h2>
        </div>
      </div>
    );
  }

  if (!user || !accessToken) {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <h1>Murmuring</h1>
          <h2>You've been invited!</h2>
          {invite && (
            <p style={{ textAlign: "center", color: "#b5bac1", marginBottom: 16 }}>
              Join <strong>#{invite.channel_name}</strong>
            </p>
          )}
          <p className="auth-link">
            <Link to={`/login?redirect=/invite/${code}`}>Log in</Link> or{" "}
            <Link to={`/register?redirect=/invite/${code}`}>register</Link> to
            accept this invite.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <h1>Murmuring</h1>
        {error ? (
          <>
            <h2>Invite Error</h2>
            <div className="form-error" style={{ textAlign: "center" }}>
              {error}
            </div>
            <Link to="/channels" className="btn-primary" style={{ display: "block", textAlign: "center", textDecoration: "none" }}>
              Go to Channels
            </Link>
          </>
        ) : invite ? (
          <>
            <h2>You've been invited to</h2>
            <p style={{ textAlign: "center", color: "#f2f3f5", fontSize: "1.25rem", margin: "16px 0" }}>
              #{invite.channel_name}
            </p>
            <button
              className="btn-primary"
              onClick={handleJoin}
              disabled={isJoining}
            >
              {isJoining ? "Joining..." : "Accept Invite"}
            </button>
          </>
        ) : null}
      </div>
    </div>
  );
}
