import { useState } from "react";
import type { FormEvent } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useAuthStore } from "../stores/authStore.ts";

export default function LoginPage() {
  const navigate = useNavigate();
  const { login, isLoading, error, setError } = useAuthStore();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      const result = await login(username, password);
      if (result.requiresTotp) {
        // TODO: TOTP page
        alert("TOTP required. Not yet implemented in the UI.");
      } else {
        navigate("/");
      }
    } catch {
      // error is set in the store
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <h1>Cairn</h1>
        <h2>Welcome back</h2>
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
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
            />
          </div>
          {error && <div className="form-error">{error}</div>}
          <button type="submit" className="btn-primary" disabled={isLoading}>
            {isLoading ? "Logging in..." : "Log In"}
          </button>
        </form>
        <p className="auth-link">
          Need an account? <Link to="/register">Register</Link>
        </p>
      </div>
    </div>
  );
}
