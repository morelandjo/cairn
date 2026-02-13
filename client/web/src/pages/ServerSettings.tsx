import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import * as modApi from "../api/moderation.ts";
import * as webhookApi from "../api/webhooks.ts";
import type { Webhook, BotAccount } from "../api/webhooks.ts";
import type { Ban, ModLogEntry, AutoModRule } from "../api/moderation.ts";

export default function ServerSettings() {
  const { serverId } = useParams<{ serverId: string }>();
  const navigate = useNavigate();
  const [tab, setTab] = useState<"mod" | "webhooks" | "bots" | "automod">("mod");

  if (!serverId) {
    return <div>No server selected</div>;
  }

  return (
    <div className="server-settings">
      <div className="settings-header">
        <h2>Server Settings</h2>
        <button onClick={() => navigate(-1)}>Back</button>
      </div>
      <div className="settings-tabs">
        <button className={tab === "mod" ? "active" : ""} onClick={() => setTab("mod")}>
          Moderation
        </button>
        <button className={tab === "webhooks" ? "active" : ""} onClick={() => setTab("webhooks")}>
          Webhooks
        </button>
        <button className={tab === "bots" ? "active" : ""} onClick={() => setTab("bots")}>
          Bots
        </button>
        <button className={tab === "automod" ? "active" : ""} onClick={() => setTab("automod")}>
          Auto-Mod
        </button>
      </div>
      <div className="settings-content">
        {tab === "mod" && <ModerationTab serverId={serverId} />}
        {tab === "webhooks" && <WebhooksTab serverId={serverId} />}
        {tab === "bots" && <BotsTab serverId={serverId} />}
        {tab === "automod" && <AutoModTab serverId={serverId} />}
      </div>
    </div>
  );
}

function ModerationTab({ serverId }: { serverId: string }) {
  const [bans, setBans] = useState<Ban[]>([]);
  const [modLog, setModLog] = useState<ModLogEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      modApi.listBans(serverId),
      modApi.getModerationLog(serverId),
    ])
      .then(([bansData, logData]) => {
        setBans(bansData.bans);
        setModLog(logData.entries);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [serverId]);

  async function handleUnban(userId: string) {
    try {
      await modApi.unbanUser(serverId, userId);
      setBans((prev) => prev.filter((b) => b.user_id !== userId));
    } catch (err) {
      console.error("Failed to unban:", err);
    }
  }

  if (loading) return <div className="loading">Loading...</div>;

  return (
    <div>
      <h3>Banned Users</h3>
      {bans.length === 0 ? (
        <p>No banned users</p>
      ) : (
        <ul className="ban-list">
          {bans.map((ban) => (
            <li key={ban.id}>
              <span>User: {ban.user_id}</span>
              {ban.reason && <span> - {ban.reason}</span>}
              <button onClick={() => handleUnban(ban.user_id)}>Unban</button>
            </li>
          ))}
        </ul>
      )}

      <h3>Moderation Log</h3>
      {modLog.length === 0 ? (
        <p>No log entries</p>
      ) : (
        <ul className="mod-log-list">
          {modLog.map((entry) => (
            <li key={entry.id}>
              <span className="mod-action">{entry.action}</span>
              <span> by {entry.moderator_id}</span>
              <span> on {entry.target_user_id}</span>
              <span className="mod-time">
                {new Date(entry.inserted_at).toLocaleString()}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function WebhooksTab({ serverId }: { serverId: string }) {
  const [webhooks, setWebhooks] = useState<Webhook[]>([]);
  const [name, setName] = useState("");
  const [channelId, setChannelId] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    webhookApi
      .listWebhooks(serverId)
      .then((data) => setWebhooks(data.webhooks))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [serverId]);

  async function handleCreate() {
    if (!name.trim() || !channelId.trim()) return;
    try {
      const data = await webhookApi.createWebhook(serverId, {
        name: name.trim(),
        channel_id: channelId.trim(),
      });
      setWebhooks((prev) => [...prev, data.webhook]);
      setName("");
      setChannelId("");
    } catch (err) {
      console.error("Failed to create webhook:", err);
    }
  }

  async function handleDelete(webhookId: string) {
    try {
      await webhookApi.deleteWebhook(serverId, webhookId);
      setWebhooks((prev) => prev.filter((w) => w.id !== webhookId));
    } catch (err) {
      console.error("Failed to delete webhook:", err);
    }
  }

  if (loading) return <div className="loading">Loading...</div>;

  return (
    <div>
      <h3>Webhooks</h3>
      <div className="create-form">
        <input
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Webhook name"
        />
        <input
          type="text"
          value={channelId}
          onChange={(e) => setChannelId(e.target.value)}
          placeholder="Channel ID"
        />
        <button onClick={handleCreate}>Create</button>
      </div>
      {webhooks.length === 0 ? (
        <p>No webhooks</p>
      ) : (
        <ul className="webhook-list">
          {webhooks.map((w) => (
            <li key={w.id}>
              <span>{w.name}</span>
              <button onClick={() => handleDelete(w.id)}>Delete</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function BotsTab({ serverId }: { serverId: string }) {
  const [bots, setBots] = useState<BotAccount[]>([]);
  const [loading, setLoading] = useState(true);
  const [newBotToken, setNewBotToken] = useState<string | null>(null);

  useEffect(() => {
    webhookApi
      .listBots(serverId)
      .then((data) => setBots(data.bots))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [serverId]);

  async function handleCreate() {
    try {
      const data = await webhookApi.createBot(serverId);
      setBots((prev) => [...prev, data.bot]);
      setNewBotToken(data.bot.token || null);
    } catch (err) {
      console.error("Failed to create bot:", err);
    }
  }

  async function handleDelete(botId: string) {
    try {
      await webhookApi.deleteBot(serverId, botId);
      setBots((prev) => prev.filter((b) => b.id !== botId));
    } catch (err) {
      console.error("Failed to delete bot:", err);
    }
  }

  if (loading) return <div className="loading">Loading...</div>;

  return (
    <div>
      <h3>Bot Accounts</h3>
      <button onClick={handleCreate}>Create Bot</button>
      {newBotToken && (
        <div className="new-bot-token">
          <strong>New bot token (save this, it won't be shown again):</strong>
          <code>{newBotToken}</code>
          <button onClick={() => setNewBotToken(null)}>Dismiss</button>
        </div>
      )}
      {bots.length === 0 ? (
        <p>No bots</p>
      ) : (
        <ul className="bot-list">
          {bots.map((bot) => (
            <li key={bot.id}>
              <span>{bot.username}</span>
              <button onClick={() => handleDelete(bot.id)}>Delete</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function AutoModTab({ serverId }: { serverId: string }) {
  const [rules, setRules] = useState<AutoModRule[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    modApi
      .listAutoModRules(serverId)
      .then((data) => setRules(data.rules))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [serverId]);

  async function handleToggle(rule: AutoModRule) {
    try {
      const data = await modApi.updateAutoModRule(serverId, rule.id, {
        enabled: !rule.enabled,
      });
      setRules((prev) =>
        prev.map((r) => (r.id === rule.id ? data.rule : r)),
      );
    } catch (err) {
      console.error("Failed to update rule:", err);
    }
  }

  async function handleDelete(ruleId: string) {
    try {
      await modApi.deleteAutoModRule(serverId, ruleId);
      setRules((prev) => prev.filter((r) => r.id !== ruleId));
    } catch (err) {
      console.error("Failed to delete rule:", err);
    }
  }

  if (loading) return <div className="loading">Loading...</div>;

  return (
    <div>
      <h3>Auto-Moderation Rules</h3>
      {rules.length === 0 ? (
        <p>No auto-mod rules configured</p>
      ) : (
        <ul className="automod-list">
          {rules.map((rule) => (
            <li key={rule.id}>
              <span className="rule-type">{rule.rule_type}</span>
              <span className={`rule-status ${rule.enabled ? "enabled" : "disabled"}`}>
                {rule.enabled ? "Enabled" : "Disabled"}
              </span>
              <button onClick={() => handleToggle(rule)}>
                {rule.enabled ? "Disable" : "Enable"}
              </button>
              <button onClick={() => handleDelete(rule.id)}>Delete</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
