# OpenClaw USB Portable Execution Workspace

本目录用于今晚“执行与打磨阶段”的所有实作资产，和主工作区中其他部署主题彻底隔离。

## 隔离原则

- 运行隔离：所有 OpenClaw 命令统一使用独立 profile，不碰默认 `~/.openclaw/`。
- 资产隔离：执行日志、证据、交付包、runbook 全部仅写入本目录。
- 文档隔离：本目录只承载本地/U 盘可迁移部署，不包含 Notion/VPS 相关内容。
- 包范围约束：导出包统一为 Feishu-only，不包含 Notion/VPS 资产。

## 目录说明

- `docs/`：执行阶段补充方案、平台差异、交付说明
- `docs/package-boundary.md`：导出包包含/排除范围
- `docs/windows-native-delivery.md`：Windows 原生 PowerShell 交付说明
- `evidence/`：脱敏后的 probe / status / smoke test 结果
- `logs/`：执行日志与会话记录
- `delivery-pack/mac/`：macOS 交付包入口
- `delivery-pack/windows/`：Windows 原生 PowerShell 交付包入口
- `scripts/`：执行阶段新增辅助脚本、handoff copy 构建脚本与共享 `lib/`
- `scripts/README.md`：脚本分层说明
- `runbooks/`：F-001 ~ F-004 的执行 runbook
- `export/`：对外拷贝副本与压缩包（Mac / Windows 分开导出）
- `export/README.md`：当前/历史导出物说明

## 约定的隔离 profile

- Profile 名称：`usb-portable`
- 实际隔离目录：`~/.openclaw-usb-portable/`
- 说明：OpenClaw CLI 的 `--profile usb-portable` 会把 `OPENCLAW_STATE_DIR` / `OPENCLAW_CONFIG_PATH` 隔离到该目录，不污染默认 profile。
