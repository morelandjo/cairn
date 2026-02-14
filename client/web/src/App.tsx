import { useEffect } from "react";
import type { ReactNode } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
  useNavigate,
} from "react-router-dom";
import { useAuthStore } from "./stores/authStore.ts";
import { useServerUrlStore } from "./stores/serverUrlStore.ts";
import LoginPage from "./pages/LoginPage.tsx";
import RegisterPage from "./pages/RegisterPage.tsx";
import ChannelView from "./pages/ChannelView.tsx";
import InvitePage from "./pages/InvitePage.tsx";
import SecuritySettings from "./pages/SecuritySettings.tsx";
import ServerSettings from "./pages/ServerSettings.tsx";
import ServerDiscovery from "./pages/ServerDiscovery.tsx";
import FederatedInvitePage from "./pages/FederatedInvitePage.tsx";
import ServerConnect from "./pages/ServerConnect.tsx";
import MainLayout from "./layouts/MainLayout.tsx";
import InsecureBanner from "./components/InsecureBanner.tsx";
import { useChannelStore } from "./stores/channelStore.ts";
import { useServerStore } from "./stores/serverStore.ts";
import "./App.css";

/** Redirects unauthenticated users to /login. */
function RequireAuth({ children }: { children: ReactNode }) {
  const user = useAuthStore((s) => s.user);
  const accessToken = useAuthStore((s) => s.accessToken);
  const isLoading = useAuthStore((s) => s.isLoading);

  if (isLoading) {
    return <div className="loading-screen">Loading...</div>;
  }

  if (!user && !accessToken) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
}

/** Gates routes on desktop until a server URL is configured. No-op in web mode. */
function RequireServer({ children }: { children: ReactNode }) {
  const serverUrl = useServerUrlStore((s) => s.serverUrl);
  const isLoaded = useServerUrlStore((s) => s.isLoaded);
  const loadServerUrl = useServerUrlStore((s) => s.loadServerUrl);
  const setServerUrl = useServerUrlStore((s) => s.setServerUrl);

  useEffect(() => {
    loadServerUrl();
  }, [loadServerUrl]);

  if (!isLoaded) {
    return <div className="loading-screen">Loading...</div>;
  }

  if (serverUrl === null) {
    return <ServerConnect onConnect={(url) => setServerUrl(url)} />;
  }

  return <>{children}</>;
}

/** Redirect to the first server or DM channels. */
function ServerRedirect() {
  const servers = useServerStore((s) => s.servers);
  const fetchServers = useServerStore((s) => s.fetchServers);
  const channels = useChannelStore((s) => s.channels);
  const fetchChannels = useChannelStore((s) => s.fetchChannels);
  const navigate = useNavigate();

  useEffect(() => {
    fetchServers();
    fetchChannels();
  }, [fetchServers, fetchChannels]);

  useEffect(() => {
    if (servers.length > 0) {
      navigate(`/servers/${servers[0].id}`, { replace: true });
    } else if (channels.length > 0) {
      navigate(`/channels/${channels[0].id}`, { replace: true });
    }
  }, [servers, channels, navigate]);

  return (
    <div className="welcome-screen">
      <h2>Welcome to Cairn</h2>
      <p>
        {servers.length === 0 && channels.length === 0
          ? "No servers yet. Create one from the sidebar!"
          : "Redirecting..."}
      </p>
    </div>
  );
}

/** Redirect to the first channel in a server. */
function ChannelRedirect() {
  const channels = useChannelStore((s) => s.channels);
  const navigate = useNavigate();
  const currentServerId = useServerStore((s) => s.currentServerId);

  useEffect(() => {
    if (channels.length > 0) {
      const path = currentServerId
        ? `/servers/${currentServerId}/channels/${channels[0].id}`
        : `/channels/${channels[0].id}`;
      navigate(path, { replace: true });
    }
  }, [channels, navigate, currentServerId]);

  return (
    <div className="welcome-screen">
      <h2>Welcome to Cairn</h2>
      <p>
        {channels.length === 0
          ? "No channels yet. Create one from the sidebar!"
          : "Redirecting..."}
      </p>
    </div>
  );
}

function AppRoutes() {
  const loadSession = useAuthStore((s) => s.loadSession);

  useEffect(() => {
    loadSession();
  }, [loadSession]);

  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route path="/invite/:code" element={<InvitePage />} />
      <Route
        path="/federated-invite/:code"
        element={
          <RequireAuth>
            <FederatedInvitePage />
          </RequireAuth>
        }
      />
      <Route
        path="/settings"
        element={
          <RequireAuth>
            <SecuritySettings />
          </RequireAuth>
        }
      />
      {/* Server settings */}
      <Route
        path="/servers/:serverId/settings"
        element={
          <RequireAuth>
            <ServerSettings />
          </RequireAuth>
        }
      />
      {/* Server discovery */}
      <Route
        path="/discover"
        element={
          <RequireAuth>
            <ServerDiscovery />
          </RequireAuth>
        }
      />
      {/* Server-scoped routes */}
      <Route
        path="/servers/:serverId"
        element={
          <RequireAuth>
            <MainLayout />
          </RequireAuth>
        }
      >
        <Route path="channels/:id" element={<ChannelView />} />
        <Route index element={<ChannelRedirect />} />
      </Route>
      {/* Backward-compatible flat channel routes */}
      <Route
        path="/channels"
        element={
          <RequireAuth>
            <MainLayout />
          </RequireAuth>
        }
      >
        <Route path=":id" element={<ChannelView />} />
        <Route index element={<ChannelRedirect />} />
      </Route>
      <Route
        path="/"
        element={
          <RequireAuth>
            <ServerRedirect />
          </RequireAuth>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <InsecureBanner />
      <RequireServer>
        <AppRoutes />
      </RequireServer>
    </BrowserRouter>
  );
}
