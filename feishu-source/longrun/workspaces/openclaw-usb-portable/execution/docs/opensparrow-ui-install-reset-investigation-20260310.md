# OpenSparrow UI 安装/重置问题调研报告（2026-03-10）

## 1) 调研目标

围绕用户反馈的三类问题做“先验证再下结论”：

1. 点击部署入口后，是否仍会触发命令行凭据输入；
2. 新机/空配置场景是否会被错误跳转到 Dashboard；
3. “清理旧环境”是否具备真正恢复未安装态的能力（而不是仅 kill 进程）。

---

## 2) 关键复现结果

## 2.1 入口链路复现（命令行提示来源）

### 观察（2026-03-10 复核）
- 当前仓库 `mac/01-开始部署.command` 已改为调用 `usb-pack/01-启动ClawBot管理界面.command`，实测启动后直接拉起 `ui/server.mjs`，不出现凭据提问。
- 旧链路 `usb-pack/mac/run-openclaw-usb.command` 仍存在，且包含：
  - `read -r -p "FEISHU_APP_ID: " ...`
  - `read -r -s -p "FEISHU_APP_SECRET: " ...`
  - `read -r -s -p "OPENAI_API_KEY: " ...`
- Windows 顶层入口 `win/01-开始部署.cmd` 当前仍调用 `usb-pack/windows/run-openclaw-usb.cmd`，最终进入 `install-local-feishu.ps1` 的交互输入逻辑（`Read-Host`）。

### 结论
- 用户看到 `FEISHU_APP_ID:` 提示时，本质走的是 **CLI 交互安装链路**，不是 UI-first。
- 对 mac 而言，若仍出现该提示，优先怀疑“使用了旧版交付包”或“直接调用了 `usb-pack/mac/run-openclaw-usb.command`”。

---

## 2.2 安装态误判复现（自动跳 Dashboard 根因）

### 复现命令（摘要）
1. 创建 profile 状态目录，仅写入 `openclaw.json`（无安装 daemon）；
2. 启动 `ui/server.mjs`（`OPENCLAW_PROFILE=<test-profile>`）；
3. 请求 `GET /api/status`。

### 实际返回
`{"installed":true,"daemon":"running",...}`

### 代码根因
- `server.mjs` 状态解析使用：`daemon = parsed.status ?? 'running'`
- 当前 OpenClaw `daemon status --json` 输出里 **没有顶层 `status`**，因此回退成 `'running'` 假阳性。
- 在 `configExists=true` 时，`installed=configExists && daemon==='running'` 被错误置为 `true`，触发前端自动跳转。

---

## 2.3 清理后仍无法回安装页复现

### 复现命令（摘要）
1. 人工准备一个带 `openclaw.json` 的 profile（模拟“残留环境”）；
2. 调用 `POST /api/cleanup`；
3. 再次调用 `GET /api/status`。

### 实际行为
- `cleanup` 仅 stop/uninstall + 端口清理；
- profile 配置目录未删除；
- `/api/status` 依旧返回 `installed:true`（叠加 2.2 的 daemon 假阳性）。

### 结论
- 当前“清理旧环境”不是“恢复初始态”，仅是“服务/端口清理”。

---

## 3) “硬编码”问题的真实来源

## 3.1 前端默认值检查
- `index.html` 中凭据默认值为 `''`（空字符串），并无硬编码 appId/appSecret/apiKey。

## 3.2 观感来源
- Dashboard 会读取 `~/.openclaw-<profile>/openclaw.json`；
- 若该文件来自历史安装残留，会显示旧凭据（常被误判为“新包硬编码”）。

---

## 4) 清理边界梳理（当前 vs 目标）

## 4.1 当前 cleanup 覆盖范围
- `daemon stop/uninstall`
- 18889 端口释放（含 force kill）

**未覆盖**：
- `~/.openclaw-<profile>` 状态目录（含配置、日志、extensions 依赖）
- workspace 目录
- 安装时复制的 skills 目录（`~/.claude/skills/superpowers`, `~/.codex/skills/superpowers`）

## 4.2 可复用的全量清理能力（已验证）
- OpenClaw 原生命令支持：
  - `openclaw --profile <p> uninstall --service --state --workspace --yes --non-interactive`
- dry-run 输出会明确删除路径，实跑可删除 service + state + workspace。

---

## 5) 根因汇总（确定性）

1. **状态解析错误**：将缺失字段回退为 `running`，导致安装态假阳性。
2. **清理语义不完整**：当前 cleanup 非“重置”，无法回到初始安装态。
3. **入口策略分裂**：仍保留可直接触发 CLI 交互的旧入口（尤其 Windows 顶层入口仍默认走 CLI），与 UI-first 目标冲突。
4. **残留配置影响体验**：历史 profile 数据被读取，造成“新机硬编码”错觉。

---

## 6) 修改方案（待实施）

1. 修复 `/api/status` 状态机：使用 `service.runtime.status` + `service.command` 解析 daemon 状态。
2. 新增“全量重置”接口：调用 `openclaw uninstall --service --state --workspace --yes --non-interactive`。
3. 前端分离按钮语义：
   - 轻量：清端口/旧 daemon；
   - 重置：删除 profile 环境并跳回 `/?force=1`。
4. 入口与文档统一 UI-first：
   - 双击入口默认启动 UI；
   - CLI 交互入口降级为高级模式并明确标注。

---

## 7) 回归验证清单（实施后执行）

1. 空 profile + 无 service：`/api/status` 返回 `installed=false`。
2. 仅残留 config：仍 `installed=false`（不跳 Dashboard）。
3. 全量重置后：profile 目录不存在、刷新回安装向导。
4. 重新安装后：可正常进入 Dashboard 并完成通道/API配置。
