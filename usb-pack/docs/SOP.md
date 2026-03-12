# OpenClaw 本地 U 盘部署 SOP（v1）

## 目标

在不依赖 VPS 的前提下，把 OpenClaw + 飞书接入流程做成可复用的 U 盘交付包，实现“插入 U 盘后，手动执行入口脚本完成部署”，并确保不污染目标机器原有默认 OpenClaw 环境。

## 关键边界（先讲清楚）

- 现代操作系统默认不允许 USB 介质自动执行安装脚本。
- 可行路径是：用户插入 U 盘后手动双击或手动运行入口脚本。
- 因安全要求，密钥不能预置在 U 盘明文文件中，应在目标机运行时输入或注入环境变量。
- 本方案优先支持本地与 U 盘交付，不处理 VPS。

## 隔离策略

本方案默认使用：

- OpenClaw profile：`usb-portable`
- Isolated state：`~/.openclaw-usb-portable/`
- Isolated workspace：`~/.openclaw-usb-portable/workspace/`
- Dedicated gateway port：默认请求 `18889`，若占用会自动切换到下一个空闲端口
- Dedicated service：`ai.openclaw.usb-portable`

这可以避免和目标机器默认 `~/.openclaw/`、默认 `18789` 端口发生冲突。

## U 盘目录建议

```text
openclaw-usb-pack/
├── README.txt
├── docs/
├── mac/
├── windows/
├── runbooks/
├── scripts/
└── skills/
```

## 目标机器前置条件

1. 已联网。
2. 若直接从仓库/staging 运行，目标机需有 Node.js 和 npm；若使用 handoff copy，平台运行时已随包提供。
3. 可访问模型 API（官方或可用中转）。
4. 飞书应用已开通消息权限并启用 WebSocket 事件方式。
5. Windows 机器仅需可运行 PowerShell，不再依赖 Git Bash。

## macOS 执行步骤

1. 插入 U 盘，进入包目录。
2. 双击 `mac/run-openclaw-usb.command`。
3. 按提示输入：
   - `FEISHU_APP_ID`
   - `FEISHU_APP_SECRET`
   - `OPENAI_API_KEY`
   - `OPENAI_BASE_URL`（可选）
4. 等待脚本完成。
5. 验收：
   - `openclaw --profile usb-portable channels status --probe`
   - `openclaw --profile usb-portable agent --agent main --message "请只回复OK" --json`
   - 飞书给机器人发 `ok`

执行日志与证据默认落在包目录下的 `.openclaw-usb-runtime/`。

## Windows 执行步骤

1. 插入 U 盘，进入包目录。
2. 双击 `windows/run-openclaw-usb.cmd`。
3. `run-openclaw-usb.cmd` 会调用 `install-local-feishu.ps1`。
4. PowerShell 会提示输入：
   - `FEISHU_APP_ID`
   - `FEISHU_APP_SECRET`
   - `OPENAI_API_KEY`
   - `OPENAI_BASE_URL`（可选）
5. PowerShell 会直接执行包内 `scripts/openclaw-usb/install-local-feishu.ps1`，优先使用包内 Windows Node/OpenClaw 运行时。
6. 验收：
   - 若本机已安装全局 `openclaw`：`openclaw --profile usb-portable channels status --probe`
   - 若仅使用包内运行时：`runtime\node\node.exe runtime\openclaw\openclaw.mjs --profile usb-portable channels status --probe`
   - agent smoke 同理可替换为 `agent --agent main --message "请只回复OK" --json`

## 验收标准

- OpenClaw daemon 运行正常。
- Feishu 通道探测为 `works`。
- 本地 agent 文字回复成功。
- 若已进行人工联调，飞书端收到机器人回复。

## 失败排查

- `openclaw` 未安装：
  - 检查 npm 全局安装权限，改用 nvm 或自定义 npm prefix。
- Windows 入口双击后被策略拦截：
  - 右键以 PowerShell 运行，或在 PowerShell 中执行 `Set-ExecutionPolicy -Scope Process Bypass` 后再重试。
- Windows 包内运行时不可用：
  - 检查 `runtime\node\node.exe` 与 `runtime\openclaw\openclaw.mjs` 是否存在。
  - 若目标机架构不匹配（x64/arm64），重新导出对应架构包。
- 网关不健康：
  - 检查 `openclaw --profile usb-portable daemon status`。
  - 查看安装输出或 `session-metadata.txt`，确认脚本最终使用的是哪个端口。
  - 若需要固定端口，再手动用 `--port <free-port>` 重跑。
- 飞书不回复：
  - 检查是否有其他实例使用同一 app id。
  - 查看 `openclaw --profile usb-portable logs --follow --plain` 是否收到入站事件。
- 模型超时：
  - 检查 `OPENAI_BASE_URL` 与网络连通性。

## 安全与收口

首次联调可以临时使用：

- 仓库 / Bash 模式可直接使用下面的命令。
- Windows handoff copy 模式可直接双击 `windows/run-openclaw-usb.cmd`。

```bash
bash scripts/openclaw-usb/install-local-feishu.sh \
  --profile usb-portable \
  --port 18889 \
  --dm-policy open \
  --allow-from-json '["*"]' \
  --require-mention false
```

完成验证后立即收口：

- 仓库 / Bash 模式使用下列命令。
- Windows handoff copy 模式直接双击 `windows/harden-openclaw-usb.cmd`。

```bash
bash scripts/openclaw-usb/harden-local-feishu.sh \
  --profile usb-portable \
  --dm-policy pairing \
  --allow-from-json '[]' \
  --require-mention true
```

复验：

```bash
openclaw --profile usb-portable config get channels.feishu.dmPolicy
openclaw --profile usb-portable config get channels.feishu.allowFrom --json
openclaw --profile usb-portable channels status --probe
```

## 交付备注

- 不将任何真实密钥提交到仓库或固化到 U 盘文件。
- staging 交付包通过以下命令生成：
  - `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/build-delivery-pack.sh`
- Mac 专属 handoff copy：
  - `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/create-mac-handoff-copy.sh`
- Windows 专属 handoff copy：
  - `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/create-windows-handoff-copy.sh`
