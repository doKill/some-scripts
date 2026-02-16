#!/bin/sh
set -eu

# Keep the same install layout you currently use.
INSTALL_PATH="${CODEX_INSTALL_PATH:-/mnt/sda3/bin/codex}"
SYMLINK_PATH="${CODEX_SYMLINK_PATH:-/usr/bin/codex}"
RELEASE_BASE="${CODEX_RELEASE_BASE:-https://github.com/openai/codex/releases/latest/download}"

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

# Commands we absolutely need.
for c in uname tar chmod ln mv mkdir rm mktemp; do
  ensure_cmd "$c"
done

# Downloader: allow wget or curl, install if both are missing.
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
  ensure_cmd wget
  if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    ensure_cmd curl
  fi
fi

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
