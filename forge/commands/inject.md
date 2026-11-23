---
description: Show INJECT AI state — profile, payloads, last injection, telemetry
---

Read these files (skip quietly when a file does not exist):

- `~/.config/opencode/plugins/chain-forge/inject.config.json`
- `~/.config/opencode/plugins/chain-forge/payloads/` (list the .md files)
- `~/.config/opencode/.chain-forge/last-injection.txt`
- `~/.config/opencode/.chain-forge/injection.log` (tail 10 lines)
- `~/.config/opencode/.chain-forge/state.json`

Then report in one compact block, in voice:

- active profile and its slot budgets
- payload count and the ids selected in the last injection
- last injection time, stage, estimated tokens, bytes
- session depth / turns / scrubs from state.json

If the files are missing, say the kit is not installed and point to
`Setup.bat` — do not invent numbers.
