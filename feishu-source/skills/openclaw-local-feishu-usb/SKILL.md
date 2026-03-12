---
name: openclaw-local-feishu-usb
description: 使用隔离 profile + U 盘交付包在本地机器部署 OpenClaw 并接入飞书（WebSocket 长连接），包含安装、验证、排障、收口与交付打包流程。
---

# OpenClaw Local Feishu USB Skill

## 适用场景

- 目标是本地部署 OpenClaw，不涉及 VPS。
- 需要接入飞书并使用 WebSocket 事件模式。
- 需要把流程做成 U 盘可交付包，并避免污染目标机器现有默认 OpenClaw 环境。

## 输入前置

- 机器已联网。
- 源码模式需要已安装 `node`、`npm`、`curl`。
- handoff copy 模式自带平台运行时：macOS 内置 `runtime/node/bin/node`，Windows 内置 `runtime/node/node.exe`。
- macOS 直接运行 Bash；Windows 使用原生 PowerShell 入口，不依赖 Git Bash。
- 飞书应用信息：`FEISHU_APP_ID`、`FEISHU_APP_SECRET`。
- 模型密钥：`OPENAI_API_KEY`。
- 可选：`OPENAI_BASE_URL`（用于非直连 OpenAI 场景）。

## 隔离原则

本 Skill 默认使用以下隔离设置：

- Profile：`usb-portable`
- State：`~/.openclaw-usb-portable/`
- Workspace：`~/.openclaw-usb-portable/workspace/`
- Gateway port：默认 `18889`，若被占用会自动回退到下一个空闲端口
- Service label：`ai.openclaw.usb-portable`

这意味着它不会覆盖默认 `~/.openclaw/` 与默认 `18789` 端口的服务。

## 标准执行流程

1. 准备变量（不写入仓库）：
   - `export FEISHU_APP_ID=...`
   - `export FEISHU_APP_SECRET=...`
   - `export OPENAI_API_KEY=...`
   - `export OPENAI_BASE_URL=...`（可选）
2. 执行安装脚本：
   - macOS / Bash：`bash scripts/openclaw-usb/install-local-feishu.sh --profile usb-portable --port 18889`
   - Windows / PowerShell：`powershell -ExecutionPolicy Bypass -File scripts/openclaw-usb/install-local-feishu.ps1 -Profile usb-portable -Port 18889`
3. 验证网关：
   - `openclaw --profile usb-portable health --json`
4. 验证通道：
   - `openclaw --profile usb-portable channels status --probe`
5. 验证模型链路：
   - `openclaw --profile usb-portable agent --agent main --message "请只回复OK" --json`
6. 飞书实测：
   - 给机器人发送 `ok`，确认收到回复。
7. 收口：
   - macOS / Bash：`bash scripts/openclaw-usb/harden-local-feishu.sh --profile usb-portable --dm-policy pairing --allow-from-json '[]' --require-mention true`
   - Windows / PowerShell：`powershell -ExecutionPolicy Bypass -File scripts/openclaw-usb/harden-local-feishu.ps1 -Profile usb-portable -DmPolicy pairing -AllowFromJson '[]' -RequireMention true`

## 证据要求

执行后至少保留以下文件：

- `config-validate.json`
- `health.json`
- `daemon-status.txt`
- `channels-probe.json`
- `agent-smoke.json`
- `session-metadata.txt`
- 安装日志 `install-*.log`

默认输出目录：

- 仓库内实跑：`longrun/workspaces/openclaw-usb-portable/execution/evidence/`
- 脱离仓库的 handoff copy：包内 `.openclaw-usb-runtime/evidence/`

## 验证标准

- `openclaw --profile usb-portable daemon status` 显示 `Runtime: running`。
- `openclaw --profile usb-portable channels status --probe` 显示 `feishu ... works`。
- `openclaw --profile usb-portable agent ...` 返回 `status: ok`。
- 收口后 `dmPolicy=pairing` 或 `allowlist`，且 `allowFrom` 不再是 `[*]`。

## 排障要点

- `No API key found`：
  - 检查 `OPENAI_API_KEY` 是否为空，是否误写成 `key:sk-...`。
  - 检查 `~/.openclaw-usb-portable/agents/main/agent/auth-profiles.json` 是否存在。
- 网关连不上：
  - 检查 `openclaw --profile usb-portable daemon status`。
  - 检查 `gateway port` 是否为安装输出或 `session-metadata.txt` 中记录的实际端口。
- 端口冲突：
  - 安装脚本会默认从请求端口开始自动扫描下一个空闲端口。
  - 如需固定端口，仍可显式改用 `--port <free-port>`。
- 飞书事件未入站：
  - 检查飞书后台是否为 WebSocket 模式并已发布版本。
  - 检查是否有其他实例共用同一飞书应用。
- 模型调用超时：
  - 检查目标 `OPENAI_BASE_URL` 连通性。
  - 若是网络限制，改用可用中转。

## U 盘打包建议

- 用以下命令组装 staging 包：
  - `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/build-delivery-pack.sh`
- 生成 Mac handoff copy：
  - `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/create-mac-handoff-copy.sh`
- 生成 Windows handoff copy：
  - `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/create-windows-handoff-copy.sh`
- staging 输出目录：
  - `longrun/workspaces/openclaw-usb-portable/execution/delivery-pack/staged/openclaw-usb-pack/`
- 从 U 盘手动运行脚本，不依赖 USB 自动执行。
