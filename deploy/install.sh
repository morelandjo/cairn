#!/usr/bin/env bash
set -euo pipefail

# Cairn Install Script
# Usage: curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | bash
# Or: ./install.sh [--config /path/to/config.yml] [--env /path/to/.env] [--json]
#
# This script provisions a bare Linux server and deploys Cairn end-to-end:
#   1. Installs Docker + Compose (if missing)
#   2. Creates a dedicated cairn system user
#   3. Configures firewall (UFW) and fail2ban
#   4. Sets up swap (for small VPS / Raspberry Pi)
#   5. Walks through interactive configuration
#   6. Deploys all services via Docker Compose
#   7. Runs database migrations and verifies health
#   8. Sets up reverse proxy with TLS (Caddy or nginx)

CAIRN_VERSION="0.1.4"
DEPLOY_DIR="/opt/cairn"
COMPOSE_URL="https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/docker-compose.prod.yml"
ENV_TEMPLATE_URL="https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/.env.example"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

JSON_MODE=false
CONFIG_FILE=""
ENV_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --env) ENV_FILE="$2"; shift 2 ;;
    --json) JSON_MODE=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log() {
  if [ "$JSON_MODE" = true ]; then
    echo "{\"level\":\"info\",\"message\":\"$1\"}"
  else
    echo -e "${GREEN}[*]${NC} $1"
  fi
}

warn() {
  if [ "$JSON_MODE" = true ]; then
    echo "{\"level\":\"warn\",\"message\":\"$1\"}"
  else
    echo -e "${YELLOW}[!]${NC} $1"
  fi
}

error() {
  if [ "$JSON_MODE" = true ]; then
    echo "{\"level\":\"error\",\"message\":\"$1\"}" >&2
  else
    echo -e "${RED}[ERROR]${NC} $1" >&2
  fi
}

prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="$3"
  if [ -n "$default" ]; then
    read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text} [${default}]: ")" value < /dev/tty
    eval "$var_name=\"${value:-$default}\""
  else
    read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text}: ")" value < /dev/tty
    eval "$var_name=\"$value\""
  fi
}

generate_secret() {
  openssl rand -hex 32
}

# ── System Provisioning ──

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use sudo)."
    exit 1
  fi
}

detect_distro() {
  if [[ ! -f /etc/os-release ]]; then
    error "Unsupported OS. Cairn requires Linux (Debian, Ubuntu, or Fedora)."
    exit 1
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  DISTRO_ID="${ID}"
  DISTRO_LIKE="${ID_LIKE:-}"
  DISTRO_CODENAME="${VERSION_CODENAME:-}"

  case "$DISTRO_ID" in
    debian|ubuntu) PKG_MANAGER="apt" ;;
    fedora)        PKG_MANAGER="dnf" ;;
    *)
      # Check ID_LIKE for derivatives (e.g. Linux Mint, Pop!_OS)
      if [[ "$DISTRO_LIKE" == *"debian"* ]] || [[ "$DISTRO_LIKE" == *"ubuntu"* ]]; then
        PKG_MANAGER="apt"
      elif [[ "$DISTRO_LIKE" == *"fedora"* ]]; then
        PKG_MANAGER="dnf"
      else
        error "Unsupported distro: $DISTRO_ID. Supported: Debian, Ubuntu, Fedora (and derivatives)."
        exit 1
      fi
      ;;
  esac
}

install_base_packages() {
  log "Installing base packages..."
  if [ "$PKG_MANAGER" = "apt" ]; then
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates gnupg lsb-release openssl >/dev/null
  else
    dnf install -y -q curl ca-certificates gnupg openssl >/dev/null
  fi
}

install_docker() {
  if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    log "Docker already installed ($(docker --version | grep -oP '\d+\.\d+\.\d+'))"
    return
  fi

  log "Installing Docker..."
  if [ "$PKG_MANAGER" = "apt" ]; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${DISTRO_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
  else
    dnf install -y -q dnf-plugins-core >/dev/null
    dnf config-manager --add-repo "https://download.docker.com/linux/fedora/docker-ce.repo"
    dnf install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
  fi

  systemctl enable --now docker
  log "Docker installed ($(docker --version | grep -oP '\d+\.\d+\.\d+'))"
}

create_user() {
  if id cairn &>/dev/null; then
    log "System user 'cairn' already exists"
    # Ensure they're in the docker group
    usermod -aG docker cairn 2>/dev/null || true
    return
  fi

  log "Creating system user 'cairn'..."
  useradd --system --create-home --shell /bin/bash --groups docker cairn
}

setup_firewall() {
  if ! command -v ufw &>/dev/null; then
    log "Installing UFW firewall..."
    if [ "$PKG_MANAGER" = "apt" ]; then
      apt-get install -y -qq ufw >/dev/null
    else
      dnf install -y -q ufw >/dev/null
    fi
  fi

  # Don't reconfigure if already active
  if ufw status | grep -q "Status: active"; then
    log "UFW firewall already active"
    return
  fi

  log "Configuring firewall..."
  ufw --force reset >/dev/null 2>&1
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow 22/tcp >/dev/null       # SSH
  ufw allow 80/tcp >/dev/null       # HTTP
  ufw allow 443/tcp >/dev/null      # HTTPS
  ufw allow 3478/tcp >/dev/null     # TURN TCP
  ufw allow 3478/udp >/dev/null     # TURN UDP
  ufw allow 49152:49200/udp >/dev/null  # TURN relay
  ufw --force enable >/dev/null
  log "Firewall configured (SSH, HTTP, HTTPS, TURN)"
}

setup_fail2ban() {
  if ! command -v fail2ban-client &>/dev/null; then
    log "Installing fail2ban..."
    if [ "$PKG_MANAGER" = "apt" ]; then
      apt-get install -y -qq fail2ban >/dev/null
    else
      dnf install -y -q fail2ban >/dev/null
    fi
  fi

  if [ ! -f /etc/fail2ban/jail.local ]; then
    log "Configuring fail2ban..."
    cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
JAIL
    systemctl enable --now fail2ban
    systemctl restart fail2ban
  else
    log "fail2ban already configured"
  fi
}

setup_swap() {
  if [ -f /swapfile ] || swapon --show | grep -q .; then
    log "Swap already configured"
    return
  fi

  total_mb=$(free -m | awk '/^Mem:/{print $2}')
  if [ "$total_mb" -lt 2048 ]; then
    log "Setting up 2GB swap (recommended for small servers)..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap enabled (2GB)"
  fi
}

# ── Prerequisites Check ──

check_prerequisites() {
  log "Checking system resources..."

  # Disk space (minimum 2GB)
  available_gb=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
  if [ "$available_gb" -lt 2 ]; then
    error "Insufficient disk space. At least 2GB required, ${available_gb}GB available."
    exit 1
  fi

  # RAM (minimum 512MB)
  total_mb=$(free -m | awk '/^Mem:/{print $2}')
  if [ "$total_mb" -lt 512 ]; then
    warn "Low memory: ${total_mb}MB. Recommended: 1GB+."
  fi

  # Port conflicts
  for port in 4000 5432 6379 7700 3478; do
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      warn "Port ${port} is already in use. This may cause conflicts."
    fi
  done

  log "System OK (${available_gb}GB disk, ${total_mb}MB RAM)"
}

# ── Interactive Wizard ──

run_wizard() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║     Cairn Installation Wizard    ║${NC}"
  echo -e "${GREEN}║          v${CAIRN_VERSION}                      ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
  echo ""

  prompt CAIRN_DOMAIN "Domain name or IP address for this instance" ""

  if [[ "$CAIRN_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ""
    warn "Using an IP address disables automatic HTTPS."
    warn "Without HTTPS, passwords and messages are sent in plain text over the network."
    warn "This is only safe on trusted private networks (LAN, VPN, Tailscale)."
    warn "To enable HTTPS, point a domain at this server and re-run the installer."
    echo ""
  fi

  prompt SERVER_PORT "HTTP port" "4000"

  # Secrets
  echo ""
  read -rp "$(echo -e "${BLUE}?${NC} Auto-generate cryptographic secrets? (Y/n): ")" secrets_choice < /dev/tty
  if [[ "$secrets_choice" =~ ^[Nn] ]]; then
    log "Enter your own secrets. Values must be non-empty."
    prompt SECRET_KEY_BASE "SECRET_KEY_BASE (base64, 48+ bytes recommended)" ""
    prompt JWT_SECRET "JWT_SECRET (base64, 48+ bytes recommended)" ""
    prompt POSTGRES_PASSWORD "POSTGRES_PASSWORD" ""
    prompt MEILI_MASTER_KEY "MEILI_MASTER_KEY" ""
    prompt SFU_AUTH_SECRET "SFU_AUTH_SECRET" ""
    prompt TURN_SECRET "TURN_SECRET" ""

    # Validate none are empty
    for var in SECRET_KEY_BASE JWT_SECRET POSTGRES_PASSWORD MEILI_MASTER_KEY SFU_AUTH_SECRET TURN_SECRET; do
      if [ -z "${!var}" ]; then
        error "$var cannot be empty."
        exit 1
      fi
    done
  else
    log "Generating secrets..."
    SECRET_KEY_BASE=$(generate_secret)
    JWT_SECRET=$(generate_secret)
    POSTGRES_PASSWORD=$(generate_secret | head -c 32)
    MEILI_MASTER_KEY=$(generate_secret | head -c 32)
    SFU_AUTH_SECRET=$(generate_secret | head -c 32)
    TURN_SECRET=$(generate_secret | head -c 32)
  fi

  # Federation
  echo ""
  read -rp "$(echo -e "${BLUE}?${NC} Enable federation? (y/N): ")" fed_choice < /dev/tty
  FEDERATION_ENABLED="false"
  if [[ "$fed_choice" =~ ^[Yy] ]]; then
    FEDERATION_ENABLED="true"
  fi

  # SSL enforcement
  FORCE_SSL="true"
  if [[ "$FEDERATION_ENABLED" == "true" ]]; then
    log "SSL enforcement: enabled (required for federation)"
  else
    echo ""
    read -rp "$(echo -e "${BLUE}?${NC} Enable SSL enforcement? Recommended unless using a VPN/tunnel (Y/n): ")" ssl_choice < /dev/tty
    if [[ "$ssl_choice" =~ ^[Nn] ]]; then
      FORCE_SSL="false"
      warn "SSL disabled. Only use this on trusted private networks."
    fi
  fi

  # Reverse proxy
  REVERSE_PROXY="none"
  # Only offer proxy setup if domain is not an IP address
  if [[ "$CAIRN_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    warn "Domain is an IP address — skipping reverse proxy (Let's Encrypt requires a domain)."
  else
    echo ""
    echo -e "${BLUE}?${NC} Set up a reverse proxy with automatic HTTPS?"
    echo "  1) Caddy (recommended — automatic TLS, zero config)"
    echo "  2) Nginx + Let's Encrypt"
    echo "  3) None (I'll configure my own)"
    read -rp "  Choice [1]: " proxy_choice < /dev/tty
    case "${proxy_choice:-1}" in
      1) REVERSE_PROXY="caddy" ;;
      2) REVERSE_PROXY="nginx" ;;
      3) REVERSE_PROXY="none" ;;
      *) REVERSE_PROXY="caddy" ;;
    esac
  fi

  # Storage
  echo ""
  read -rp "$(echo -e "${BLUE}?${NC} Use S3 for file storage? (y/N): ")" s3_choice < /dev/tty
  STORAGE_BACKEND="local"
  S3_BUCKET=""
  S3_ENDPOINT=""
  if [[ "$s3_choice" =~ ^[Yy] ]]; then
    STORAGE_BACKEND="s3"
    prompt S3_BUCKET "S3 bucket name" "cairn-uploads"
    prompt S3_ENDPOINT "S3 endpoint URL" "https://s3.amazonaws.com"
  fi

  echo ""
  log "Configuration complete."
}

# ── Write Config ──

write_env() {
  local env_path="$1"
  cat > "$env_path" <<EOF
# Cairn Configuration — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
CAIRN_DOMAIN=${CAIRN_DOMAIN}
SERVER_PORT=${SERVER_PORT}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
JWT_SECRET=${JWT_SECRET}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MEILI_MASTER_KEY=${MEILI_MASTER_KEY}
SFU_AUTH_SECRET=${SFU_AUTH_SECRET}
TURN_SECRET=${TURN_SECRET}
TURN_URLS=turn:${CAIRN_DOMAIN}:3478
FEDERATION_ENABLED=${FEDERATION_ENABLED}
FORCE_SSL=${FORCE_SSL}
STORAGE_BACKEND=${STORAGE_BACKEND}
S3_BUCKET=${S3_BUCKET}
S3_ENDPOINT=${S3_ENDPOINT}
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
EOF
  chmod 600 "$env_path"
}

install_cairn_ctl() {
  if [ -f /usr/local/bin/cairn-ctl ]; then
    return
  fi
  local ctl_url="https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/cairn-ctl"
  log "Installing cairn-ctl..."
  curl -sSL "$ctl_url" -o /usr/local/bin/cairn-ctl
  chmod +x /usr/local/bin/cairn-ctl
}

# ── Reverse Proxy ──

setup_caddy() {
  local domain="$1"
  local port="$2"

  log "Installing Caddy..."
  if [ "$PKG_MANAGER" = "apt" ]; then
    apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https >/dev/null 2>&1 || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y -qq caddy >/dev/null
  else
    dnf install -y -q 'dnf-command(copr)' >/dev/null 2>&1 || true
    dnf copr enable -y @caddy/caddy >/dev/null 2>&1
    dnf install -y -q caddy >/dev/null
  fi

  log "Writing Caddyfile..."
  cat > /etc/caddy/Caddyfile <<EOF
${domain} {
    reverse_proxy localhost:${port}
}
EOF

  systemctl enable --now caddy
  systemctl reload caddy 2>/dev/null || true
  log "Caddy configured — TLS certificates will be obtained automatically"
}

setup_nginx() {
  local domain="$1"
  local port="$2"

  log "Installing nginx and Certbot..."
  if [ "$PKG_MANAGER" = "apt" ]; then
    apt-get install -y -qq nginx certbot python3-certbot-nginx >/dev/null
  else
    dnf install -y -q nginx certbot python3-certbot-nginx >/dev/null
  fi

  log "Writing nginx config..."
  local config_path
  if [ "$PKG_MANAGER" = "apt" ]; then
    config_path="/etc/nginx/sites-available/cairn"
  else
    config_path="/etc/nginx/conf.d/cairn.conf"
  fi

  cat > "$config_path" <<'NGINX'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    location / {
        proxy_pass http://127.0.0.1:PORT_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Long-lived WebSocket connections
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
NGINX

  # Replace placeholders (avoids issues with nginx $ variables in heredoc)
  sed -i "s/DOMAIN_PLACEHOLDER/${domain}/g" "$config_path"
  sed -i "s/PORT_PLACEHOLDER/${port}/g" "$config_path"

  # Debian/Ubuntu: symlink to sites-enabled, remove default
  if [ "$PKG_MANAGER" = "apt" ]; then
    ln -sf /etc/nginx/sites-available/cairn /etc/nginx/sites-enabled/cairn
    rm -f /etc/nginx/sites-enabled/default
  fi

  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx

  log "Obtaining TLS certificate..."
  certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email

  log "nginx configured with TLS — certificate will auto-renew"
}

# ── Main ──

main() {
  check_root
  detect_distro

  echo ""
  echo -e "${GREEN}Cairn Installer v${CAIRN_VERSION}${NC}"
  echo ""

  # Phase 1: System provisioning
  log "Preparing system..."
  install_base_packages
  check_prerequisites
  install_docker
  create_user
  setup_swap
  setup_firewall
  setup_fail2ban

  echo ""
  log "System provisioning complete."

  # Phase 2: Create deploy directory
  mkdir -p "$DEPLOY_DIR"/{backups,keys}
  chown -R cairn:cairn "$DEPLOY_DIR"
  chmod 750 "$DEPLOY_DIR"

  # Phase 3: Configuration
  if [ -n "$ENV_FILE" ]; then
    log "Using provided .env file: $ENV_FILE"
    cp "$ENV_FILE" "$DEPLOY_DIR/.env"
    chmod 600 "$DEPLOY_DIR/.env"
    chown cairn:cairn "$DEPLOY_DIR/.env"
  elif [ -f "$DEPLOY_DIR/.env" ]; then
    warn "Existing .env found at $DEPLOY_DIR/.env — keeping it."
  else
    run_wizard
    write_env "$DEPLOY_DIR/.env"
    chown cairn:cairn "$DEPLOY_DIR/.env"
    log "Configuration written to $DEPLOY_DIR/.env"
  fi

  # Phase 4: Download compose file
  log "Downloading docker-compose.yml..."
  if [ -n "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$DEPLOY_DIR/docker-compose.yml"
  else
    curl -sSL "$COMPOSE_URL" -o "$DEPLOY_DIR/docker-compose.yml"
  fi
  chown cairn:cairn "$DEPLOY_DIR/docker-compose.yml"

  # Phase 5: Install cairn-ctl
  install_cairn_ctl

  # Phase 6: Pull images and start services (as cairn user)
  log "Pulling Docker images (this may take a few minutes)..."
  cd "$DEPLOY_DIR"
  sudo -u cairn docker compose pull

  # Phase 7: Start database services and run migrations BEFORE the server
  log "Starting database services..."
  sudo -u cairn docker compose up -d postgres redis meilisearch

  log "Waiting for database to be ready..."
  for _ in $(seq 1 30); do
    if sudo -u cairn docker compose exec -T postgres pg_isready -U cairn &>/dev/null; then
      break
    fi
    sleep 2
  done

  # Verify postgres password matches (catches stale volumes from failed installs)
  local pg_password
  pg_password=$(grep -oP 'POSTGRES_PASSWORD=\K.*' "$DEPLOY_DIR/.env" 2>/dev/null || true)
  if [ -n "$pg_password" ]; then
    if ! sudo -u cairn docker compose exec -T -e PGPASSWORD="$pg_password" postgres \
        psql -U cairn -d cairn -c "SELECT 1" &>/dev/null; then
      warn "Postgres password mismatch — resetting database volume..."
      sudo -u cairn docker compose down -v postgres
      sudo -u cairn docker compose up -d postgres
      for _ in $(seq 1 15); do
        if sudo -u cairn docker compose exec -T postgres pg_isready -U cairn &>/dev/null; then
          break
        fi
        sleep 2
      done
    fi
  fi

  log "Running database migrations..."
  sudo -u cairn docker compose run --rm -T server bin/cairn eval "Cairn.Release.migrate()"

  # Phase 8: Start all services
  log "Starting all services..."
  sudo -u cairn docker compose up -d

  log "Waiting for server to be healthy..."
  local port
  port=$(grep -oP 'SERVER_PORT=\K\d+' "$DEPLOY_DIR/.env" 2>/dev/null || echo "4000")
  for _ in $(seq 1 30); do
    if curl -sf "http://localhost:${port}/health" &>/dev/null; then
      break
    fi
    sleep 2
  done

  # Final health check
  if curl -sf "http://localhost:${port}/health" &>/dev/null; then
    local domain
    domain=$(grep -oP 'CAIRN_DOMAIN=\K.*' "$DEPLOY_DIR/.env" 2>/dev/null || echo "localhost")
    local reverse_proxy
    reverse_proxy="${REVERSE_PROXY:-none}"

    # Set up reverse proxy (if selected during wizard)
    if [ "$reverse_proxy" = "caddy" ]; then
      setup_caddy "$domain" "$port"
    elif [ "$reverse_proxy" = "nginx" ]; then
      setup_nginx "$domain" "$port"
    fi

    echo ""
    log "Cairn is running!"

    # Create admin account
    echo ""
    echo -e "${BLUE}?${NC} Create an admin account"
    prompt ADMIN_USERNAME "  Admin username" ""
    while true; do
      read -srp "$(echo -e "${BLUE}?${NC}   Admin password: ")" ADMIN_PASSWORD < /dev/tty
      echo ""
      read -srp "$(echo -e "${BLUE}?${NC}   Confirm password: ")" ADMIN_PASSWORD_CONFIRM < /dev/tty
      echo ""
      if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
        break
      fi
      warn "Passwords do not match. Try again."
    done

    if [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ]; then
      sudo -u cairn docker compose exec -T server bin/cairn eval \
        "Cairn.Release.create_admin(\"$ADMIN_USERNAME\", \"$ADMIN_PASSWORD\")" \
        &>/dev/null && log "Admin account '${ADMIN_USERNAME}' created." \
        || warn "Failed to create admin account. Create one manually: cairn-ctl admin create <username> <password>"
    fi

    echo ""
    if [ "$reverse_proxy" = "caddy" ] || [ "$reverse_proxy" = "nginx" ]; then
      echo -e "  ${GREEN}URL:${NC}     https://${domain}"
    else
      echo -e "  ${GREEN}URL:${NC}     http://${domain}:${port}"
    fi
    echo -e "  ${GREEN}Config:${NC}  $DEPLOY_DIR/.env"
    echo -e "  ${GREEN}Logs:${NC}    cd $DEPLOY_DIR && docker compose logs -f"
    echo -e "  ${GREEN}Manage:${NC}  cairn-ctl status"

    if [ "$reverse_proxy" = "none" ]; then
      echo ""
      echo -e "  ${YELLOW}Note:${NC} No reverse proxy was configured. Traffic is unencrypted (HTTP)."
      echo "  To add HTTPS later, see: https://cairn.dev/self-hosting/reverse-proxy.html"
    fi
    echo ""
  else
    error "Health check failed. Check logs: cd $DEPLOY_DIR && docker compose logs"
    exit 1
  fi
}

main "$@"
