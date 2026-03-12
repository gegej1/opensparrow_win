# OpenClaw 本地 / U 盘可迁移部署方案（执行与打磨版）

## 目标

本方案只解决一件事：把 OpenClaw + 飞书 WebSocket + OpenAI 兼容模型链路，做成一个可在新机器上重复执行、可打包到 U 盘交付、且不污染现有默认环境的本地部署包。

## 与主工作区的隔离原则

本方案与主工作区中 Notion / VPS / 其他部署主题强隔离：

1. 功能隔离：本目录只处理本地与 U 盘交付，不触碰 Notion 联动流程。
2. 运行隔离：所有执行统一使用 `openclaw --profile usb-portable`。
3. 状态隔离：配置、state、agent auth、workspace、service、gateway port 全部隔离。
4. 证据隔离：日志、probe、smoke test、交付包 staging 全部写到本目录。
5. 导出边界隔离：对外导出副本只保留 Feishu 本地/U 盘部署资产，不混入 Notion/VPS 内容。

## 我们隔离的是什么

- OpenClaw profile：`usb-portable`
- OpenClaw state/config：`~/.openclaw-usb-portable/`
- OpenClaw config file：`~/.openclaw-usb-portable/openclaw.json`
- Agent auth：`~/.openclaw-usb-portable/agents/main/agent/auth-profiles.json`
- Agent workspace：`~/.openclaw-usb-portable/workspace/`
- Gateway service label：`ai.openclaw.usb-portable`
- Gateway port：默认请求 `18889`，若占用则自动回退到下一个空闲端口
- 执行日志：`longrun/workspaces/openclaw-usb-portable/execution/logs/`
- 验证证据：`longrun/workspaces/openclaw-usb-portable/execution/evidence/`
- U 盘 staging 包：`longrun/workspaces/openclaw-usb-portable/execution/delivery-pack/staged/openclaw-usb-pack/`

## 仍然共享的东西

- 全局 `openclaw` CLI 二进制本身可能复用机器已安装版本。
- 全局 `node` / `npm` 复用系统已有安装。
- 这意味着“工具链共享”，但“运行时状态隔离”。

## 交付件拆分

### 1. 源资产

- 安装脚本：`scripts/openclaw-usb/install-local-feishu.sh`
- 收口脚本：`scripts/openclaw-usb/harden-local-feishu.sh`
- Skill：`skills/openclaw-local-feishu-usb/SKILL.md`
- SOP：`research/openclaw-usb-installer/SOP.md`
- 来源：`research/openclaw-usb-installer/SOURCES.md`

### 2. 执行资产

- 方案文档：`longrun/workspaces/openclaw-usb-portable/execution/docs/`
- Runbook：`longrun/workspaces/openclaw-usb-portable/execution/runbooks/`
- 本机联调辅助脚本：`longrun/workspaces/openclaw-usb-portable/execution/scripts/`
- 交付包模板：`longrun/workspaces/openclaw-usb-portable/execution/delivery-pack/`

### 3. 最终 U 盘包

最终通过 build 脚本组装出一个独立目录：

```text
openclaw-usb-pack/
├── README.txt
├── docs/
│   ├── SOP.md
│   ├── SOURCES.md
│   ├── isolation-boundary.md
│   └── solution-architecture.md
├── mac/
│   ├── run-openclaw-usb.command
│   └── harden-openclaw-usb.command
├── windows/
│   ├── run-openclaw-usb.cmd
│   ├── install-local-feishu.ps1
│   └── harden-local-feishu.ps1
├── runbooks/
│   ├── F-001-install-and-configure.md
│   ├── F-002-skill-polish.md
│   ├── F-003-usb-delivery-pack.md
│   └── F-004-security-hardening.md
├── scripts/
│   └── openclaw-usb/
│       ├── install-local-feishu.sh
│       └── harden-local-feishu.sh
└── skills/
    └── openclaw-local-feishu-usb/
        └── SKILL.md
```


## 导出范围约束

- Mac / Windows 导出包统一采用 **Feishu-only** 范围。
- Notion 相关 specs / scripts / research 不进入导出副本。
- 如果需要源码参考，只附带 002 USB/Feishu 本地部署相关文件，不附带 003 Notion 集成资产。
- 导出公共逻辑统一收敛到 `execution/scripts/lib/export-common.sh`，平台脚本只保留平台差异。

## 平台策略

### macOS

- 主入口：`.command` 文件
- 运行方式：手动双击或 Terminal 执行
- 说明：不绕过 Gatekeeper，不做 USB 自动执行

### Windows

- 主入口：`.cmd` 调起原生 PowerShell
- 安装逻辑：PowerShell 直接执行 `scripts/openclaw-usb/install-local-feishu.ps1`
- 运行时：Windows handoff copy 内置 `runtime/node/node.exe` 与 `runtime/openclaw/openclaw.mjs`
- 打包方式：使用独立 `create-windows-handoff-copy.sh` 生成 Windows 专属副本
- 说明：不绕过 AutoRun / AutoPlay 策略，不做自动执行

## 执行顺序

1. 先在 macOS 本机用隔离 profile 完成 F-001 实跑。
2. 基于实跑结果补证据、补 Skill、补 SOP。
3. 组装 U 盘交付包。
4. 完成 F-004 收口命令与复验。
5. Windows 入口、原生脚本与平台专属导出包同日补齐；若无 Windows 主机，先完成静态交付资产。

## 验收输出

每次 F-001 实跑必须至少产出：

- `config-validate.json`
- `health.json`
- `daemon-status.txt`
- `channels-probe.json`
- `agent-smoke.json`
- `session-metadata.txt`
- 安装日志文件

## 今晚完成标准

- macOS：实机完成一次隔离安装与 probe/agent 验证
- Windows：原生 PowerShell 入口、平台专属导出包与说明补齐
- 文档：Skill / SOP / spec / plan / tasks / longrun 全部同步
- 交付：staging 包可直接拷到 U 盘
