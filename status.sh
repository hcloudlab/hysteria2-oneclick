#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/etc/hysteria/config.yaml"
CLIENT_FILE="/root/hysteria2-client.txt"
SERVICE_NAME="hysteria-server.service"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

get_port() {
  if [[ -f "$CONFIG_FILE" ]]; then
    awk -F: '/^listen:/ {gsub(/[[:space:]]/, "", $3); if ($3 != "") print $3; else print "443"; exit}' "$CONFIG_FILE"
  else
    printf '443\n'
  fi
}

main() {
  local port
  port="$(get_port)"

  printf "${BOLD}${GREEN}============================================================${NC}\n"
  printf "${BOLD}${GREEN}Hysteria2 状态检查${NC}\n"
  printf "${BOLD}${GREEN}============================================================${NC}\n"

  if command -v hysteria >/dev/null 2>&1; then
    info "Hysteria2 版本：$(hysteria version 2>/dev/null | head -n 1 || true)"
  else
    warn "未检测到 hysteria 命令。"
  fi

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      info "服务状态：active"
    else
      warn "服务状态：inactive 或 failed"
    fi

    systemctl status "$SERVICE_NAME" --no-pager || true
  else
    warn "未找到 systemd 服务：$SERVICE_NAME"
  fi

  printf "\n"
  info "当前配置端口：${port}/udp"

  if ss -ulpn | grep -q ":${port}"; then
    info "监听检查：检测到 ${port}/udp 正在监听。"
    ss -ulpn | grep ":${port}" || true
  else
    warn "监听检查：未检测到 ${port}/udp。"
    warn "请检查服务日志：journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
  fi

  printf "\n"
  if [[ -f "$CONFIG_FILE" ]]; then
    info "服务端配置文件存在：$CONFIG_FILE"
  else
    warn "服务端配置文件不存在：$CONFIG_FILE"
  fi

  printf "\n"
  if [[ -f "$CLIENT_FILE" ]]; then
    printf "${BOLD}${CYAN}============================================================${NC}\n"
    printf "${BOLD}${CYAN}📌 Hysteria2 客户端配置${NC}\n"
    printf "${BOLD}${CYAN}============================================================${NC}\n"
    cat "$CLIENT_FILE"
    printf "\n"
  else
    warn "未找到客户端配置文件：$CLIENT_FILE"
  fi
}

main "$@"
