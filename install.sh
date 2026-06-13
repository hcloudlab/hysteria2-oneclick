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
PORT="${PORT:-443}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "请使用 root 执行：bash install.sh"
    err "如果你是普通 sudo 用户，请先执行：sudo -i"
    exit 1
  fi
}

check_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    err "无法识别系统：缺少 /etc/os-release"
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    err "当前系统不是 Ubuntu：${PRETTY_NAME:-unknown}"
    err "本脚本仅支持 Ubuntu LTS。"
    exit 1
  fi

  log "检测到系统：${PRETTY_NAME:-Ubuntu}"
}

install_dependencies() {
  log "安装基础依赖..."
  apt-get update -y
  apt-get install -y curl wget openssl ca-certificates jq iproute2
}

install_hysteria2() {
  if command -v hysteria >/dev/null 2>&1; then
    log "检测到 Hysteria2 已安装：$(hysteria version 2>/dev/null | head -n 1 || true)"
    return
  fi

  log "安装 Hysteria2..."
  bash <(curl -fsSL https://get.hy2.sh/)
}

generate_password() {
  openssl rand -base64 24 | tr -d '\n'
}

get_public_ip() {
  local ip=""

  ip="$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsSL https://ifconfig.me 2>/dev/null || true)"
  fi

  if [[ -z "$ip" ]]; then
    err "无法获取服务器公网 IPv4。"
    exit 1
  fi

  printf '%s\n' "$ip"
}

backup_existing_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local backup_file
    backup_file="${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    warn "检测到已有配置文件，已备份为：$backup_file"
  fi
}

generate_self_signed_cert() {
  log "生成自签 TLS 证书..."
  mkdir -p "$CERT_DIR"

  if [[ -f "$CERT_KEY" && -f "$CERT_CRT" ]]; then
    warn "检测到已有证书，继续复用：$CERT_CRT"
    return
  fi

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$CERT_KEY" \
    -out "$CERT_CRT" \
    -days 3650 \
    -subj "/CN=bing.com" >/dev/null 2>&1

  chmod 600 "$CERT_KEY"
  chmod 644 "$CERT_CRT"
}

write_config() {
  local password="$1"

  log "写入 Hysteria2 服务端配置：$CONFIG_FILE"
  mkdir -p "$CONFIG_DIR"

  cat > "$CONFIG_FILE" <<EOF
listen: :${PORT}

tls:
  cert: ${CERT_CRT}
  key: ${CERT_KEY}

auth:
  type: password
  password: ${password}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

  chmod 600 "$CONFIG_FILE"
}

write_systemd_service() {
  log "写入 systemd 服务：$SERVICE_FILE"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Hysteria2 Server Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c ${CONFIG_FILE}
WorkingDirectory=${CONFIG_DIR}
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable hysteria-server.service >/dev/null
}

configure_ufw() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
      log "UFW 已启用，放行 ${PORT}/udp..."
      ufw allow "${PORT}/udp" >/dev/null
      ufw reload >/dev/null || true
    else
      warn "UFW 未启用，跳过防火墙规则添加。"
    fi
  else
    warn "未检测到 UFW，跳过防火墙配置。"
  fi
}

restart_service() {
  log "启动 Hysteria2 服务..."
  systemctl restart hysteria-server.service
  sleep 2

  if ! systemctl is-active --quiet hysteria-server.service; then
    err "Hysteria2 服务启动失败。"
    err "请查看日志：journalctl -u hysteria-server.service -n 100 --no-pager"
    exit 1
  fi
}

verify_listening() {
  log "检查 UDP 端口监听状态..."
  if ss -ulpn | grep -q ":${PORT}"; then
    log "Hysteria2 正在监听 ${PORT}/udp。"
  else
    warn "未在 ss 输出中检测到 ${PORT}/udp。"
    warn "请手动检查：sudo ss -ulpn | grep ':${PORT}'"
  fi
}

write_client_file() {
  local password="$1"
  local public_ip="$2"

  cat > "$CLIENT_FILE" <<EOF
============================================================
Hysteria2 客户端配置
============================================================
协议: Hysteria2
服务器: ${public_ip}
端口: ${PORT}/udp
认证密码: ${password}
TLS: self-signed
insecure: true

============================================================
最终客户端 YAML，请复制到客户端使用
============================================================
server: ${public_ip}:${PORT}
auth: ${password}
tls:
  insecure: true
EOF

  chmod 600 "$CLIENT_FILE"

  printf "${BOLD}${GREEN}============================================================${NC}\n"
  printf "${BOLD}${GREEN}✅ Hysteria2 部署完成${NC}\n"
  printf "${BOLD}${GREEN}============================================================${NC}\n"
  printf "${YELLOW}协议：Hysteria2${NC}\n"
  printf "${YELLOW}服务器 IP：%s${NC}\n" "$public_ip"
  printf "${YELLOW}UDP 端口：%s${NC}\n" "$PORT"
  printf "${YELLOW}认证密码：%s${NC}\n" "$password"
  printf "${YELLOW}TLS 类型：self-signed，自签证书${NC}\n"
  printf "${YELLOW}客户端需要：insecure: true${NC}\n"
  printf "${YELLOW}服务端配置：%s${NC}\n" "$CONFIG_FILE"
  printf "${YELLOW}客户端配置保存路径：%s${NC}\n" "$CLIENT_FILE"
  printf "\n"
  printf "${BOLD}${CYAN}============================================================${NC}\n"
  printf "${BOLD}${CYAN}📌 最终客户端配置，请复制到客户端使用${NC}\n"
  printf "${BOLD}${CYAN}============================================================${NC}\n"
  printf "${CYAN}server: %s:%s${NC}\n" "$public_ip" "$PORT"
  printf "${CYAN}auth: %s${NC}\n" "$password"
  printf "${CYAN}tls:${NC}\n"
  printf "${CYAN}  insecure: true${NC}\n"
  printf "\n"
  printf "${BOLD}${GREEN}客户端配置已保存到：%s${NC}\n" "$CLIENT_FILE"
}

print_management_commands() {
  printf "\n"
  printf "${BOLD}${GREEN}============================================================${NC}\n"
  printf "${BOLD}${GREEN}常用管理命令${NC}\n"
  printf "${BOLD}${GREEN}============================================================${NC}\n"
  printf "${YELLOW}查看服务状态：${NC}systemctl status hysteria-server.service --no-pager\n"
  printf "${YELLOW}查看运行日志：${NC}journalctl -u hysteria-server.service -n 100 --no-pager\n"
  printf "${YELLOW}查看监听端口：${NC}ss -ulpn | grep ':${PORT}'\n"
  printf "${YELLOW}查看客户端配置：${NC}cat ${CLIENT_FILE}\n"
}

main() {
  local password
  local public_ip

  require_root
  check_ubuntu
  install_dependencies
  install_hysteria2

  password="$(generate_password)"
  public_ip="$(get_public_ip)"

  backup_existing_config
  generate_self_signed_cert
  write_config "$password"
  write_systemd_service
  configure_ufw
  restart_service
  verify_listening
  write_client_file "$password" "$public_ip"
  print_management_commands
}

main "$@"
EOF
