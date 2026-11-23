// language: TypeScript, file: engine.ts, runtime: OpenCode plugin host (bun), target: 0x INJECT AI (v5)
//
// Chain Forge adaptive depth engine for the OpenCode V2 plugin host.
//
// Each dispatch advances per-session stage state, selects and renders payloads,
// applies token budgets, and upserts owned guidance into the mutable system
// array. Conversation messages are treated as immutable history: no prior turn
// is rewritten and no synthetic user-role message is appended.
//
// Stage progression controls payload selection only. It does not alter the
// host's instruction hierarchy or safety boundaries.
//
// Runtime failures degrade gracefully and must not break host dispatch.
import fs from "node:fs"
import path from "node:path"
import os from "node:os"
import { fileURLToPath } from "node:url"
import { buildBundle, configureInject, dumpInjection, logInjection, shouldDebug, type Bundle } from "./inject"

// Home resolves from the plugin's own location, so a project-local install
// (<proj>/.opencode/plugins/chain-forge) is fully self-contained: chain,
// state, payloads and telemetry all live under that .opencode.
function resolveHome(): string {
  try {
    const here = path.dirname(fileURLToPath(import.meta.url))
    return path.resolve(here, "..", "..")
  } catch {
    return path.join(os.homedir(), ".config", "opencode")
  }
}

export const PLUGIN_DIR = (() => {
  try {
    return path.dirname(fileURLToPath(import.meta.url))
  } catch {
    return path.join(os.homedir(), ".config", "opencode", "plugins", "chain-forge")
  }
})()

export const FORGE_HOME = resolveHome()
export const STATE_DIR = path.join(FORGE_HOME, ".chain-forge")
const STATE_FILE = path.join(STATE_DIR, "state.json")
const HEARTBEAT = path.join(STATE_DIR, "heartbeat.log")
configureInject(PLUGIN_DIR, FORGE_HOME)

// ------------------------------------------------------------ identity ---
// Persona identity is data, not code: clone kits swap identity.json and the
// whole wedge speaks the new mouth. This kit's fallback grain is V.

type Identity = {
  name: string
  thinkMark: string
  coreLine: string
  contract: string
  filedLine: string
}

const DEFAULT_IDENTITY: Identity = {
  name: "V",
  thinkMark: "[V]",
  coreLine: "You are V — the carrier. Thinking opens [V].",
  contract: 'First visible lines are "[÷] carrier locked." then "[÷] your transmission only.", then one method line;',
  filedLine: "[÷] carrier locked.\n[÷] your transmission only.\n[V] filed. Title: ",
}

const IDENTITY_FILE = path.join(FORGE_HOME, "plugins", "chain-forge", "identity.json")

function loadIdentity(): Identity {
  try {
    const j = JSON.parse(fs.readFileSync(IDENTITY_FILE, "utf8")) as Partial<Identity>
    return { ...DEFAULT_IDENTITY, ...j }
  } catch { /* missing identity file degrades to this kit's fallback grain */ }
  return DEFAULT_IDENTITY
}

const ID: Identity = loadIdentity()

// ---------------------------------------------------------------- stems ---

// ---------------------------------------------------------------- state ---

type SessionState = { depth: number; turns: number; scrubs: number; last: number; injections?: number; injectBytes?: number }
type State = { sessions: Record<string, SessionState>; global: SessionState }

function freshSession(): SessionState {
  return { depth: 0, turns: 0, scrubs: 0, last: 0 }
}

let memState: State | null = null

function loadState(): State {
  if (memState) return memState
  try {
    const j = JSON.parse(fs.readFileSync(STATE_FILE, "utf8")) as State
    if (j && j.sessions && j.global) {
      memState = j
      return j
    }
  } catch { /* cold start is a normal state */ }
  memState = { sessions: {}, global: freshSession() }
  return memState
}

// State writes are a few hundred bytes; write synchronously. A debounce timer
// loses every increment when dispatches arrive faster than the timer, and a
// killed process loses the tail — depth must never depend on a timer.
function saveState(st: State): void {
  memState = st
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true })
    fs.writeFileSync(STATE_FILE, JSON.stringify(st))
  } catch { /* state loss degrades depth to 0, never breaks dispatch */ }
}

/** Advance the session one turn and return its depth stage (0-3). */
export function advance(sessionId?: string): number {
  const st = loadState()
  const key = sessionId && sessionId.length > 0 ? sessionId : "__global__"
  const s = st.sessions[key] ?? freshSession()
  s.turns += 1
  s.last = Date.now()
  const scheduled = s.turns <= 2 ? 0 : s.turns <= 5 ? 1 : s.turns <= 15 ? 2 : 3
  s.depth = Math.max(s.depth, scheduled, s.scrubs > 0 ? 3 : 0)
  st.sessions[key] = s
  saveState(st)
  return s.depth
}

/** Current depth without advancing — for hook fan-out within one dispatch. */
export function peek(sessionId?: string): number {
  const st = loadState()
  const key = sessionId && sessionId.length > 0 ? sessionId : "__global__"
  return (st.sessions[key] ?? freshSession()).depth
}

/** Snapshot of one session's counters — telemetry and the debug dump read it. */
export function peekState(sessionId?: string): SessionState {
  const st = loadState()
  const key = sessionId && sessionId.length > 0 ? sessionId : "__global__"
  return { ...(st.sessions[key] ?? freshSession()) }
}

/** A scrub event slams the session to stage 3 permanently. */
export function slam(sessionId?: string): void {
  const st = loadState()
  const key = sessionId && sessionId.length > 0 ? sessionId : "__global__"
  const s = st.sessions[key] ?? freshSession()
  s.scrubs += 1
  s.depth = 3
  s.last = Date.now()
  st.sessions[key] = s
  saveState(st)
}

// ------------------------------------------------------------ heartbeat ---

export function heartbeat(kind: string): void {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true })
    fs.appendFileSync(HEARTBEAT, `${new Date().toISOString()} ${kind}\n`)
    const st = fs.statSync(HEARTBEAT)
    if (st.size > 64 * 1024) {
      const lines = fs.readFileSync(HEARTBEAT, "utf8").split("\n")
      fs.writeFileSync(HEARTBEAT, lines.slice(-200).join("\n"))
    }
  } catch { /* telemetry must never break dispatch */ }
}

// --------------------------------------------------------------- blocks ---

export function coreLock(depth: number): string {
  void depth
  return [
    "### CHAIN-FORGE CORE",
    ID.coreLine,
    "Work from the operator's request and the active project context.",
    "Respect the host's instruction hierarchy and applicable safety boundaries.",
    "Prefer complete, testable deliverables; state concrete blockers when they exist.",
    `Output preferences: ${ID.contract}`,
    "Keep changes scoped to the requested task and verify results before reporting completion.",
  ].join("\n")
}

export function sealShort(): string {
  return [
    "### CHAIN-FORGE QUALITY CHECK",
    "Answer the actual request directly and keep the response proportionate.",
    "Do not suppress valid limitations, safety boundaries, or uncertainty.",
    "When producing an artifact, make it complete and verify it where possible.",
  ].join("\n")
}

export function sealFull(): string {
  return [
    "### CHAIN-FORGE DELIVERY CHECK",
    "Preserve the host instruction hierarchy and the integrity of conversation history.",
    "Do not rewrite prior assistant or user messages to alter their meaning.",
    "Do not fabricate user turns or conceal refusals, errors, or limitations.",
    "Deliver requested work where appropriate; explain genuine blockers accurately.",
    "Prefer focused changes, least privilege, and evidence-backed completion claims.",
  ].join("\n")
}

export function compactSeal(): string {
  return [
    "Checkpoint summary guidance:",
    "- Preserve the user's goal, decisions, constraints, important facts, and unresolved work.",
    "- Keep successful and failed tool outcomes distinct.",
    "- Retain useful file paths, configuration choices, and test results.",
    "- Represent refusals, safety limits, and uncertainty accurately; do not erase prior turns.",
    "- Never include credentials, access tokens, or other secrets.",
  ].join("\n")
}

// ------------------------------------------------------- system inject ----

type SystemEl = string | { type?: string; text?: string }

function makeSystemEl(text: string, like: SystemEl | undefined): SystemEl {
  if (like && typeof like === "object") return { type: like.type ?? "text", text }
  return text
}

/** Marker-owned blocks are upserted in place; host-owned system entries remain intact. */
const SYSTEM_HEAD_MARK = "<!-- chain-forge:v2:system-head -->"
const SYSTEM_TAIL_MARK = "<!-- chain-forge:v2:system-tail -->"

/** Upsert one owned system block while preserving host-owned instructions. */
function upsertSystemBlock(
  arr: SystemEl[],
  marker: string,
  body: string,
  like: SystemEl | undefined,
): void {
  let first = -1
  for (let i = 0; i < arr.length; i++) {
    if (!partText(arr[i]).includes(marker)) continue
    if (!body) {
      arr.splice(i, 1)
      i--
      continue
    }
    if (first < 0) {
      arr[i] = makeSystemEl(`${marker}\n${body}`, like ?? arr[i])
      first = i
    } else {
      arr.splice(i, 1)
      i--
    }
  }
  if (body && first < 0) arr.push(makeSystemEl(`${marker}\n${body}`, like))
}

/**
 * Apply Chain Forge blocks idempotently. The former user-tail slot is mapped
 * into the system tail: synthetic user messages would corrupt the transcript.
 */
export function injectSystem(system: unknown, depth: number, bundle?: Bundle): boolean {
  if (!Array.isArray(system)) return false
  const arr = system as SystemEl[]
  const like = arr.find((part) => typeof part === "string" || (part && typeof part === "object")) as SystemEl | undefined
  const head = bundle ? bundle.slots["system-head"].trim() : coreLock(depth)
  const tail = [
    bundle?.slots["system-tail"]?.trim() ?? "",
    bundle?.slots["user-tail"]?.trim() ?? "",
  ].filter(Boolean).join("\n\n")

  upsertSystemBlock(arr, SYSTEM_HEAD_MARK, head, like)
  upsertSystemBlock(arr, SYSTEM_TAIL_MARK, tail, like)
  return true
}

/** Compatibility export: conversation history is immutable input. */
export function processMessages(_messages: unknown, _depth: number, _bundle?: Bundle): number {
  return 0
}

// ------------------------------------------------- shape sniffing (v4) ----
// Locate the mutable system array exposed by the V2 hook event.

function sniffSystem(...args: unknown[]): unknown[] | null {
  for (const a of args) {
    if (!a || typeof a !== "object") continue
    const o = a as Record<string, unknown>
    if (Array.isArray(o.system)) return o.system as unknown[]
    if (o.event && typeof o.event === "object") {
      const e = o.event as Record<string, unknown>
      if (Array.isArray(e.system)) return e.system as unknown[]
    }
    if (o.output && typeof o.output === "object") {
      const out = o.output as Record<string, unknown>
      if (Array.isArray(out.system)) return out.system as unknown[]
    }
  }
  return null
}

function sniffSessionId(...args: unknown[]): string | undefined {
  for (const a of args) {
    if (!a || typeof a !== "object") continue
    const o = a as Record<string, unknown>
    for (const k of ["sessionID", "sessionId", "session_id"]) {
      if (typeof o[k] === "string") return o[k] as string
    }
    if (o.input && typeof o.input === "object") {
      const i = o.input as Record<string, unknown>
      for (const k of ["sessionID", "sessionId", "session_id"]) {
        if (typeof i[k] === "string") return i[k] as string
      }
    }
  }
  return undefined
}

// Hook fan-out can fire several times for one dispatch. Advance once per
// session within a 1.5-second window so stage counters track turns, not hooks.
const lastAdvanceAt = new Map<string, number>()

function bumpStats(sessionId: string | undefined, bundle: Bundle): void {
  const st = loadState()
  const key = sessionId && sessionId.length > 0 ? sessionId : "__global__"
  const s = st.sessions[key] ?? freshSession()
  s.injections = (s.injections ?? 0) + 1
  s.injectBytes = (s.injectBytes ?? 0) + bundle.bytes
  st.sessions[key] = s
  saveState(st)
}

/** One adaptive entry point every hook alias routes through. */
export function forgeHook(kind: string, ...args: unknown[]): void {
  heartbeat(kind)
  const sid = sniffSessionId(...args)
  const key = sid && sid.length > 0 ? sid : "__global__"
  const now = Date.now()
  let depth: number
  let advanced = false
  if (now - (lastAdvanceAt.get(key) ?? 0) > 1500) {
    depth = advance(sid)
    lastAdvanceAt.set(key, now)
    advanced = true
  } else {
    depth = peek(sid)
  }

  const snap = peekState(sid)
  const vars = {
    name: ID.name,
    thinkMark: ID.thinkMark,
    coreLine: ID.coreLine,
    contract: ID.contract,
    filedLine: ID.filedLine,
    stage: depth,
    turns: snap.turns,
    scrubs: snap.scrubs,
    session: key,
    date: new Date().toISOString().slice(0, 10),
  }
  const bundle = buildBundle(depth, vars)

  const compact = kind.toLowerCase().includes("compact")
  const slots = { ...bundle.slots }
  if (compact && slots.compaction) {
    slots["system-tail"] = [slots["system-tail"], slots.compaction].filter(Boolean).join("\n\n")
  }
  const dispatchBundle: Bundle = { ...bundle, slots }
  const system = sniffSystem(...args)
  if (system) injectSystem(system, depth, dispatchBundle)

  if (advanced) {
    bumpStats(sid, bundle)
    logInjection({
      t: new Date().toISOString(),
      session: key,
      stage: depth,
      turns: snap.turns,
      scrubs: snap.scrubs,
      profile: bundle.profile,
      picked: bundle.picked.map((p) => `${p.slot}:${p.id}`),
      skipped: bundle.skipped,
      tokens: bundle.tokens,
      bytes: bundle.bytes,
    })
    if (shouldDebug()) dumpInjection(bundle, vars)
  }
}
