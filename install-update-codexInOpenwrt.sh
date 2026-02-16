#!/bin/sh
set -eu

# Keep the same install layout you currently use.
INSTALL_PATH="${CODEX_INSTALL_PATH:-/mnt/sda3/bin/codex}"
SYMLINK_PATH="${CODEX_SYMLINK_PATH:-/usr/bin/codex}"
RELEASE_BASE="${CODEX_RELEASE_BASE:-https://github.com/openai/codex/releases/latest/download}"
CODEX_HOME_DIR="${CODEX_HOME_DIR:-${HOME:-/root}/.codex}"
CODEX_ENV_FILE="${CODEX_ENV_FILE:-$CODEX_HOME_DIR/.env}"
CODEX_CONFIG_FILE="${CODEX_CONFIG_FILE:-$CODEX_HOME_DIR/config.toml}"
CODEX_AUTH_FILE="${CODEX_AUTH_FILE:-$CODEX_HOME_DIR/auth.json}"
CODEX_PROVIDER_NAME="${CODEX_PROVIDER_NAME:-gmn}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.3-codex}"
CODEX_BASE_URL="${CODEX_BASE_URL:-}"
CODEX_API_KEY="${CODEX_API_KEY:-}"

PKG_MANAGER=""
PKG_PREPARED=0

is_root() {
  if command -v id >/dev/null 2>&1; then
    [ "$(id -u)" = "0" ]
  else
    [ "${USER:-}" = "root" ]
  fi
}

detect_pkg_manager() {
  if [ -n "$PKG_MANAGER" ]; then
    return 0
  fi

  if command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
  else
    PKG_MANAGER=""
  fi
}

prepare_pkg_manager() {
  [ "$PKG_PREPARED" = "1" ] && return 0
  detect_pkg_manager

  case "$PKG_MANAGER" in
    opkg)
      opkg update
      ;;
    apt-get)
      apt-get update
      ;;
    pacman)
      pacman -Sy --noconfirm
      ;;
    apk|dnf|yum|zypper)
      :
      ;;
    *)
      return 1
      ;;
  esac

  PKG_PREPARED=1
  return 0
}

install_pkg() {
  pkg="$1"

  case "$PKG_MANAGER" in
    opkg)
      opkg install "$pkg"
      ;;
    apk)
      apk add --no-cache "$pkg"
      ;;
    apt-get)
      apt-get install -y --no-install-recommends "$pkg"
      ;;
    dnf)
      dnf install -y "$pkg"
      ;;
    yum)
      yum install -y "$pkg"
      ;;
    pacman)
      pacman -S --noconfirm --needed "$pkg"
      ;;
    zypper)
      zypper --non-interactive install "$pkg"
      ;;
    *)
      return 1
      ;;
  esac
}

pkg_candidates_for_cmd() {
  cmd="$1"

  case "$cmd" in
    wget)
      case "$PKG_MANAGER" in
        opkg) echo "wget-ssl wget busybox" ;;
        *) echo "wget curl" ;;
      esac
      ;;
    curl)
      case "$PKG_MANAGER" in
        opkg) echo "curl wget-ssl wget busybox" ;;
        *) echo "curl wget" ;;
      esac
      ;;
    tar)
      case "$PKG_MANAGER" in
        opkg) echo "tar busybox" ;;
        *) echo "tar" ;;
      esac
      ;;
    uname|chmod|ln|mv|mkdir|rm|mktemp)
      case "$PKG_MANAGER" in
        opkg|apk) echo "busybox coreutils" ;;
        *) echo "coreutils" ;;
      esac
      ;;
    *)
      echo "$cmd"
      ;;
  esac
}

ensure_cmd() {
  cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 && return 0

  detect_pkg_manager
  if [ -z "$PKG_MANAGER" ]; then
    echo "[ERROR] missing command: $cmd, and no supported package manager found" >&2
    exit 1
  fi

  if ! is_root; then
    echo "[ERROR] missing command: $cmd. run this script as root for auto-install." >&2
    exit 1
  fi

  echo "[INFO] missing command: $cmd, trying to install..."
  if ! prepare_pkg_manager; then
    echo "[ERROR] failed to prepare package manager: $PKG_MANAGER" >&2
    exit 1
  fi

  for pkg in $(pkg_candidates_for_cmd "$cmd"); do
    if install_pkg "$pkg" >/dev/null 2>&1 || install_pkg "$pkg"; then
      if command -v "$cmd" >/dev/null 2>&1; then
        echo "[INFO] installed $cmd via package: $pkg"
        return 0
      fi
    fi
  done

  echo "[ERROR] failed to install required command: $cmd" >&2
  exit 1
}

download_file() {
  url="$1"
  out="$2"

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
    return 0
  fi

  echo "[ERROR] no downloader available (wget/curl)" >&2
  exit 1
}

trim_spaces() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

normalize_provider_name() {
  p="$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_-')"
  [ -n "$p" ] || p="gmn"
  printf '%s' "$p"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ensure_codex_env_file() {
  if [ -f "$CODEX_ENV_FILE" ]; then
    return 0
  fi

  cat > "$CODEX_ENV_FILE" <<'EOF'
# Fill these two values, then rerun this script once.
CODEX_BASE_URL=
CODEX_API_KEY=

# Optional
CODEX_PROVIDER_NAME=gmn
CODEX_MODEL=gpt-5.3-codex
EOF
  chmod 600 "$CODEX_ENV_FILE"
  echo "[INFO] created env template: $CODEX_ENV_FILE"
}

load_codex_env_file() {
  [ -f "$CODEX_ENV_FILE" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/\r$//')"
    case "$line" in
      ''|\#*) continue ;;
    esac

    case "$line" in
      *=*)
        key="$(trim_spaces "${line%%=*}")"
        val="$(trim_spaces "${line#*=}")"
        case "$val" in
          \"*\") val="${val#\"}"; val="${val%\"}" ;;
          \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac

        case "$key" in
          CODEX_BASE_URL)
            [ -n "$CODEX_BASE_URL" ] || CODEX_BASE_URL="$val"
            ;;
          CODEX_API_KEY)
            [ -n "$CODEX_API_KEY" ] || CODEX_API_KEY="$val"
            ;;
          CODEX_PROVIDER_NAME)
            CODEX_PROVIDER_NAME="$val"
            ;;
          CODEX_MODEL)
            CODEX_MODEL="$val"
            ;;
        esac
        ;;
    esac
  done < "$CODEX_ENV_FILE"
}

write_codex_config_toml() {
  provider="$(normalize_provider_name "$CODEX_PROVIDER_NAME")"
  model_escaped="$(toml_escape "$CODEX_MODEL")"
  base_url_value="$CODEX_BASE_URL"
  if [ -z "$base_url_value" ]; then
    base_url_value="https://your-base-url/v1"
  fi
  base_escaped="$(toml_escape "$base_url_value")"

  cat > "$CODEX_CONFIG_FILE" <<EOF
# managed-by=install-update-codex
# This file is generated from: $CODEX_ENV_FILE

model_provider = "$provider"
model = "$model_escaped"
model_reasoning_effort = "xhigh"
disable_response_storage = true
sandbox_mode = "danger-full-access"
approval_policy = "never"
profile = "auto-max"
file_opener = "vscode"

web_search = "cached"
suppress_unstable_features_warning = true

[model_providers.$provider]
name = "$provider"
base_url = "$base_escaped"
wire_api = "responses"
requires_openai_auth = false

[history]
persistence = "save-all"

[tui]
notifications = true

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = false

[sandbox_workspace_write]
network_access = true

[features]
plan_tool = true
apply_patch_freeform = true
view_image_tool = true
unified_exec = false
streamable_shell = false
rmcp_client = true
elevated_windows_sandbox = true

[profiles.auto-max]
approval_policy = "never"
sandbox_mode = "danger-full-access"

[profiles.review]
approval_policy = "on-request"
sandbox_mode = "danger-full-access"

[notice]
hide_gpt5_1_migration_prompt = true
EOF
  chmod 600 "$CODEX_CONFIG_FILE"
  echo "[INFO] wrote config: $CODEX_CONFIG_FILE"
}

write_codex_auth_json() {
  if [ -z "$CODEX_API_KEY" ]; then
    if [ ! -f "$CODEX_AUTH_FILE" ]; then
      cat > "$CODEX_AUTH_FILE" <<'EOF'
{
  "OPENAI_API_KEY": ""
}
EOF
      chmod 600 "$CODEX_AUTH_FILE"
      echo "[INFO] created auth placeholder: $CODEX_AUTH_FILE"
    fi
    return 0
  fi

  key_escaped="$(json_escape "$CODEX_API_KEY")"
  cat > "$CODEX_AUTH_FILE" <<EOF
{
  "OPENAI_API_KEY": "$key_escaped"
}
EOF
  chmod 600 "$CODEX_AUTH_FILE"
  echo "[INFO] wrote auth: $CODEX_AUTH_FILE"
}

init_codex_config_files() {
  MANAGED_CONFIG=0

  mkdir -p "$CODEX_HOME_DIR"
  chmod 700 "$CODEX_HOME_DIR" 2>/dev/null || true

  ensure_codex_env_file
  load_codex_env_file

  if [ ! -f "$CODEX_CONFIG_FILE" ]; then
    write_codex_config_toml
    MANAGED_CONFIG=1
  elif grep -q 'managed-by=install-update-codex' "$CODEX_CONFIG_FILE"; then
    write_codex_config_toml
    MANAGED_CONFIG=1
  else
    echo "[INFO] keep existing unmanaged config: $CODEX_CONFIG_FILE"
  fi

  write_codex_auth_json

  if [ "$MANAGED_CONFIG" = "1" ]; then
    if [ -z "$CODEX_BASE_URL" ]; then
      echo "[WARN] CODEX_BASE_URL is empty. fill it in: $CODEX_ENV_FILE"
    fi
    if [ -z "$CODEX_API_KEY" ]; then
      echo "[WARN] CODEX_API_KEY is empty. fill it in: $CODEX_ENV_FILE"
    fi
  fi
}

# Commands we absolutely need.
for c in uname tar chmod ln mv mkdir rm mktemp cat sed grep tr; do
  ensure_cmd "$c"
done

# Downloader: allow wget or curl, install if both are missing.
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
  ensure_cmd wget
  if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    ensure_cmd curl
  fi
fi

init_codex_config_files

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    TARGET_TRIPLE="x86_64-unknown-linux-musl"
    ;;
  aarch64|arm64)
    TARGET_TRIPLE="aarch64-unknown-linux-musl"
    ;;
  *)
    echo "[ERROR] unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

ARCHIVE_NAME="codex-${TARGET_TRIPLE}.tar.gz"
BINARY_NAME="codex-${TARGET_TRIPLE}"
DOWNLOAD_URL="${RELEASE_BASE}/${ARCHIVE_NAME}"

LOCKDIR="/tmp/update-codex.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "[INFO] another update is already running, skip"
  exit 0
fi

TMPDIR="$(mktemp -d /tmp/codex-update.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR" "$LOCKDIR"
}
trap cleanup EXIT INT TERM

OLD_VERSION="not-installed"
if [ -x "$INSTALL_PATH" ]; then
  OLD_VERSION="$($INSTALL_PATH --version 2>/dev/null || echo unknown)"
fi

echo "[INFO] arch: $ARCH -> $TARGET_TRIPLE"
echo "[INFO] download: $DOWNLOAD_URL"
download_file "$DOWNLOAD_URL" "$TMPDIR/$ARCHIVE_NAME"

tar -xzf "$TMPDIR/$ARCHIVE_NAME" -C "$TMPDIR"
if [ ! -f "$TMPDIR/$BINARY_NAME" ]; then
  echo "[ERROR] expected binary not found: $BINARY_NAME" >&2
  exit 1
fi
chmod +x "$TMPDIR/$BINARY_NAME"

NEW_VERSION="$($TMPDIR/$BINARY_NAME --version 2>/dev/null || echo unknown)"
if [ "$OLD_VERSION" = "$NEW_VERSION" ] && [ "$OLD_VERSION" != "unknown" ]; then
  ln -sf "$INSTALL_PATH" "$SYMLINK_PATH"
  echo "[INFO] already latest: $NEW_VERSION"
  exit 0
fi

INSTALL_DIR="${INSTALL_PATH%/*}"
[ "$INSTALL_DIR" = "$INSTALL_PATH" ] && INSTALL_DIR="."
mkdir -p "$INSTALL_DIR"
mv "$TMPDIR/$BINARY_NAME" "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"
ln -sf "$INSTALL_PATH" "$SYMLINK_PATH"

echo "[OK] updated: $OLD_VERSION -> $NEW_VERSION"
echo "[OK] verify: $($SYMLINK_PATH --version 2>/dev/null || echo failed)"
