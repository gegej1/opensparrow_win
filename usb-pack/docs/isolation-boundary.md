# 隔离边界说明

## 为什么只做 profile 隔离还不够

如果只加 `--profile usb-portable`，OpenClaw 的默认网关端口仍可能是 `18789`，会和本机已存在的默认服务冲突。

因此本方案采用“五层隔离”：

1. Profile 隔离：`openclaw --profile usb-portable`
2. 配置/状态隔离：`~/.openclaw-usb-portable/`
3. Workspace 隔离：`~/.openclaw-usb-portable/workspace/`
4. Service 隔离：`ai.openclaw.usb-portable`
5. Gateway 端口隔离：默认 `18889`

## 不会碰到的默认资产

- 默认 profile：`~/.openclaw/`
- 默认 config：`~/.openclaw/openclaw.json`
- 默认 agent auth：`~/.openclaw/agents/main/agent/auth-profiles.json`
- 默认 service：`ai.openclaw.gateway`
- 默认端口：`18789`

## 例外

以下内容仍属于共享系统依赖，不在 profile 隔离范围内：

- `node`
- `npm`
- `openclaw` 可执行文件

如果系统没有安装这些依赖，安装脚本会先检查并在缺失时报错或安装 CLI。
