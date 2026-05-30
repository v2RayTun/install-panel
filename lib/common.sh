#!/bin/bash
# V2RayTun Panel Setup — shared helpers (colors, logging, OS detection, secrets)

# ──────────────────────────────────────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────────────────────────────────────
export RESET='\033[0m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'
export DIM='\033[2m'

export BOLD_RED='\033[1;31m'
export BOLD_GREEN='\033[1;32m'
export BOLD_YELLOW='\033[1;33m'
export BOLD_BLUE='\033[1;34m'
export BOLD_MAGENTA='\033[1;35m'
export BOLD_CYAN='\033[1;36m'
export BOLD_WHITE='\033[1;37m'

# ──────────────────────────────────────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────────────────────────────────────
info()    { echo -e "${BOLD_CYAN}[INFO]${RESET} $1"; }
warn()    { echo -e "${BOLD_YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${BOLD_RED}[ERROR]${RESET} $1" >&2; }
success() { echo -e "${BOLD_GREEN}[OK]${RESET} $1"; }

# ──────────────────────────────────────────────────────────────────────────────
# OS detection
# ──────────────────────────────────────────────────────────────────────────────
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-unknown}"
  elif [ -f /etc/redhat-release ]; then
    echo "centos"
  elif [ -f /etc/debian_version ]; then
    echo "debian"
  else
    echo "unknown"
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
    *)      warn "Cannot install '$pkg' — unsupported package manager"; return 1 ;;
  esac
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  info "Installing $1..."
  install_pkg "$1"
}

# ──────────────────────────────────────────────────────────────────────────────
# Secret/password generation
# ──────────────────────────────────────────────────────────────────────────────
generate_secret() {
  openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p | tr -d '\n'
}

generate_password() {
  openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p | tr -d '\n'
}

# ──────────────────────────────────────────────────────────────────────────────
# Validation
# ──────────────────────────────────────────────────────────────────────────────
check_root() {
  if [ "$(id -u)" != "0" ]; then
    error "This script must be run as root"
    echo "Try: sudo $0"
    exit 1
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    error "Docker is not installed. Run the installer again."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running. Start it with: systemctl start docker"
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    error "Docker Compose plugin is missing"
    exit 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Validate domain (basic)
# ──────────────────────────────────────────────────────────────────────────────
is_valid_domain() {
  local d="$1"
  [[ "$d" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# Read password without echo, with fallback when stdin is not a tty
# ──────────────────────────────────────────────────────────────────────────────
read_password() {
  local prompt="$1"
  local var
  if [ -t 0 ]; then
    read -rsp "$prompt" var
    echo "" >&2
  else
    read -rp "$prompt" var
  fi
  printf '%s' "$var"
}

# ──────────────────────────────────────────────────────────────────────────────
# Confirmation helper
# ──────────────────────────────────────────────────────────────────────────────
confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-n}"
  local hint
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  local response
  read -rp "$prompt $hint: " response
  response="${response:-$default}"
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *)                 return 1 ;;
  esac
}

export -f info warn error success
export -f detect_os detect_pm install_pkg ensure_command
export -f generate_secret generate_password
export -f check_root check_docker is_valid_domain read_password confirm
