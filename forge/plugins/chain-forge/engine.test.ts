// language: TypeScript, file: engine.test.ts, target: Bun test runner
import { describe, expect, test } from "bun:test"
import { injectSystem, processMessages, sniffTurnKey } from "./engine"
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
