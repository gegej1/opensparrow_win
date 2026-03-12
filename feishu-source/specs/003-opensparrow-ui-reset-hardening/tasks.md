# Tasks: OpenSparrow UI 安装态判定与全量清理

**Input**: `specs/003-opensparrow-ui-reset-hardening/spec.md`, `specs/003-opensparrow-ui-reset-hardening/plan.md`  
**Prerequisites**: `spec.md`, `plan.md`

## Phase 1: 状态判定修复（P1）

- [x] T001 重构 `/api/status` 解析逻辑，基于 `service.runtime.status` 与 `service.command`
- [x] T002 建立 daemon 状态映射：`running/stopped/not_installed/unknown`
- [x] T003 更新 `installed` 判定策略并补充注释与回归样例

## Phase 2: 全量重置能力（P1）

- [x] T004 新增后端 reset 接口（Factory Reset）
- [x] T005 reset 接口调用 `openclaw uninstall --service --state --workspace --yes --non-interactive`
- [x] T006 增加可选 skills 清理（`~/.claude/skills/superpowers`, `~/.codex/skills/superpowers`）
- [x] T007 输出清理结果清单（删除路径、失败项、端口状态）

## Phase 3: 前端交互修复（P1）

- [x] T008 Dashboard 新增“全量重置”按钮与危险确认弹窗
- [x] T009 全量重置成功后跳转 `/?force=1`
- [x] T010 安装页自动跳转逻辑改为依赖修正后的状态返回

## Phase 4: 入口与文档收敛（P1）

- [x] T011 统一推荐入口为 UI-first，并保留旧 CLI 入口的“高级模式”说明
- [x] T012 更新 `README-FIRST.txt` / `usb-pack/README.txt` / SOP 路径指引
- [x] T013 在 longrun 增补一次“新机首次部署 + 重置再部署”验证记录

## Phase 5: 回归与验收（P1）

- [x] T014 回归场景 A：仅残留 config，不应跳 Dashboard
- [x] T015 回归场景 B：stop/uninstall 后状态应为非 running
- [x] T016 回归场景 C：全量重置后应回到安装向导
- [x] T017 回归场景 D：重新部署后 Dashboard 正常

## Validation Checklist

- [x] V001 `/api/status` 不再出现“无 service 仍 running”的假阳性
- [x] V002 “清理后仍跳 Dashboard”问题消失
- [x] V003 双击入口不出现 `FEISHU_APP_ID` 终端交互提示（UI-first）
- [x] V004 全量重置后 profile 目录与 service 清理完成
- [x] V005 文档与实际入口一致，无歧义路径
