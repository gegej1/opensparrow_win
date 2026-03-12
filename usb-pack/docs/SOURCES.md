# Sources

## OpenClaw 官方

1. OpenClaw CLI 文档首页: https://docs.openclaw.ai/cli
2. OpenClaw Gateway 文档: https://docs.openclaw.ai/cli/gateway
3. OpenClaw Channels 文档: https://docs.openclaw.ai/cli/channels
4. OpenClaw Troubleshooting: https://docs.openclaw.ai/troubleshooting
5. OpenClaw Setup 文档: https://docs.openclaw.ai/cli/setup

## 飞书官方

1. 服务端 SDK / 长连接入口: https://open.feishu.cn/document/server-docs/server-side-sdk
2. 事件订阅说明: https://open.feishu.cn/document/home/introduction-to-event-subscription

## 系统与 U 盘执行限制（官方/高可信）

1. Microsoft AutoRun/AutoPlay 与策略说明: https://learn.microsoft.com/windows/win32/shell/autoplay-reg
2. Microsoft AutoRun 限制背景（Windows 安全策略相关）: https://learn.microsoft.com/security-updates/securityadvisories/2011/967940
3. Apple Gatekeeper 说明: https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web
4. Node.js 官方下载与发行目录: https://nodejs.org/en/download

## 结论摘要

- USB 自动执行在现代系统中不是默认可行路径。
- 交付方案应采用“手动运行入口脚本 + 明确验证步骤”的 SOP。
- Mac / Windows 应分别导出平台专属 handoff copy，并各自携带对应运行时。
- 对于 OpenClaw 场景，使用“隔离 profile + 独立端口 + 手动入口脚本”的本地部署路径是可行且可复刻的主路径。
