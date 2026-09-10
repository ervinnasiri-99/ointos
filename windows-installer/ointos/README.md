# ointos/ — OintOS Windows-side producer

Libertix fork'un OintOS tarafı. `upstream/` (pinned submodule) okunur
referans; tüm OintOS kodu burada.

- `config/ointos-policy.json` — guardrail değerleri (plan.py ile aynı olmalı)
- `catalog/ointos-iso.sha256` — ISO pin (URL + hash birlikte bump)
- `scripts/New-OIntOSStaging.ps1` — staging üreticisi (UEFI-only, default -DryRun)
- `tests/` — stdlib contract testi + fixture'lar

Canlı koşu SADECE test VM'inde, snapshot sonrası, dry-run transcript
incel endikten sonra. Ana makinede yıkıcı işlem YOK.
