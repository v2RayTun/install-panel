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
VERSION="${V2RAYTUN_VERSION:-1.0.10}"
INSTALLER_VERSION="${INSTALLER_VERSION:-1.0.10}"

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
    read -rp "Subscription page domain (Enter = same as panel): " sub_domain
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
SWAGGER_ENABLED=true
LOG_LEVEL=info
BACKEND_PORT=3000
FRONTEND_PORT=8080
REGISTRY=${REGISTRY}
VERSION=${VERSION}
API_INSTANCES=max
WORKER_INSTANCES=2
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

  info "Starting services..."
  (cd "$PANEL_DOCKER_DIR" && docker compose up -d) || {
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
  echo -e "  2. Open ${GREEN}https://${panel_domain}/register${RESET}"
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

  info "Pulling latest images..."
  docker compose pull

  info "Restarting services with the new images..."
  docker compose up -d

  success "Panel updated"
  echo ""
  docker compose ps
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

  if [ "$panel_domain" = "$sub_domain" ]; then
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
    reverse_proxy localhost:3000
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
node_install() {
  print_banner
  echo -e "${BOLD_MAGENTA}  Install Node${RESET}"
  echo -e "${MAGENTA}════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
  check_docker

  echo -e "${CYAN}Two ways to install a node:${RESET}"
  echo -e "  ${GREEN}1)${RESET} ${BOLD}Paste docker-compose from the panel${RESET} (recommended, includes mTLS certificates)"
  echo -e "  ${GREEN}2)${RESET} Interactive (manual: panel URL + node UUID + ports)"
  echo ""
  read -rp "Choice (1/2, default 1): " METHOD
  METHOD="${METHOD:-1}"

  case "$METHOD" in
    2) node_install_interactive ;;
    *) node_install_from_panel ;;
  esac
}

node_install_from_panel() {
  echo ""
  echo -e "${CYAN}1.${RESET} Open Panel → Nodes → Create Node"
  echo -e "${CYAN}2.${RESET} Fill in Name, Address (this server's IP), Port"
  echo -e "${CYAN}3.${RESET} Click Create, then Copy the docker-compose snippet"
  echo -e "${CYAN}4.${RESET} Paste it below, then press Ctrl+D when done"
  echo ""

  mkdir -p "$NODE_DIR"
  cd "$NODE_DIR"

  echo -e "${YELLOW}Paste docker-compose content (Ctrl+D to finish):${RESET}"
  cat > docker-compose.yml

  if [ ! -s docker-compose.yml ]; then
    error "Empty input"
    rm -f docker-compose.yml
    return 1
  fi

  info "Pulling node image..."
  docker compose pull

  info "Starting node..."
  docker compose up -d

  if [ $? -eq 0 ]; then
    success "Node started. It should appear as Connected in the panel within ~60 seconds."
    echo ""
    echo -e "  Logs: ${YELLOW}cd $NODE_DIR && docker compose logs -f${RESET}"
    echo -e "  Make sure the connection port is open in your firewall."
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
  info "Pulling latest image..."
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
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local db_file="$BACKUP_DIR/db-$ts.sql.gz"

  info "Dumping PostgreSQL..."
  if docker exec v2raytunpanel-postgres pg_dump -U v2raytunpanel v2raytunpanel | gzip > "$db_file"; then
    success "Database saved to $db_file ($(du -sh "$db_file" | cut -f1))"
  else
    error "Database backup failed"
    rm -f "$db_file"
    return 1
  fi

  if docker ps --format '{{.Names}}' | grep -q '^v2raytunpanel-redis$'; then
    info "Saving Redis snapshot..."
    docker exec v2raytunpanel-redis redis-cli BGSAVE >/dev/null 2>&1 || true
    sleep 2
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
      d) panel_remove; press_any_key ;;
      D) node_remove; press_any_key ;;
      0) info "Goodbye!"; exit 0 ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
  done
}

menu_help() {
  cat << 'HELP'
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
  attach           Attach to running tmux setup session
  resume           Resume interrupted installation (docker compose up -d)
  help             Show this help

Environment:
  V2RAYTUN_REGISTRY        Docker registry hostname
  V2RAYTUN_VERSION         Image tag (default 1.0.10)
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
    remove-panel)   panel_remove ;;
    remove-node)    node_remove ;;
    help|--help|-h) menu_help ;;
    "")
      # If a V2RAYTUN_ACTION was set on a non-interactive shell (no TTY),
      # run the action once and exit instead of falling into the menu.
      local _interactive=1
      if [ ! -t 0 ] || [ ! -t 1 ]; then _interactive=0; fi

      case "${V2RAYTUN_ACTION:-}" in
        install-panel) panel_install; [ "$_interactive" = 1 ] && { press_any_key; menu_main; } ;;
        install-node)  node_install;  [ "$_interactive" = 1 ] && { press_any_key; menu_main; } ;;
        update-panel)  panel_update;  [ "$_interactive" = 1 ] && { press_any_key; menu_main; } ;;
        update-node)   node_update;   [ "$_interactive" = 1 ] && { press_any_key; menu_main; } ;;
        "")            [ "$_interactive" = 1 ] && menu_main || menu_help ;;
        *)             error "Unknown V2RAYTUN_ACTION: $V2RAYTUN_ACTION"; exit 1 ;;
      esac
      ;;
    *) error "Unknown command: $1"; menu_help; exit 1 ;;
  esac
}

main "$@"
