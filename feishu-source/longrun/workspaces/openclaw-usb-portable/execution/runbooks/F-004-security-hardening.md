# F-004 Runbook - 安全收口

## 目标

把联调阶段的 `dmPolicy=open` 收口到 `pairing` 或 `allowlist`，避免长期开放。

## 主命令

```bash
bash scripts/openclaw-usb/harden-local-feishu.sh \
  --profile usb-portable \
  --dm-policy pairing \
  --allow-from-json '[]' \
  --require-mention true
```

## 复验命令

```bash
openclaw --profile usb-portable channels status --probe
openclaw --profile usb-portable daemon status
```

## 通过标准

- 配置已切换为 `pairing` 或 `allowlist`
- `allowFrom` 不再是 `[*]`
- 验证命令仍可正常执行
