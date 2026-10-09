#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# V2RayTun Panel — Setup Manager (interactive)
#
# Sourced by /usr/local/bin/v2raytunsetup and by the bootstrap install.sh.
# Pulls images from the public Docker registry — no auth or source clone needed.
# ═════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(dirname "$SCRIPT_DIR")"

. "$SCRIPT_DIR/common.sh"

[ -f "$SETUP_DIR/.config" ] && . "$SETUP_DIR/.config"

REGISTRY="${V2RAYTUN_REGISTRY:-docker-registry.v2raytun.com}"
VERSION="${V2RAYTUN_VERSION:-1.0.57}"
INSTALLER_VERSION="${INSTALLER_VERSION:-1.0.57}"

PANEL_DIR="/opt/v2raytunpanel"
PANEL_DOCKER_DIR="$PANEL_DIR/docker"
CADDY_DIR="$PANEL_DIR/caddy"
NODE_DIR="/opt/v2raytunpanel-node"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/v2raytunpanel}"
TMUX_SESSION="v2raytunpanel-setup"

PANEL_IMAGE="${REGISTRY}/v2raytunpanel-panel:${VERSION}"
FRONTEND_IMAGE="${REGISTRY}/v2raytunpanel-frontend:${VERSION}"
NODE_IMAGE="${REGISTRY}/v2raytunpanel-node:${VERSION}"

# ──────────────────────────────────────────────────────────────────────────────
# Banner
# ──────────────────────────────────────────────────────────────────────────────
print_banner() {
  clear 2>/dev/null || true
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "  ${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "  ${CYAN}║  ${YELLOW}██╗   ██╗██████╗ ██████╗  █████╗ ██╗   ██╗████████╗██╗   ██╗███╗   ██╗ ${CYAN}║${RESET}"
  echo -e "  ${CYAN}║  ${YELLOW}╚██╗ ██╔╝╚════██╗██╔══██╗██╔══██╗╚██╗ ██╔╝╚══██╔══╝██║   ██║████╗  ██║ ${CYAN}║${RESET}"
  echo -e "  ${CYAN}║  ${YELLOW} ╚████╔╝  █████╔╝██████╔╝███████║ ╚████╔╝    ██║   ██║   ██║██╔██╗ ██║ ${CYAN}║${RESET}"
  echo -e "  ${CYAN}║  ${YELLOW}  ╚██╔╝  ██╔═══╝ ██╔══██╗██╔══██║  ╚██╔╝     ██║   ██║   ██║██║╚██╗██║ ${CYAN}║${RESET}"
  echo -e "  ${CYAN}║  ${YELLOW}   ██║   ███████╗██║  ██║██║  ██║   ██║      ██║   ╚██████╔╝██║ ╚████║ ${CYAN}║${RESET}"
  echo -e "  ${CYAN}║  ${YELLOW}   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝      ╚═╝    ╚═════╝ ╚═╝  ╚═══╝ ${CYAN}║${RESET}"
  echo -e "  ${CYAN}║                          ${GREEN}P A N E L${CYAN}                                       ║${RESET}"
  echo -e "  ${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════════════${RESET}"
  echo -e "  ${BOLD_GREEN}V2RayTun Panel${RESET}  ${DIM}—${RESET}  Setup Manager  ${CYAN}v${INSTALLER_VERSION}${RESET}"
  echo -e "  Registry:  ${YELLOW}${REGISTRY}${RESET}"
  echo -e "  Version:   ${YELLOW}${VERSION}${RESET}"
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
}

press_any_key() {
  echo ""
  read -n 1 -s -r -p "Press any key to continue..."
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Registry: public, no authentication required
# ──────────────────────────────────────────────────────────────────────────────
verify_registry_access() {
  info "Verifying registry access..."
  if docker pull "$PANEL_IMAGE" >/dev/null 2>&1; then
    success "Registry accessible (${REGISTRY})"
    return 0
  else
    error "Cannot pull from ${REGISTRY}. Check your network connectivity."
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Panel: install
# ──────────────────────────────────────────────────────────────────────────────
panel_install() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Install Panel${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  check_docker

  if [ -f "$PANEL_DOCKER_DIR/docker-compose.yml" ] && [ -f "$PANEL_DOCKER_DIR/.env" ]; then
    warn "Existing installation detected at ${PANEL_DOCKER_DIR}"
    if ! confirm "Reinstall? This will WIPE all data." "n"; then
      info "Cancelled"
      return 0
    fi
    info "Stopping and removing existing installation..."
    (cd "$PANEL_DOCKER_DIR" && docker compose down -v --remove-orphans 2>/dev/null) || true
    [ -f "$CADDY_DIR/docker-compose.yml" ] && (cd "$CADDY_DIR" && docker compose down 2>/dev/null) || true
    rm -rf "$PANEL_DOCKER_DIR" "$CADDY_DIR"
  fi

  local panel_domain="${V2RAYTUN_PANEL_DOMAIN:-}"
  local sub_domain="${V2RAYTUN_SUB_DOMAIN:-}"

  if [ -z "$panel_domain" ]; then
    if [ ! -t 0 ]; then
      error "V2RAYTUN_PANEL_DOMAIN is required in non-interactive mode"
      return 1
    fi
    while true; do
      read -rp "Panel domain (e.g. panel.example.com): " panel_domain
      if [ -z "$panel_domain" ]; then
        warn "Domain is required"
      elif is_valid_domain "$panel_domain"; then
        break
      else
        warn "Invalid domain format"
      fi
    done
  fi
  if [ -z "$sub_domain" ]; then
    if [ -t 0 ]; then
      read -rp "Subscription page domain (Enter = same as panel): " sub_domain
    fi
    sub_domain="${sub_domain:-$panel_domain}"
  fi

  if ! verify_registry_access; then
    error "Cannot continue without registry access"
    return 1
  fi

  info "Generating configuration..."
  mkdir -p "$PANEL_DOCKER_DIR"

  local pg_pass rq_pass jwt_auth jwt_api
  pg_pass=$(generate_password)
  rq_pass=$(generate_password)
  jwt_auth=$(generate_secret)
  jwt_api=$(generate_secret)

  cat > "$PANEL_DOCKER_DIR/.env" << EOF
POSTGRES_USER=v2raytunpanel
POSTGRES_PASSWORD=${pg_pass}
POSTGRES_DB=v2raytunpanel
RABBITMQ_USER=v2raytunpanel
RABBITMQ_PASSWORD=${rq_pass}
RABBITMQ_VHOST=v2raytunpanel
JWT_AUTH_SECRET=${jwt_auth}
JWT_API_TOKENS_SECRET=${jwt_api}
SUB_PUBLIC_DOMAIN=${sub_domain}/api/sub
SUBSCRIPTION_PAGE_URL=https://${sub_domain}/sub
LOG_LEVEL=info
BACKEND_PORT=3000
FRONTEND_PORT=8080
REGISTRY=${REGISTRY}
VERSION=${VERSION}
NODE_IMAGE_SOURCE=registry
NODE_DOCKER_IMAGE=${REGISTRY}/v2raytunpanel-node:${VERSION}
EOF
  chmod 600 "$PANEL_DOCKER_DIR/.env"

  cp "$SETUP_DIR/compose/docker-compose.panel.yml" "$PANEL_DOCKER_DIR/docker-compose.yml"
  success "Configuration saved at ${PANEL_DOCKER_DIR}"

  info "Pulling images (this may take a few minutes)..."
  (cd "$PANEL_DOCKER_DIR" && docker compose pull) || {
    error "docker compose pull failed"
    return 1
  }

  info "Starting database first..."
  cd "$PANEL_DOCKER_DIR"
  docker compose up -d postgres redis rabbitmq || {
    error "Failed to start infrastructure containers"
    echo "Check logs: cd $PANEL_DOCKER_DIR && docker compose logs"
    return 1
  }

  # Postgres reports healthy via pg_isready before its init has finished applying
  # the password, which makes the backend's first migration fail with P1000.
  # Wait until an authenticated query actually succeeds before starting the app.
  info "Waiting for database to accept connections..."
  local pg_ok=0 j
  for j in $(seq 1 45); do
    if docker compose exec -T -e PGPASSWORD="$pg_pass" postgres \
        psql -U v2raytunpanel -d v2raytunpanel -c 'select 1' >/dev/null 2>&1; then
      pg_ok=1
      break
    fi
    sleep 2
  done
  if [ "$pg_ok" != "1" ]; then
    error "Database did not become ready in time"
    echo "Check logs: cd $PANEL_DOCKER_DIR && docker compose logs postgres"
    return 1
  fi

  info "Starting services..."
  docker compose up -d || {
    error "docker compose up failed"
    echo "Check logs: cd $PANEL_DOCKER_DIR && docker compose logs"
    return 1
  }

  info "Waiting for backend to become healthy..."
  local i
  for i in $(seq 1 90); do
    if curl -sf "http://localhost:3000/api/health/ready" >/dev/null 2>&1; then
      success "Backend is healthy"
      break
    fi
    if [ $((i % 15)) -eq 0 ]; then
      local status
      status=$(docker inspect -f '{{.State.Status}}' v2raytunpanel-backend 2>/dev/null || echo "unknown")
      if [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
        error "Backend container crashed. Last logs:"
        (cd "$PANEL_DOCKER_DIR" && docker compose logs --tail=40 backend)
        return 1
      fi
      info "Still waiting... ($i/90s, container status: $status)"
    fi
    sleep 1
  done

  caddy_setup "$panel_domain" "$sub_domain"

  print_banner
  echo -e "${BOLD_GREEN}  Installation complete${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "  ${BOLD_WHITE}Panel URL:${RESET}      https://${panel_domain}"
  echo -e "  ${BOLD_WHITE}Subscription:${RESET}   https://${sub_domain}/api/sub/{shortUuid}"
  echo -e "  ${BOLD_WHITE}Files:${RESET}          ${PANEL_DOCKER_DIR}"
  echo ""
  echo -e "${MAGENTA}────────────────────────────────────────────────────────────────────${RESET}"
  echo -e "  ${BOLD_CYAN}Next steps:${RESET}"
  echo -e "  1. Wait ~60 seconds for Caddy to obtain an SSL certificate"
  echo -e "  2. Open ${GREEN}https://${panel_domain}/auth/login${RESET}"
  echo -e "  3. Create the first admin account"
  echo ""
  echo -e "  ${BOLD_CYAN}Useful commands:${RESET}"
  echo -e "  ${YELLOW}v2raytunsetup status${RESET}   — show running containers"
  echo -e "  ${YELLOW}v2raytunsetup logs${RESET}     — tail backend logs"
  echo -e "  ${YELLOW}v2raytunsetup update${RESET}   — pull new images and restart"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Panel: update
# ──────────────────────────────────────────────────────────────────────────────
panel_update() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Update Panel${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""

  if [ ! -f "$PANEL_DOCKER_DIR/docker-compose.yml" ]; then
    error "Panel not installed at ${PANEL_DOCKER_DIR}"
    return 1
  fi
  check_docker

  cd "$PANEL_DOCKER_DIR"

  # Bring the pinned versions in .env up to this installer's target. Without this
  # the panel image tag (VERSION) and the baked node image (NODE_DOCKER_IMAGE)
  # stay at whatever was written at install time, so "Update Panel" would just
  # re-pull the same old version and freshly-created nodes would keep pinning an
  # outdated node image.
  if [ -f "$PANEL_DOCKER_DIR/.env" ]; then
    info "Setting version to ${VERSION}..."
    sed -i "s|^VERSION=.*|VERSION=${VERSION}|" "$PANEL_DOCKER_DIR/.env"
    sed -i "s|^NODE_DOCKER_IMAGE=.*|NODE_DOCKER_IMAGE=${REGISTRY}/v2raytunpanel-node:${VERSION}|" "$PANEL_DOCKER_DIR/.env"
  fi

  # An install keeps the compose file of the installer that set it up. Bring it to this
  # installer's template (the old one stays next to it): the backups volume, log rotation and
  # healthchecks reach existing panels only this way.
  local ts saved_backups=""
  ts=$(date +%Y%m%d-%H%M%S)
  if ! cmp -s "$SETUP_DIR/compose/docker-compose.panel.yml" docker-compose.yml; then
    if ! grep -q "/app/backups" docker-compose.yml && docker ps -a --format '{{.Names}}' | grep -qx v2raytunpanel-backend; then
      # Panel backups lived in the container's own layer: copy them out before it is recreated.
      saved_backups="$PANEL_DIR/backups-before-$ts"
      if docker cp v2raytunpanel-backend:/app/backups/. "$saved_backups" 2>/dev/null && [ -n "$(ls -A "$saved_backups" 2>/dev/null)" ]; then
        info "Panel backups copied out of the old container to $saved_backups"
      else
        rm -rf "$saved_backups"
        saved_backups=""
      fi
    fi
    cp docker-compose.yml "docker-compose.yml.bak-$ts"
    cp "$SETUP_DIR/compose/docker-compose.panel.yml" docker-compose.yml
    info "docker-compose.yml brought to the current template (the previous one: docker-compose.yml.bak-$ts)"
  fi

  info "Pulling images (${VERSION})..."
  docker compose pull || {
    error "docker compose pull failed"
    return 1
  }

  info "Restarting services with the new images..."
  docker compose up -d || {
    error "docker compose up failed"
    echo "Check logs: cd $PANEL_DOCKER_DIR && docker compose logs"
    return 1
  }

  # The backend refuses to start on a database schema it could not update, so a panel that
  # never gets ready is a failed update, not a slow one.
  info "Waiting for the backend to become ready..."
  if ! wait_backend_ready 180; then
    error "The backend did not become ready. See: cd $PANEL_DOCKER_DIR && docker compose logs backend"
    [ -n "$saved_backups" ] && warn "The old panel backups are kept in $saved_backups"
    return 1
  fi

  if [ -n "$saved_backups" ]; then
    if docker cp "$saved_backups/." v2raytunpanel-backend:/app/backups/ && docker exec -u 0 v2raytunpanel-backend chown -R node:node /app/backups; then
      success "Panel backups moved to the persistent volume"
    else
      warn "Could not move the old panel backups into the volume; they stay in $saved_backups"
    fi
  fi

  caddy_enable_log_rotation "$ts"

  success "Panel updated to ${VERSION}"
  echo ""
  docker compose ps
}

# Caddy installed by older installers logs without rotation and its log grows forever. Insert the
# same limits as the panel services (a targeted edit keeps any local changes to the file) and
# recreate the container; certificates live in the caddy_data volume and survive it.
caddy_enable_log_rotation() {
  local ts="$1" file="$CADDY_DIR/docker-compose.yml"
  [ -f "$file" ] || return 0
  grep -q 'max-size' "$file" && return 0
  if ! grep -q '^    container_name: v2raytunpanel-caddy$' "$file"; then
    warn "Caddy compose file has an unexpected layout; add log rotation to $file by hand"
    return 0
  fi
  cp "$file" "$file.bak-$ts"
  awk '{ print } /^    container_name: v2raytunpanel-caddy$/ {
    print "    logging:"
    print "      driver: json-file"
    print "      options:"
    print "        max-size: \"10m\""
    print "        max-file: \"3\""
  }' "$file.bak-$ts" > "$file"
  if (cd "$CADDY_DIR" && docker compose up -d >/dev/null 2>&1); then
    success "Caddy logs now rotate (10 MB x 3)"
  else
    cp "$file.bak-$ts" "$file"
    (cd "$CADDY_DIR" && docker compose up -d >/dev/null 2>&1)
    warn "Could not recreate Caddy with log rotation; the previous compose file was restored"
  fi
}

# Polls the backend's readiness endpoint every 2 s, up to the given number of tries.
wait_backend_ready() {
  local tries="${1:-90}" i
  for i in $(seq 1 "$tries"); do
    curl -sf "http://localhost:3000/api/health/ready" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# The agent port only has to answer the panel: to anyone else it gives the node away.
restrict_agent_port() {
  local port panel_ip="${V2RAYTUN_PANEL_IP:-}"
  port=$(sed -n 's/.*NODE_PORT=\([0-9][0-9]*\).*/\1/p' docker-compose.yml 2>/dev/null | head -1)
  [ -n "$port" ] || return 0
  if ! command -v ufw >/dev/null 2>&1 || ! ufw status 2>/dev/null | grep -q "Status: active"; then
    warn "Allow the agent port ${port}/tcp to the panel's IP only (firewall on this server or at the provider)."
    return 0
  fi
  if [ -z "$panel_ip" ] && [ -t 0 ]; then
    read -rp "Panel server IP (the agent port ${port} will answer only it; Enter = skip): " panel_ip
  fi
  if [ -z "$panel_ip" ]; then
    warn "ufw is active: allow the agent port to the panel only: ufw allow from <panel IP> to any port ${port} proto tcp && ufw deny ${port}/tcp"
    return 0
  fi
  if ufw allow from "$panel_ip" to any port "$port" proto tcp >/dev/null && ufw deny "$port"/tcp >/dev/null; then
    success "Agent port ${port}/tcp answers ${panel_ip} only"
  else
    warn "Could not add the ufw rules for the agent port ${port}/tcp"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Panel: status / logs / remove
# ──────────────────────────────────────────────────────────────────────────────
panel_status() {
  if [ ! -f "$PANEL_DOCKER_DIR/docker-compose.yml" ]; then
    warn "Panel not installed"
    return 0
  fi
  echo ""
  echo -e "${BOLD_CYAN}Panel containers:${RESET}"
  (cd "$PANEL_DOCKER_DIR" && docker compose ps)
  echo ""
  if [ -f "$NODE_DIR/docker-compose.yml" ]; then
    echo -e "${BOLD_CYAN}Node container:${RESET}"
    (cd "$NODE_DIR" && docker compose ps)
    echo ""
  fi
}

panel_logs() {
  local service="${1:-backend}"
  if [ ! -f "$PANEL_DOCKER_DIR/docker-compose.yml" ]; then
    error "Panel not installed"
    return 1
  fi
  cd "$PANEL_DOCKER_DIR"
  docker compose logs -f --tail=200 "$service"
}

panel_remove() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Remove Panel${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  if [ ! -f "$PANEL_DOCKER_DIR/docker-compose.yml" ]; then
    warn "Panel not installed"
    return 0
  fi
  warn "This will REMOVE the panel and ALL its data (database, redis, backups)."
  if ! confirm "Continue?" "n"; then
    info "Cancelled"
    return 0
  fi
  (cd "$PANEL_DOCKER_DIR" && docker compose down -v --remove-orphans) || true
  [ -f "$CADDY_DIR/docker-compose.yml" ] && (cd "$CADDY_DIR" && docker compose down -v) || true
  rm -rf "$PANEL_DIR"
  success "Panel removed"
}

# ──────────────────────────────────────────────────────────────────────────────
# Caddy reverse proxy + auto SSL
# ──────────────────────────────────────────────────────────────────────────────
caddy_setup() {
  local panel_domain="$1"
  local sub_domain="$2"

  info "Setting up Caddy reverse proxy with automatic SSL..."
  mkdir -p "$CADDY_DIR"
  cd "$CADDY_DIR"

  # Subscription-link User-Agent router (shared by both layouts):
  #   /sub/{id} in a browser    → web page (frontend :8080)
  #   /sub/{id} in a VPN client → raw subscription config (backend), by
  #     rewriting /sub/... to /api/sub/... so the client gets configs, not HTML.
  # Every real browser sends a "Mozilla/..." User-Agent while subscription
  # clients (v2RayTun, Happ, Streisand, Shadowrocket, ...) do not, so a single
  # Mozilla check cleanly separates the two. Client requests are the fallthrough.
  local sub_browser_matcher='    @subBrowser {
        path /sub /sub/*
        header User-Agent *Mozilla*
    }
    handle @subBrowser {
        reverse_proxy localhost:8080
    }
    @subClient path /sub /sub/*
    handle @subClient {
        rewrite * /api{uri}
        reverse_proxy localhost:3000
    }'

  if [ "$panel_domain" = "$sub_domain" ]; then
    cat > Caddyfile << EOF
${panel_domain} {
${sub_browser_matcher}
    handle /api/* {
        reverse_proxy localhost:3000
    }
    handle /ws {
        reverse_proxy localhost:3000
    }
    handle {
        reverse_proxy localhost:8080
    }
}
EOF
  else
    cat > Caddyfile << EOF
${panel_domain} {
    handle /api/* {
        reverse_proxy localhost:3000
    }
    handle /ws {
        reverse_proxy localhost:3000
    }
    handle {
        reverse_proxy localhost:8080
    }
}

${sub_domain} {
${sub_browser_matcher}
    handle {
        reverse_proxy localhost:3000
    }
}
EOF
  fi

  cat > docker-compose.yml << 'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: v2raytunpanel-caddy
    restart: unless-stopped
    network_mode: host
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config

volumes:
  caddy_data:
  caddy_config:
EOF

  if docker compose up -d; then
    success "Caddy is running — HTTPS will be issued automatically by Let's Encrypt"
  else
    warn "Caddy failed to start. Check: cd $CADDY_DIR && docker compose logs"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Node: install (interactive + paste-from-panel)
# ──────────────────────────────────────────────────────────────────────────────
ensure_awg_kernel_module() {
  if lsmod 2>/dev/null | grep -q amneziawg; then
    success "AmneziaWG kernel module already loaded"
    return 0
  fi

  if modprobe amneziawg 2>/dev/null; then
    success "AmneziaWG kernel module loaded"
    return 0
  fi

  info "Installing AmneziaWG kernel module (amneziawg-dkms)..."

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq linux-headers-"$(uname -r)" dkms 2>/dev/null || true

    # Preferred: the official AmneziaWG PPA (Ubuntu). The old single-URL GitHub
    # release deb is unreliable (asset names/versions drift and 404), so the PPA
    # is the primary path and the direct deb below is only a fallback.
    if ! dpkg -l amneziawg-dkms 2>/dev/null | grep -q '^ii' && grep -qi ubuntu /etc/os-release 2>/dev/null; then
      info "Installing AmneziaWG from the official PPA..."
      apt-get install -y -qq software-properties-common 2>/dev/null || true
      add-apt-repository -y ppa:amnezia/ppa >/dev/null 2>&1 && apt-get update -qq
      apt-get install -y amneziawg-dkms 2>&1 | tail -3 || true
    fi

    if ! dpkg -l amneziawg-dkms 2>/dev/null | grep -q '^ii'; then
      # Fallback: direct release deb (best-effort, may not exist for all arches).
      local awg_deb="/tmp/amneziawg-dkms.deb"
      local arch
      arch="$(dpkg --print-architecture)"
      if curl -fsSL -o "$awg_deb" \
        "https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/releases/latest/download/amneziawg-dkms_1.0.0_${arch}.deb" 2>/dev/null; then
        dpkg -i "$awg_deb" || apt-get install -f -y -qq
        rm -f "$awg_deb"
      fi
    fi

    if modprobe amneziawg 2>/dev/null; then
      success "AmneziaWG kernel module installed and loaded"
      return 0
    fi

    dkms autoinstall 2>/dev/null || true
    modprobe amneziawg 2>/dev/null && {
      success "AmneziaWG kernel module installed and loaded"
      return 0
    }
  fi

  warn "Could not load amneziawg kernel module"
  warn "AWG nodes will not work without it. Please install manually."
  warn "See: https://github.com/amnezia-vpn/amneziawg-linux-kernel-module"
  return 1
}

node_install() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Install Node / Установка ноды${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  check_docker
  node_install_from_panel
}

node_install_from_panel() {
  echo ""
  echo -e "${CYAN}1.${RESET} Open Panel → Nodes → Create Node"
  echo -e "${CYAN}2.${RESET} Fill in Name, Address (this server's IP), Port"
  echo -e "${CYAN}3.${RESET} Click Create, then Copy the docker-compose snippet"
  echo ""

  mkdir -p "$NODE_DIR"
  cd "$NODE_DIR"

  if [ -n "${V2RAYTUN_DOCKER_COMPOSE:-}" ]; then
    echo "$V2RAYTUN_DOCKER_COMPOSE" > docker-compose.yml
    info "Using docker-compose from V2RAYTUN_DOCKER_COMPOSE env"
  elif [ -f /tmp/v2raytun-compose.yml ]; then
    cp /tmp/v2raytun-compose.yml docker-compose.yml
    rm -f /tmp/v2raytun-compose.yml
    info "Using docker-compose from /tmp/v2raytun-compose.yml"
  else
    echo -e "${CYAN}1.${RESET} Откройте панель → Ноды → Создать ноду"
    echo -e "    Open Panel → Nodes → Create Node"
    echo -e "${CYAN}2.${RESET} Укажите имя, IP этого сервера и порт"
    echo -e "    Fill in Name, Address (this server IP), Port"
    echo -e "${CYAN}3.${RESET} Скопируйте docker-compose из панели"
    echo -e "    Copy the docker-compose from the panel"
    echo -e "${CYAN}4.${RESET} Вставьте ниже, затем нажмите Ctrl+D"
    echo -e "    Paste below, then press Ctrl+D when done"
    echo ""
    echo -e "${YELLOW}Docker-compose (Ctrl+D):${RESET}"
    cat > docker-compose.yml
  fi

  if [ ! -s docker-compose.yml ]; then
    error "Empty input / Пустой ввод"
    rm -f docker-compose.yml
    return 1
  fi

  # Validate SECRET_KEY is not truncated (no python3 dependency)
  local sk
  sk=$(sed -n 's/.*SECRET_KEY=\([^ ]*\).*/\1/p' docker-compose.yml 2>/dev/null | head -1)
  if [ -n "$sk" ]; then
    local decoded
    decoded=$(echo "$sk" | base64 -d 2>/dev/null) || decoded=""
    if [ -z "$decoded" ] || ! echo "$decoded" | grep -q '"version"'; then
      # Try gzip decode
      decoded=$(echo "$sk" | base64 -d 2>/dev/null | gzip -d 2>/dev/null) || decoded=""
      if [ -z "$decoded" ] || ! echo "$decoded" | grep -q '"version"'; then
        warn ""
        warn "SECRET_KEY обрезан или повреждён! / SECRET_KEY truncated or corrupted!"
        warn "Это случается при вставке длинного текста в терминал."
        warn ""
        warn "Альтернативные способы / Alternative methods:"
        warn "  Сохраните файл перед запуском скрипта / Save file before running:"
        warn "  scp compose.yml root@this-server:/tmp/v2raytun-compose.yml"
        warn ""
        error "SECRET_KEY невалиден. Исправьте docker-compose.yml и запустите снова."
        return 1
      fi
    fi
    success "SECRET_KEY OK"
  fi

  if grep -qi 'awg\|amneziawg\|wireguard' docker-compose.yml 2>/dev/null; then
    info "AWG node detected — checking kernel module..."
    ensure_awg_kernel_module || warn "Continuing without AWG kernel module..."
  fi

  # Enable IP forwarding on host (required for VPN, cannot use sysctls with host network mode)
  if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]; then
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    grep -q 'net.ipv4.ip_forward' /etc/sysctl.conf 2>/dev/null || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    info "Enabled net.ipv4.ip_forward"
  fi

  info "Pulling node image..."
  docker compose pull

  info "Starting node..."
  docker compose up -d

  if [ $? -eq 0 ]; then
    success "Node started. It should appear as Connected in the panel within ~60 seconds."
    restrict_agent_port
    echo ""
    echo -e "  Logs: ${YELLOW}cd $NODE_DIR && docker compose logs -f${RESET}"
  else
    error "Failed to start node"
    return 1
  fi
}

node_install_interactive() {
  echo ""
  warn "For full mTLS setup use option 1 (paste docker-compose from panel)."
  echo ""
  read -rp "Panel URL (e.g. https://panel.example.com): " PANEL_ADDRESS
  read -rp "Node UUID (from panel: Nodes → Create Node): " NODE_UUID
  read -rp "Connection port (default 62050): " CONN_PORT
  CONN_PORT="${CONN_PORT:-62050}"
  read -rp "Service port (default 62051): " SVC_PORT
  SVC_PORT="${SVC_PORT:-62051}"

  if [ -z "$PANEL_ADDRESS" ] || [ -z "$NODE_UUID" ]; then
    error "Panel URL and Node UUID are required"
    return 1
  fi

  mkdir -p "$NODE_DIR"
  cd "$NODE_DIR"

  cat > .env << EOF
PANEL_ADDRESS=${PANEL_ADDRESS}
NODE_UUID=${NODE_UUID}
CONNECTION_PORT=${CONN_PORT}
SERVICE_PORT=${SVC_PORT}
LOG_LEVEL=info
REGISTRY=${REGISTRY}
VERSION=${VERSION}
EOF
  chmod 600 .env

  cp "$SETUP_DIR/compose/docker-compose.node.yml" docker-compose.yml

  # Enable IP forwarding on host (required for VPN, cannot use sysctls with host network mode)
  if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]; then
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    grep -q 'net.ipv4.ip_forward' /etc/sysctl.conf 2>/dev/null || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    info "Enabled net.ipv4.ip_forward"
  fi

  info "Pulling node image..."
  docker compose pull

  info "Starting node..."
  if docker compose up -d; then
    success "Node started. Check the panel for Connected status."
    echo ""
    echo -e "  Make sure port ${GREEN}${CONN_PORT}${RESET} is open in your firewall."
    echo -e "  Logs: ${YELLOW}cd $NODE_DIR && docker compose logs -f${RESET}"
  else
    error "Failed to start node"
    return 1
  fi
}

node_update() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Update Node${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""

  if [ ! -f "$NODE_DIR/docker-compose.yml" ]; then
    error "Node not installed at ${NODE_DIR}"
    return 1
  fi
  check_docker

  cd "$NODE_DIR"

  # The compose comes from the panel with the node image pinned to the panel's version at that
  # time; without rewriting the tag, "Update Node" re-pulls the same old image.
  if grep -qE "v2raytunpanel-node:[^[:space:]\"']+" docker-compose.yml; then
    info "Setting node image to ${VERSION}..."
    sed -i -E "s#(v2raytunpanel-node:)[^[:space:]\"']+#\1${VERSION}#" docker-compose.yml
  fi

  info "Pulling image (${VERSION})..."
  docker compose pull

  info "Restarting node..."
  docker compose up -d

  success "Node updated"
  docker compose ps
}

node_remove() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Remove Node${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  if [ ! -f "$NODE_DIR/docker-compose.yml" ]; then
    warn "Node not installed"
    return 0
  fi
  if ! confirm "Remove node and its data?" "n"; then
    info "Cancelled"
    return 0
  fi
  (cd "$NODE_DIR" && docker compose down -v --remove-orphans) || true
  rm -rf "$NODE_DIR"
  success "Node removed"
}

# ──────────────────────────────────────────────────────────────────────────────
# Backup / restore
# ──────────────────────────────────────────────────────────────────────────────
backup_create() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Create Backup${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""

  if ! docker ps --format '{{.Names}}' | grep -q '^v2raytunpanel-postgres$'; then
    error "Panel postgres container is not running"
    return 1
  fi

  mkdir -p "$BACKUP_DIR"

  local avail_mb
  avail_mb=$(df -m "$BACKUP_DIR" | awk 'NR==2{print $4}')
  if [ "${avail_mb:-0}" -lt 200 ]; then
    error "Less than 200 MB free on backup disk — aborting"
    return 1
  fi

  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local db_file="$BACKUP_DIR/db-$ts.sql.gz"

  info "Dumping PostgreSQL..."
  set -o pipefail
  if docker exec v2raytunpanel-postgres pg_dump -U v2raytunpanel v2raytunpanel 2>/dev/null | gzip > "$db_file"; then
    success "Database saved to $db_file ($(du -sh "$db_file" | cut -f1))"
  else
    error "Database backup failed"
    rm -f "$db_file"
    set +o pipefail
    return 1
  fi
  set +o pipefail

  if docker ps --format '{{.Names}}' | grep -q '^v2raytunpanel-redis$'; then
    info "Saving Redis snapshot..."
    docker exec v2raytunpanel-redis redis-cli SAVE >/dev/null 2>&1 || true
    docker cp v2raytunpanel-redis:/data/dump.rdb "$BACKUP_DIR/redis-$ts.rdb" 2>/dev/null \
      && success "Redis snapshot saved" \
      || warn "Redis snapshot skipped"
  fi

  if [ -f "$PANEL_DOCKER_DIR/.env" ]; then
    cp "$PANEL_DOCKER_DIR/.env" "$BACKUP_DIR/env-$ts.bak"
    chmod 600 "$BACKUP_DIR/env-$ts.bak"
    success ".env saved to $BACKUP_DIR/env-$ts.bak"
  fi

  echo ""
  echo -e "  ${BOLD_WHITE}Backup location:${RESET} $BACKUP_DIR"
  echo -e "  ${BOLD_WHITE}Files:${RESET}"
  ls -lh "$BACKUP_DIR"/*-"$ts"* 2>/dev/null | awk '{print "    "$9, "("$5")"}'
}

backup_restore() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Restore from Backup${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""

  if [ ! -d "$BACKUP_DIR" ]; then
    error "Backup directory not found: $BACKUP_DIR"
    return 1
  fi

  echo -e "${CYAN}Available database backups:${RESET}"
  ls -lh "$BACKUP_DIR"/db-*.sql.gz 2>/dev/null | awk '{print "  "$9, "("$5", "$6, $7, $8")"}'
  echo ""
  read -rp "Filename or full path: " FILE
  [ -z "$FILE" ] && { warn "Cancelled"; return 0; }

  local path="$FILE"
  [ ! -f "$path" ] && path="$BACKUP_DIR/$FILE"
  [ ! -f "$path" ] && { error "File not found"; return 1; }

  warn "This will OVERWRITE the current database!"
  if ! confirm "Continue?" "n"; then
    info "Cancelled"
    return 0
  fi

  info "Restoring..."
  if gunzip -c "$path" | docker exec -i v2raytunpanel-postgres psql -U v2raytunpanel v2raytunpanel >/dev/null; then
    success "Database restored. Restarting backend..."
    (cd "$PANEL_DOCKER_DIR" && docker compose restart backend)
  else
    error "Restore failed"
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Migration from Remnawave
# ──────────────────────────────────────────────────────────────────────────────
PANEL_API="http://localhost:3000/api"

# Parse a JSON value out of stdin. Uses python3 (present on Debian/Ubuntu).
_json_get() {
  # $1 = dotted path, e.g. data.accessToken  (arrays as .0, .1)
  python3 - "$1" <<'PY' 2>/dev/null
import sys, json
path = sys.argv[1].split('.') if sys.argv[1] else []
try:
    cur = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in path:
    if isinstance(cur, list):
        try:
            cur = cur[int(p)]
        except Exception:
            sys.exit(0)
    elif isinstance(cur, dict) and p in cur:
        cur = cur[p]
    else:
        sys.exit(0)
if isinstance(cur, (dict, list)):
    print(json.dumps(cur))
elif isinstance(cur, bool):
    print('true' if cur else 'false')
elif cur is None:
    print('')
else:
    print(cur)
PY
}

_require_migration_prereqs() {
  if ! command -v python3 >/dev/null 2>&1; then
    error "python3 is required for migration (JSON handling). Install it: apt-get install -y python3"
    return 1
  fi
  if ! curl -sf "$PANEL_API/health/ready" >/dev/null 2>&1; then
    error "Local panel is not reachable at $PANEL_API. Install/start the panel first."
    return 1
  fi
  return 0
}

# Log into the local (target) panel, echo the JWT on success.
_panel_login() {
  local user="$1" pass="$2" resp token
  resp=$(curl -s -m 15 -X POST "$PANEL_API/auth/login" \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"username":sys.argv[1],"password":sys.argv[2]}))' "$user" "$pass")")
  token=$(printf '%s' "$resp" | _json_get data.accessToken)
  [ -z "$token" ] && token=$(printf '%s' "$resp" | _json_get accessToken)
  printf '%s' "$token"
}

migrate_from_remna() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Migration from Remnawave ${YELLOW}[BETA]${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "${YELLOW}This feature is in beta testing — take a backup before running it.${RESET}"
  echo -e "${DIM}Transfers users (with their keys/subscriptions), config profiles, hosts,"
  echo -e "squads, subscription templates and node metadata from a Remnawave panel"
  echo -e "into this panel.${RESET}"
  echo -e "${DIM}Verified for Remnawave 3.4.4 — other versions may need a tool update;"
  echo -e "field mismatches are reported at the preview step.${RESET}"
  echo ""

  _require_migration_prereqs || return 1

  # ── Target panel admin ──────────────────────────────────────────────────
  echo -e "${CYAN}Step 1/4 — Log in to THIS panel (target)${RESET}"
  read -rp "  Admin username: " TGT_USER
  read -rsp "  Admin password: " TGT_PASS; echo ""
  local jwt
  jwt=$(_panel_login "$TGT_USER" "$TGT_PASS")
  if [ -z "$jwt" ]; then
    error "Login to local panel failed. Check the admin username/password."
    return 1
  fi
  success "Authenticated with the local panel."

  # ── Source panel ────────────────────────────────────────────────────────
  echo ""
  echo -e "${CYAN}Step 2/4 — Source Remnawave panel${RESET}"
  read -rp "  Source panel URL (https://panel.example.com): " SRC_URL
  read -rsp "  Source token (admin or API token, read access): " SRC_TOKEN; echo ""
  local insecure="false"
  if confirm "  Allow self-signed TLS on the source?" "n"; then insecure="true"; fi

  local src_json
  src_json=$(python3 -c 'import json,sys; print(json.dumps({"kind":"remnawave-api","config":{"baseUrl":sys.argv[1],"token":sys.argv[2],"allowInsecureTls":sys.argv[3]=="true"}}))' "$SRC_URL" "$SRC_TOKEN" "$insecure")

  info "Testing connection to the source..."
  local test_resp test_panel
  test_resp=$(curl -s -m 30 -X POST "$PANEL_API/migration/test-connection" \
    -H "Authorization: Bearer $jwt" -H 'Content-Type: application/json' \
    -d "{\"source\":$src_json}")
  test_panel=$(printf '%s' "$test_resp" | _json_get data.sourcePanel)
  if [ -z "$test_panel" ]; then
    local emsg
    emsg=$(printf '%s' "$test_resp" | _json_get message)
    [ -z "$emsg" ] && emsg=$(printf '%s' "$test_resp" | _json_get error.message)
    error "Connection failed: ${emsg:-unknown error}"
    return 1
  fi
  success "Connected to source: $test_panel"

  # ── Options ─────────────────────────────────────────────────────────────
  echo ""
  echo -e "${CYAN}Step 3/4 — Options${RESET}"
  local preserve_short="true" conflict="skip" dry="false"
  confirm "  Preserve short UUID (keep existing subscription links)?" "y" || preserve_short="false"
  echo "  On username conflict: [1] skip (default)  [2] suffix  [3] overwrite"
  read -rp "  Choice [1]: " c
  case "$c" in 2) conflict="suffix";; 3) conflict="overwrite";; *) conflict="skip";; esac
  if confirm "  Dry run first (count only, write nothing)?" "y"; then dry="true"; fi

  local opts_json
  opts_json=$(python3 -c 'import json,sys
print(json.dumps({
  "scope":{"configProfiles":True,"hosts":True,"squads":True,"externalSquads":True,
           "subscriptionSettings":False,"subscriptionTemplates":True,
           "subscriptionPageConfigs":True,"configSnippets":True,
           "users":True,"hwidDevices":True,"nodes":True},
  "preserveShortUuid":sys.argv[1]=="true","preserveCreatedAt":True,
  "usernameConflict":sys.argv[2],"unsupportedStrategyFallback":"MONTH","dryRun":sys.argv[3]=="true"}))' \
    "$preserve_short" "$conflict" "$dry")

  info "Computing preview (nothing is changed)..."
  local prev
  prev=$(curl -s -m 120 -X POST "$PANEL_API/migration/preview" \
    -H "Authorization: Bearer $jwt" -H 'Content-Type: application/json' \
    -d "{\"source\":$src_json,\"options\":$opts_json}")
  echo ""
  echo -e "${BOLD_GREEN}  Preview:${RESET}"
  printf '%s' "$prev" | python3 - <<'PY' 2>/dev/null || { error "Preview failed (see panel logs)."; return 1; }
import sys, json
d = json.load(sys.stdin)
data = d.get('data', d)
c = data.get('counts', {})
skipped = data.get('skipped', {})
print(f"    {'':24} {'import':>7} {'skip':>7}")
for k in ['users','configProfiles','hosts','squads','externalSquads','hwidDevices','nodes',
          'subscriptionTemplates','subscriptionPageConfigs','configSnippets']:
    print(f"    {k:24} {c.get(k,0):>7} {skipped.get(k,0):>7}")
for label, key, sample in [('username conflicts', 'usernameConflictCount', 'usernameConflicts'),
                           ('short UUID conflicts', 'shortUuidConflictCount', 'shortUuidConflicts')]:
    n = data.get(key, len(data.get(sample) or []))
    if n:
        print(f"    {label}: {n}")
def names(items, field):
    shown = [str(i.get(field, '')) for i in items[:10]]
    more = len(items) - len(shown)
    return ', '.join(shown) + (f" (+{more})" if more > 0 else '')
for w in data.get('warnings', []):
    print(f"    [warn] {w.get('message','')}")
    if w.get('detail'):
        print(f"           {w['detail']}")
    if w.get('hostSettings'):
        print(f"           hosts: {names(w['hostSettings'], 'remark')}")
    if w.get('nodeLimits'):
        print(f"           nodes: {names(w['nodeLimits'], 'name')}")
for b in data.get('blockers', []):
    print(f"    [BLOCK] {b.get('message','')}")
sys.exit(2 if data.get('blockers') else 0)
PY
  local prev_rc=$?
  if [ "$prev_rc" = "2" ]; then
    error "Migration is blocked by the issues above. Resolve them and retry."
    return 1
  fi

  # ── Execute ─────────────────────────────────────────────────────────────
  echo ""
  echo -e "${CYAN}Step 4/4 — Run${RESET}"
  if [ "$dry" = "false" ]; then
    warn "This writes data into the current panel. A backup first is recommended (menu option 5)."
    confirm "  Proceed with the real migration?" "n" || { info "Cancelled."; return 0; }
  fi

  info "Running migration..."
  local res
  res=$(curl -s -m 600 -X POST "$PANEL_API/migration/execute" \
    -H "Authorization: Bearer $jwt" -H 'Content-Type: application/json' \
    -d "{\"source\":$src_json,\"options\":$opts_json}")
  echo ""
  echo -e "${BOLD_GREEN}  Report:${RESET}"
  printf '%s' "$res" | python3 - <<'PY' 2>/dev/null || { error "Migration failed (see panel logs)."; return 1; }
import sys, json
d = json.load(sys.stdin)
data = d.get('data', d)
if data.get('dryRun'):
    print("    (dry run — nothing was written)")
for k in ['users','configProfiles','hosts','squads','externalSquads','hwidDevices','nodes',
          'subscriptionTemplates','subscriptionPageConfigs','configSnippets']:
    s = data.get(k, {})
    if isinstance(s, dict):
        line = f"    {k:24} imported {s.get('imported',0)}, skipped {s.get('skipped',0)}"
        if s.get('failed'): line += f", failed {s.get('failed')}"
        print(line)
for w in data.get('warnings', []):
    print(f"    [note] {w.get('message','')}")
PY

  echo ""
  if [ "$dry" = "false" ]; then
    success "Migration finished."
    if confirm "  Re-provision migrated nodes now (SSH / manual)?" "n"; then
      migrate_reprovision_nodes "$jwt"
    fi
  else
    info "Dry run complete. Re-run without dry run to apply."
  fi
}

# ── SSH helpers for node re-provisioning ─────────────────────────────────────
# Prompt for an auth method and credentials. Sets MIG_SSH_MODE (key|password|agent),
# MIG_SSH_USER, MIG_SSH_KEY, MIG_SSH_PASS.
_migrate_ssh_prompt_auth() {
  echo ""
  echo -e "${CYAN}  SSH authentication method:${RESET}"
  echo -e "    ${BLUE}1)${RESET} SSH private key (file path)"
  echo -e "    ${BLUE}2)${RESET} Login / password"
  echo -e "    ${BLUE}3)${RESET} Default key / ssh-agent"
  local choice
  read -rp "  Choice [1]: " choice; choice="${choice:-1}"
  read -rp "  SSH user [root]: " MIG_SSH_USER; MIG_SSH_USER="${MIG_SSH_USER:-root}"
  MIG_SSH_KEY=""; MIG_SSH_PASS=""; MIG_SSH_MODE="agent"
  case "$choice" in
    1)
      MIG_SSH_MODE="key"
      read -rp "  Private key path [~/.ssh/id_ed25519]: " MIG_SSH_KEY
      MIG_SSH_KEY="${MIG_SSH_KEY:-$HOME/.ssh/id_ed25519}"
      MIG_SSH_KEY="${MIG_SSH_KEY/#\~/$HOME}"
      if [ ! -f "$MIG_SSH_KEY" ]; then
        warn "Key file not found: $MIG_SSH_KEY (will still try, ssh may fall back to agent)"
      fi
      ;;
    2)
      MIG_SSH_MODE="password"
      if ! command -v sshpass >/dev/null 2>&1; then
        info "Installing sshpass (required for password auth)..."
        if command -v apt-get >/dev/null 2>&1; then
          apt-get install -y -qq sshpass >/dev/null 2>&1 || true
        elif command -v yum >/dev/null 2>&1; then
          yum install -y -q sshpass >/dev/null 2>&1 || true
        fi
        if ! command -v sshpass >/dev/null 2>&1; then
          warn "Could not install sshpass automatically. Falling back to key/agent auth."
          MIG_SSH_MODE="agent"
          return 0
        fi
      fi
      read -rsp "  SSH password: " MIG_SSH_PASS; echo ""
      ;;
    *) MIG_SSH_MODE="agent" ;;
  esac
}

# Run a command on a node over SSH honoring the chosen auth mode.
# Usage: _migrate_ssh_run <address> <remote_command>   (stdin is forwarded)
_migrate_ssh_run() {
  local address="$1" cmd="$2"
  local base_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 -o LogLevel=ERROR)
  case "$MIG_SSH_MODE" in
    key)      ssh "${base_opts[@]}" -o BatchMode=yes -i "$MIG_SSH_KEY" "$MIG_SSH_USER@$address" "$cmd" ;;
    password) sshpass -p "$MIG_SSH_PASS" ssh "${base_opts[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no "$MIG_SSH_USER@$address" "$cmd" ;;
    *)        ssh "${base_opts[@]}" -o BatchMode=yes "$MIG_SSH_USER@$address" "$cmd" ;;
  esac
}

# Test connectivity to a node and print a status line. Returns 0 when reachable.
_migrate_ssh_check() {
  local address="$1"
  printf "  %-42s" "$MIG_SSH_USER@$address"
  if _migrate_ssh_run "$address" "echo ok" </dev/null >/dev/null 2>&1; then
    echo -e "${GREEN}[CONNECTED]${RESET}"
    return 0
  fi
  echo -e "${RED}[FAILED]${RESET}"
  return 1
}

# Bring migrated (disabled) nodes online: attempt SSH auto-install, else print
# the manual command per node.
migrate_reprovision_nodes() {
  local jwt="$1" nodes
  nodes=$(curl -s -m 30 "$PANEL_API/nodes" -H "Authorization: Bearer $jwt")
  local list
  list=$(printf '%s' "$nodes" | python3 - <<'PY' 2>/dev/null
import sys, json
d = json.load(sys.stdin)
arr = d.get('data', d)
if isinstance(arr, dict):
    arr = arr.get('nodes', [])
for n in arr:
    if n.get('isDisabled'):
        print(f"{n.get('uuid')}\t{n.get('name')}\t{n.get('address')}")
PY
)
  if [ -z "$list" ]; then
    info "No disabled nodes to re-provision."
    return 0
  fi

  echo ""
  echo -e "${CYAN}Disabled nodes to bring online:${RESET}"
  echo "$list" | awk -F'\t' '{print "  - "$2" ("$3")"}'
  echo ""

  local use_ssh="n"
  if confirm "  Try automatic re-provisioning over SSH?" "n"; then use_ssh="y"; fi
  if [ "$use_ssh" = "y" ]; then
    _migrate_ssh_prompt_auth
    echo ""
    echo -e "${CYAN}  Checking SSH connectivity to every node:${RESET}"
    while IFS=$'\t' read -r _u _n _address; do
      [ -z "$_address" ] && continue
      _migrate_ssh_check "$_address" || true
    done <<< "$list"
    echo ""
    if ! confirm "  Continue with these credentials?" "y"; then
      _migrate_ssh_prompt_auth
      echo ""
      echo -e "${CYAN}  Re-checking SSH connectivity:${RESET}"
      while IFS=$'\t' read -r _u _n _address; do
        [ -z "$_address" ] && continue
        _migrate_ssh_check "$_address" || true
      done <<< "$list"
      echo ""
    fi
  fi

  # fd 3 keeps stdin free for the interactive per-node prompts below.
  while IFS=$'\t' read -r -u 3 uuid name address; do
    [ -z "$uuid" ] && continue
    echo ""
    echo -e "${BOLD_MAGENTA}  Node: $name ($address)${RESET}"
    local compose
    compose=$(curl -s -m 30 "$PANEL_API/nodes/$uuid/docker-compose" -H "Authorization: Bearer $jwt" | _json_get data.dockerCompose)
    [ -z "$compose" ] && compose=$(curl -s -m 30 "$PANEL_API/nodes/$uuid/docker-compose" -H "Authorization: Bearer $jwt" | _json_get dockerCompose)
    if [ -z "$compose" ]; then
      warn "Could not fetch docker-compose for this node from the panel; skipping."
      continue
    fi

    local done_auto="n"
    if [ "$use_ssh" = "y" ]; then
      if ! _migrate_ssh_check "$address"; then
        warn "SSH is not reachable for $name — offering per-node credentials."
        if confirm "  Enter different credentials for this node?" "y"; then
          local prev_mode="$MIG_SSH_MODE" prev_user="$MIG_SSH_USER" prev_key="$MIG_SSH_KEY" prev_pass="$MIG_SSH_PASS"
          _migrate_ssh_prompt_auth
          if ! _migrate_ssh_check "$address"; then
            warn "Still unreachable — falling back to manual instructions."
            MIG_SSH_MODE="$prev_mode"; MIG_SSH_USER="$prev_user"; MIG_SSH_KEY="$prev_key"; MIG_SSH_PASS="$prev_pass"
          fi
        fi
      fi
      info "Connecting to $MIG_SSH_USER@$address ..."
      if printf '%s' "$compose" | _migrate_ssh_run "$address" \
          'mkdir -p /opt/v2raytunpanel-node && cat > /opt/v2raytunpanel-node/docker-compose.yml && cd /opt/v2raytunpanel-node && (command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh) && docker compose pull && docker compose up -d' \
          >/dev/null 2>&1; then
        success "Re-provisioned $name over SSH."
        curl -s -m 15 -X POST "$PANEL_API/nodes/$uuid/enable" -H "Authorization: Bearer $jwt" >/dev/null 2>&1 || true
        done_auto="y"
      else
        warn "Automatic SSH re-provisioning failed for $name."
      fi
    fi

    if [ "$done_auto" = "n" ]; then
      echo -e "${YELLOW}  Manual step for $name:${RESET} on the node server run"
      echo -e "    ${DIM}bash <(curl -fsSL https://raw.githubusercontent.com/v2RayTun/install-panel/main/install.sh)${RESET}"
      echo -e "    ${DIM}then choose 'Install Node' and paste this docker-compose:${RESET}"
      echo ""
      echo "$compose"
      echo ""
      echo -e "${DIM}  After the node connects, enable it in the panel (Nodes page).${RESET}"
    fi
  done 3<<< "$list"
}

# ──────────────────────────────────────────────────────────────────────────────
# Menus
# ──────────────────────────────────────────────────────────────────────────────
menu_main() {
  while true; do
    print_banner
    echo -e "${BOLD_MAGENTA}Main menu:${RESET}"
    echo ""
    echo -e "  ${BLUE}1)${RESET} Install / reinstall Panel"
    echo -e "  ${BLUE}2)${RESET} Install Node"
    echo -e "  ${BLUE}3)${RESET} Update Panel"
    echo -e "  ${BLUE}4)${RESET} Update Node"
    echo -e "  ${BLUE}5)${RESET} Backup database"
    echo -e "  ${BLUE}6)${RESET} Restore from backup"
    echo -e "  ${BLUE}7)${RESET} Show status"
    echo -e "  ${BLUE}8)${RESET} Tail backend logs"
    echo -e "  ${BLUE}m)${RESET} Migrate from Remnawave ${YELLOW}[beta]${RESET}"
    echo -e "  ${BLUE}d)${RESET} Remove Panel  ${DIM}(destructive)${RESET}"
    echo -e "  ${BLUE}D)${RESET} Remove Node   ${DIM}(destructive)${RESET}"
    echo -e "  ${RED}0)${RESET} Exit"
    echo ""
    read -rp "Choice: " CHOICE
    case "$CHOICE" in
      1) panel_install; press_any_key ;;
      2) node_install; press_any_key ;;
      3) panel_update; press_any_key ;;
      4) node_update; press_any_key ;;
      5) backup_create; press_any_key ;;
      6) backup_restore; press_any_key ;;
      7) panel_status; press_any_key ;;
      8) panel_logs ;;
      m|M) migrate_from_remna; press_any_key ;;
      d) panel_remove; press_any_key ;;
      D) node_remove; press_any_key ;;
      0) info "Goodbye!"; exit 0 ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
  done
}

menu_help() {
  cat << HELP
v2raytunsetup — V2RayTun Panel Setup Manager

Usage:
  v2raytunsetup [command]

Commands:
  (no args)        Show interactive main menu
  install-panel    Install panel non-interactively
  install-node     Install node non-interactively
  update [panel]   Update panel images and restart
  update node      Update node image and restart
  status           Show running containers
  logs [service]   Tail container logs (default: backend)
  backup           Create database + redis backup
  restore          Restore database from backup
  migrate          Migrate from a Remnawave panel into this panel
  attach           Attach to running tmux setup session
  resume           Resume interrupted installation (docker compose up -d)
  help             Show this help

Environment:
  V2RAYTUN_REGISTRY        Docker registry hostname
  V2RAYTUN_VERSION         Image tag (default ${VERSION})
  V2RAYTUN_PANEL_IP        Node install: the panel's IP, the only one the agent port answers (when ufw is active)
HELP
}

# ──────────────────────────────────────────────────────────────────────────────
# Entrypoint dispatcher
# ──────────────────────────────────────────────────────────────────────────────
main() {
  check_root

  case "${1:-}" in
    attach)
      if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        exec tmux attach-session -t "$TMUX_SESSION"
      else
        warn "No active setup session"
      fi
      ;;
    resume)
      if [ -f "$PANEL_DOCKER_DIR/docker-compose.yml" ]; then
        info "Resuming panel..."
        cd "$PANEL_DOCKER_DIR" && docker compose up -d
      else
        warn "Panel not installed"
      fi
      ;;
    status)         panel_status ;;
    logs)           panel_logs "${2:-backend}" ;;
    update)
      case "${2:-panel}" in
        panel) panel_update ;;
        node)  node_update ;;
        *)     error "Unknown target: $2"; exit 1 ;;
      esac
      ;;
    install-panel)  panel_install ;;
    install-node)   node_install ;;
    backup)         backup_create ;;
    restore)        backup_restore ;;
    migrate)        migrate_from_remna ;;
    remove-panel)   panel_remove ;;
    remove-node)    node_remove ;;
    help|--help|-h) menu_help ;;
    "")
      # If a V2RAYTUN_ACTION was set on a non-interactive shell (no TTY),
      # run the action once and exit instead of falling into the menu.
      local _interactive=1
      if [ ! -t 0 ] || [ ! -t 1 ]; then _interactive=0; fi

      case "${V2RAYTUN_ACTION:-}" in
        install-panel) panel_install; if [ "$_interactive" = 1 ]; then press_any_key; menu_main; fi ;;
        install-node)  node_install; if [ "$_interactive" = 1 ]; then press_any_key; menu_main; fi ;;
        update-panel)  panel_update; if [ "$_interactive" = 1 ]; then press_any_key; menu_main; fi ;;
        update-node)   node_update; if [ "$_interactive" = 1 ]; then press_any_key; menu_main; fi ;;
        "")            [ "$_interactive" = 1 ] && menu_main || menu_help ;;
        *)             error "Unknown V2RAYTUN_ACTION: $V2RAYTUN_ACTION"; exit 1 ;;
      esac
      ;;
    *) error "Unknown command: $1"; menu_help; exit 1 ;;
  esac
}

main "$@"
