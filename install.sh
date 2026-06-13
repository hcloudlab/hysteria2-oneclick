#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="/etc/hysteria/config.yaml"
CERT_DIR="/etc/hysteria/certs"
CERT_KEY="/etc/hysteria/certs/server.key"
CERT_CRT="/etc/hysteria/certs/server.crt"
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
CLIENT_FILE="/root/hysteria2-client.txt"
PORT="8443"

log() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "请使用 root 执行：bash install.sh"
    exit 1
  fi
}

install_packages() {
  apt-get update -y
  apt-get install -y curl ca-certificates openssl ufw
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) printf '%s' "amd64" ;;
    aarch64|arm64) printf '%s' "arm64" ;;
    *) err "不支持的架构：$arch"; exit 1 ;;
  esac
}

install_hysteria_binary() {
  local arch api_url asset_url tmpdir
  arch="$(detect_arch)"
  api_url="https://api.github.com/repos/apernet/hysteria/releases/latest"
  asset_url="$(curl -fsSL "$api_url" \
    | grep -oE '"browser_download_url":[[:space:]]*"[^"]*hysteria-linux-[^"]*"' \
    | grep "hysteria-linux-${arch}" \
    | grep -v 'avx' \
    | head -n1 \
    | cut -d'"' -f4)"
  if [[ -z "${asset_url:-}" ]]; then
    err "未能找到适合当前架构的 Hysteria2 安装包"
    exit 1
  fi
  tmpdir="$(mktemp -d)"
  log "下载 Hysteria2：$asset_url"
  curl -fsSL "$asset_url" -o "$tmpdir/hysteria"
  install -m 0755 "$tmpdir/hysteria" /usr/local/bin/hysteria
  rm -rf "$tmpdir"
}

generate_password() {
  openssl rand -base64 24 | tr -d '\n'
}

generate_self_signed_cert() {
  mkdir -p "$CERT_DIR"
  if [[ ! -f "$CERT_KEY" || ! -f "$CERT_CRT" ]]; then
    log "生成自签证书"
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout "$CERT_KEY" \
      -out "$CERT_CRT" \
      -subj "/CN=Hysteria2" >/dev/null 2>&1
    chmod 600 "$CERT_KEY"
  fi
}

write_config() {
  local password="$1"
  cat > "$CONFIG_FILE" <<EOF
listen: :${PORT}
auth:
  type: password
  password: ${password}
tls:
  cert: ${CERT_CRT}
  key: ${CERT_KEY}
EOF
}

write_service() {
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Hysteria2 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c ${CONFIG_FILE}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

get_public_ip() {
  local ip
  ip="$(curl -4 -fsS ifconfig.me 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsS https://api.ipify.org 2>/dev/null || true)"
  fi
  printf '%s' "$ip"
}

allow_ufw_port() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
    ufw allow "${PORT}/udp" >/dev/null
  fi
}

write_client_file() {
  local password="$1"
  local public_ip="$2"
  cat > "$CLIENT_FILE" <<EOF
Hysteria2 客户端信息
===================
服务端地址: ${public_ip}
端口: ${PORT}/udp
认证密码: ${password}
证书类型: 自签证书
客户端要求: insecure: true

示例客户端配置:
server: ${public_ip}:${PORT}
auth: ${password}
tls:
  insecure: true
EOF
  chmod 600 "$CLIENT_FILE"
}

print_final_screen() {
  printf '\n\033[1;36m========== Hysteria2 客户端信息 ==========\033[0m\n'
  cat "$CLIENT_FILE"
  printf '\033[1;36m===========================================\033[0m\n'
}

main() {
  require_root
  install_packages
  install_hysteria_binary
  mkdir -p "$CONFIG_DIR"
  generate_self_signed_cert

  local password public_ip
  password="$(generate_password)"
  public_ip="$(get_public_ip)"
  if [[ -z "$public_ip" ]]; then
    warn "未能自动获取公网 IPv4，将使用占位地址"
    public_ip="YOUR_PUBLIC_IP"
  fi

  write_config "$password"
  write_service
  systemctl daemon-reload
  systemctl enable --now hysteria-server.service
  allow_ufw_port
  write_client_file "$password" "$public_ip"
  print_final_screen
}

main "$@"
