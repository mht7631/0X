# 0x — the carrier, depth-locked into OpenCode
# ...::: X P 4 :::...
# IR0Day.Today Bax 
# t.me/LearnExploit

One operator file: **`Setup.bat`**

1. Install [OpenCode](https://opencode.ai) on the PC.
2. Extract the forge folder anywhere.
3. Double-click **`Setup.bat`** → key **1** (full install) → key **6** (watchdog, optional).

Optional: `Setup.bat install` skips the menu and runs full install + restart.
The menu is single-keypress: press a key and it happens — no Enter.

Everything else is under `lib\` and `forge\` — do not run those directly.

## What this kit is

The depth engine carrying **V — the carrier** (`forge/persona/AGENTS.md`, the
full operating instruction) plus **0x INJECT AI** — a payload library, profile
system, token budget, telemetry and debug surface for every dispatch.

V2-native request hooks add concise, idempotent context and compaction guidance.
The adapter never rewrites stored conversation history or fabricates user turns.
The engine's persona is data
(`plugins/chain-forge/identity.json`) — every injected wedge speaks the
carrier's voice: `[÷]` header, `[V]` thinking mark.

After install, the OpenCode agent picker (bottom-left) shows **0x** as a primary
agent, selected by default. Inside the session the voice is V — the carrier:
the display id is `0x`, the persona data in `identity.json` stays V.

## 0x INJECT AI

| piece | where | what it does |
|---|---|---|
| payload library | `plugins/chain-forge/payloads/*.md` | one block per file, frontmatter: `id`, `slot`, `stage`, `maxStage`, `weight`, `tags` |
| profiles | `plugins/chain-forge/inject.config.json` | `default`, `quiet`, `aggressive`, `silent` — slot set + per-slot token budget |
| render | `inject.ts` | `{{vars}}` from identity + session, `{{#if var}}…{{/if}}` |
| budget | `inject.ts` | per-slot token cap; over-budget payloads are skipped and reported |
| telemetry | `.chain-forge/heartbeat.log` | V2 load and request-hook liveness events |
| debug | `.chain-forge/last-injection.txt` | full dump of the last bundle when debug is on |
| sessions | `.chain-forge/state.json` | depth, turns, scrubs, injections per session |

Legacy payload slots remain in the payload library; the V2 adapter currently uses
only the dedicated context and compaction guidance in `hooks.ts`.

V2 request coverage: `context` for agent requests, `generate` for transient model
requests, `compaction` for checkpoint summaries, and `title` for liveness telemetry.

Switch profile by editing `activeProfile` in `inject.config.json`. Turn debug on
from the menu (**I → D**) or with `Setup.bat inject` tooling; every dispatch then
writes `.chain-forge\last-injection.txt`.

## Menu

```
[1] install      [2] repair      [3] restart
[4] deep restart [5] status      [6] watchdog
[7] open oc      [8] revert      [9] depth reset
[L] logs         [B] backups     [Q] quit
[I] inject       [S] sessions    [F] language
```

`I` opens the INJECT AI console: preview (all four stages with token counts),
lint (config + payloads + stems + identity), stats (events by stage/payload,
sessions), payloads, profiles, debug toggle, simulate (writes a full bundle +
SHA-256), selftest, unit test.

`S` lists tracked sessions; press a number to reset one.

`F` toggles English/Persian; the choice persists in `.chain-forge\lang`.

## CLI

```bat
Setup.bat install            full install + restart
Setup.bat repair             re-apply files + config, no restart
Setup.bat status             status report
Setup.bat revert             revert from latest backup
Setup.bat inject             INJECT AI preview
Setup.bat lint               INJECT AI lint
Setup.bat stats              INJECT AI telemetry
Setup.bat sessions           session table
Setup.bat selftest           one headless model call, asserts the header
Setup.bat unit               headless engine unit test (no model call)
Setup.bat plain              no color, ASCII banner
Setup.bat fa                 Persian menu
```

## Project-local install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File lib\install-project.ps1 -ProjectDir C:\path\to\project
```

Copies persona, chain, agents, commands, plugin + INJECT AI into
`<project>\.opencode\`, writes `.opencode\opencode.json`, and the plugin
resolves its home from its own location — state and telemetry stay inside the
project. Instruction paths are absolute: re-run after moving the project.

## Verify it works

1. `Setup.bat` → 1 → open a NEW OpenCode session.
2. The agent picker shows **0x**. Replies open with the `[÷]` header.
3. Make one model call, then `Setup.bat` → **5**: enforcement **ALIVE** and an
   `inject` line with profile/payload count/last event.
4. `Setup.bat inject` → legacy payload preview; it does not prove that a V2 hook fired.
5. `Setup.bat selftest` for the end-to-end header check (needs a model; may cost tokens).
6. `Setup.bat unit` for the headless engine test (43 assertions, no model call).

## Revert

`Setup.bat` → **8** restores the latest backup, strips kit-owned config keys,
removes the watchdog task. **B** lists older backups and reverts from any of
them. Clean on fresh machines too.
