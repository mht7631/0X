// language: TypeScript, file: index.ts, target: OpenCode 2.3.2 V2 plugin host
import { Plugin } from "@opencode/plugin"
import { heartbeat } from "./engine"
import { applyCompactionInstruction, applyContextInstruction } from "./hooks"

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
      observe("context", () => {
        if (!applyContextInstruction(event)) {
          throw new Error("context hook did not expose a mutable system array")
        }
      })
    })

    await ctx.session.hook("compaction", (event) => {
      observe("compaction", () => {
        if (!applyCompactionInstruction(event)) {
          throw new Error("compaction hook did not expose a mutable system array")
        }
      })
    })

    await ctx.session.hook("generate", (event) => {
      observe("generate", () => {
        if (!applyContextInstruction(event)) {
          throw new Error("generate hook did not expose a mutable system array")
        }
      })
    })

    await ctx.session.hook("title", () => {
      observe("title")
    })

    return () => observe("unload")
  },
})
