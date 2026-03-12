# Feature Specification: OpenClaw U 盘本地部署 Skill + 脚本

**Feature Branch**: `002-openclaw-usb-installer`  
**Created**: 2026-03-09  
**Status**: Execution & Polish  
**Input**: 用户希望将已验证通过的本地 OpenClaw + 飞书接入流程沉淀为一个可复用 Skill 与一个脚本，并能放入 U 盘执行。

## User Scenarios & Testing

### User Story 1 - 一次性本地部署脚本 (Priority: P1)

作为实施人员，我需要在新机器上通过一条脚本完成 OpenClaw 本地部署与飞书接入基础配置，并且不污染机器原有默认 OpenClaw 环境。

**Why this priority**: 这是“插 U 盘即可部署”的核心能力，没有脚本就无法复刻。

**Independent Test**: 在干净机器或独立 profile 执行脚本后，`openclaw --profile usb-portable channels status --probe` 返回 `feishu configured/running/works`。

**Acceptance Scenarios**:

1. **Given** 机器已联网且有 Node/npm，**When** 执行安装脚本并提供 app id/secret 与模型 key，**Then** OpenClaw 服务启动且飞书通道可探测成功。
2. **Given** 已配置完成，**When** 执行 `openclaw --profile usb-portable agent --agent main --message "请只回复OK" --json`，**Then** 返回 `status: ok`。
3. **Given** 本机已有默认 OpenClaw 配置，**When** 运行本功能脚本，**Then** 默认 profile 与默认端口不被覆盖。

---

### User Story 2 - 可复用 Skill 文档 (Priority: P1)

作为团队成员，我需要一个标准化 Skill，明确“每一步装什么、做什么、怎么验、怎么收口”。

**Why this priority**: 脚本解决执行，Skill 解决交接与复用，二者必须一起交付。

**Independent Test**: 新成员仅按 Skill 文档可在 1 小时内完成同样部署并通过验证清单。

**Acceptance Scenarios**:

1. **Given** 团队内新成员，**When** 按 Skill 执行，**Then** 能完成安装、配置、验证、排障与权限收口。

---

### User Story 3 - U 盘执行 SOP (Priority: P2)

作为推广/交付人员，我需要知道“U 盘方案在哪些系统可行、有哪些限制、推荐操作路径是什么”。

**Why this priority**: 需要避免“自动运行”误解，先给出可执行且合规的 SOP。

**Independent Test**: 按 SOP 在 macOS/Windows 上从 U 盘手动启动脚本，能触发安装流程并完成验证。

**Acceptance Scenarios**:

1. **Given** U 盘插入目标机器，**When** 用户手动启动 macOS 或 Windows 入口脚本，**Then** 安装流程开始并输出明确步骤日志。
2. **Given** 交付人员打包好 staging 包，**When** 拷贝到 U 盘，**Then** 包内结构、文档、入口脚本和运行指引完整。

### Edge Cases

- 机器可联网但无法访问 `api.openai.com`，需要支持自定义 `OPENAI_BASE_URL`。
- 机器 npm 全局目录无写权限，脚本需给出替代路径提示（如 nvm/本地 prefix）。
- 机器本地已有默认 OpenClaw 服务运行，脚本必须通过独立 profile 与独立端口避免冲突。
- 飞书权限已开通但消息不回，需区分“事件未入站”和“模型调用失败”。
- 不可将真实密钥固化在 U 盘明文配置中，脚本必须从环境变量或交互输入获取。

## Requirements

### Functional Requirements

- **FR-001**: 必须提供一个中文 Skill 文档，覆盖前置条件、执行步骤、验证点、排障、收口。
- **FR-002**: 必须提供一个可执行脚本，完成本地 OpenClaw + 飞书基础配置。
- **FR-003**: 脚本必须支持参数、环境变量或交互输入注入 `FEISHU_APP_ID`、`FEISHU_APP_SECRET`、`OPENAI_API_KEY`。
- **FR-004**: 脚本必须支持可选 `OPENAI_BASE_URL`，用于非官方直连场景。
- **FR-005**: 脚本执行结束后必须输出验收命令清单与证据目录。
- **FR-006**: 必须提供 U 盘部署 SOP，并明确“现代系统不支持 USB 自动执行”的限制与替代方案。
- **FR-007**: 所有文档与脚本示例不得包含真实密钥。
- **FR-008**: 安装脚本必须支持 isolated profile、isolated workspace、dedicated gateway port。
- **FR-009**: 必须提供 macOS 手动入口与 Windows 手动入口。
- **FR-010**: 必须把执行证据落盘到独立目录，便于 longrun 回写。
- **FR-011**: 必须提供收口脚本或等价命令，把 `dmPolicy=open` 收口到 `pairing` 或 `allowlist`。

### Key Entities

- **Installer Script**: `scripts/openclaw-usb/install-local-feishu.sh`，负责安装与配置自动化。
- **Hardening Script**: `scripts/openclaw-usb/harden-local-feishu.sh`，负责联调后的权限收口。
- **Skill Doc**: `skills/openclaw-local-feishu-usb/SKILL.md`，负责标准流程说明与操作准则。
- **USB SOP**: `research/openclaw-usb-installer/SOP.md`，负责跨系统执行路径和风险边界。
- **Execution Workspace**: `longrun/workspaces/openclaw-usb-portable/execution/`，负责执行阶段方案、runbook、日志、证据与 staging 包。

## Success Criteria

### Measurable Outcomes

- **SC-001**: 在已满足前置条件的新机器或独立 profile 上，单次脚本执行完成到通道探测成功不超过 20 分钟。
- **SC-002**: Skill 文档中的每个步骤都至少包含 1 条可执行验证命令。
- **SC-003**: U 盘 SOP 覆盖 macOS 与 Windows 两类系统的执行入口与限制说明。
- **SC-004**: 产出的脚本在缺失关键参数时会明确失败并给出修复提示。
- **SC-005**: 执行结果会落盘成证据文件，供 longrun 回写 passes 与 progress。
- **SC-006**: 隔离 profile 部署不覆盖默认 `~/.openclaw/` 与默认 `18789` 端口。
