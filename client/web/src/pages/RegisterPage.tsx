import { useState, useRef, useEffect } from "react";
import type { FormEvent } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useAuthStore } from "../stores/authStore.ts";
import "altcha";

export default function RegisterPage() {
  const navigate = useNavigate();
  const { register, recoveryCodes, clearRecoveryCodes, isLoading, error, setError } =
    useAuthStore();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [altchaPayload, setAltchaPayload] = useState<string | null>(null);
  const altchaRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const el = altchaRef.current;
    if (!el) return;
    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      if (detail?.payload) {
        setAltchaPayload(detail.payload as string);
      }
    };
    el.addEventListener("statechange", handler);
    return () => el.removeEventListener("statechange", handler);
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      await register(username, password, displayName || undefined, {
        altcha: altchaPayload ?? undefined,
        website: "",
      });
    } catch {
      // error is set in the store
    }
  }

  function handleContinue() {
    clearRecoveryCodes();
    navigate("/");
  }

  if (recoveryCodes) {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <h1>Recovery Codes</h1>
          <p>
            Save these recovery codes in a safe place. You will need them if you
            lose access to your account.
          </p>
          <div className="recovery-codes">
            {recoveryCodes.map((code) => (
              <code key={code}>{code}</code>
            ))}
          </div>
          <button className="btn-primary" onClick={handleContinue}>
            I have saved my codes
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <h1>Cairn</h1>
        <h2>Create an account</h2>
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label htmlFor="username">Username</label>
            <input
              id="username"
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
              autoFocus
              autoComplete="username"
            />
          </div>
          <div className="form-group">
            <label htmlFor="display-name">Display Name (optional)</label>
            <input
              id="display-name"
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              autoComplete="name"
            />
          </div>
          <div className="form-group">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              autoComplete="new-password"
            />
          </div>
          <div style={{ position: "absolute", left: "-9999px" }} aria-hidden="true">
            <label htmlFor="website">Website</label>
            <input id="website" name="website" type="text" tabIndex={-1} autoComplete="off" />
          </div>
          <altcha-widget
            ref={altchaRef}
            challengeurl="/api/v1/auth/challenge"
            auto="onsubmit"
            hidefooter
          />
          {error && <div className="form-error">{error}</div>}
          <button type="submit" className="btn-primary" disabled={isLoading}>
            {isLoading ? "Creating account..." : "Register"}
          </button>
        </form>
        <p className="auth-link">
          Already have an account? <Link to="/login">Log In</Link>
        </p>
      </div>
    </div>
  );
}
