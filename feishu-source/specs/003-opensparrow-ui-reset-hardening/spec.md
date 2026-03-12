# Feature Specification: OpenSparrow UI 安装态判定与全量清理

**Feature Branch**: `003-opensparrow-ui-reset-hardening`  
**Created**: 2026-03-10  
**Status**: Draft (Investigation Complete, Implementation Pending)  
**Input**: 用户反馈“新机点击开始部署后仍可能跳 Dashboard、配置看似被硬编码、清理按钮无法真正回到初始状态”。

## User Scenarios & Testing

### User Story 1 - 新机必须停留在安装向导 (Priority: P1)

作为交付对象，我在一台新机器首次双击入口后，必须停留在安装向导页面，而不是自动跳 Dashboard。

**Why this priority**: 这是 OpenSparrow 的首屏核心体验，错误跳转会导致“未配置却显示已部署”的认知错误。

**Independent Test**: 使用仅有 `openclaw.json`（无有效 daemon）的 profile，访问 `/api/status` 应返回 `installed=false`，前端不跳 `/dashboard`。

**Acceptance Scenarios**:
1. **Given** 仅存在配置文件但 daemon 未运行，**When** 打开 `/`，**Then** 停留安装向导。
2. **Given** daemon 真正运行且配置完整，**When** 打开 `/`，**Then** 才自动跳 `/dashboard`。
3. **Given** URL 包含 `?force=1` 或路径 `/setup`，**When** 打开页面，**Then** 强制停留安装向导。

---

### User Story 2 - 清理必须是“可回到未安装态” (Priority: P1)

作为运维/实施人员，我希望点击“清理”后可以回到可重新部署的未安装状态，而不是只停进程。

**Why this priority**: 当前“清理后仍跳 Dashboard”会造成循环故障，阻断重装与交付。

**Independent Test**: 执行清理后，`~/.openclaw-<profile>` 不存在，`/api/status.installed=false`，刷新后进入安装向导。

**Acceptance Scenarios**:
1. **Given** 已部署 profile，**When** 触发全量清理，**Then** 服务、状态目录、workspace 均被移除。
2. **Given** 执行全量清理后，**When** 刷新页面，**Then** 进入安装向导而不是 Dashboard。
3. **Given** 端口被其他进程占用，**When** 清理执行，**Then** 返回明确错误与下一步指引。

---

### User Story 3 - 入口链路必须统一到 UI-first (Priority: P1)

作为终端用户，我双击“开始部署”后应进入可视化部署流程，不再被命令行逐项询问凭据。

**Why this priority**: UI-first 是当前产品定位；命令行问答会与网页表单形成冲突。

**Independent Test**: 双击顶层入口不再打印 `FEISHU_APP_ID:` 等交互提示，直接启动 UI。

**Acceptance Scenarios**:
1. **Given** 使用 `mac/01-开始部署.command`，**When** 启动，**Then** 直接进入 UI 服务与浏览器页面。
2. **Given** 文档入口说明，**When** 用户按文档操作，**Then** 不会误走旧 CLI 交互入口。

### Edge Cases

- `daemon status --json` 输出中不存在顶层 `status` 字段（仅有 `service.runtime.status`）。
- 配置文件存在但仅是残留/半配置，不应被判定为“已安装完成”。
- 清理后若仍有第三方进程占用 18889，需可诊断而非误报成功。
- “清理凭据/状态”与“清理运行时依赖”边界需定义清楚，避免误删用户无关资产。

## Requirements

### Functional Requirements

- **FR-001**: `/api/status` 必须正确解析 `openclaw daemon status --json`（优先 `service.runtime.status` / `service.command`），不得默认回退为 `running`。
- **FR-002**: `installed` 判定必须基于“可运行且配置完成”的状态，不得仅凭配置文件存在。
- **FR-003**: 提供“全量清理（Factory Reset）”能力，至少覆盖 service/state/workspace。
- **FR-004**: 清理完成后前端必须可回到安装向导（含自动跳转策略）。
- **FR-005**: 顶层“开始部署”入口必须走 UI-first 链路，不触发 CLI 交互式凭据输入。
- **FR-006**: 文档需明确“旧 CLI 入口”和“新 UI 入口”的关系与推荐路径，避免误用。
- **FR-007**: 清理能力需区分“轻量端口清理”与“全量重置”，并在 UI 上明确语义。

### Key Entities

- **Install Status State Machine**: `unknown/not_installed/stopped/running` 到 `installed` 的映射规则。
- **Reset Scope**: service、profile state、workspace、skills copy（可选）等清理边界。
- **Entry Routing Contract**: `01-开始部署.command`、`/`、`/setup`、`?force=1` 的行为约束。

## Success Criteria

### Measurable Outcomes

- **SC-001**: 在“仅有残留配置文件”的场景下，首次打开不再自动跳 Dashboard。
- **SC-002**: 全量清理后 `installed=false` 且刷新进入安装向导，成功率 100%（本地回归样本 >= 5）。
- **SC-003**: 顶层入口不再出现 `FEISHU_APP_ID` 终端交互提示。
- **SC-004**: 清理失败时返回可执行诊断信息（占用 PID / 路径 / 下一步命令）。
- **SC-005**: 所有新增行为有可复现命令与证据记录到 longrun 文档。
