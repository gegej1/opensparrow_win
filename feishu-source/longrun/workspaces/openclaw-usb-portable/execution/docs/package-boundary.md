# Package Boundary: Feishu-Only

## 目的

本交付包只服务于一个目标：

- OpenClaw 本地部署
- Feishu WebSocket 接入
- U 盘手动交付与安装

不承载 Notion、VPS、群聊归档、知识检索或其他扩展主题。

## 允许打包的内容

- `scripts/openclaw-usb/`
- `skills/openclaw-local-feishu-usb/`
- `research/openclaw-usb-installer/`
- `specs/002-openclaw-usb-installer/`
- `longrun/workspaces/openclaw-usb-portable/` 中与 USB/Feishu 本地部署直接相关的说明、runbook、导出脚本
- 包内运行时：`runtime/node/`、`runtime/openclaw/`
- 包运行时临时数据：包目录下 `.openclaw-usb-runtime/`

## 明确排除的内容

- `research/openclaw-feishu-notion/`
- `scripts/openclaw-notion/`
- `specs/003-feishu-notion-sync/`
- 与 Notion 归档、检索、问答、引用回复相关的任何脚本或文档
- VPS / Hetzner / 远程部署资产
- 本机 `.env`、密钥、会话数据、默认 `~/.openclaw/` 状态

## 平台统一规则

无论导出给 macOS 还是 Windows，交付包都必须遵循同一条边界：

- 只包含 Feishu 本地 / U 盘部署资产
- 不额外混入 Notion / VPS / 其他主题的仓库内容

## 判断标准

如果某个文件不是为“明天在目标机器上安装 OpenClaw + Feishu”服务，就不应进入导出包。
