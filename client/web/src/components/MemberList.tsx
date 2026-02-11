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
  } | null>(null);

  const online = members.filter((m) => onlineUsers.has(m.id));
  const offline = members.filter((m) => !onlineUsers.has(m.id));

  function renderMember(m: (typeof members)[0]) {
    const isFederated = "home_instance" in m && !!(m as Record<string, unknown>).home_instance;
    const homeInstance = isFederated ? (m as Record<string, unknown>).home_instance as string : null;
    const memberDid = (m as Record<string, unknown>).did as string | undefined;

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
        {isFederated && homeInstance && memberDid && (
          <button
            className="btn-dm-federated"
            title="Send DM request"
            onClick={() =>
              setDmTarget({
                did: memberDid,
                instance: homeInstance,
                name: m.display_name || m.username,
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
          onClose={() => setDmTarget(null)}
        />
      )}
    </>
  );
}
