# Windows Native Delivery Notes

## 目标

为 Windows 目标机提供一份 **Feishu-only**、**原生 PowerShell**、**可拷贝到 U 盘** 的 OpenClaw 本地部署包。

## 交付边界

- 只包含 OpenClaw + Feishu 本地/U 盘部署内容。
- 不包含 Notion、VPS、知识检索、群聊归档等其他主题。
- 不绕过 AutoRun / AutoPlay。
- 不预置真实密钥；密钥仅在目标机运行时输入。

## 运行时策略

- 入口：`windows/run-openclaw-usb.cmd`
- 实际执行：`windows/install-local-feishu.ps1`
- 主逻辑：`scripts/openclaw-usb/install-local-feishu.ps1`
- bundled runtime：
  - `runtime/node/node.exe`
  - `runtime/openclaw/openclaw.mjs`

## 默认隔离

- profile：`usb-portable`
- state：`%USERPROFILE%\.openclaw-usb-portable\`
- workspace：`%USERPROFILE%\.openclaw-usb-portable\workspace\`
- gateway port：优先使用 `18889`，若占用则自动回退到下一个空闲端口

## 导出方式

在仓库根目录执行：

```bash
bash longrun/workspaces/openclaw-usb-portable/execution/scripts/create-windows-handoff-copy.sh
```

默认导出：

- 目录：`longrun/workspaces/openclaw-usb-portable/execution/export/windows-feishu-usb-copy-*/`
- 压缩包：同名 `.zip`

## 目标机使用方式

1. 把 `usb-pack/` 整个目录拷到 Windows 本地磁盘。
2. 双击 `windows/run-openclaw-usb.cmd`。
3. 输入：
   - `FEISHU_APP_ID`
   - `FEISHU_APP_SECRET`
   - `OPENAI_API_KEY`
   - `OPENAI_BASE_URL`（可选）
4. 等待脚本完成。
5. 联调后运行 `windows/harden-openclaw-usb.cmd` 收口权限。

## 当前状态

- 设计与脚本已完成到“可交付”级别。
- 当前仓库在 macOS 上完成了路径与隔离验证。
- Windows 方案尚未在真实 Windows 主机完成实机验收，交付前建议补一次主机验证。
