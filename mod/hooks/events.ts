import type { EventId } from '../types'
import { isNightHour, isThirdSaturdayOfOctober, moonPhase } from './almanac'
import { JAR_PRICE } from './homestead'
import { pickWeighted } from './util'
import { spanOf } from './visits'

// Random happenings: which can run right now, and what Jeb says as they go.
// Pure; the clock and the dice are handed in.

export type EventCtx = {
  now: Date
  isBusy: boolean
  errorStreak: number
}

// What happens a given fraction (0-1) of the way through, and what Jeb says.
// A `sell` beat's line is what the sale turned out to be: `ifSold` when a jar went,
// `ifNot` when none did (both fall back to `line`).
export type Beat = {
  at: number
  line: string
  effect?: 'sell' | 'raid' | 'bark'
  ifSold?: string
  ifNot?: string
}

export const EVENT_IDS: EventId[] = [
  'revenuer',
  'neighbor',
  'bear',
  'whistlepig',
  'mothman',
  'bugs',
  'bells',
  'storm',
  'fog',
  'turkeys',
  'parachute',
  'track',
  'hornworm',
  'applebutter',
  'bees',
  'sorghum',
  'ramps',
  'sang',
  'quilting',
  'britches',
]

// 500 ms ticks: 30 to 60 seconds, roughly three times what they once were.
export const DURATIONS: Record<EventId, [number, number]> = {
  revenuer: [84, 108],
  neighbor: [72, 96],
  bear: [60, 96],
  whistlepig: [60, 84],
  mothman: [48, 72],
  bugs: [72, 120],
  bells: [48, 72],
  storm: [72, 120],
  fog: [84, 120],
  turkeys: [72, 108],
  parachute: [90, 120],
  track: [60, 60],
  hornworm: [60, 90],
  applebutter: [72, 108],
  bees: [60, 84],
  sorghum: [72, 96],
  ramps: [60, 84],
  sang: [60, 84],
  quilting: [72, 96],
  britches: [72, 96],
  // A creative drop's happening: 30 to 60 seconds.
  drop: [60, 120],
}

// The stretches of a happening (fractions of its run) where nothing on the road
// moves: it stands, and the scene writes a frame only on the slow 3 s cadence.
// The revenuer, the storm, the turkeys and the parachute move all the way.
const REST: Record<EventId, readonly [number, number][]> = {
  revenuer: [],
  neighbor: [[0.5, 0.8]],
  bear: [[0, 1]],
  whistlepig: [[0, 1]],
  mothman: [[0, 1]],
  bugs: [[0, 1]],
  bells: [[0, 1]],
  storm: [],
  fog: [[0, 1]],
  turkeys: [],
  parachute: [],
  track: [[0, 1]],
  hornworm: [[0, 1]],
  applebutter: [[0, 1]],
  bees: [[0, 1]],
  sorghum: [[0, 1]],
  ramps: [[0, 1]],
  sang: [[0, 1]],
  quilting: [[0, 1]],
  britches: [[0, 1]],
  drop: [[0, 1]],
}

// The tick a happening's current standing stretch began (the first tick when
// it stands from the start), or nothing while it moves.
export const restOf = (ev: { id: EventId; t: number; dur: number }): number | undefined => {
  const p = ev.t / ev.dur
  const window = REST[ev.id].find(([from, to]) => p >= from && p < to)

  return window ? Math.ceil(window[0] * ev.dur) : undefined
}

const inMonths = (date: Date, ...months: number[]) => months.includes(date.getMonth())

export const weightOf = (id: EventId, ctx: EventCtx): number => {
  const { now } = ctx
  const month = now.getMonth()
  const day = now.getDate()
  const hour = now.getHours()
  const weekday = now.getDay()
  const isNight = isNightHour(hour)
  const isWeekend = weekday === 0 || weekday === 6

  switch (id) {
    case 'revenuer':
      return 1
    case 'neighbor':
      return 3
    case 'bear':
      return inMonths(now, 8, 9, 10) ? 3 : 0
    case 'whistlepig':
      return inMonths(now, 5, 6, 7, 8) ? 3 : 0
    case 'mothman': {
      if (!isNight) {
        return 0
      }
      const { phase } = moonPhase(now)
      const isDark = phase < 0.1 || phase > 0.9
      const isLateSeptember = month === 8 && day >= 20
      const isHalloween = month === 9 && day === 31

      return (isHalloween ? 8 : isLateSeptember ? 5 : 1.5) * (isDark ? 1.5 : 1)
    }
    case 'bugs':
      return inMonths(now, 5, 6) && isNight ? 4 : 0
    case 'bells':
      return weekday === 0 && hour >= 9 && hour < 12 ? 6 : 0
    case 'storm': {
      const isSummerAfternoon = inMonths(now, 5, 6, 7) && hour >= 12 && hour < 19

      return ctx.errorStreak >= 3 ? 8 : isSummerAfternoon ? 3 : 0
    }
    case 'fog':
      return month === 7 && hour >= 5 && hour < 11 ? 5 : 0
    case 'turkeys':
      return inMonths(now, 3, 4, 10) && !isNight ? 3 : 0
    case 'parachute':
      return isThirdSaturdayOfOctober(now) && !isNight ? 8 : 0
    case 'track':
      return hour >= 17 && hour < 21 ? 3 : 0
    case 'hornworm':
      return inMonths(now, 6, 7) && !isNight ? 3 : 0
    case 'applebutter':
      return month === 9 && isWeekend && !isNight ? 5 : 0
    case 'bees':
      return inMonths(now, 3, 4) && !isNight ? 3 : 0
    case 'sorghum':
      return inMonths(now, 8, 9) && !isNight ? 3 : 0
    case 'ramps':
      return month === 3 && !isNight ? 3 : 0
    case 'sang':
      return month === 8 && !isNight ? 3 : 0
    case 'quilting':
      return inMonths(now, 11, 0, 1) && !isNight ? 3 : 0
    case 'britches':
      return inMonths(now, 6, 7) && !isNight ? 3 : 0
    // Only a creative drop starts one: never drawn from the pool.
    case 'drop':
      return 0
  }
}

export const eligibleEvents = (ctx: EventCtx, blocked: ReadonlySet<EventId> = new Set()) =>
  EVENT_IDS.flatMap(id => {
    const weight = weightOf(id, ctx)

    return weight > 0 && !blocked.has(id) ? [{ id, weight }] : []
  })

// A weighted draw; `rng` is a 0-1 source.
export const pickEvent = (
  ctx: EventCtx,
  blocked: ReadonlySet<EventId>,
  rng: () => number,
): EventId | undefined => {
  return pickWeighted(eligibleEvents(ctx, blocked), rng)?.id
}

export const durationOf = (id: EventId, rng: () => number) => spanOf(DURATIONS[id], rng)


const SOLD_LINE = `Sold Miss Opal a jar. $${JAR_PRICE}.`
const NO_JAR_LINE = 'Next batch, Miss Opal.'

// What Jeb says along the way. `hasJar`: an apple cinnamon jar is on the shelf.
export const beatsOf = (id: EventId, hasJar: boolean): Beat[] => {
  switch (id) {
    case 'revenuer':
      return [
        { at: 0, line: 'Revenuer on the road. Tarp on the still!' },
        { at: 0.4, line: 'Just tomatoes, officer.' },
        { at: 0.85, line: 'Coast is clear.' },
      ]
    case 'neighbor':
      return [
        { at: 0, line: "Miss Opal's comin' up the road." },
        // The sale is decided when the beat comes, on the farm as stored: the
        // line Jeb says is the one that matches what happened.
        {
          at: 0.6,
          line: hasJar ? SOLD_LINE : NO_JAR_LINE,
          effect: 'sell',
          ifSold: SOLD_LINE,
          ifNot: NO_JAR_LINE,
        },
      ]
    case 'bear':
      return [
        { at: 0, line: "Bear's in the apple tree!" },
        { at: 0.4, line: "Blue's barkin' his head off.", effect: 'bark' },
      ]
    case 'whistlepig':
      return [
        { at: 0, line: 'Whistle pig in the corn!' },
        { at: 0.5, line: 'Lost a stalk to that whistle pig.', effect: 'raid' },
      ]
    case 'mothman':
      return [{ at: 0.1, line: "Saw red eyes on the ridge. Probably nothin'." }]
    case 'bugs':
      return [{ at: 0, line: "Lightnin' bugs are out." }]
    case 'bells':
      return [{ at: 0, line: 'Church bells down the valley.' }]
    case 'storm':
      return [
        { at: 0, line: "Storm's buildin' over the ridge." },
        { at: 0.6, line: "Rain's comin'. Bring the wash in." },
      ]
    case 'fog':
      return [
        { at: 0, line: "Fog's thick in the holler." },
        { at: 0.5, line: "That's one snow come winter." },
      ]
    case 'turkeys':
      return [{ at: 0, line: "Wild turkeys struttin' by." }]
    case 'parachute':
      return [{ at: 0, line: 'Parachute day. Look at them come down.' }]
    case 'track':
      return [
        { at: 0, line: "Blue's struck a track!", effect: 'bark' },
        { at: 0.5, line: "He's treed somethin'." },
      ]
    case 'hornworm':
      return [{ at: 0, line: 'Hornworms again.' }]
    case 'applebutter':
      return [{ at: 0, line: "Stir it or it'll scorch." }]
    case 'bees':
      return [
        { at: 0, line: "Tellin' the bees the news, same as Granny did." },
        { at: 0.6, line: "Hummin' back. Reckon they heard." },
      ]
    case 'sorghum':
      return [
        { at: 0, line: "Sorghum's a-boilin'. Keep her stirred." },
        { at: 0.7, line: 'Skim that green off. Syrup is near.' },
      ]
    case 'ramps':
      return [
        { at: 0, line: 'Ramps are up on the north slope.' },
        { at: 0.6, line: 'Smells like spring, and a mite like trouble.' },
      ]
    case 'sang':
      return [
        { at: 0, line: "Sang season's open. Eyes on the ground." },
        { at: 0.6, line: 'Four prongs, red berries. Plant the seed back.' },
      ]
    case 'quilting':
      return [
        { at: 0, line: "Piecin' a quilt from feed sacks, same as Granny." },
        { at: 0.6, line: 'Small stitches. These cold nights run long.' },
      ]
    case 'britches':
      return [
        { at: 0, line: "Stringin' beans for leather britches." },
        { at: 0.6, line: 'Hang them high and dry. Come winter, we feast.' },
      ]
    // A drop's first line is said when it arrives (see register.tsx).
    case 'drop':
      return []
  }
}
