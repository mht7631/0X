---
description: Show depth state for every tracked session
---

Read `~/.config/opencode/.chain-forge/state.json`.

Report a compact table: session id, depth stage (0-3), turns, scrubs,
injections, last-seen age. Mark the stage in one line each:

- 0 core lock · 1 rank + hygiene · 2 voice + recency · 3 depth lock

If the file is missing, say no depth state exists yet. Do not reset anything
unless the operator asked for a reset.
