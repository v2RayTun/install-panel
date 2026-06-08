#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# V2RayTun Panel — Universal Installer (no GitHub tokens, no source clone)
# ═════════════════════════════════════════════════════════════════════════════
#
# One-liner:
#   bash <(curl -fsSL https://raw.githubusercontent.com/PonomarevAleksandr/V2RayTunPanelSetup/main/install.sh)
#
# Optional environment overrides (no prompt):
#   V2RAYTUN_REGISTRY        Docker registry hostname (default docker-registry.v2raytun.com)
#   V2RAYTUN_VERSION         Image tag to pull (default 1.0.10)
#   V2RAYTUN_ACTION          Direct action: install-panel | install-node | update-panel | update-node
#   V2RAYTUN_PANEL_DOMAIN    Pre-fill panel domain (skips prompt)
#   V2RAYTUN_SUB_DOMAIN      Pre-fill subscription domain (defaults to panel domain)
#   V2RAYTUNSETUP_REPO       Source for helper scripts (default PonomarevAleksandr/V2RayTunPanelSetup)
#   V2RAYTUNSETUP_BRANCH     Branch (default main)
#
# ═════════════════════════════════════════════════════════════════════════════

set -e

INSTALLER_VERSION="1.0.13"
DEFAULT_REGISTRY="docker-registry.v2raytun.com"
DEFAULT_VERSION="1.0.13"

REPO="${V2RAYTUNSETUP_REPO:-PonomarevAleksandr/V2RayTunPanelSetup}"
BRANCH="${V2RAYTUNSETUP_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
SETUP_DIR="/opt/v2raytunpanel-setup"
TMUX_SESSION="v2raytunpanel-setup"

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'

info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }

print_banner() {
  clear 2>/dev/null || true
  echo ""
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
  echo -e "  ${BOLD}V2RayTun Panel${RESET} — Universal Installer ${CYAN}v${INSTALLER_VERSION}${RESET}"
  echo -e "  Registry: ${YELLOW}${V2RAYTUN_REGISTRY:-$DEFAULT_REGISTRY}${RESET}"
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════════════${RESET}"
  echo ""
}

check_root() {
  if [ "$(id -u)" != "0" ]; then
    error "This script must be run as root"
    echo ""
    echo "Try:"
    echo "  sudo bash <(curl -fsSL ${RAW_BASE}/install.sh)"
    exit 1
  fi
}

detect_pm() {
  if command -v apt-get &>/dev/null; then echo "apt"; return; fi
  if command -v dnf     &>/dev/null; then echo "dnf"; return; fi
  if command -v yum     &>/dev/null; then echo "yum"; return; fi
  if command -v apk     &>/dev/null; then echo "apk"; return; fi
  if command -v pacman  &>/dev/null; then echo "pacman"; return; fi
  if command -v zypper  &>/dev/null; then echo "zypper"; return; fi
  echo "unknown"
}

install_pkg() {
  local pkg="$1"
  case "$(detect_pm)" in
    apt)    apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq "$pkg" >/dev/null 2>&1 ;;
    dnf)    dnf install -y -q "$pkg" >/dev/null 2>&1 ;;
    yum)    yum install -y -q "$pkg" >/dev/null 2>&1 ;;
    apk)    apk add --no-cache --quiet "$pkg" >/dev/null 2>&1 ;;
    pacman) pacman -Sy --noconfirm --quiet "$pkg" >/dev/null 2>&1 ;;
    zypper) zypper -q install -y "$pkg" >/dev/null 2>&1 ;;
    *)      warn "Unknown package manager. Install '$pkg' manually."; return 1 ;;
  esac
}

ensure_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  info "Installing $1..."
  install_pkg "$1" || { error "Failed to install $1"; exit 1; }
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    success "Docker already installed"
  else
    info "Installing Docker..."
    if ! curl -fsSL https://get.docker.com | sh; then
      error "Docker installation failed"
      echo "Install manually: https://docs.docker.com/engine/install/"
      exit 1
    fi
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable docker >/dev/null 2>&1 || true
      systemctl start  docker >/dev/null 2>&1 || true
    fi
  fi

  if ! docker compose version >/dev/null 2>&1; then
    info "Installing Docker Compose plugin..."
    if ! install_pkg docker-compose-plugin 2>/dev/null; then
      mkdir -p /usr/local/lib/docker/cli-plugins
      curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
      chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi
  fi

  if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running"
    echo "Start it with: systemctl start docker"
    exit 1
  fi
}

fetch_assets() {
  info "Fetching helper scripts from ${REPO}@${BRANCH}..."
  rm -rf "$SETUP_DIR"
  mkdir -p "$SETUP_DIR/lib" "$SETUP_DIR/compose"

  local files=(
    "lib/common.sh"
    "lib/v2raytunsetup.sh"
    "compose/docker-compose.panel.yml"
    "compose/docker-compose.node.yml"
  )

  for f in "${files[@]}"; do
    if ! curl -fsSL "${RAW_BASE}/${f}" -o "${SETUP_DIR}/${f}"; then
      error "Failed to fetch ${f}"
      echo "URL: ${RAW_BASE}/${f}"
      exit 1
    fi
  done

  chmod +x "$SETUP_DIR/lib/v2raytunsetup.sh"

  cat > "$SETUP_DIR/.config" << EOF
RAW_BASE="${RAW_BASE}"
V2RAYTUN_REGISTRY="${V2RAYTUN_REGISTRY:-$DEFAULT_REGISTRY}"
V2RAYTUN_VERSION="${V2RAYTUN_VERSION:-$DEFAULT_VERSION}"
INSTALLER_VERSION="${INSTALLER_VERSION}"
EOF

  success "Helper scripts cached at ${SETUP_DIR}"
}

install_global_command() {
  cat > /usr/local/bin/v2raytunsetup << 'GLOBALCMD'
#!/bin/bash
SETUP_DIR="/opt/v2raytunpanel-setup"

if [ ! -f "$SETUP_DIR/lib/v2raytunsetup.sh" ]; then
  echo "v2raytunsetup is not installed. Re-run installer:"
  echo "  bash <(curl -fsSL https://raw.githubusercontent.com/PonomarevAleksandr/V2RayTunPanelSetup/main/install.sh)"
  exit 1
fi

exec bash "$SETUP_DIR/lib/v2raytunsetup.sh" "$@"
GLOBALCMD
  chmod +x /usr/local/bin/v2raytunsetup
  success "Command 'v2raytunsetup' installed globally"
}

ensure_tmux_session() {
  if [ -n "$TMUX" ]; then
    return 0
  fi

  if ! command -v tmux >/dev/null 2>&1; then
    install_pkg tmux 2>/dev/null || return 0
  fi

  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}Existing setup session detected${RESET}"
    echo "  1) Attach to it (recommended)"
    echo "  2) Kill it and start fresh"
    echo "  3) Continue without tmux"
    read -rp "Choice (1/2/3, default 1): " CH
    case "${CH:-1}" in
      1) exec tmux attach-session -t "$TMUX_SESSION" ;;
      2) tmux kill-session -t "$TMUX_SESSION" 2>/dev/null ;;
      3) return 0 ;;
    esac
  fi

  echo ""
  echo -e "${YELLOW}Starting tmux session '${TMUX_SESSION}' for safe SSH installation${RESET}"
  echo -e "  If your connection drops, re-run ${GREEN}v2raytunsetup attach${RESET} to resume"
  sleep 2

  exec tmux new-session -s "$TMUX_SESSION" \
    "V2RAYTUN_REGISTRY=${V2RAYTUN_REGISTRY:-$DEFAULT_REGISTRY} \
     V2RAYTUN_VERSION=${V2RAYTUN_VERSION:-$DEFAULT_VERSION} \
     V2RAYTUN_PANEL_DOMAIN='${V2RAYTUN_PANEL_DOMAIN:-}' \
     V2RAYTUN_SUB_DOMAIN='${V2RAYTUN_SUB_DOMAIN:-}' \
     V2RAYTUN_ACTION='${V2RAYTUN_ACTION:-}' \
     bash $SETUP_DIR/lib/v2raytunsetup.sh"
}

main() {
  print_banner
  check_root
  ensure_command curl
  ensure_command tar
  ensure_docker
  fetch_assets
  install_global_command

  # Headless / non-interactive run (no TTY, e.g. CI or `ssh host bash <(...)`):
  # skip the tmux wrapper and let v2raytunsetup.sh's V2RAYTUN_ACTION flow exit
  # cleanly after the requested action.
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    exec bash "$SETUP_DIR/lib/v2raytunsetup.sh"
  fi

  if [ "${1:-}" != "--no-tmux" ]; then
    ensure_tmux_session
  fi

  exec bash "$SETUP_DIR/lib/v2raytunsetup.sh"
}

main "$@"
