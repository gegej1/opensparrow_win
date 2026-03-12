# Agent Guidelines (Spec‑Kit / Company Baseline)

本目录用于沉淀可复用的 Spec‑Kit（Codex）工作流与公司级工程规范，便于复制到不同项目中使用。

## 必须遵守

- 以 `.specify/memory/constitution.md` 为最高工程规范（质量门槛、流程、约束）。
- 每个功能先落文档：`specs/<feature>/spec.md` → `plan.md` → `tasks.md`，再改代码。
- 代码变更必须配套可复现的验证方式（测试/脚本/命令），并在 PR 描述中说明如何验证。
- 不提交任何密钥/凭证：`.codex/auth.json`、`.codex/config.toml` 必须保持忽略。
- 文档同步（每个 PR 都要做）：
  - 至少更新 1 条“对外可读的变更记录”（例如 `docs/PRD.md` 的“变更记录”）
  - 若使用方式、命令参数、运行方式变化：同步更新 `README.md`
  - 若开发流程、约束、关键命令变化：同步更新 `AGENTS.md` 与/或 `.specify/memory/constitution.md`

## 推荐工作流

0. `./scripts/codex`（启动 Codex 并加载 `/speckit.*` 命令）
1. `./.specify/scripts/bash/create-new-feature.sh "一句话需求" --short-name xxx`
2. `./.specify/scripts/bash/setup-plan.sh`
3. 在 Codex 内运行 `/speckit.tasks`
4. 按 `tasks.md` 逐条完成并勾选（小步提交、频繁验证）

## 子项目约定

- 进入任何“子项目根目录”（例如包含 `package.json`/`pyproject.toml`/`go.mod` 等）时：
  - 若没有 `AGENTS.md`：创建一个最小 `AGENTS.md`（运行/测试/代码风格/目录结构/配置说明）
  - 若有：遵循其约束；更深层的 `AGENTS.md` 优先级更高

## 常用命令（按项目填写）

```bash
# 安装/初始化（示例）
# make bootstrap

# 测试（示例）
# make test

# 运行（示例）
# make run
```
