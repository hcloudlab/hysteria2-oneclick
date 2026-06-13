# Hysteria2 一键部署脚本

## 1. 项目用途

本项目用于在已经部署过 vpsguard 的 Ubuntu LTS 服务器上，自动化安装 Hysteria2 并完成基础服务配置。脚本会自动生成自签证书、随机认证密码、systemd 服务、客户端信息文件，并在终端输出可直接使用的客户端配置。

## 2. 适用环境

- Ubuntu LTS
- 已经部署过 vpsguard 的 VPS
- 需要无人值守安装 Hysteria2 的场景
- 需要保留现有 SSH、安全策略、fail2ban、UFW 基础策略的场景

## 3. 一键安装命令

```bash
bash install.sh
```

## 4. 查看状态命令

```bash
bash status.sh
```

## 5. 卸载命令

```bash
bash uninstall.sh
```

## 6. 客户端配置说明

安装完成后，客户端信息会保存到：

```bash
/root/hysteria2-client.txt
```

该文件中包含服务端地址、端口、密码、自签证书说明和示例客户端配置。Hysteria2 默认使用 `8443/udp`，并使用自签证书，因此客户端通常需要显式开启 `insecure: true`。

## 7. 为什么默认使用自签证书

默认使用自签证书的原因是为了实现完全无人值守安装。这样脚本不需要预先准备真实域名和证书，也不依赖外部 ACME 申请流程，适合快速部署和测试环境。

## 8. 客户端需要 insecure: true

因为自签证书没有受信任的公共 CA 链，客户端在连接时需要开启 `insecure: true` 才能跳过证书校验。

## 9. 常见故障排查

1. 服务起不来：先执行 `bash status.sh` 查看 systemd 状态和日志。
2. 端口不通：确认 `8443/udp` 是否已放行，检查云厂商安全组和本机 UFW。
3. 客户端连不上：确认客户端配置中的 `server`、`port`、`password` 是否与 `/root/hysteria2-client.txt` 一致。
4. 证书报错：自签证书属于预期行为，客户端需要启用 `insecure: true`。
5. 安装失败：检查 VPS 是否能够访问软件源，或是否存在旧的 Hysteria2 配置与服务残留。
