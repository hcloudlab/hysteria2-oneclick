#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="hysteria-server.service"
CONFIG_FILE="/etc/hysteria/config.yaml"
CLIENT_FILE="/root/hysteria2-client.txt"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "请使用 root 执行：bash status.sh" >&2
  exit 1
fi

printf '\033[1;34mHysteria2 状态检查\033[0m\n'
systemctl status "$SERVICE" --no-pager || true

printf '\n\033[1;34m配置文件\033[0m\n'
if [[ -f "$CONFIG_FILE" ]]; then
  ls -l "$CONFIG_FILE"
else
  echo "未找到配置文件：$CONFIG_FILE"
fi

printf '\n\033[1;34m客户端文件\033[0m\n'
if [[ -f "$CLIENT_FILE" ]]; then
  ls -l "$CLIENT_FILE"
else
  echo "未找到客户端文件：$CLIENT_FILE"
fi
