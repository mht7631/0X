// language: TypeScript, file: index.ts, target: OpenCode 2.3.2 V2 plugin host
import { Plugin } from "@opencode/plugin"
import { forgeHook, heartbeat } from "./engine"

function observe(kind: string, action?: () => void): void {
  try {
    heartbeat(`v2:${kind}`)
    action?.()
  } catch (error) {
    // Keep the host dispatch healthy while making plugin failures diagnosable.
    console.error(`[chain-forge] ${kind} hook failed:`, error)
  }
}

export default Plugin.define({
  id: "chain-forge",
  async setup(ctx) {
    observe("load")

    await ctx.session.hook("context", (event) => {
      observe("context", () => forgeHook("context", event))
    })

    await ctx.session.hook("compaction", (event) => {
      observe("compaction", () => forgeHook("compaction", event))
    })

    await ctx.session.hook("generate", (event) => {
      observe("generate", () => forgeHook("generate", event))
    })

    await ctx.session.hook("title", () => {
      observe("title")
    })

    return () => observe("unload")
  },
})
