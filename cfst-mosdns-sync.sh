#!/bin/sh

set -eu

CFST_BIN="${CFST_BIN:-/usr/bin/cfst}"
IP_FILE="${IP_FILE:-/usr/share/CloudflareST/ip.txt}"
WORK_DIR="${WORK_DIR:-/tmp/cfst-mosdns}"
RESULT_CSV="${RESULT_CSV:-$WORK_DIR/result.csv}"
CFST_AUTO_INSTALL="${CFST_AUTO_INSTALL:-1}"
CFST_RELEASE_BASE_URL="${CFST_RELEASE_BASE_URL:-https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download}"
CFST_IPTXT_URL="${CFST_IPTXT_URL:-https://raw.githubusercontent.com/XIU2/CloudflareSpeedTest/master/ip.txt}"
CFST_ASSET_ARCH_OVERRIDE="${CFST_ASSET_ARCH_OVERRIDE:-}"
CFST_TEST_URL="${CFST_TEST_URL:-https://speed.cloudflare.com/__down?bytes=20000000}"
CFST_DEBUG="${CFST_DEBUG:-0}"
TOPN="${TOPN:-5}"
THREADS="${THREADS:-100}"
PING_TIMES="${PING_TIMES:-4}"
DOWNLOAD_COUNT="${DOWNLOAD_COUNT:-10}"
DOWNLOAD_TIME="${DOWNLOAD_TIME:-5}"
LATENCY_LIMIT="${LATENCY_LIMIT:-9999}"
LOSS_RATE_LIMIT="${LOSS_RATE_LIMIT:-1}"
SPEED_LIMIT="${SPEED_LIMIT:-0}"
USE_DOWNLOAD_TEST="${USE_DOWNLOAD_TEST:-1}"
LOCK_FILE="${LOCK_FILE:-/tmp/cfst-mosdns.lock}"
CLOUDFLARE_SECTION="${CLOUDFLARE_SECTION:-mosdns.config}"
MOSDNS_RESTART_CMD="${MOSDNS_RESTART_CMD:-/etc/init.d/mosdns restart}"
PASSWALL_BYPASS_LOCALHOST_PROXY="${PASSWALL_BYPASS_LOCALHOST_PROXY:-1}"
PASSWALL_SECTION="${PASSWALL_SECTION:-passwall2.@global[0]}"
PASSWALL_RESTART_CMD="${PASSWALL_RESTART_CMD:-/etc/init.d/passwall2 restart}"

PASSWALL_TOUCHED=0
PASSWALL_ORIG_LOCALHOST_PROXY=""

log() {
  printf '%s\n' "$*"
  logger -t cfst-mosdns-sync "$*" 2>/dev/null || true
}

fetch_url() {
  url="$1"
  output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 15 --max-time 240 "$url" -o "$output" >/dev/null 2>&1
    return $?
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$output" "$url"
    return $?
  fi

  if command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -O "$output" "$url"
    return $?
  fi

  return 127
}

detect_cfst_asset_arch() {
  machine="${CFST_ASSET_ARCH_OVERRIDE:-$(uname -m)}"
  case "$machine" in
    x86_64|amd64)
      echo "amd64"
      ;;
    i386|i486|i586|i686|x86)
      echo "386"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7*|armv7l)
      echo "armv7"
      ;;
    armv6*|armv6l)
      echo "armv6"
      ;;
    armv5*|armv5l|arm)
      echo "armv5"
      ;;
    mips64el|mips64le)
      echo "mips64le"
      ;;
    mips64)
      echo "mips64"
      ;;
    mipsel|mipsle)
      echo "mipsle"
      ;;
    mips)
      echo "mips"
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_cfst() {
  if [ -x "$CFST_BIN" ] && [ -f "$IP_FILE" ]; then
    return 0
  fi

  if [ "$CFST_AUTO_INSTALL" != "1" ]; then
    log "cfst or ip.txt missing and CFST_AUTO_INSTALL=0"
    return 1
  fi

  asset_arch="$(detect_cfst_asset_arch 2>/dev/null || true)"
  if [ -z "$asset_arch" ]; then
    log "unsupported arch for auto install: ${CFST_ASSET_ARCH_OVERRIDE:-$(uname -m)}"
    return 1
  fi

  asset_name="cfst_linux_${asset_arch}.tar.gz"
  asset_url="${CFST_RELEASE_BASE_URL}/${asset_name}"
  tmp_dir="$(mktemp -d)"
  archive_file="$tmp_dir/$asset_name"

  log "cfst missing, downloading: $asset_name"
  if ! fetch_url "$asset_url" "$archive_file"; then
    log "failed to download cfst from: $asset_url"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! tar -xzf "$archive_file" -C "$tmp_dir" >/dev/null 2>&1; then
    log "failed to extract archive: $archive_file"
    rm -rf "$tmp_dir"
    return 1
  fi

  if [ ! -f "$tmp_dir/cfst" ]; then
    log "cfst binary not found in archive"
    rm -rf "$tmp_dir"
    return 1
  fi

  mkdir -p "$(dirname "$CFST_BIN")"
  cp -f "$tmp_dir/cfst" "$CFST_BIN"
  chmod 0755 "$CFST_BIN"

  if [ ! -f "$IP_FILE" ]; then
    mkdir -p "$(dirname "$IP_FILE")"
    if [ -f "$tmp_dir/ip.txt" ]; then
      cp -f "$tmp_dir/ip.txt" "$IP_FILE"
    else
      if ! fetch_url "$CFST_IPTXT_URL" "$IP_FILE"; then
        log "failed to download ip.txt from: $CFST_IPTXT_URL"
        rm -rf "$tmp_dir"
        return 1
      fi
    fi
    chmod 0644 "$IP_FILE" 2>/dev/null || true
  fi

  rm -rf "$tmp_dir"
  return 0
}

if [ -f "$LOCK_FILE" ]; then
  old_pid="$(cat "$LOCK_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    log "another sync process is running: pid=$old_pid"
    exit 1
  fi
fi

echo "$$" > "$LOCK_FILE"

cleanup() {
  rc="$?"
  set +e
  if [ "$PASSWALL_TOUCHED" = "1" ] && [ -n "$PASSWALL_ORIG_LOCALHOST_PROXY" ]; then
    log "restore passwall2 localhost_proxy=$PASSWALL_ORIG_LOCALHOST_PROXY"
    uci -q set "$PASSWALL_SECTION.localhost_proxy=$PASSWALL_ORIG_LOCALHOST_PROXY"
    uci commit passwall2
    sh -c "$PASSWALL_RESTART_CMD" >/dev/null 2>&1 || {
      log "failed to restore passwall2, run manually: $PASSWALL_RESTART_CMD"
      rc=1
    }
  fi
  rm -f "$LOCK_FILE"
  exit "$rc"
}
trap cleanup EXIT INT TERM

if ! ensure_cfst; then
  log "unable to prepare cfst runtime (bin: $CFST_BIN, ip_file: $IP_FILE)"
  exit 1
fi

case "$TOPN" in
  ''|*[!0-9]*)
    log "TOPN must be a positive integer"
    exit 1
    ;;
esac

if [ "$TOPN" -le 0 ]; then
  log "TOPN must be > 0"
  exit 1
fi

if [ "$PASSWALL_BYPASS_LOCALHOST_PROXY" = "1" ]; then
  pw_enabled="$(uci -q get "$PASSWALL_SECTION.enabled" 2>/dev/null || echo 0)"
  pw_localhost_proxy="$(uci -q get "$PASSWALL_SECTION.localhost_proxy" 2>/dev/null || echo 0)"
  if [ "$pw_enabled" = "1" ] && [ "$pw_localhost_proxy" = "1" ]; then
    log "passwall2 localhost_proxy=1 detected, disable temporarily for accurate testing"
    PASSWALL_ORIG_LOCALHOST_PROXY="$pw_localhost_proxy"
    uci -q set "$PASSWALL_SECTION.localhost_proxy=0"
    uci commit passwall2
    sh -c "$PASSWALL_RESTART_CMD" >/dev/null 2>&1 || {
      log "failed to restart passwall2 after disabling localhost_proxy"
      exit 1
    }
    PASSWALL_TOUCHED=1
  fi
fi

mkdir -p "$WORK_DIR"
NEW_IPS_FILE="$WORK_DIR/new_ips.txt"
CUR_IPS_FILE="$WORK_DIR/current_ips.txt"
CFST_LOG="$WORK_DIR/cfst.log"
MOSDNS_LOG="$WORK_DIR/mosdns-restart.log"

set -- \
  -f "$IP_FILE" \
  -n "$THREADS" \
  -t "$PING_TIMES" \
  -dn "$DOWNLOAD_COUNT" \
  -dt "$DOWNLOAD_TIME" \
  -tl "$LATENCY_LIMIT" \
  -tlr "$LOSS_RATE_LIMIT" \
  -sl "$SPEED_LIMIT" \
  -p 0 \
  -o "$RESULT_CSV"

if [ "$USE_DOWNLOAD_TEST" != "1" ]; then
  set -- "$@" -dd
fi

if [ -n "$CFST_TEST_URL" ]; then
  set -- "$@" -url "$CFST_TEST_URL"
fi

if [ "$CFST_DEBUG" = "1" ]; then
  set -- "$@" -debug
fi

log "start CloudflareSpeedTest"
if ! "$CFST_BIN" "$@" >"$CFST_LOG" 2>&1; then
  log "CloudflareSpeedTest failed, see $CFST_LOG"
  exit 1
fi

awk -F',' 'NR>1 {gsub(/\r/, "", $1); if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $1}' "$RESULT_CSV" \
  | head -n "$TOPN" > "$NEW_IPS_FILE"

if [ ! -s "$NEW_IPS_FILE" ]; then
  log "no valid IPv4 found in $RESULT_CSV"
  exit 1
fi

: > "$CUR_IPS_FILE"
uci -q show "$CLOUDFLARE_SECTION.cloudflare_ip" 2>/dev/null \
  | sed 's/^.*=//' \
  | tr -d "'" \
  | tr ' ' '\n' \
  | sed '/^$/d' > "$CUR_IPS_FILE" || true

if cmp -s "$CUR_IPS_FILE" "$NEW_IPS_FILE"; then
  log "cloudflare_ip unchanged, skip mosdns restart"
  exit 0
fi

log "apply new cloudflare_ip list into UCI: $CLOUDFLARE_SECTION.cloudflare_ip"
uci -q delete "$CLOUDFLARE_SECTION.cloudflare_ip" 2>/dev/null || true
while IFS= read -r ip; do
  [ -n "$ip" ] || continue
  uci add_list "$CLOUDFLARE_SECTION.cloudflare_ip=$ip"
done < "$NEW_IPS_FILE"
uci commit mosdns

if ! sh -c "$MOSDNS_RESTART_CMD" >"$MOSDNS_LOG" 2>&1; then
  log "failed to restart mosdns, see $MOSDNS_LOG"
  exit 1
fi

log "sync complete, selected IP count: $(wc -l < "$NEW_IPS_FILE")"
log "selected IPs: $(tr '\n' ' ' < "$NEW_IPS_FILE")"
