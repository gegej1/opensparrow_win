# Implementation Plan: OpenClaw U 盘本地部署 Skill + 脚本

**Branch**: `002-openclaw-usb-installer` | **Date**: 2026-03-09 | **Spec**: `specs/002-openclaw-usb-installer/spec.md`  
**Input**: Feature specification from `specs/002-openclaw-usb-installer/spec.md`

## Summary

将当前已跑通的本地 OpenClaw + 飞书接入流程沉淀为五类交付件：

1. 一份可复用 Skill（面向团队执行一致性）。
2. 一份本地安装脚本（面向新机器快速落地）。
3. 一份收口脚本（面向联调后安全收敛）。
4. 一份 U 盘执行 SOP + 双平台入口（面向推广和交付）。
5. 一套 execution 工作区（面向今晚执行、证据、日志与 staging 包管理）。

## Technical Context

**Language/Version**: Bash + PowerShell + Markdown  
**Primary Dependencies**: `openclaw` CLI, `node`, `npm`, `curl`, `jq`  
**Storage**: 文档与脚本文件（仓库内）+ 执行证据目录  
**Testing**: 命令行验证（`health` / `channels status --probe` / `agent` / `daemon status`）  
**Target Platform**: macOS（实跑） / Windows（原生 PowerShell 交付） / Linux（Bash 兼容）  
**Project Type**: 文档 + 运维脚本 + 交付包模板  
**Performance Goals**: 单机安装配置在 20 分钟内完成  
**Constraints**: 不落地真实密钥；不依赖 VPS；优先可复刻；必须隔离默认 profile  
**Scale/Scope**: 1 个 skill + 2 个脚本 + 1 套 SOP + 1 套 longrun execution 资产

## Constitution Check

- 文档先行：`spec.md` / `plan.md` / `tasks.md` 已完成并继续同步。✅
- 可复现验证：每个阶段都给出可执行验证命令与证据目录。✅
- 安全约束：全部密钥使用占位符、运行时输入或本机临时迁移，不写入仓库。✅
- 对外可读变更记录：同步更新 `README.md`。✅

## Project Structure

### Documentation (this feature)

```text
specs/002-openclaw-usb-installer/
├── spec.md
├── plan.md
└── tasks.md

research/openclaw-usb-installer/
├── SOP.md
└── SOURCES.md
```

### Source Code (repository root)

```text
skills/openclaw-local-feishu-usb/
└── SKILL.md

scripts/openclaw-usb/
├── install-local-feishu.sh
├── install-local-feishu.ps1
├── harden-local-feishu.sh
└── harden-local-feishu.ps1

longrun/workspaces/openclaw-usb-portable/
├── app_spec.md
├── feature_list.json
├── claude-progress.txt
├── init.sh
└── execution/
    ├── README.md
    ├── docs/
    │   └── windows-native-delivery.md
    ├── delivery-pack/
    ├── evidence/
    ├── logs/
    ├── runbooks/
    └── scripts/
        ├── build-delivery-pack.sh
        ├── create-mac-handoff-copy.sh
        └── create-windows-handoff-copy.sh
```

**Structure Decision**: 文档放 `specs/` + `research/`；可执行资产放 `skills/` 与 `scripts/`；执行期临时与交付资产全部隔离在 `longrun/workspaces/openclaw-usb-portable/execution/`。

## Execution Notes

- 默认 profile：`usb-portable`
- 默认 port：`18889`
- 默认 workspace：`~/.openclaw-usb-portable/workspace/`
- 默认服务标签：`ai.openclaw.usb-portable`
- 默认 staging 包输出：`longrun/workspaces/openclaw-usb-portable/execution/delivery-pack/staged/openclaw-usb-pack/`

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Bash + PowerShell scripts | macOS 保持 Bash 主线，Windows 需要原生 PowerShell 入口与独立运行时 | 只保留 Bash 会导致 Windows 交付入口不完整 |
| Execution workspace | 今晚执行、日志、证据、交付包必须和主工作区其他主题强隔离 | 直接混放到 `research/` / `scripts/` 会和 Notion/VPS 方案混杂 |
