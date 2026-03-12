# App Spec: OpenClaw USB Portable Installer

## 0) Project metadata
- Project name: OpenClaw USB Portable Installer
- Workspace name: openclaw-usb-portable
- Existing repo path (if migrating): /Users/eduardogan/Desktop/GHJProject/openclawtest
- Primary owner: GHJ Project team
- Last updated (YYYY-MM-DD): 2026-03-09

## 1) Product goal
Build a portable delivery package for local OpenClaw deployment.
The package must include one reusable skill, one executable setup script, one hardening script, and one SOP.
It must support a clean machine setup with Feishu WebSocket channel and OpenAI model access.
It must be isolated by default: no hardcoded secrets, no writes into the default OpenClaw profile, and explicit post-install verification.

## 2) In-scope user workflows
1. Operator runs one script on a new local machine to install and configure OpenClaw + Feishu.
2. Team member follows skill documentation to reproduce setup, verify outputs, and troubleshoot failures.
3. Delivery engineer builds a USB package with manual start flow on macOS/Windows.
4. Operator runs a follow-up hardening step to move from open mode to pairing/allowlist.

## 3) Out of scope
- VPS deployment automation.
- Kernel-level USB autorun bypass solutions.
- Persisting plaintext credentials in repository or U-disk files.

## 4) Technical baseline
- Runtime: Bash + PowerShell（Windows 原生脚本 + 平台专属 handoff copy）
- Framework: OpenClaw CLI
- Package manager: npm
- Data store: isolated OpenClaw state under `~/.openclaw-usb-portable`
- External APIs/services: Feishu Open Platform, OpenAI-compatible model endpoint
- Required environment variables: `FEISHU_APP_ID`, `FEISHU_APP_SECRET`, `OPENAI_API_KEY`
- Optional environment variables: `OPENAI_BASE_URL`, `OPENCLAW_PROFILE_NAME`, `OPENCLAW_GATEWAY_PORT`
- Allowed ports: preferred loopback port `18889` by default, with automatic fallback to the next free port

## 5) Existing-project migration constraints
- Stable modules that must not break: existing `research/openclaw-deploy/*` docs and current default OpenClaw local profile
- APIs/contracts that must remain backward compatible: existing OpenClaw CLI commands in docs
- Files/directories that cannot be touched: `.codex/auth.json`, `.codex/config.toml`
- Required coding conventions: Spec-Kit document-first flow
- Required review/testing gates: script syntax check + command-level verification list + evidence files

## 6) Commands contract
- Install (macOS/Linux): `bash scripts/openclaw-usb/install-local-feishu.sh --profile usb-portable --port 18889`
- Install (Windows): `powershell -ExecutionPolicy Bypass -File scripts/openclaw-usb/install-local-feishu.ps1 -Profile usb-portable -Port 18889`
- Harden (macOS/Linux): `bash scripts/openclaw-usb/harden-local-feishu.sh --profile usb-portable --dm-policy pairing --allow-from-json '[]' --require-mention true`
- Harden (Windows): `powershell -ExecutionPolicy Bypass -File scripts/openclaw-usb/harden-local-feishu.ps1 -Profile usb-portable -DmPolicy pairing -AllowFromJson '[]' -RequireMention true`
- Build portable pack: `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/build-delivery-pack.sh`
- Build Mac handoff copy: `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/create-mac-handoff-copy.sh`
- Build Windows handoff copy: `bash longrun/workspaces/openclaw-usb-portable/execution/scripts/create-windows-handoff-copy.sh`
- Start app/service: `openclaw --profile usb-portable daemon restart`
- Health: `openclaw --profile usb-portable health --json`
- Probe: `openclaw --profile usb-portable channels status --probe`
- Smoke: `openclaw --profile usb-portable agent --agent main --message "请只回复OK" --json`
- Lint: `bash -n scripts/openclaw-usb/install-local-feishu.sh && bash -n scripts/openclaw-usb/harden-local-feishu.sh`

## 7) Quality and non-functional requirements
- Performance: local setup in <= 20 minutes under normal network.
- Security: secrets are runtime inputs only; no repository hardcoding.
- Accessibility: installer output must be plain and actionable.
- Observability: installer prints status and writes evidence/log files.
- Reliability: idempotent config commands and clear failure messages.
- Isolation: state/config/workspace/service/port do not collide with the default profile.

## 8) Definition of done
- [x] All in-scope workflows have matching entries in `feature_list.json`.
- [x] Each workflow is verifiable end-to-end through real user flow or generated evidence.
- [x] Migration constraints are respected (default profile remains untouched).
- [x] `init.sh` can prepare the environment in a repeatable way.
- [x] Session handoff is clear from `claude-progress.txt`.
- [x] A staging delivery pack can be built for USB copy.
