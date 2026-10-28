import type { Crop } from '../types'
import type { DenyRule } from './classify'
import { CROP_NAMES } from './crops'

// Jeb's lines and numbers for the real workday: tests as weather, lint as
// weeding, the Compose service as a building, a triage ticket as a loose cow,
// the user's deny rules, and the talk-less dial. Pure.

// Tests as weather.
export const TEST_RUN_LINE = "Watchin' the sky…"
export const RAIN_LINE = 'Rain on the corn.'
export const BAD_BATCH_LINE = 'Bad batch.'
export const FIRST_RAIN_LINE = 'Rain finally come.'
export const COUNTY_RAIN_LINE = 'Whole county got rain.'
export const DROUGHT_LINE = 'Drought down the valley.'
export const STREAK_LINE = "Three bad batches runnin'."
export const HAND_WATER_LINE = "Hand's waterin' the whole county."

// Lint and analysis as weeding.
export const CLEAN_LINE = 'Rows are clean.'
export const WEEDS_LINE = "Weeds comin' up."
export const PHPSTAN_LINE = "Noted the weeds. Leavin' 'em."
export const HOED_LINE = 'Hoed the rows.'

// Docker Compose as the buildings.
export const UP_LINE = "Firin' up the barn."
export const RUN_LINE = 'Hired a day hand.'

// The building a service stands for, drawn by the house: the barn, the
// hothouse, the root cellar. Any other service has none.
export const BUILDINGS: Readonly<Record<string, string>> = { app: '🛖', hot: '🌱', database: '🥔' }

export const buildingOf = (svc: string | undefined) =>
  svc !== undefined && Object.hasOwn(BUILDINGS, svc) ? (BUILDINGS[svc] as string) : ''

// The service a cooldown is kept under: the three known ones, or 'other'.
export const serviceKey = (svc: string | undefined) =>
  svc !== undefined && Object.hasOwn(BUILDINGS, svc) ? svc : 'other'

// The deny rules in Jeb's voice.
export const DENY_LINES: Record<DenyRule, string> = {
  reset: "Ain't backin' the wagon up without the boss.",
  force: "Not pushin' that fence over.",
  down: 'Barn stays standin\'.',
  rmrf: "Not burnin' the field.",
  clean: "Leavin' the crop in the ground.",
}

// How long each thing keeps quiet after it speaks, in milliseconds.
export const TEST_CAP_MS = 45_000
export const LINT_CAP_MS = 90_000
export const BUILDING_CAP_MS = 600_000
export const DENY_CAP_MS = 600_000
export const HUSH_MS = 300_000
export const BUSY_TALK_MS = 600_000
export const IDLE_TALK_MS = 300_000

// Fails in a row that earn the streak line.
export const STREAK_AT = 3

// The rain or the dry spell lasts this many 500 ms ticks (about six seconds).
export const WEATHER_TICKS = 12

// A stream is in a writing burst past this many text chunks in this many ticks.
export const BURST_CHUNKS = 20
export const BURST_TICKS = 4

export const MAX_COWS = 3
export const MAX_KEPT_COWS = 9
export const MAX_SEEN_KEYS = 64
const KEY = /\b[A-Z][A-Z0-9]{1,9}-\d+\b/g
const MAX_KEY = 16
const MAX_KEYS = 5

// Only ticket keys (BRKT-86) from a string, at most five, and nothing else of it.
// They are turned into neighbors' numbers as soon as they are read, and kept as no text.
export const ticketKeys = (text: unknown): string[] => {
  if (typeof text !== 'string') {
    return []
  }
  const found: string[] = []
  for (const match of text.matchAll(KEY)) {
    const key = match[0]
    if (key.length <= MAX_KEY && !found.includes(key)) {
      found.push(key)
    }
    if (found.length >= MAX_KEYS) {
      break
    }
  }

  return found
}

// The cows are neighbors' numbers (see anonymize.ts), never the keys themselves.
export const cowLine = (fresh: readonly number[]) =>
  fresh.length === 1 ? `Neighbor's cow got loose: number ${fresh[0]}.` : `${fresh.length} cows loose.`

// A cow's label: its number.
export const cowLabel = (n: number) => `#${n}`

// Which plot a filtered test's rain falls on: the same command, the same plot.
export const plotFor = (seed: string): Crop => {
  let sum = 0
  for (let i = 0; i < seed.length; i += 1) {
    sum = (sum * 31 + seed.charCodeAt(i)) % 9973
  }

  return CROP_NAMES[sum % CROP_NAMES.length] as Crop
}

// Every line this module can say, for the glyph checks.
export const WORKDAY_LINES = [
  TEST_RUN_LINE, RAIN_LINE, BAD_BATCH_LINE, FIRST_RAIN_LINE, COUNTY_RAIN_LINE, DROUGHT_LINE,
  STREAK_LINE, HAND_WATER_LINE, CLEAN_LINE, WEEDS_LINE, PHPSTAN_LINE, HOED_LINE, UP_LINE, RUN_LINE,
  ...Object.values(DENY_LINES), cowLine([42]), cowLine([4, 21, 99]),
]
