import { useState } from "react";
import { useChannelStore } from "../stores/channelStore.ts";
import { usePresenceStore } from "../stores/presenceStore.ts";
import FederatedDmDialog from "./FederatedDmDialog.tsx";

export default function MemberList() {
  const members = useChannelStore((s) => s.members);
  const onlineUsers = usePresenceStore((s) => s.onlineUsers);
  const [dmTarget, setDmTarget] = useState<{
    did: string;
    instance: string;
    name: string;
    insecure?: boolean;
  } | null>(null);

  const online = members.filter((m) => onlineUsers.has(m.id));
  const offline = members.filter((m) => !onlineUsers.has(m.id));

  function renderMember(m: (typeof members)[0]) {
    const extra = m as unknown as Record<string, unknown>;
    const isFederated = "home_instance" in m && !!extra.home_instance;
    const homeInstance = isFederated ? extra.home_instance as string : null;
    const memberDid = extra.did as string | undefined;
    const isInsecure = isFederated && extra.secure === false;

    return (
      <div key={m.id} className={`member-item ${onlineUsers.has(m.id) ? "online" : "offline"}`}>
        <span className="member-status-dot" />
        <span className="member-name">
          {m.display_name || m.username}
          {isFederated && homeInstance && (
            <span className="member-instance" title={`Home instance: ${homeInstance}`}>
              @{homeInstance}
            </span>
          )}
        </span>
        {isFederated && (
          <span className="member-federated-badge" title="Federated user">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" style={{ opacity: 0.5 }}>
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
            </svg>
          </span>
        )}
        {isInsecure && (
          <span className="member-insecure-badge" title="Insecure instance (no HTTPS)">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 17c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm6-9h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6h1.9c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm0 12H6V10h12v10z" />
            </svg>
          </span>
        )}
        {isFederated && homeInstance && memberDid && (
          <button
            className="btn-dm-federated"
            title="Send DM request"
            onClick={() =>
              setDmTarget({
                did: memberDid,
                instance: homeInstance,
                name: m.display_name || m.username,
                insecure: isInsecure,
              })
            }
          >
            DM
          </button>
        )}
      </div>
    );
  }

  return (
    <>
      <div className="member-list">
        <div className="member-section">
          <h4>Online — {online.length}</h4>
          {online.map(renderMember)}
        </div>
        <div className="member-section">
          <h4>Offline — {offline.length}</h4>
          {offline.map(renderMember)}
        </div>
      </div>
      {dmTarget && (
        <FederatedDmDialog
          recipientDid={dmTarget.did}
          recipientInstance={dmTarget.instance}
          recipientName={dmTarget.name}
          recipientInsecure={dmTarget.insecure}
          onClose={() => setDmTarget(null)}
        />
      )}
    </>
  );
}
