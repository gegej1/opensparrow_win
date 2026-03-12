# F-001 Runbook - 安装与配置

## 目标

在本机用隔离 profile 完成 OpenClaw + Feishu + OpenAI 兼容模型的可运行配置，并生成完整证据。

## 主命令

```bash
bash scripts/openclaw-usb/install-local-feishu.sh \
  --profile usb-portable \
  --port 18889 \
  --evidence-dir longrun/workspaces/openclaw-usb-portable/execution/evidence/f001-run
```

## 通过标准

- `openclaw --profile usb-portable health --json` 成功
- `openclaw --profile usb-portable channels status --probe` 显示 `feishu ... works`
- `openclaw --profile usb-portable agent --agent main --message "请只回复OK" --json` 成功
- 飞书实测可收到回复

## 证据归档

- `config-validate.json`
- `health.json`
- `daemon-status.txt`
- `channels-probe.json`
- `agent-smoke.json`
- `session-metadata.txt`
- `logs/install-*.log`
