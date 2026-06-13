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
HY2_SNI="${HY2_SNI:-bing.com}"

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

install_hysteria2() {
  log "安装 Hysteria2..."

  if command -v hysteria >/dev/null 2>&1; then
    log "检测到已安装：$(hysteria version 2>/dev/null | head -n1)"
    return 0
  fi

  curl -fsSL https://get.hy2.sh/ -o /tmp/get_hy2.sh || {
    err "下载 Hysteria2 官方安装脚本失败"
    exit 1
  }

  bash /tmp/get_hy2.sh || {
    err "执行 Hysteria2 安装脚本失败"
    exit 1
  }

  command -v hysteria >/dev/null 2>&1 || {
    err "hysteria 安装失败：未找到 hysteria 命令"
    exit 1
  }

  log "已安装：$(hysteria version 2>/dev/null | head -n1)"
}

generate_password() {
  openssl rand -hex 12
  printf '\n'
}

generate_self_signed_cert() {
  mkdir -p "$CERT_DIR"
  if [[ ! -f "$CERT_KEY" || ! -f "$CERT_CRT" ]]; then
    log "生成自签证书"
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout "$CERT_KEY" \
      -out "$CERT_CRT" \
      -subj "/CN=${HY2_SNI}" >/dev/null 2>&1
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
SNI: ${HY2_SNI}
Insecure: true
证书类型: 自签证书
Shadowrocket / URI: hysteria2://${password}@${public_ip}:${PORT}?insecure=1&sni=${HY2_SNI}#Hysteria2

Clash / Mihomo YAML:
proxies:
  - name: Hysteria2-${public_ip}
    type: hysteria2
    server: ${public_ip}
    port: ${PORT}
    password: ${password}
    sni: ${HY2_SNI}
    skip-cert-verify: true
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
  install_hysteria2
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
