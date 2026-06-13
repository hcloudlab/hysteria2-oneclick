#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="hysteria-server.service"
CONFIG_DIR="/etc/hysteria"
CLIENT_FILE="/root/hysteria2-client.txt"
BINARY="/usr/local/bin/hysteria"

log() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "请使用 root 执行：bash uninstall.sh" >&2
  exit 1
fi

log "停止并禁用服务"
systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true

log "删除 systemd 服务文件"
rm -f "/etc/systemd/system/${SERVICE}"
systemctl daemon-reload

log "删除配置目录"
rm -rf "$CONFIG_DIR"

log "删除二进制"
rm -f "$BINARY"

log "保留客户端文件以便审计：$CLIENT_FILE"
log "卸载完成"
