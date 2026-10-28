import type { ActiveEvent, Anim, Crop, IdleAct, Mood, Pose, SquareCode, Truck, Visit } from '../types'
import { AREA_KEY_RE } from './areas'
import type { Talk } from './options'
import { HAND_LOOKS, hashOf } from './shared'
import { cleanText, recordOf } from './util'
import { BUILDINGS, MAX_COWS } from './workday'

// The live record: what one running session shows right now, for the desktop to
// draw. Each session writes its own under `live:<token>` (the token is a keyed hash
// of its session, new each day, see anonymize.ts), only when something in it
// changed, and at most once a 500 ms tick; it takes it out when the session ends.
// Every field is the session's own state, already anonymized: the line is the one
// in Jeb's bubble (his own words), the cows are neighbors' numbers, the hands a
// look and a plot. Pure; the store calls live in register.tsx.
//
// A field at its default is left out, so a quiet record is a few dozen bytes. `v`,
// `at` (ms, when it was written) and `frame` (the scene's animation frame then)
// are always there; `at` and `frame` move with every write but never cause one.

export const LIVE_PREFIX = 'live:'
export const LIVE_VERSION = 1
// A record older than this, whose session no fresh heartbeat names, is taken out.
export const LIVE_TTL_MS = 600_000
// The most live records kept, this session's own among them.
export const MAX_LIVE = 8
export const MAX_LIVE_LINE = 120

export type LiveHand = { plot: Crop; look: number }
export type LiveFx = 'wag' | 'wink' | 'puff' | 'sip'
export type LiveBuilding = 'app' | 'hot' | 'database'

// The fields, each with its default when left out.
export type LiveBody = {
  pose?: Pose // 'none'
  mood?: Mood // 'idle'
  line?: string // only while the bubble is up (8 s from saidAt)
  saidAt?: number // with the line: when it was said (ms)
  dim?: true
  act?: IdleAct // 'banjo'
  busy?: true
  dogRun?: number // 0: cells Blue has run left of home
  still?: true
  truck?: Truck // none
  visit?: Visit // none
  event?: ActiveEvent // none
  fx?: LiveFx[] // none
  gated?: true
  stitch?: true
  weather?: { kind: 'rain' | 'dry'; plot: Crop | 'all' } // none
  building?: LiveBuilding // none
  hands?: LiveHand[] // none
  more?: Partial<Record<Crop, number>> // none
  mates?: number // 0
  cows?: number[] // none: neighbors' numbers, at most three
  moreCows?: number // 0
  live?: SquareCode // 'N': this session's square so far
  rainbow?: true
  wet?: true
  star?: number // 0
  hidden?: true
  talk?: Talk // 'ambient'
  area?: string // none: the key of the project's area, 8 hex (see areas.ts)
}

export type LiveRecord = { v: typeof LIVE_VERSION; at: number; frame: number } & LiveBody

// Every key a live record may hold, in the order it is written.
export const LIVE_FIELDS = [
  'v',
  'at',
  'frame',
  'pose',
  'mood',
  'line',
  'saidAt',
  'dim',
  'act',
  'busy',
  'dogRun',
  'still',
  'truck',
  'visit',
  'event',
  'fx',
  'gated',
  'stitch',
  'weather',
  'building',
  'hands',
  'more',
  'mates',
  'cows',
  'moreCows',
  'live',
  'rainbow',
  'wet',
  'star',
  'hidden',
  'talk',
  'area',
] as const

// What the session hands in: the scene's state (see `snapshot` in register.tsx)
// and the bits of its own the scene does not hold.
export type LiveInput = {
  anim: Anim
  mood: Mood
  line: string
  saidAt: number
  isBusy: boolean
  isStill: boolean
  talk: Talk
  // Every loose cow, as a neighbor's number.
  cows: readonly number[]
  // The key of the project's area, when the session works in one.
  area?: string
}

const FX: readonly LiveFx[] = ['wag', 'wink', 'puff', 'sip']

// The Compose service a building's glyph stands for.
const serviceOf = (glyph: string) =>
  Object.entries(BUILDINGS).find(([, shown]) => shown === glyph)?.[0] as LiveBuilding | undefined

// The record's fields as they stand, the defaults left out.
export const liveBody = (input: LiveInput): LiveBody => {
  const { anim } = input
  const body: LiveBody = {}
  if (anim.pose !== 'none') {
    body.pose = anim.pose
  }
  if (input.mood !== 'idle') {
    body.mood = input.mood
  }
  const line = cleanText(input.line, MAX_LIVE_LINE)
  if (anim.isTalking && line !== '') {
    body.line = line
    body.saidAt = input.saidAt
  }
  if (anim.isDim) {
    body.dim = true
  }
  if (anim.idleAct !== 'banjo') {
    body.act = anim.idleAct
  }
  if (input.isBusy) {
    body.busy = true
  }
  if (anim.dogRun > 0) {
    body.dogRun = anim.dogRun
  }
  if (input.isStill) {
    body.still = true
  }
  if (anim.truck) {
    const { t, load, sputter, dog } = anim.truck
    body.truck = { t, load, sputter, dog }
  }
  if (anim.visit) {
    const { kind, x, facing, phase } = anim.visit
    body.visit = { kind, x, facing, phase }
  }
  if (anim.event) {
    const { id, t, dur, v, art } = anim.event
    body.event = art ? { id, t, dur, v, art } : { id, t, dur, v }
  }
  const fx = FX.filter(key => anim[key])
  if (fx.length > 0) {
    body.fx = fx
  }
  if (anim.isGated) {
    body.gated = true
  }
  if (anim.stitch) {
    body.stitch = true
  }
  if (anim.weather.kind !== 'none') {
    body.weather = { kind: anim.weather.kind, plot: anim.weather.plot }
  }
  const building = serviceOf(anim.building)
  if (building) {
    body.building = building
  }
  if (anim.hands.length > 0) {
    body.hands = anim.hands.map(hand => ({ plot: hand.plot, look: hashOf(hand.id) % HAND_LOOKS }))
  }
  const more = Object.entries(anim.more).filter(([, n]) => typeof n === 'number' && n > 0)
  if (more.length > 0) {
    body.more = Object.fromEntries(more) as Partial<Record<Crop, number>>
  }
  if (anim.mates > 0) {
    body.mates = anim.mates
  }
  if (input.cows.length > 0) {
    body.cows = input.cows.slice(0, MAX_COWS)
  }
  if (input.cows.length > MAX_COWS) {
    body.moreCows = input.cows.length - MAX_COWS
  }
  if (anim.live !== 'N') {
    body.live = anim.live
  }
  if (anim.rainbow) {
    body.rainbow = true
  }
  if (anim.wet) {
    body.wet = true
  }
  if (anim.star > 0) {
    body.star = anim.star
  }
  if (input.talk !== 'ambient') {
    body.talk = input.talk
  }
  if (input.area !== undefined && AREA_KEY_RE.test(input.area)) {
    body.area = input.area
  }

  return body
}

// The record as written: its version, when, the frame, and the fields.
export const liveRecord = (body: LiveBody, at: number, frame: number): LiveRecord => ({
  v: LIVE_VERSION,
  at,
  frame,
  ...body,
})

export const liveKey = (token: string) => `${LIVE_PREFIX}${token}`

// The token of a store key, if it is a live record's.
export const tokenOfKey = (key: string) => (key.startsWith(LIVE_PREFIX) ? key.slice(LIVE_PREFIX.length) : undefined)

// When a stored record was written, if it reads as one.
export const liveAtOf = (value: unknown) => {
  const item = recordOf(value)
  const at = Number(item.at)

  return item.v === LIVE_VERSION && Number.isFinite(at) && at > 0 ? at : undefined
}

// The other sessions' records to take out: a record that does not read as one, or
// is older than the TTL (or from the future) and not named by a fresh heartbeat;
// then, past MAX_LIVE with this session's own, the oldest of the rest (the ones a
// heartbeat names go last). `self` is never among them.
export const livePrune = (
  records: readonly { token: string; at: number | undefined }[],
  linked: ReadonlySet<string>,
  self: string,
  nowMs: number,
): string[] => {
  const gone: string[] = []
  const kept: { token: string; at: number; isLinked: boolean }[] = []
  for (const { token, at } of records) {
    if (token === self) {
      continue
    }
    const isLinked = linked.has(token)
    const isFresh = at !== undefined && at > nowMs - LIVE_TTL_MS && at <= nowMs + LIVE_TTL_MS
    if (at === undefined || (!isLinked && !isFresh)) {
      gone.push(token)
    } else {
      kept.push({ token, at, isLinked })
    }
  }
  kept.sort((a, b) => Number(b.isLinked) - Number(a.isLinked) || b.at - a.at)

  return [...gone, ...kept.slice(MAX_LIVE - 1).map(one => one.token)]
}
