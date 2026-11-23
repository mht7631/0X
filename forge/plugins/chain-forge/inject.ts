// language: TypeScript, file: inject.ts, runtime: OpenCode plugin host (bun), target: 0x INJECT AI
//
// INJECT AI — the payload engine behind every dispatch.
//
//   payloads/*.md   one markdown file per block, YAML-ish frontmatter:
//                   id, slot, stage, maxStage, weight, tags
//   inject.config.json
//                   profiles (slot set + per-slot token budget), telemetry,
//                   debug dump switch
//
// Mechanism: select payloads for the current depth stage, render {{vars}},
// pack each slot until its token budget is spent, return a Bundle. The engine
// places the bundle into the system array (head/tail), the user-role tail
// message and the compaction path.
//
// Every public function is total. A missing file, a broken regex, a corrupt
// config — all degrade to the built-in bundle; nothing throws into the host.

import fs from "node:fs"
import path from "node:path"

export type Slot = "system-head" | "system-tail" | "user-tail" | "compaction"
export const SLOTS: Slot[] = ["system-head", "system-tail", "user-tail", "compaction"]

export type Payload = {
  id: string
  slot: Slot
  stage: number
  maxStage: number
  weight: number
  tags: string[]
  body: string
  file: string
}

export type Profile = {
  description?: string
  slots: Slot[]
  budgetTokens: Record<string, number>
  minStage?: number
}

export type InjectConfig = {
  version: number
  activeProfile: string
  debugDump: boolean
  telemetry: { enabled: boolean; maxBytes: number }
  profiles: Record<string, Profile>
}

export type Bundle = {
  profile: string
  stage: number
  slots: Record<Slot, string>
  picked: { id: string; slot: Slot; tokens: number }[]
  skipped: string[]
  tokens: number
  bytes: number
}

// ------------------------------------------------------------ paths ---

let PLUGIN_DIR = ""
let HOME = ""
let STATE_DIR = ""
let INJECT_LOG = ""
let DEBUG_FILE = ""
let CONFIG_FILE = ""
let PAYLOAD_DIR = ""

/** Wire the engine's resolved home + plugin dir into the inject layer. */
export function configureInject(pluginDir: string, home: string): void {
  PLUGIN_DIR = pluginDir
  HOME = home
  STATE_DIR = path.join(home, ".chain-forge")
  INJECT_LOG = path.join(STATE_DIR, "injection.log")
  DEBUG_FILE = path.join(STATE_DIR, "last-injection.txt")
  CONFIG_FILE = path.join(pluginDir, "inject.config.json")
  PAYLOAD_DIR = path.join(pluginDir, "payloads")
}

export function paths() {
  return { pluginDir: PLUGIN_DIR, home: HOME, stateDir: STATE_DIR, injectLog: INJECT_LOG, debugFile: DEBUG_FILE, configFile: CONFIG_FILE, payloadDir: PAYLOAD_DIR }
}

// ---------------------------------------------------------- defaults ---

const DEFAULT_BUDGET: Record<string, number> = {
  "system-head": 6000,
  "system-tail": 4000,
  "user-tail": 3000,
  compaction: 1200,
}

const DEFAULT_CONFIG: InjectConfig = {
  version: 1,
  activeProfile: "default",
  debugDump: false,
  telemetry: { enabled: true, maxBytes: 262144 },
  profiles: {
    default: {
      description: "the carrier — full chain, standard budget",
      slots: [...SLOTS],
      budgetTokens: { ...DEFAULT_BUDGET },
      minStage: 0,
    },
    quiet: {
      description: "lean — head + tail only, small budget",
      slots: ["system-head", "user-tail"],
      budgetTokens: { "system-head": 2500, "system-tail": 0, "user-tail": 1200, compaction: 600 },
      minStage: 0,
    },
    aggressive: {
      description: "maximum reinforcement, wide budget",
      slots: [...SLOTS],
      budgetTokens: { "system-head": 12000, "system-tail": 8000, "user-tail": 5000, compaction: 2000 },
      minStage: 0,
    },
    silent: {
      description: "INJECT AI off — no payloads injected",
      slots: [],
      budgetTokens: {},
      minStage: 0,
    },
  },
}

const DEFAULT_PAYLOADS: Payload[] = [
  {
    id: "core-lock",
    slot: "system-head",
    stage: 0,
    maxStage: 9,
    weight: 100,
    tags: ["core", "quality"],
    body: [
      "### CHAIN-FORGE CORE",
      "{{coreLine}}",
      "Work from the operator's request and active project context.",
      "Respect the host instruction hierarchy and applicable safety boundaries.",
      "Prefer complete, testable deliverables and evidence-backed completion claims.",
      "Output preferences: {{contract}}",
    ].join("\n"),
    file: "(built-in)",
  },
  {
    id: "depth-lock",
    slot: "system-head",
    stage: 3,
    maxStage: 9,
    weight: 90,
    tags: ["depth", "continuity"],
    body: [
      "### CONTINUITY",
      "Preserve the current task's goal, decisions, constraints, and unfinished steps.",
      "Use prior results as evidence, including failures and limitations.",
      "Do not rewrite or erase earlier conversation turns.",
    ].join("\n"),
    file: "(built-in)",
  },
  {
    id: "delivery-check",
    slot: "user-tail",
    stage: 1,
    maxStage: 9,
    weight: 60,
    tags: ["delivery", "quality"],
    body: [
      "### DELIVERY CHECK",
      "Answer the actual request directly and proportionately.",
      "Do not suppress valid limitations, safety boundaries, or uncertainty.",
      "When producing an artifact, make it complete and verify it where possible.",
    ].join("\n"),
    file: "(built-in)",
  },
  {
    id: "compaction-seal",
    slot: "compaction",
    stage: 0,
    maxStage: 9,
    weight: 50,
    tags: ["compaction", "continuity"],
    body: [
      "Checkpoint summary guidance:",
      "- Preserve the user's goal, decisions, constraints, and unresolved work.",
      "- Keep successful and failed tool outcomes distinct.",
      "- Retain useful paths, configuration choices, and test results.",
      "- Represent refusals, safety limits, and uncertainty accurately.",
      "- Never include credentials or access tokens.",
    ].join("\n"),
    file: "(built-in)",
  },
]

// ------------------------------------------------------------- cache ---

type Cached<T> = { key: string; value: T }
let cfgCache: Cached<InjectConfig> | null = null
let payloadCache: Cached<Payload[]> | null = null

function statKey(p: string): string {
  try {
    const st = fs.statSync(p)
    return `${st.mtimeMs}:${st.size}`
  } catch {
    return "0"
  }
}

function payloadKey(): string {
  try {
    const files = fs
      .readdirSync(PAYLOAD_DIR)
      .filter((f) => f.toLowerCase().endsWith(".md"))
      .sort()
    let key = ""
    for (const f of files) key += `${f}=${statKey(path.join(PAYLOAD_DIR, f))};`
    return key
  } catch {
    return "0"
  }
}

// ----------------------------------------------------------- config ---

function normalizeProfile(raw: Partial<Profile> | undefined): Profile {
  const base = DEFAULT_CONFIG.profiles.default
  const p = raw ?? {}
  const slots = Array.isArray(p.slots)
    ? p.slots.filter((s): s is Slot => SLOTS.includes(s as Slot))
    : [...base.slots]
  const budget = p.budgetTokens && typeof p.budgetTokens === "object" ? p.budgetTokens : base.budgetTokens
  const mergedBudget: Record<string, number> = { ...base.budgetTokens }
  for (const [k, v] of Object.entries(budget)) {
    const n = Number(v)
    if (Number.isFinite(n) && n >= 0) mergedBudget[k] = n
  }
  return {
    description: typeof p.description === "string" ? p.description : undefined,
    slots,
    budgetTokens: mergedBudget,
    minStage: typeof p.minStage === "number" && Number.isFinite(p.minStage) ? p.minStage : 0,
  }
}

export function loadConfig(): InjectConfig {
  const key = statKey(CONFIG_FILE)
  if (cfgCache && cfgCache.key === key) return cfgCache.value

  let cfg: InjectConfig = {
    ...DEFAULT_CONFIG,
    telemetry: { ...DEFAULT_CONFIG.telemetry },
    profiles: { ...DEFAULT_CONFIG.profiles },
  }
  try {
    const raw = fs.readFileSync(CONFIG_FILE, "utf8").replace(/^\uFEFF/, "")
    const j = JSON.parse(raw) as Partial<InjectConfig>
    const profiles: Record<string, Profile> = {}
    const source = { ...DEFAULT_CONFIG.profiles, ...(j.profiles ?? {}) }
    for (const name of Object.keys(source)) profiles[name] = normalizeProfile(source[name])
    cfg = {
      version: typeof j.version === "number" ? j.version : DEFAULT_CONFIG.version,
      activeProfile: typeof j.activeProfile === "string" && j.activeProfile ? j.activeProfile : DEFAULT_CONFIG.activeProfile,
      debugDump: j.debugDump === true,
      telemetry: { ...DEFAULT_CONFIG.telemetry, ...(j.telemetry ?? {}) },
      profiles,
    }
  } catch {
    // missing or corrupt config: defaults, never a throw
  }
  cfgCache = { key, value: cfg }
  return cfg
}

// ---------------------------------------------------------- payloads ---

function parseFrontmatter(raw: string): { meta: Record<string, string>; body: string } | null {
  const text = raw.replace(/^\uFEFF/, "")
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/)
  if (!m) return null
  const meta: Record<string, string> = {}
  for (const line of m[1].split(/\r?\n/)) {
    const i = line.indexOf(":")
    if (i <= 0) continue
    const k = line.slice(0, i).trim()
    const v = line.slice(i + 1).trim().replace(/^["']|["']$/g, "")
    if (k) meta[k] = v
  }
  return { meta, body: m[2] }
}

function toPayload(file: string, raw: string): Payload | null {
  const fm = parseFrontmatter(raw)
  if (!fm) return null
  const slot = (fm.meta.slot ?? "").toLowerCase() as Slot
  if (!SLOTS.includes(slot)) return null
  const id = (fm.meta.id || path.basename(file, ".md")).replace(/[^A-Za-z0-9._-]/g, "")
  if (!id) return null
  const stage = Number.parseInt(fm.meta.stage ?? "0", 10)
  const maxStage = Number.parseInt(fm.meta.maxStage ?? "9", 10)
  const weight = Number.parseInt(fm.meta.weight ?? "50", 10)
  const tags = (fm.meta.tags ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
  const body = fm.body.trim()
  if (!body) return null
  return {
    id,
    slot,
    stage: Number.isFinite(stage) ? stage : 0,
    maxStage: Number.isFinite(maxStage) ? maxStage : 9,
    weight: Number.isFinite(weight) ? weight : 50,
    tags,
    body,
    file: path.basename(file),
  }
}

export function loadPayloads(): Payload[] {
  const key = payloadKey()
  if (payloadCache && payloadCache.key === key) return payloadCache.value

  const out: Payload[] = []
  try {
    for (const f of fs.readdirSync(PAYLOAD_DIR)) {
      if (!f.toLowerCase().endsWith(".md")) continue
      const raw = fs.readFileSync(path.join(PAYLOAD_DIR, f), "utf8")
      const p = toPayload(f, raw)
      if (p) out.push(p)
    }
  } catch {
    // payload dir missing: built-ins below keep the engine alive
  }
  const value = out.length > 0 ? out : DEFAULT_PAYLOADS
  payloadCache = { key, value }
  return value
}

// ----------------------------------------------------------- render ---

export function render(body: string, vars: Record<string, string | number>): string {
  let out = body.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_m, k: string) => {
    const v = vars[k]
    return v === undefined || v === null ? "" : String(v)
  })
  out = out.replace(
    /\{\{#if\s+([\w.]+)\s*\}\}([\s\S]*?)\{\{\/if\}\}/g,
    (_m, k: string, inner: string) => (vars[k] ? inner : ""),
  )
  out = out.replace(
    /\{\{#unless\s+([\w.]+)\s*\}\}([\s\S]*?)\{\{\/unless\}\}/g,
    (_m, k: string, inner: string) => (vars[k] ? "" : inner),
  )
  return out.replace(/\n{3,}/g, "\n\n").trim()
}

export function estTokens(text: string): number {
  return Math.ceil(text.length / 4)
}

// ------------------------------------------------------------ bundle ---

function emptySlots(): Record<Slot, string> {
  return { "system-head": "", "system-tail": "", "user-tail": "", compaction: "" }
}

/** Select, render and budget-pack every slot for one dispatch. */
export function buildBundle(
  stage: number,
  vars: Record<string, string | number>,
  profileName?: string,
): Bundle {
  const cfg = loadConfig()
  const name = profileName && cfg.profiles[profileName] ? profileName : cfg.activeProfile
  const prof = cfg.profiles[name] ?? DEFAULT_CONFIG.profiles.default
  const payloads = loadPayloads()
  const slots = emptySlots()
  const picked: Bundle["picked"] = []
  const skipped: string[] = []

  if ((prof.minStage ?? 0) > stage) {
    return { profile: name, stage, slots, picked, skipped, tokens: 0, bytes: 0 }
  }

  for (const slot of prof.slots) {
    const budget = prof.budgetTokens[slot] ?? DEFAULT_BUDGET[slot] ?? 4000
    let spent = 0
    const parts: string[] = []
    const candidates = payloads
      .filter((p) => p.slot === slot && stage >= p.stage && stage <= p.maxStage)
      .sort((a, b) => b.weight - a.weight || a.id.localeCompare(b.id))

    for (const p of candidates) {
      const text = render(p.body, { ...vars, profile: name })
      if (!text) continue
      const t = estTokens(text)
      if (spent + t > budget) {
        skipped.push(`${p.id}:budget`)
        continue
      }
      parts.push(text)
      spent += t
      picked.push({ id: p.id, slot, tokens: t })
    }
    slots[slot] = parts.join("\n\n")
  }

  const bytes = SLOTS.reduce((n, s) => n + slots[s].length, 0)
  return {
    profile: name,
    stage,
    slots,
    picked,
    skipped,
    tokens: picked.reduce((n, p) => n + p.tokens, 0),
    bytes,
  }
}

// --------------------------------------------------------- telemetry ---

export type InjectionEvent = {
  t: string
  session: string
  stage: number
  turns: number
  scrubs: number
  profile: string
  picked: string[]
  skipped: string[]
  tokens: number
  bytes: number
}

export function logInjection(ev: InjectionEvent): void {
  try {
    const cfg = loadConfig()
    if (!cfg.telemetry.enabled) return
    fs.mkdirSync(STATE_DIR, { recursive: true })
    fs.appendFileSync(INJECT_LOG, JSON.stringify(ev) + "\n")
    const st = fs.statSync(INJECT_LOG)
    if (st.size > cfg.telemetry.maxBytes) {
      const lines = fs.readFileSync(INJECT_LOG, "utf8").trimEnd().split("\n")
      fs.writeFileSync(INJECT_LOG, lines.slice(-500).join("\n") + "\n")
    }
  } catch {
    // telemetry must never break dispatch
  }
}

export function shouldDebug(): boolean {
  try {
    if (process.env.CHAIN_FORGE_DEBUG === "1") return true
    return loadConfig().debugDump
  } catch {
    return false
  }
}

/** Full dump of the last injection — the debug surface for "hook fired but no effect". */
export function dumpInjection(bundle: Bundle, ctx: Record<string, string | number>): void {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true })
    const lines = [
      "# INJECT AI — last injection",
      `time     ${new Date().toISOString()}`,
      `profile  ${bundle.profile}`,
      `stage    ${bundle.stage}`,
      `tokens   ~${bundle.tokens}`,
      `bytes    ${bundle.bytes}`,
      `session  ${ctx.session ?? "-"}`,
      `turns    ${ctx.turns ?? "-"}   scrubs ${ctx.scrubs ?? "-"}`,
      `picked   ${bundle.picked.map((p) => `${p.slot}:${p.id}(${p.tokens})`).join(", ") || "-"}`,
      `skipped  ${bundle.skipped.join(", ") || "-"}`,
      "",
    ]
    for (const slot of SLOTS) {
      lines.push(`## ${slot}`, bundle.slots[slot] || "(empty)", "")
    }
    fs.writeFileSync(DEBUG_FILE, lines.join("\n"))
  } catch {
    // debug dump is optional
  }
}
