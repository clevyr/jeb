import type { DropZone } from '../types'
import type { Drop, DropCtx } from './surprise'
import { ARC_MAX_STEPS, TINT_NAMES, validateDrop } from './surprise'

// The offline generator: a seeded, procedural surprise built from the same
// schema as the model's, from local pools. It always works, so the day's three
// drops happen with the model off, denied, broken or out of budget. Pure.
//
// Its range grows with the level exactly as the model's does: sayings, happenings
// and almanac lines from level 1; decor from 2; a short arc (3 steps) from 4 and
// longer ones (4 to 5 steps, the last leaving a permanent structure) from 5; a
// festival from 6. It draws no custom pictures. Six recurring characters come
// back by name through the log.

export const CHARACTERS = ['Cousin Delbert', 'Aunt Pearl', 'Uncle Clyde', 'Widow Hazel', 'Little Wade', 'Granny Mae'] as const

export type Season = 'spring' | 'summer' | 'fall' | 'winter'

export const seasonOfMonth = (month: number): Season =>
  month >= 2 && month <= 4 ? 'spring' : month >= 5 && month <= 7 ? 'summer' : month >= 8 && month <= 10 ? 'fall' : 'winter'

export type OfflineInput = {
  now: Date
  slot: number
  level: number
  total: number
  // Friendly labels of the MCP servers present and the counts the read-only tools gave.
  labels: readonly string[]
  counts: Readonly<Record<string, number>>
  // Summaries of the log, newest last.
  recent: readonly string[]
  isArcOpen: boolean
  knownArt: readonly string[]
}

const hashOf = (text: string) => {
  let h = 2166136261
  for (let i = 0; i < text.length; i += 1) {
    h = Math.imul(h ^ text.charCodeAt(i), 16777619)
  }

  return h >>> 0
}

export const seededRng = (seed: number) => {
  let a = seed >>> 0

  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)

    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

type Rng = () => number
const pick = <T>(list: readonly T[], rng: Rng): T => list[Math.floor(rng() * list.length)] as T

type Sprite = { sprite: string; zone: DropZone; frames: 1 | 2 }
const sp = (sprite: string, zone: DropZone, frames: 1 | 2 = 1): Sprite => ({ sprite, zone, frames })

const SAYINGS: Record<Season, string[]> = {
  spring: ["Peepers are singin' down by the creek.", "Ground's soft enough to turn.", "Redbud's out on the ridge."],
  summer: ["Corn's knee high by the Fourth, near enough.", 'Cicadas are loud as a sawmill today.', 'Too hot to argue with a hen.'],
  fall: ['Smells like woodsmoke and apples out there.', 'Leaves are turnin on the far ridge.', 'First frost is comin, I can feel it.'],
  winter: ['Frost on the glass this mornin.', "Wood stack's lookin good.", 'Quiet as a barn in January.'],
}

const ALMANAC: Record<Season, string[]> = {
  spring: ['Old-timers plant by the moon, and so do I.', 'A late frost always comes for the early bloom.'],
  summer: ['Dog days make the garden sulk and the fiddle sweat.', 'Fog in August means snow come winter.'],
  fall: ['Thick husks on the corn mean a hard winter.', 'Woolly worms read the winter, if you ask nice.'],
  winter: ['A bright January moon means a cold February.', 'Mind the woodpile: half left by Groundhog Day.'],
}

type Happening = { lines: string[]; sprites: Sprite[]; seasons?: Season[] }
const HAPPENINGS: Happening[] = [
  { lines: ["A hen's loose out on the road."], sprites: [sp('hen', 'road', 2)] },
  { lines: ['Deer at the edge of the yard.'], sprites: [sp('deer', 'yard')] },
  { lines: ["Somebody's cow got out again."], sprites: [sp('cow', 'yard', 2)] },
  { lines: ['Turkeys are struttin by.'], sprites: [sp('turkey', 'road', 2)], seasons: ['fall', 'spring'] },
  { lines: ['Butterflies are thick over the clover.'], sprites: [sp('butterfly', 'sky', 2), sp('butterfly', 'sky', 2)], seasons: ['spring', 'summer'] },
  { lines: ["A cardinal's scoldin me."], sprites: [sp('cardinal', 'sky')] },
  { lines: ['Whistle pig poked his head up.'], sprites: [sp('groundhog', 'field')] },
  { lines: ["Miss Opal's takin the air."], sprites: [sp('opal', 'road', 2)] },
  { lines: ['Fireflies are puttin on a show.'], sprites: [sp('firefly', 'sky', 2), sp('firefly', 'field', 2)], seasons: ['summer'] },
  { lines: ['A rainbow! Well, look at that.'], sprites: [sp('rainbow', 'sky')], seasons: ['spring', 'summer'] },
]

type Decor = { lines: string[]; sprites: Sprite[]; window: { from: number; to: number } | null; lasts: 'today' | 'week' }
const DECOR: Decor[] = [
  { lines: ['Set a mug out on the porch rail.'], sprites: [sp('mug', 'porch')], window: { from: 5, to: 11 }, lasts: 'today' },
  { lines: ["The pup's nappin out in the yard."], sprites: [sp('pup', 'yard', 2)], window: { from: 12, to: 17 }, lasts: 'today' },
  { lines: ['Hung a lantern by the door.'], sprites: [sp('lantern', 'porch', 2)], window: { from: 17, to: 23 }, lasts: 'week' },
  { lines: ["Cake's coolin on the sill."], sprites: [sp('cake', 'porch')], window: { from: 11, to: 20 }, lasts: 'today' },
  { lines: ['A jar of cider by the step.'], sprites: [sp('jar', 'porch')], window: null, lasts: 'week' },
  { lines: ['Clouds are sittin low on the ridge.'], sprites: [sp('cloud', 'sky')], window: { from: 6, to: 18 }, lasts: 'today' },
]

type ArcTemplate = {
  name: string
  summary: string
  steps: { day: number; kind: 'happening' | 'saying' | 'decor'; lines: string[]; sprites?: Sprite[]; keep?: boolean }[]
}

// {c} is the character's name.
const ARCS: ArcTemplate[] = [
  {
    name: 'lost-hen',
    summary: '{c} lost a hen and the yard went looking',
    steps: [
      { day: 1, kind: 'happening', lines: ['{c} lost a hen. Keep an eye out.'], sprites: [sp('hen', 'road', 2)] },
      { day: 2, kind: 'happening', lines: ["Found {c}'s hen down by the yard."], sprites: [sp('hen', 'yard', 2)] },
      { day: 3, kind: 'saying', lines: ['{c} says thank ye. Pie is comin.'] },
    ],
  },
  {
    name: 'birdhouse-job',
    summary: '{c} built a birdhouse for the yard',
    steps: [
      { day: 1, kind: 'saying', lines: ['{c} is fixin to build somethin.'] },
      { day: 2, kind: 'happening', lines: ['{c} dropped off a load of boards.'], sprites: [sp('lumber', 'yard')] },
      { day: 3, kind: 'happening', lines: ["Hammerin all mornin at {c}'s."], sprites: [sp('bluebird', 'sky', 2)] },
      { day: 4, kind: 'saying', lines: ['Almost done. Needs a bit of paint.'] },
      { day: 5, kind: 'decor', lines: ['{c} finished a birdhouse for the yard.'], sprites: [sp('birdhouse', 'yard')], keep: true },
    ],
  },
  {
    name: 'harvest-supper',
    summary: '{c} threw a harvest supper',
    steps: [
      { day: 1, kind: 'saying', lines: ['{c} wants to host a harvest supper.'] },
      { day: 2, kind: 'happening', lines: ['Apples comin in by the crate.'], sprites: [sp('apples', 'yard')] },
      { day: 3, kind: 'happening', lines: ["Cake's coolin on the sill."], sprites: [sp('cake', 'porch')] },
      { day: 4, kind: 'decor', lines: ['Hung a lantern for the supper.'], sprites: [sp('lantern', 'porch', 2)], keep: true },
    ],
  },
]

export const nameIn = (text: string) => CHARACTERS.find(name => text.includes(name))

// The character of the day: one from the recent log most of the time, so a name
// comes back, else any.
const characterOf = (recent: readonly string[], rng: Rng): string => {
  for (let i = recent.length - 1; i >= 0; i -= 1) {
    const found = nameIn(recent[i] as string)
    if (found && rng() < 0.6) {
      return found
    }
  }

  return pick(CHARACTERS, rng)
}

const fill = (text: string, name: string) => text.split('{c}').join(name).slice(0, 64)

const SAFE: Drop = {
  kind: 'saying',
  name: 'porch-sitting',
  lines: ['Nothin to report. Fine by me.'],
  summary: 'Nothin to report.',
  sprites: [],
  window: null,
  lasts: 'today',
  art: [],
  keep: false,
  festival: '',
  steps: [],
}

type Pick = 'arc' | 'decor' | 'saying' | 'happening' | 'almanac' | 'mcp' | 'char'

// The surprise for a slot, the same for the same day, slot and total.
export const offlineDrop = (input: OfflineInput): Drop => {
  const { now } = input
  const key = `${now.getFullYear()}-${now.getMonth()}-${now.getDate()}|${input.slot}|${input.total}`
  const rng = seededRng(hashOf(key))
  const season = seasonOfMonth(now.getMonth())
  const ctx: DropCtx = { level: input.level, knownArt: input.knownArt, isArcOpen: input.isArcOpen }
  const stepCap = input.level >= 5 ? ARC_MAX_STEPS : input.level >= 4 ? 3 : 0
  const arcs = input.isArcOpen ? ARCS.filter(arc => arc.steps.length <= stepCap) : []
  const named = input.labels.filter(label => /^[A-Za-z0-9 .]{1,24}$/.test(label))
  const id = `${now.getMonth() + 1}${now.getDate()}-${input.slot}`
  const character = characterOf(input.recent, rng)

  const weights: [Pick, number][] = [
    ['arc', arcs.length > 0 ? (input.level >= 5 ? 3 : 2) : 0],
    ['decor', input.level >= 2 ? 2 : 0],
    ['saying', 3],
    ['happening', 3],
    ['almanac', 1],
    ['mcp', named.length > 0 ? 2 : 0],
    ['char', 2],
  ]
  let at = rng() * weights.reduce((sum, [, weight]) => sum + weight, 0)
  const kind: Pick = weights.find(([, weight]) => (at -= weight) < 0)?.[0] ?? 'saying'

  let raw: Record<string, unknown>
  switch (kind) {
    case 'arc': {
      const arc = pick(arcs, rng)
      raw = {
        kind: 'arc',
        name: arc.name,
        summary: fill(arc.summary, character).slice(0, 80),
        steps: arc.steps.map((step, i) => ({
          day: step.day,
          kind: step.kind,
          name: `${arc.name}-${i + 1}`.slice(0, 24),
          lines: step.lines.map(line => fill(line, character)),
          sprites: step.sprites ?? [],
          keep: step.keep === true,
        })),
      }
      break
    }
    case 'decor': {
      const decor = pick(DECOR, rng)
      raw = { kind: 'decor', name: `decor-${id}`, lines: decor.lines, sprites: decor.sprites, window: decor.window, lasts: decor.lasts }
      break
    }
    case 'happening': {
      const fits = HAPPENINGS.filter(h => h.seasons === undefined || h.seasons.includes(season))
      const one = pick(fits, rng)
      const isFestival = input.level >= 6 && rng() < 0.125
      raw = isFestival
        ? {
            kind: 'happening',
            name: `festival-${id}`,
            lines: ['County festival day! The whole ridge is dressed up.'],
            summary: 'A festival day colored the whole farm',
            sprites: [sp('lantern', 'sky', 2), sp('cake', 'porch'), sp('butterfly', 'sky', 2)],
            festival: pick(TINT_NAMES, rng),
          }
        : { kind: 'happening', name: `happening-${id}`, lines: one.lines, sprites: one.sprites }
      break
    }
    case 'almanac':
      raw = { kind: 'almanac', name: `almanac-${id}`, lines: [pick(ALMANAC[season], rng)], lasts: 'today' }
      break
    case 'mcp': {
      const label = pick(named, rng)
      const n = input.counts[label]
      const line = n !== undefined && n > 0 ? `Reckon ${label} has ${n} things waitin on you.` : `Heard the ${label} crew's been busy.`
      raw = { kind: 'saying', name: `saying-${id}`, lines: [line.slice(0, 64)], lasts: 'today' }
      break
    }
    case 'char':
      raw =
        rng() < 0.5
          ? {
              kind: 'happening',
              name: `visit-${id}`,
              lines: [fill('{c} came by on the road.', character)],
              summary: fill('{c} came by', character),
              sprites: [sp(rng() < 0.5 ? 'opal' : 'tractor', 'road', 2)],
            }
          : {
              kind: 'saying',
              name: `saying-${id}`,
              lines: [fill('{c} sends word from down the holler.', character)],
              summary: fill('{c} sent word', character),
              lasts: 'today',
            }
      break
    default:
      raw = { kind: 'saying', name: `saying-${id}`, lines: [pick(SAYINGS[season], rng)], lasts: 'today' }
  }

  const done = validateDrop(raw, ctx)

  return done.ok ? done.drop : SAFE
}
