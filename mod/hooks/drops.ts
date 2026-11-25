import type {
  ArcState,
  ArcStep,
  Creative,
  CreativeLogEntry,
  DropArt,
  DropKind,
  DropLasts,
  DropSprite,
  DropWindow,
  Drops,
  Farm,
  FarmViewDrops,
  Structure,
  Surprise,
} from '../types'
import {
  isBuiltin,
  isKind,
  isTint,
  lastsOf,
  levelOf,
  SUMMARY_MAX,
  spritesOf,
  storedLines,
  storedName,
  validateArt,
  windowOf,
} from './surprise'
import { dateKeyOf, recordOf } from './util'

// The creative drops' bookkeeping: three slots a day, the claim that keeps two
// sessions from generating one slot twice, the budget, the arcs, the memory and
// what is on show. Pure: the clock is handed in; nothing here asks the host.

export const SLOT_HOURS: readonly number[] = [9, 12, 15]
// A claim older than this with no surprise behind it is a dead claimant's: the
// slot is taken over, with the offline generator.
export const CLAIM_TTL_MS = 120_000
// A session that opens after a slot's time runs the missed slots one per this long.
export const CATCHUP_GAP_MS = 600_000
// The model: three drops a day and a retry each, never more than six calls.
export const MODEL_DAILY_CAP = 6
export const SURPRISES_MAX = 30
export const LOG_MAX = 40
export const STRUCT_MAX = 12
export const ART_STORE_MAX = 16
// How many of the log's last summaries go to the model.
export const RECENT_SENT = 12
// An arc that has not moved in this many days is let go.
export const ARC_STALL_DAYS = 14
export const NEWS_MAX = 20
export const TOTAL_MAX = 1_000_000_000
// The most creative sprites a frame draws.
export const MAX_DRAWN = 8
export const MAX_CLAIMS = 3

export type CreativeFarm = Pick<Farm, 'drops' | 'modelCalls' | 'surprises' | 'creativeLog' | 'creative' | 'newsSeen'>

const DATE_RE = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/
const isDay = (value: unknown): value is string => typeof value === 'string' && DATE_RE.test(value)
const count = (value: unknown, max: number) => {
  const n = Math.floor(Number(value))

  return Number.isFinite(n) && n > 0 ? Math.min(max, n) : 0
}

export const daysBetween = (from: string, to: string) => {
  const [y1, m1, d1] = from.split('-').map(Number) as [number, number, number]
  const [y2, m2, d2] = to.split('-').map(Number) as [number, number, number]

  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86_400_000)
}

// ---- the stored shapes: fresh, and read back ----

export const freshDrops = (): Drops => ({ day: '', done: [], claims: [] })
export const freshCreative = (): Creative => ({
  total: 0,
  arc: null,
  structures: [],
  art: [],
  festival: { d: '', tint: '' },
})

export const dropsOf = (value: unknown): Drops => {
  const item = recordOf(value)
  const done = [...new Set((Array.isArray(item.done) ? item.done : []).filter((slot: unknown) => SLOT_HOURS.includes(slot as number)))] as number[]
  const claims: Drops['claims'] = []
  for (const entry of Array.isArray(item.claims) ? item.claims : []) {
    const one = recordOf(entry)
    if (SLOT_HOURS.includes(one.slot as number) && !claims.some(claim => claim.slot === one.slot)) {
      claims.push({ slot: one.slot as number, at: count(one.at, 4_102_444_800_000) })
    }
  }

  return { day: isDay(item.day) ? item.day : '', done: done.sort((a, b) => a - b), claims: claims.slice(-MAX_CLAIMS) }
}

export const modelCallsOf = (value: unknown): { day: string; n: number } => {
  const item = recordOf(value)

  return { day: isDay(item.day) ? item.day : '', n: count(item.n, 1000) }
}

const windowStored = (value: unknown): DropWindow | null => windowOf(value) ?? null

const stepOf = (value: unknown): ArcStep | undefined => {
  const item = recordOf(value)
  const lines = storedLines(item.lines)
  const day = Math.floor(Number(item.day))
  if (!isKind(item.kind) || lines.length === 0 || !Number.isInteger(day) || day < 1 || day > 7) {
    return undefined
  }
  const sprites = spritesOf(item.sprites)
  const kind: DropKind = (item.kind === 'happening' || item.kind === 'decor') && sprites.length === 0 ? 'saying' : item.kind

  return {
    day,
    kind,
    lines,
    sprites: kind === 'happening' || kind === 'decor' ? sprites : [],
    window: kind === 'decor' ? windowStored(item.window) : null,
    lasts: lastsOf(item.lasts) ?? 'today',
    keep: item.keep === true && kind === 'decor',
    festival: isTint(item.festival) ? item.festival : '',
  }
}

const arcOf = (value: unknown): ArcState | null => {
  const item = recordOf(value)
  const name = storedName(item.name)
  const steps = (Array.isArray(item.steps) ? item.steps : [])
    .slice(0, 7)
    .map(stepOf)
    .filter((step): step is ArcStep => step !== undefined)
  if (name === '' || steps.length < 2 || !isDay(item.start)) {
    return null
  }

  return {
    name,
    made: item.made === 'haiku' ? 'haiku' : 'local',
    start: item.start,
    last: isDay(item.last) ? item.last : item.start,
    at: Math.min(steps.length, count(item.at, 7)),
    steps,
  }
}

export const surprisesOf = (value: unknown): Surprise[] => {
  const out: Surprise[] = []
  for (const entry of (Array.isArray(value) ? value : []).slice(-SURPRISES_MAX * 2)) {
    const item = recordOf(entry)
    const lines = storedLines(item.lines)
    const name = storedName(item.name)
    if (!isDay(item.day) || !SLOT_HOURS.includes(item.slot as number) || !isKind(item.kind) || name === '' || lines.length === 0) {
      continue
    }
    const sprites = spritesOf(item.sprites)
    const kind: DropKind = (item.kind === 'happening' || item.kind === 'decor') && sprites.length === 0 ? 'saying' : item.kind
    out.push({
      day: item.day,
      slot: item.slot as number,
      kind,
      name,
      lines,
      sprites: kind === 'happening' || kind === 'decor' ? sprites : [],
      window: kind === 'decor' ? windowStored(item.window) : null,
      lasts: lastsOf(item.lasts) ?? 'today',
      made: item.made === 'haiku' ? 'haiku' : 'local',
      arc: storedName(item.arc),
      step: Math.min(7, count(item.step, 7)),
      festival: isTint(item.festival) ? item.festival : '',
    })
  }

  return out.slice(-SURPRISES_MAX)
}

const summaryText = (value: unknown) =>
  // eslint-disable-next-line no-control-regex
  typeof value === 'string' ? value.replace(/[^\x20-\x7e]/g, ' ').trim().slice(0, SUMMARY_MAX) : ''

export const logOf = (value: unknown): CreativeLogEntry[] => {
  const out: CreativeLogEntry[] = []
  for (const entry of (Array.isArray(value) ? value : []).slice(-LOG_MAX * 2)) {
    const item = recordOf(entry)
    const name = storedName(item.name)
    const summary = summaryText(item.summary)
    if (!isDay(item.day) || !isKind(item.kind) || name === '' || summary === '') {
      continue
    }
    const arc = storedName(item.arc)
    out.push({ day: item.day, name, kind: item.kind, summary, ...(arc === '' ? {} : { arc }) })
  }

  return out.slice(-LOG_MAX)
}

const structureOf = (value: unknown): Structure | undefined => {
  const item = recordOf(value)
  const sprites = spritesOf(item.sprites)
  const name = storedName(item.name)
  if (name === '' || sprites.length === 0 || !isDay(item.day)) {
    return undefined
  }

  return { name, day: item.day, arc: storedName(item.arc), sprites }
}

export const creativeOf = (value: unknown): Creative => {
  const item = recordOf(value)
  const art: DropArt[] = []
  for (const entry of Array.isArray(item.art) ? item.art : []) {
    const one = validateArt(entry)
    if (one) {
      const at = art.findIndex(other => other.id === one.id)
      if (at >= 0) {
        art.splice(at, 1)
      }
      art.push(one)
    }
  }
  const festival = recordOf(item.festival)

  return {
    total: count(item.total, TOTAL_MAX),
    arc: arcOf(item.arc),
    structures: (Array.isArray(item.structures) ? item.structures : [])
      .slice(-STRUCT_MAX * 2)
      .map(structureOf)
      .filter((one): one is Structure => one !== undefined)
      .slice(-STRUCT_MAX),
    art: art.slice(-ART_STORE_MAX),
    festival: isDay(festival.d) && isTint(festival.tint) ? { d: festival.d, tint: festival.tint } : { d: '', tint: '' },
  }
}

// The ids of the news announced: plain ids, once each, the last NEWS_MAX kept.
export const NEWS_ID_RE = /^[A-Za-z0-9._-]{1,32}$/
export const newsSeenOf = (value: unknown): string[] =>
  [...new Set((Array.isArray(value) ? value : []).filter((id): id is string => typeof id === 'string' && NEWS_ID_RE.test(id)))].slice(-NEWS_MAX)

export type News = { id: string; line: string }
export const NEWS_LINE_MAX = 80

// A news item read strictly: an id and a line of printable ASCII, the line cut
// to 80. Anything else (null, a wrong type, no id, an empty or non-ASCII line)
// is nothing.
export const newsOf = (value: unknown): News | null => {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null
  }
  const item = value as Record<string, unknown>
  if (typeof item.id !== 'string' || !NEWS_ID_RE.test(item.id) || typeof item.line !== 'string') {
    return null
  }
  const line = item.line.trim()
  if (line === '' || !/^[\x20-\x7e]+$/.test(line)) {
    return null
  }

  return { id: item.id, line: line.slice(0, NEWS_LINE_MAX).trimEnd() }
}

export const withNewsSeen = <F extends Pick<Farm, 'newsSeen'>>(farm: F, id: string): F =>
  farm.newsSeen.includes(id) ? farm : { ...farm, newsSeen: [...farm.newsSeen, id].slice(-NEWS_MAX) }

// ---- the schedule ----

const slotAt = (now: Date, hour: number) => new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour).getTime()

export type DueInput = {
  drops: Drops
  nowMs: number
  // When this session began and when it last ran a drop (0: none yet), on the session clock.
  startedAt: number
  lastAt: number
}

// Drops come on workdays only, Monday to Friday.
export const isDropDay = (now: Date) => now.getDay() >= 1 && now.getDay() <= 5

// The slot to run now, if any: the earliest whose time has passed today that is
// not done and not under a fresh claim. A slot whose time came while the session
// was open runs at once; one the session missed (it opened after) runs at most
// one every ten minutes of the session. Plain arithmetic. None on a weekend.
export const dueSlot = ({ drops, nowMs, startedAt, lastAt }: DueInput): number | undefined => {
  const now = new Date(nowMs)
  if (!isDropDay(now)) {
    return undefined
  }
  const isToday = drops.day === dateKeyOf(now)
  for (const hour of SLOT_HOURS) {
    const at = slotAt(now, hour)
    if (nowMs < at) {
      return undefined
    }
    if (isToday && drops.done.includes(hour)) {
      continue
    }
    const held = isToday ? drops.claims.find(claim => claim.slot === hour) : undefined
    if (held && nowMs - held.at < CLAIM_TTL_MS) {
      continue
    }
    const isCatchUp = startedAt > at
    if (isCatchUp && lastAt > 0 && nowMs - lastAt < CATCHUP_GAP_MS) {
      return undefined
    }

    return hour
  }

  return undefined
}

// The slot a forced surprise (JEB_DROP_NOW) is made for: the latest slot whose hour has
// come today, else the first. It only flavours the prompt; the forced surprise is not
// recorded against it (see applyDelivery's isForced).
export const forcedSlot = (nowMs: number): number => {
  const hour = new Date(nowMs).getHours()

  return [...SLOT_HOURS].reverse().find(slot => slot <= hour) ?? SLOT_HOURS[0]
}

export type Claimed<F> = { farm: F; outcome: 'claimed' | 'takeover' | 'busy' | 'done' }

// Claims a slot on the farm as stored, before anything is generated: the one
// that finds it free (or held by a dead claimant) has it, and the other finds it
// busy or done. A takeover is the offline generator's.
export const claimSlot = <F extends Pick<Farm, 'drops'>>(farm: F, slot: number, nowMs: number): Claimed<F> => {
  const key = dateKeyOf(new Date(nowMs))
  const isNewDay = farm.drops.day !== key
  const day: Drops = isNewDay ? { day: key, done: [], claims: [] } : farm.drops
  const here = isNewDay ? { ...farm, drops: day } : farm
  if (day.done.includes(slot)) {
    return { farm: here, outcome: 'done' }
  }
  const held = day.claims.find(claim => claim.slot === slot)
  if (held && nowMs - held.at < CLAIM_TTL_MS) {
    return { farm: here, outcome: 'busy' }
  }
  const claims = [...day.claims.filter(claim => claim.slot !== slot), { slot, at: nowMs }].slice(-MAX_CLAIMS)

  return { farm: { ...farm, drops: { ...day, claims } }, outcome: held ? 'takeover' : 'claimed' }
}

// ---- the budget ----

// Takes one model call from the day's six, on the farm as stored.
export const reserveModel = <F extends Pick<Farm, 'modelCalls'>>(farm: F, nowMs: number): { farm: F; ok: boolean } => {
  const key = dateKeyOf(new Date(nowMs))
  const calls = farm.modelCalls.day === key ? farm.modelCalls : { day: key, n: 0 }
  if (calls.n >= MODEL_DAILY_CAP) {
    return { farm: calls === farm.modelCalls ? farm : { ...farm, modelCalls: calls }, ok: false }
  }

  return { farm: { ...farm, modelCalls: { day: key, n: calls.n + 1 } }, ok: true }
}

// A reservation's nonce: 8 hex digits.
export const isNonce = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{8}$/.test(value)

// The nonces as stored: the valid ones, once each, at most `max`.
export const modelTakenOf = (value: unknown, max: number): string[] =>
  Array.isArray(value) ? [...new Set(value.filter(isNonce))].slice(0, max) : []

// `reserveModel` with the reservation marked by `nonce` (made once per reservation, so a
// re-apply onto another session's write keeps it). The nonces are today's: they start
// over when the day changes. A farm that already holds the nonce is returned as it is.
export const reserveModelAs = <F extends Pick<Farm, 'modelCalls' | 'modelTaken'>>(
  farm: F,
  nowMs: number,
  nonce: string,
): { farm: F; ok: boolean } => {
  const key = dateKeyOf(new Date(nowMs))
  const isToday = farm.modelCalls.day === key
  const before = isToday ? farm.modelTaken : []
  if (before.includes(nonce)) {
    return { farm, ok: true }
  }
  const taken = reserveModel(farm, nowMs)
  if (!taken.ok) {
    return { farm: isToday ? taken.farm : { ...taken.farm, modelTaken: [] }, ok: false }
  }

  return { farm: { ...taken.farm, modelTaken: [...before, nonce].slice(-MODEL_DAILY_CAP) }, ok: true }
}

export const callsToday = (farm: Pick<Farm, 'modelCalls'>, nowMs: number) =>
  farm.modelCalls.day === dateKeyOf(new Date(nowMs)) ? farm.modelCalls.n : 0

// ---- arcs ----

export const arcIsStalled = (arc: ArcState, today: string) => daysBetween(arc.last, today) > ARC_STALL_DAYS

// The arc that is under way (not finished, not stalled), or nothing.
export const activeArc = (farm: Pick<Farm, 'creative'>, today: string): ArcState | null => {
  const { arc } = farm.creative

  return arc && arc.at < arc.steps.length && !arcIsStalled(arc, today) ? arc : null
}

// The arc's next step if its day has come: step 1 is the day it began.
export const nextArcStep = (arc: ArcState | null, today: string): { step: ArcStep; index: number } | undefined => {
  if (!arc || arc.at >= arc.steps.length || arcIsStalled(arc, today)) {
    return undefined
  }
  const step = arc.steps[arc.at] as ArcStep

  return daysBetween(arc.start, today) + 1 >= step.day ? { step, index: arc.at } : undefined
}

// ---- delivering a surprise ----

export type Delivery = {
  slot: number
  made: 'haiku' | 'local'
  kind: DropKind
  name: string
  lines: string[]
  summary: string
  sprites: DropSprite[]
  window: DropWindow | null
  lasts: DropLasts
  festival: string
  keep: boolean
  // Custom pictures this drop defines.
  art: DropArt[]
  // Part of an arc: its name and step (1-based); `begin` is the arc itself when
  // this drop starts one.
  arc: { name: string; step: number } | null
  begin?: ArcState
}

export const isLive = (item: { day: string; lasts: DropLasts }, today: string) => {
  const age = daysBetween(item.day, today)

  return item.lasts === 'week' ? age >= 0 && age < 7 : age === 0
}

const expire = (list: readonly Surprise[], today: string) => list.filter(item => isLive(item, today))

const sameSprites = (sprites: readonly DropSprite[], id: string) => sprites.some(sprite => sprite.sprite === id)

// The pictures the farm keeps, at most sixteen, the least recently used out
// first (one a structure or the arc names goes last): a picture a drop defines
// or names moves to the newest end.
const keepArt = (
  have: readonly DropArt[],
  add: readonly DropArt[],
  used: readonly string[],
  holds: (id: string) => boolean,
): DropArt[] => {
  let list = [...have]
  for (const art of add) {
    list = [...list.filter(other => other.id !== art.id), art]
  }
  for (const id of used) {
    const at = list.findIndex(other => other.id === id)
    if (at >= 0) {
      list = [...list.slice(0, at), ...list.slice(at + 1), list[at] as DropArt]
    }
  }
  while (list.length > ART_STORE_MAX) {
    const free = list.findIndex(art => !holds(art.id))
    list.splice(free >= 0 ? free : 0, 1)
  }

  return list
}

// Writes a delivered surprise into the farm as stored: the surprise, its log
// line, the count, the arc (begun, stepped or finished), a permanent structure
// when the final step keeps one, the festival, the custom art, and the slot done
// with its claim let go. A slot already done delivers nothing. A forced delivery
// (JEB_DROP_NOW) is stored as a surprise but leaves the day's slots and claims as they are.
export const applyDelivery = <F extends CreativeFarm>(
  farm: F,
  d: Delivery,
  nowMs: number,
  isForced = false,
): { farm: F; surprise?: Surprise } => {
  const today = dateKeyOf(new Date(nowMs))
  const day: Drops = farm.drops.day === today ? farm.drops : { day: today, done: [], claims: [] }
  if (!isForced && day.done.includes(d.slot)) {
    return { farm }
  }
  // Two sessions may each begin an arc in different slots: the one that finds
  // another under way delivers its first step as a plain surprise.
  const begin = d.begin && !activeArc(farm, today) ? d.begin : undefined
  const info = d.begin && !begin ? null : d.arc
  const surprise: Surprise = {
    day: today,
    slot: d.slot,
    kind: d.kind,
    name: d.name,
    lines: d.lines,
    sprites: d.sprites,
    window: d.window,
    lasts: d.lasts,
    made: d.made,
    arc: info?.name ?? '',
    step: info?.step ?? 0,
    festival: d.festival,
  }
  const log: CreativeLogEntry = {
    day: today,
    name: d.name,
    kind: d.kind,
    summary: summaryText(d.summary) || summaryText(d.lines[0]),
    ...(info ? { arc: info.name } : {}),
  }

  // The arc: a new one is stored then stepped; one under way is stepped.
  let arc = begin ?? farm.creative.arc
  if (arc && info && arc.name === info.name) {
    arc = { ...arc, at: info.step, last: today }
    if (begin) {
      arc = { ...arc, start: today }
    }
  }
  if (arc && (arc.at >= arc.steps.length || arcIsStalled(arc, today))) {
    arc = null
  }

  let structures = farm.creative.structures
  if (d.keep && d.sprites.length > 0) {
    structures = [...structures, { name: d.name, day: today, arc: info?.name ?? '', sprites: d.sprites }].slice(-STRUCT_MAX)
  }
  const holds = (id: string) =>
    structures.some(one => sameSprites(one.sprites, id)) || (arc?.steps.some(step => sameSprites(step.sprites, id)) ?? false)
  const named = d.sprites.map(sprite => sprite.sprite)

  return {
    surprise,
    farm: {
      ...farm,
      drops: isForced
        ? { day: today, done: day.done, claims: day.claims }
        : { day: today, done: [...day.done, d.slot].sort((a, b) => a - b), claims: day.claims.filter(claim => claim.slot !== d.slot) },
      surprises: [...expire(farm.surprises, today), surprise].slice(-SURPRISES_MAX),
      creativeLog: [...farm.creativeLog, log].slice(-LOG_MAX),
      creative: {
        total: Math.min(TOTAL_MAX, farm.creative.total + 1),
        arc,
        structures,
        art: keepArt(farm.creative.art, d.art, named, holds),
        festival: d.festival !== '' ? { d: today, tint: d.festival } : farm.creative.festival,
      },
    },
  }
}

// ---- what the model is told, and what is on show ----

export const levelOfFarm = (farm: Pick<Farm, 'creative'>) => levelOf(farm.creative.total)

// The last twelve summaries of the log, "day name: summary", newest last.
export const recentSummaries = (log: readonly CreativeLogEntry[]) =>
  log.slice(-RECENT_SENT).map(entry => `${entry.day} ${entry.name}${entry.arc ? ` (arc ${entry.arc})` : ''}: ${entry.summary}`)

export const todays = (surprises: readonly Surprise[], now: Date) => surprises.filter(item => item.day === dateKeyOf(now))

// The sayings of today: they join the bubble pool for the day.
export const sayingPool = (surprises: readonly Surprise[], now: Date): string[] =>
  todays(surprises, now)
    .filter(item => item.kind === 'saying')
    .flatMap(item => item.lines)

// The almanac lines still live (today's, or the week's).
export const almanacLines = (surprises: readonly Surprise[], now: Date): string[] => {
  const today = dateKeyOf(now)

  return surprises.filter(item => item.kind === 'almanac' && isLive(item, today)).flatMap(item => item.lines.slice(0, 1))
}



// What shows of the drops: the decor with a picture to draw, the
// structures, only the custom art any of them names, and the festival.
export const viewOfDrops = (farm: Pick<Farm, 'surprises' | 'creative'>): FarmViewDrops => {
  const decor = farm.surprises
    .filter(item => item.kind === 'decor' && item.sprites.length > 0)
    .map(item => ({ day: item.day, sprites: item.sprites, window: item.window, lasts: item.lasts }))
  const structures = farm.creative.structures.map(one => one.sprites)
  const named = new Set([...decor.flatMap(item => item.sprites), ...structures.flat()].map(sprite => sprite.sprite))

  return { decor, structures, art: farm.creative.art.filter(art => named.has(art.id)), festival: farm.creative.festival }
}

export type Placed = { sprite: DropSprite; art?: DropArt }

// The creative sprites on show at `now`, at most eight: the permanent
// structures (always), then the decor within its days and its hours. A sprite
// whose picture is gone from the art is skipped.
export const dropLooks = (view: Partial<FarmViewDrops> | undefined, now: Date): Placed[] => {
  const hasDecor = Array.isArray(view?.decor) && view.decor.length > 0
  const hasStructures = Array.isArray(view?.structures) && view.structures.length > 0
  if (!view || (!hasDecor && !hasStructures)) {
    return []
  }
  const today = dateKeyOf(now)
  const hour = now.getHours()
  const art = new Map((Array.isArray(view.art) ? view.art : []).map(one => [one.id, one]))
  const out: Placed[] = []
  const add = (sprite: DropSprite) => {
    const one = art.get(sprite.sprite)
    if (!isBuiltin(sprite.sprite) && !one) {
      return
    }
    if (out.length < MAX_DRAWN) {
      out.push(one ? { sprite, art: one } : { sprite })
    }
  }
  for (const group of Array.isArray(view.structures) ? view.structures : []) {
    group.forEach(add)
  }
  for (const item of Array.isArray(view.decor) ? view.decor : []) {
    const isShown = isLive(item, today) && (item.window === null || (hour >= item.window.from && hour < item.window.to))
    if (isShown) {
      item.sprites.forEach(add)
    }
  }

  return out
}


// The tint of today's festival, or ''.
export const festivalOf = (view: Partial<FarmViewDrops> | undefined, now: Date) =>
  view?.festival && view.festival.d !== '' && view.festival.d === dateKeyOf(now) ? view.festival.tint : ''
