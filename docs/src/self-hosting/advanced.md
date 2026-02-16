# Manual Installation

These guides cover manual configuration, custom proxy setups, and federation. If you used the [install script](quickstart.md), most of this was handled automatically.

You can skip the wizard by providing a pre-filled `.env` file:

```sh
curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | sudo bash -s -- --env /path/to/.env
```

Or supply a custom Docker Compose file:

```sh
curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | sudo bash -s -- --config /path/to/docker-compose.yml
```

See [Configuration](configuration.md) for all available `.env` variables.

## Recommended additions

The install wizard sets up these components automatically. If you're installing manually, set them up yourself:

| Component | Required? | Purpose |
|-----------|-----------|---------|
| Docker + Docker Compose | **Yes** | Runs all Cairn services as containers |
| UFW (firewall) | Recommended | Restricts inbound traffic to required ports only |
| fail2ban | Recommended | Blocks IPs after repeated failed SSH login attempts |
| Swap (2 GB) | Recommended (<2 GB RAM) | Prevents out-of-memory kills on small VPS / Raspberry Pi |
| Reverse proxy (Caddy/nginx) | Recommended | TLS termination and HTTPS. See [Reverse Proxy](reverse-proxy.md) |

### Docker + Docker Compose

Cairn requires Docker Engine with the Compose plugin (v2). The standalone `docker-compose` binary is not supported.

**Debian / Ubuntu:**

```sh
# Add Docker's official GPG key and repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
```

**Fedora:**

```sh
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
```

### UFW firewall

```sh
apt-get install -y ufw   # or: dnf install -y ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp          # SSH
ufw allow 80/tcp          # HTTP
ufw allow 443/tcp         # HTTPS
ufw allow 3478/tcp        # TURN TCP
ufw allow 3478/udp        # TURN UDP
ufw allow 49152:49200/udp # TURN relay range
ufw --force enable
```

### fail2ban

```sh
apt-get install -y fail2ban   # or: dnf install -y fail2ban

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF

systemctl enable --now fail2ban
systemctl restart fail2ban
```

### Swap

Only needed on servers with less than 2 GB of RAM:

```sh
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

## Guides

- [Configuration](configuration.md) — environment variables, storage backends, SSL
- [Reverse Proxy](reverse-proxy.md) — Caddy and nginx configs with TLS (for manual setup)
- [Federation](federation.md) — connect your instance to others
