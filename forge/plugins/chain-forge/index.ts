// language: TypeScript, file: index.ts, runtime: OpenCode plugin host (bun), target: 0x INJECT AI (v5)
//
// Hook surface. Exports the documented OpenCode plugin shape — an async
// function returning a hooks object — with every known alias of the relevant
// hooks wired to the same engine. Aliases the host does not know are simply
// never called; aliases that do exist all land in forgeHook, which sniffs the
// payload shape and injects wherever the system/messages arrays actually sit.
// This is the v4 answer to "the hooks must fire": cover the whole surface.
//
// No runtime imports from @opencode-ai/plugin — structural typing only, so a
// missing or renamed types package can never fail plugin load.
import { forgeHook, heartbeat } from "./engine"

type HookArgs = unknown[]

function safe(kind: string) {
  return (...args: HookArgs) => {
    try {
      forgeHook(kind, ...args)
    } catch {
      // The chain degrades; it never breaks the host's dispatch.
    }
  }
}

function buildHooks(): Record<string, (...args: HookArgs) => void> {
  const hooks: Record<string, (...args: HookArgs) => void> = {
    // Documented experimental transforms (primary injection points).
    "experimental.chat.system.transform": safe("system"),
    "experimental.chat.messages.transform": safe("messages"),
    "experimental.session.compacting": safe("compact"),
    // Aux model calls: heartbeat + depth only via shape sniff; forgeHook
    // injects only where it finds arrays, so title/summary output formats
    // stay clean.
    "experimental.text.complete": safe("aux"),
    // Common lifecycle hooks.
    "chat.message": safe("chat"),
    "chat.params": safe("params"),
    event: safe("event"),
    // Legacy / alternate spellings seen across host versions. Unknown keys
    // are ignored by the host; known ones route to the same engine.
    "chat.system.transform": safe("system"),
    "chat.messages.transform": safe("messages"),
    "messages.transform": safe("messages"),
    "system.transform": safe("system"),
    "session.compacting": safe("compact"),
    compaction: safe("compact"),
    context: safe("context"),
    title: safe("aux"),
    generate: safe("aux"),
    prompt: safe("prompt"),
  }
  return hooks
}

// Documented plugin signature: async (ctx) => hooks.
const chainForge = async (_ctx: unknown) => {
  try {
    heartbeat("load")
  } catch { /* even the load heartbeat is optional */ }
  return buildHooks()
}

export default chainForge
export { chainForge }
