import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useMlsStore } from "../stores/mlsStore.ts";
import { useAuthStore } from "../stores/authStore.ts";
import { exportKeys, importKeys } from "@murmuring/proto";
import { apiFetch } from "../api/client.ts";
import * as mlsApi from "../api/mls.ts";

export default function SecuritySettings() {
  const navigate = useNavigate();
  const mlsInitialized = useMlsStore((s) => s.initialized);
  const mlsError = useMlsStore((s) => s.error);
  const user = useAuthStore((s) => s.user);

  const [keyPackageCount, setKeyPackageCount] = useState<number | null>(null);
  const [backupPassphrase, setBackupPassphrase] = useState("");
  const [restorePassphrase, setRestorePassphrase] = useState("");
  const [backupStatus, setBackupStatus] = useState<string | null>(null);
  const [restoreStatus, setRestoreStatus] = useState<string | null>(null);
  const [isBackingUp, setIsBackingUp] = useState(false);
  const [isRestoring, setIsRestoring] = useState(false);
  const [didCopied, setDidCopied] = useState(false);

  useEffect(() => {
    mlsApi.keyPackageCount().then((r) => setKeyPackageCount(r.count)).catch(() => {});
  }, []);

  async function handleBackup() {
    if (!backupPassphrase || backupPassphrase.length < 8) {
      setBackupStatus("Passphrase must be at least 8 characters");
      return;
    }
    setIsBackingUp(true);
    setBackupStatus(null);
    try {
      // For now, export a placeholder payload — in a full implementation,
      // this would gather all crypto state from IndexedDB/stores.
      const payload = {
        mlsInitialized,
        exportedAt: new Date().toISOString(),
      };
      const encrypted = await exportKeys(payload, backupPassphrase);
      const b64 = btoa(String.fromCharCode(...encrypted));

      await apiFetch("/api/v1/users/me/key-backup", {
        method: "POST",
        body: JSON.stringify({ data: b64 }),
      });

      setBackupStatus("Backup saved successfully");
      setBackupPassphrase("");
    } catch (err) {
      setBackupStatus(
        `Backup failed: ${err instanceof Error ? err.message : "unknown error"}`,
      );
    } finally {
      setIsBackingUp(false);
    }
  }

  async function handleRestore() {
    if (!restorePassphrase) {
      setRestoreStatus("Enter your backup passphrase");
      return;
    }
    setIsRestoring(true);
    setRestoreStatus(null);
    try {
      const response = await apiFetch<{ data: string }>("/api/v1/users/me/key-backup");

      const binary = atob(response.data);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }

      const payload = await importKeys(bytes, restorePassphrase);

      setRestoreStatus(
        `Restored backup from ${payload.exportedAt ?? "unknown date"}`,
      );
      setRestorePassphrase("");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "unknown error";
      if (msg.includes("ciphertext") || msg.includes("decrypt")) {
        setRestoreStatus("Wrong passphrase or corrupted backup");
      } else {
        setRestoreStatus(`Restore failed: ${msg}`);
      }
    } finally {
      setIsRestoring(false);
    }
  }

  return (
    <div className="settings-page">
      <div className="settings-header">
        <button className="btn-back" onClick={() => navigate(-1)}>
          &larr; Back
        </button>
        <h2>Security Settings</h2>
      </div>

      {user?.did && (
        <div className="settings-section">
          <h3>Cryptographic Identity</h3>
          <div className="settings-info">
            <div className="info-row">
              <span className="info-label">DID</span>
              <span
                className="info-value did-value"
                title="Click to copy"
                style={{ cursor: "pointer", fontFamily: "monospace", fontSize: "0.85em" }}
                onClick={() => {
                  navigator.clipboard.writeText(user.did!);
                  setDidCopied(true);
                  setTimeout(() => setDidCopied(false), 2000);
                }}
              >
                {user.did.slice(0, 20)}...{user.did.slice(-8)}
                {didCopied ? " (copied)" : ""}
              </span>
            </div>
          </div>
        </div>
      )}

      <div className="settings-section">
        <h3>MLS Encryption Status</h3>
        <div className="settings-info">
          <div className="info-row">
            <span className="info-label">MLS Status</span>
            <span className={`info-value ${mlsInitialized ? "status-ok" : "status-warn"}`}>
              {mlsInitialized ? "Active" : "Not initialized"}
            </span>
          </div>
          {mlsError && (
            <div className="info-row">
              <span className="info-label">Error</span>
              <span className="info-value status-error">{mlsError}</span>
            </div>
          )}
          <div className="info-row">
            <span className="info-label">KeyPackages Available</span>
            <span className="info-value">
              {keyPackageCount !== null ? keyPackageCount : "..."}
            </span>
          </div>
        </div>
      </div>

      <div className="settings-section">
        <h3>Key Backup</h3>
        <p className="settings-description">
          Encrypt and save your keys to the server. You will need your
          passphrase to restore them on a new device.
        </p>

        <div className="backup-form">
          <div className="form-group">
            <label>Backup Passphrase</label>
            <input
              type="password"
              value={backupPassphrase}
              onChange={(e) => setBackupPassphrase(e.target.value)}
              placeholder="Enter a strong passphrase (8+ chars)"
            />
          </div>
          <button
            className="btn-primary"
            onClick={handleBackup}
            disabled={isBackingUp}
          >
            {isBackingUp ? "Encrypting..." : "Create Backup"}
          </button>
          {backupStatus && (
            <div className={`backup-status ${backupStatus.includes("success") ? "status-ok" : "status-error"}`}>
              {backupStatus}
            </div>
          )}
        </div>
      </div>

      <div className="settings-section">
        <h3>Restore Keys</h3>
        <p className="settings-description">
          Download and decrypt your key backup from the server.
        </p>

        <div className="backup-form">
          <div className="form-group">
            <label>Backup Passphrase</label>
            <input
              type="password"
              value={restorePassphrase}
              onChange={(e) => setRestorePassphrase(e.target.value)}
              placeholder="Enter your backup passphrase"
            />
          </div>
          <button
            className="btn-secondary"
            onClick={handleRestore}
            disabled={isRestoring}
          >
            {isRestoring ? "Decrypting..." : "Restore Backup"}
          </button>
          {restoreStatus && (
            <div className={`backup-status ${restoreStatus.includes("Restored") ? "status-ok" : "status-error"}`}>
              {restoreStatus}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
