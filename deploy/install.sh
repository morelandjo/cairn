#!/usr/bin/env bash
set -euo pipefail

# Murmuring Install Script
# Usage: curl -sSL https://get.murmuring.dev/install | bash
# Or: ./install.sh [--config /path/to/config.yml] [--env /path/to/.env] [--json]

VERSION="0.1.0"
DEPLOY_DIR="/opt/murmuring"
COMPOSE_URL="https://raw.githubusercontent.com/murmuring/murmuring/main/deploy/docker-compose.prod.yml"
ENV_TEMPLATE_URL="https://raw.githubusercontent.com/murmuring/murmuring/main/deploy/.env.example"

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
    read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text} [${default}]: ")" value
    eval "$var_name=\"${value:-$default}\""
  else
    read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text}: ")" value
    eval "$var_name=\"$value\""
  fi
}

generate_secret() {
  openssl rand -base64 48 | tr -d '\n'
}

# ── Prerequisites Check ──

check_prerequisites() {
  log "Checking prerequisites..."

  # OS
  if [[ ! -f /etc/os-release ]]; then
    error "Unsupported OS. Murmuring requires Linux (Debian, Ubuntu, or Fedora)."
    exit 1
  fi

  # Docker
  if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Install it first: https://docs.docker.com/engine/install/"
    exit 1
  fi

  # Docker Compose (v2 plugin)
  if ! docker compose version &>/dev/null; then
    error "Docker Compose v2 is not installed. Install docker-compose-plugin."
    exit 1
  fi

  # Ports
  for port in 4000 5432 6379 7700 3478; do
    if ss -tlnp | grep -q ":${port} "; then
      warn "Port ${port} is already in use. This may cause conflicts."
    fi
  done

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

  log "Prerequisites OK (Docker $(docker --version | grep -oP '\d+\.\d+\.\d+'), ${available_gb}GB disk, ${total_mb}MB RAM)"
}

# ── Interactive Wizard ──

run_wizard() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║     Murmuring Installation Wizard    ║${NC}"
  echo -e "${GREEN}║          v${VERSION}                      ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
  echo ""

  prompt MURMURING_DOMAIN "Domain name or IP address for this instance" ""
  prompt SERVER_PORT "HTTP port" "4000"

  # Secrets
  echo ""
  read -rp "$(echo -e "${BLUE}?${NC} Auto-generate cryptographic secrets? (Y/n): ")" secrets_choice
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
  read -rp "$(echo -e "${BLUE}?${NC} Enable federation? (y/N): ")" fed_choice
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
    read -rp "$(echo -e "${BLUE}?${NC} Enable SSL enforcement? Recommended unless using a VPN/tunnel (Y/n): ")" ssl_choice
    if [[ "$ssl_choice" =~ ^[Nn] ]]; then
      FORCE_SSL="false"
      warn "SSL disabled. Only use this on trusted private networks."
    fi
  fi

  # Storage
  echo ""
  read -rp "$(echo -e "${BLUE}?${NC} Use S3 for file storage? (y/N): ")" s3_choice
  STORAGE_BACKEND="local"
  S3_BUCKET=""
  S3_ENDPOINT=""
  if [[ "$s3_choice" =~ ^[Yy] ]]; then
    STORAGE_BACKEND="s3"
    prompt S3_BUCKET "S3 bucket name" "murmuring-uploads"
    prompt S3_ENDPOINT "S3 endpoint URL" "https://s3.amazonaws.com"
  fi

  echo ""
  log "Configuration complete."
}

# ── Write Config ──

write_env() {
  local env_path="$1"
  cat > "$env_path" <<EOF
# Murmuring Configuration — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
MURMURING_DOMAIN=${MURMURING_DOMAIN}
SERVER_PORT=${SERVER_PORT}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
JWT_SECRET=${JWT_SECRET}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MEILI_MASTER_KEY=${MEILI_MASTER_KEY}
SFU_AUTH_SECRET=${SFU_AUTH_SECRET}
TURN_SECRET=${TURN_SECRET}
TURN_URLS=turn:${MURMURING_DOMAIN}:3478
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

# ── Main ──

main() {
  check_prerequisites

  # Create deploy directory
  mkdir -p "$DEPLOY_DIR"

  if [ -n "$ENV_FILE" ]; then
    log "Using provided .env file: $ENV_FILE"
    cp "$ENV_FILE" "$DEPLOY_DIR/.env"
    chmod 600 "$DEPLOY_DIR/.env"
  elif [ -f "$DEPLOY_DIR/.env" ]; then
    warn "Existing .env found at $DEPLOY_DIR/.env — keeping it."
  else
    run_wizard
    write_env "$DEPLOY_DIR/.env"
    log "Configuration written to $DEPLOY_DIR/.env"
  fi

  # Download docker-compose
  log "Downloading docker-compose.yml..."
  if [ -n "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$DEPLOY_DIR/docker-compose.yml"
  else
    curl -sSL "$COMPOSE_URL" -o "$DEPLOY_DIR/docker-compose.yml"
  fi

  # Pull images
  log "Pulling Docker images (this may take a few minutes)..."
  cd "$DEPLOY_DIR"
  docker compose pull

  # Start services
  log "Starting services..."
  docker compose up -d

  # Wait for health
  log "Waiting for services to be healthy..."
  for i in $(seq 1 30); do
    if curl -sf http://localhost:${SERVER_PORT:-4000}/health &>/dev/null; then
      break
    fi
    sleep 2
  done

  # Run migrations
  log "Running database migrations..."
  docker compose exec -T server bin/murmuring eval "Murmuring.Release.migrate()" 2>/dev/null || true

  # Final check
  if curl -sf http://localhost:${SERVER_PORT:-4000}/health &>/dev/null; then
    echo ""
    log "Murmuring is running!"
    echo ""
    echo -e "  ${GREEN}URL:${NC}     http://${MURMURING_DOMAIN:-localhost}:${SERVER_PORT:-4000}"
    echo -e "  ${GREEN}Config:${NC}  $DEPLOY_DIR/.env"
    echo -e "  ${GREEN}Logs:${NC}    cd $DEPLOY_DIR && docker compose logs -f"
    echo -e "  ${GREEN}Manage:${NC}  murmuring-ctl status"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    if [[ "${FORCE_SSL:-true}" == "true" ]]; then
      echo "  1. Set up a reverse proxy (nginx/Caddy) with TLS for $MURMURING_DOMAIN"
    else
      echo -e "  1. ${YELLOW}Warning: SSL is disabled. Only use this on trusted networks.${NC}"
    fi
    echo "  2. Create an admin account"
    echo "  3. Configure federation (if enabled)"
    echo ""
  else
    error "Health check failed. Check logs: cd $DEPLOY_DIR && docker compose logs"
    exit 1
  fi
}

main "$@"
