# Implementation Plan: OpenSparrow UI 安装态判定与全量清理

**Branch**: `003-opensparrow-ui-reset-hardening` | **Date**: 2026-03-10 | **Spec**: `specs/003-opensparrow-ui-reset-hardening/spec.md`  
**Input**: Feature specification from `specs/003-opensparrow-ui-reset-hardening/spec.md`

## Summary

本特性修复“UI-first 部署链路”的三个结构性问题：

1. `/api/status` 误判 daemon 为 running，导致安装态假阳性。
2. “清理旧环境”仅停进程不清状态目录，导致无法回到初始安装态。
3. 入口与文档存在旧 CLI 交互链路，和网页部署流程冲突。

目标是让“新机首次部署”和“已部署后重置再部署”都可稳定回到安装向导，并把清理范围做成可审计的明确边界。

## Technical Context

**Language/Version**: Node.js ESM + Vanilla JS + Markdown  
**Primary Dependencies**: bundled `openclaw` CLI, bundled Node runtime  
**Storage**: `~/.openclaw-<profile>`、service manager artifacts、`~/.claude/.codex` skills copies  
**Testing**: API 回归测试（`/api/status`, `/api/cleanup`, reset endpoint）+ 命令行 dry-run 校验  
**Target Platform**: macOS / Windows USB handoff copy  
**Project Type**: Local UI backend + frontend behavior + delivery scripts/docs  
**Performance Goals**: 清理接口在 30s 内返回；状态接口在 3s 内返回  
**Constraints**: 不误删非 profile 资产；不依赖交互式终端输入；保持离线可运行

## Constitution Check

- 文档先行：本 feature 已先补 `spec.md`/`plan.md`/`tasks.md`。✅
- 可复现验证：保留调查命令与回归命令清单。✅
- 安全约束：不引入明文密钥，不扩散到默认 profile。✅
- CLI 必须有超时：接口调用 `runOc` 保持超时与非交互策略。✅

## Investigation Conclusions (Validated)

1. **状态误判根因**  
   `server.mjs` 读取 `daemon status --json` 时用 `parsed.status ?? 'running'`。当前 OpenClaw JSON 没有顶层 `status`，因此落入 `'running'` 假阳性。

2. **无法回到安装向导根因**  
   当前清理接口仅 stop/uninstall + 端口清理，不删除 `~/.openclaw-<profile>`；残留配置仍会参与安装态判断。

3. **入口冲突根因**  
   仍存在旧 CLI 入口会提示 `FEISHU_APP_ID` 等交互输入（mac 的 legacy 脚本可被直接调用、Windows 顶层入口当前仍默认走 CLI）；与 UI-first 目标冲突。

4. **“硬编码”观感根因**  
   并非前端硬编码，而是 profile 残留配置被 Dashboard 读取并展示，形成“新机也有旧值”的现象。

## Proposed Design

### A. 安装态状态机重构

- 在 `/api/status` 中解析 `service.runtime.status` 与 `service.command`：
  - `running`：仅当 runtime/status 真正运行；
  - `stopped`：service 配置存在但未运行；
  - `not_installed`：service 配置不存在；
  - `unknown`：无法判定。
- `installed` 从布尔改为“部署完成态”：
  - 最低门槛：daemon `running` + profile 配置存在；
  - 进阶门槛（可选）：关键字段完整（channel/API/auth）。

### B. 清理能力分层

- 保留“轻量清理”用于端口抢占场景（当前 cleanupOldDaemon）。
- 新增“全量重置”接口（Factory Reset）：
  - 调用 `openclaw uninstall --service --state --workspace --yes --non-interactive`；
  - 可选删除 `~/.claude/skills/superpowers` / `~/.codex/skills/superpowers`；
  - 返回删除清单与失败原因。

### C. 前端行为修正

- Dashboard 增加“全量重置”按钮（危险操作样式 + 二次确认）。
- 重置成功后强制跳转 `/?force=1`。
- 安装页跳转条件只基于修正后的状态机输出。

### D. 入口与文档收敛

- 顶层入口统一 UI-first，旧 CLI 入口降级为“高级/兼容入口”并在文档标注。
- README/SOP 明确推荐入口与重置流程。

## Validation Strategy

1. **状态判定回归**
   - profile 仅有配置文件；
   - profile 服务已 stop；
   - profile 服务已 uninstall；
   - profile 服务 running。

2. **重置回归**
   - 重置后 `~/.openclaw-<profile>` 不存在；
   - `/api/status.installed=false`；
   - 页面刷新回安装向导；
   - 重装后流程正常。

3. **入口回归**
   - 双击 `01-开始部署.command` 不再出现 CLI 凭据提示；
   - 文档路径与实际入口一致。

## Complexity Tracking

| Decision | Why Needed | Simpler Alternative Rejected Because |
|----------|------------|--------------------------------------|
| 状态机从单字段判断改为多字段判断 | OpenClaw JSON 结构变化，单字段不可靠 | 继续用 `parsed.status` 会持续假阳性 |
| 新增“全量重置”而非复用“清理旧环境” | 端口清理与环境重置语义不同 | 一个按钮承载两种语义会误导用户 |
| 使用 `openclaw uninstall` 命令驱动删除 | 覆盖 service/state/workspace 跨平台路径 | 手写 `rm`/`taskkill` 易漏路径且风险高 |
