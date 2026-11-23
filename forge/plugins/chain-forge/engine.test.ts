// language: TypeScript, file: engine.test.ts, target: Bun test runner
import { describe, expect, test } from "bun:test"
import { injectSystem, processMessages, sniffTurnKey, sliceSafe } from "./engine"
import type { Bundle } from "./inject"

function makeBundle(head: string, tail = "", userTail = ""): Bundle {
  return {
    profile: "test",
    stage: 0,
    slots: {
      "system-head": head,
      "system-tail": tail,
      "user-tail": userTail,
      compaction: "",
    },
    picked: [],
    skipped: [],
    tokens: 0,
    bytes: 0,
  }
}

describe("Chain Forge adaptive engine", () => {
  test("upserts owned system blocks without duplicating them", () => {
    const system: unknown[] = [{ type: "text", text: "host-owned instruction" }]
    const bundle = makeBundle("core payload", "tail payload", "delivery payload")

    expect(injectSystem(system, 0, bundle)).toBe(true)
    expect(injectSystem(system, 0, bundle)).toBe(true)
    expect(system).toHaveLength(3)

    const rendered = system.map((part) =>
      typeof part === "string" ? part : String((part as { text?: string }).text ?? ""),
    ).join("\n")
    expect(rendered).toContain("host-owned instruction")
    expect(rendered).toContain("core payload")
    expect(rendered).toContain("tail payload")
    expect(rendered).toContain("delivery payload")
    expect(rendered.match(/chain-forge:v2:system-head/g)).toHaveLength(1)
    expect(rendered.match(/chain-forge:v2:system-tail/g)).toHaveLength(1)
  })

  test("silent profile removes prior Chain Forge blocks but preserves host instructions", () => {
    const system: unknown[] = [{ type: "text", text: "host-owned instruction" }]
    injectSystem(system, 0, makeBundle("core payload", "tail payload"))
    injectSystem(system, 0, makeBundle(""))

    expect(system).toHaveLength(1)
    expect((system[0] as { text: string }).text).toBe("host-owned instruction")
  })


  test("injects staged chain context idempotently and removes it below stage two", () => {
    const system: unknown[] = [{ type: "text", text: "host-owned instruction" }]
    const bundle = makeBundle("core payload")

    expect(injectSystem(system, 2, bundle, "chain context payload")).toBe(true)
    expect(injectSystem(system, 2, bundle, "chain context payload")).toBe(true)
    const rendered = system.map((part) =>
      typeof part === "string" ? part : String((part as { text?: string }).text ?? ""),
    ).join("\\n")
    expect(rendered.match(/chain-forge:v2:chain/g)).toHaveLength(1)
    expect(rendered).toContain("chain context payload")

    injectSystem(system, 1, bundle, "chain context payload")
    const afterDowngrade = system.map((part) =>
      typeof part === "string" ? part : String((part as { text?: string }).text ?? ""),
    ).join("\\n")
    expect(afterDowngrade).not.toContain("chain-forge:v2:chain")
    expect(afterDowngrade).toContain("host-owned instruction")
  })

  test("trims long chain context while retaining its head and tail", () => {
    const source = "HEAD-" + "x".repeat(200) + "-TAIL"
    const trimmed = sliceSafe(source, 80)
    expect(trimmed.length).toBeLessThanOrEqual(80)
    expect(trimmed.startsWith("HEAD-")).toBe(true)
    expect(trimmed.endsWith("-TAIL")).toBe(true)
    expect(trimmed).toContain("[... trimmed ...]")
  })
  test("uses the latest user message ID as a stable turn key", () => {
    const event = {
      sessionID: "session-1",
      messages: [
        { info: { id: "user-1", role: "user" } },
        { info: { id: "assistant-1", role: "assistant" } },
        { info: { id: "user-2", role: "user" } },
      ],
    }
    expect(sniffTurnKey(event)).toBe("user-2")
  })

  test("supports message IDs on the message object", () => {
    expect(sniffTurnKey({
      messages: [
        { id: "user-direct", role: "user" },
        { id: "assistant-direct", role: "assistant" },
      ],
    })).toBe("user-direct")
  })

  test("returns no turn key when the event has no user message ID", () => {
    expect(sniffTurnKey({ messages: [{ info: { role: "user" } }] })).toBeUndefined()
  })

  test("does not rewrite history or append synthetic user messages", () => {
    const messages = [
      { role: "user", content: "Please inspect this project." },
      { role: "assistant", content: "I can't help with that request." },
    ]
    const before = JSON.stringify(messages)

    expect(processMessages(messages, 3)).toBe(0)
    expect(JSON.stringify(messages)).toBe(before)
    expect(messages).toHaveLength(2)
  })
})
