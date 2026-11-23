// language: TypeScript, file: hooks.test.ts, target: Bun test runner
import { describe, expect, test } from "bun:test"
import {
  applyCompactionInstruction,
  applyContextInstruction,
  CONTEXT_MARKER,
  upsertSystemInstruction,
} from "./hooks"

describe("Chain Forge V2 system hooks", () => {
  test("adds context guidance without changing existing system parts", () => {
    const system: unknown[] = [{ type: "text", text: "host instructions" }]
    expect(applyContextInstruction({ system })).toBe(true)
    expect(system).toHaveLength(2)
    expect((system[0] as { text: string }).text).toBe("host instructions")
    expect((system[1] as { text: string }).text).toContain(CONTEXT_MARKER)
  })

  test("replaces its own marker instead of stacking duplicates", () => {
    const system: unknown[] = []
    upsertSystemInstruction(system, CONTEXT_MARKER, "first")
    upsertSystemInstruction(system, CONTEXT_MARKER, "second")
    expect(system).toHaveLength(1)
    expect((system[0] as { text: string }).text).toContain("second")
    expect((system[0] as { text: string }).text).not.toContain("first")
  })

  test("adds compaction guidance only to the outgoing system prompt", () => {
    const system: unknown[] = []
    expect(applyCompactionInstruction({ system })).toBe(true)
    expect(system).toHaveLength(1)
    expect((system[0] as { text: string }).text).toContain("Checkpoint summary guidance")
  })

  test("returns false for a missing system array", () => {
    expect(upsertSystemInstruction(null as unknown as unknown[], "marker", "text")).toBe(false)
  })
})
