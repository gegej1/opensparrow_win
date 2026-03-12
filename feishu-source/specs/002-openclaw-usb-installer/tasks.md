# Tasks: OpenClaw U 盘本地部署 Skill + 脚本

**Input**: `specs/002-openclaw-usb-installer/spec.md`, `specs/002-openclaw-usb-installer/plan.md`  
**Prerequisites**: `spec.md`, `plan.md`

## Phase 1: 研究与约束确认

- [x] T001 梳理本地已验证链路（OpenClaw + 飞书 + 模型）并形成输入清单
- [x] T002 收集官方安装与通道文档来源，记录到 `research/openclaw-usb-installer/SOURCES.md`
- [x] T003 收集 U 盘执行约束（USB 自动运行限制、手动启动替代方案）

## Phase 2: 产物实现（P1）

- [x] T004 [US1] 编写安装脚本 `scripts/openclaw-usb/install-local-feishu.sh`
- [x] T005 [US2] 编写 Skill `skills/openclaw-local-feishu-usb/SKILL.md`
- [x] T006 [US3] 编写 U 盘 SOP `research/openclaw-usb-installer/SOP.md`

## Phase 3: longrun 拆分（P2）

- [x] T007 创建 longrun 工作区 `longrun/workspaces/openclaw-usb-portable/`
- [x] T008 填充 longrun 项目说明 `longrun/workspaces/openclaw-usb-portable/app_spec.md`
- [x] T009 拆分执行特性 `longrun/workspaces/openclaw-usb-portable/feature_list.json`

## Phase 4: 文档同步

- [x] T010 更新 `specs/002-openclaw-usb-installer/spec.md`
- [x] T011 更新 `specs/002-openclaw-usb-installer/plan.md`
- [x] T012 更新对外变更记录 `README.md`

## Phase 5: 执行与打磨

- [x] T013 建立完全隔离的执行目录 `longrun/workspaces/openclaw-usb-portable/execution/`
- [x] T014 [US1] 升级安装脚本，支持 isolated profile / workspace / gateway port / evidence 输出
- [x] T015 [US3] 补齐 macOS `.command` 与 Windows `.cmd` / `.ps1` 入口
- [x] T016 [US3] 增加交付包构建脚本与 staging 目录
- [x] T017 [US1] 在本机使用隔离 profile 实跑 F-001 并采集证据
- [x] T018 [US4] 增加权限收口脚本并实跑收口验证
- [x] T019 [US2][US3][US4] 回写 Skill / SOP / longrun progress / feature passes

## Validation Checklist

- [x] V001 脚本在缺失关键参数时会失败并提示
- [x] V002 Skill 含前置条件、步骤、验证、排障、收口
- [x] V003 SOP 明确 USB 自动运行不可行边界和替代执行方式
- [x] V004 longrun 已拆分为可迭代的 feature 列表
- [x] V005 隔离 profile 使用独立 state / workspace / port，不覆盖默认 profile
- [x] V006 staging 交付包已成功组装
- [x] V007 `F-001` 证据已落盘（health / daemon / probe / agent）
- [x] V008 `F-004` 收口后 `dmPolicy=pairing`、`allowFrom=[]` 且 probe 仍为 works
