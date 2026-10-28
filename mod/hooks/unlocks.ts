import { isNightHour } from './almanac'
import { dateKeyOf } from './util'

export { dateKeyOf }

// Little things that turn up around the farm through the day. Each local day a
// few of them (3 to 5) are unlocked, at random moments: the first no sooner than
// twenty minutes into a session, then an hour to three apart. An unlock either
// stays on the farm (a decoration) or switches on a touch tied to the day or the
// hour. Pure: the clock and the dice are handed in; nothing here asks the host.

export const UNLOCK_IDS = [
  'birdhouse',
  'woodpile',
  'garden',
  'creek',
  'cardinal',
  'owl',
  'butterflies',
  'deer',
  'drift',
  'afterrain',
  'shootingstar',
  'mug',
  'lunch',
  'napchair',
  'porchlight',
  'sundayhat',
  'washday',
  'postcard',
  'anniversary',
  'midnightcoffee',
] as const

export type UnlockId = (typeof UNLOCK_IDS)[number]

// The most ids the store keeps, and the day's bounds.
export const UNLOCKS_MAX = 64
export const DAY_MIN = 3
export const DAY_MAX = 5

const MINUTE = 60_000
const HOUR = 60 * MINUTE
export const FIRST_UNLOCK_MS: readonly [number, number] = [20 * MINUTE, 35 * MINUTE]
export const GAP_UNLOCK_MS: readonly [number, number] = [HOUR, 3 * HOUR]
export const RETRY_UNLOCK_MS = 30 * MINUTE
export const RAINBOW_TICKS = 180
export const WET_MS = 15 * MINUTE
export const STAR_TICKS = 10
// How many minutes past midnight the late-night coffee may come, as hours.
export const COFFEE_FROM = 0
export const COFFEE_TO = 5

// The scheduling data kept in the farm: the local day it is for, how many are
// to unlock that day and how many have, the earliest moment (ms since the epoch)
// the next may, the day the farm was first scheduled (its anniversary) and the
// last day the late-night coffee came.
export type UnlockDay = { d: string; n: number; done: number; next: number; since: string; coffee: string }

export const freshUnlockDay = (): UnlockDay => ({ d: '', n: 0, done: 0, next: 0, since: '', coffee: '' })

const span = (range: readonly [number, number], rng: () => number) =>
  range[0] + Math.floor(rng() * (range[1] - range[0] + 1))

export const firstUnlockSpan = (rng: () => number) => span(FIRST_UNLOCK_MS, rng)

// The first moment of the next local day, plus the wait a session needs before
// its first unlock.
export const nextDayAt = (now: Date, rng: () => number) =>
  new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime() + span(FIRST_UNLOCK_MS, rng)

export type Unlockable = {
  id: UnlockId
  // What it is called.
  name: string
  // Jeb's one warm line when it turns up: a hint, never the name.
  line: string
  // Whether it can turn up now (a season it belongs to, something it needs).
  isFit: (now: Date, farm: UnlockFarm) => boolean
}

export type UnlockFarm = { upgrades: readonly string[]; unlocks: readonly string[]; unlockDay: UnlockDay }

const months = (...list: number[]) => (now: Date) => list.includes(now.getMonth())
const always = () => true

const daysBetween = (from: string, now: Date) => {
  const [y, m, d] = from.split('-').map(Number) as [number, number, number]

  return (Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) - Date.UTC(y, m - 1, d)) / 86_400_000
}

export const UNLOCKABLES: readonly Unlockable[] = [
  { id: 'birdhouse', name: 'a birdhouse under the eave, and a bluebird now and then', line: 'Found a few boards. Reckon somebody might move in.', isFit: always },
  { id: 'woodpile', name: 'a woodpile that grows with the lumber, and an axe in the chopping block', line: 'Winter keeps. Best get ahead of it.', isFit: always },
  { id: 'garden', name: 'a kitchen garden by the house, tomatoes and sunflowers', line: 'Turned a little dirt by the house. We will see what comes up.', isFit: months(2, 3, 4, 5, 6, 7, 8) },
  { id: 'creek', name: 'a creek in the yard, with Jeb fishing on Saturday afternoons', line: "Heard the creek's runnin' good. Saturdays might be worth savin'.", isFit: always },
  { id: 'cardinal', name: 'a cardinal on the roof', line: "Somebody red is watchin' from the roof.", isFit: always },
  { id: 'owl', name: 'a barred owl at night', line: "Somethin' keeps askin' who cooks for us after dark.", isFit: always },
  { id: 'butterflies', name: 'butterflies over the fields on summer afternoons', line: "The clover is somethin' to see this time of year.", isFit: months(3, 4, 5, 6, 7, 8) },
  { id: 'deer', name: 'a deer at dusk', line: "Keep your eyes on the edge of the field come evenin'.", isFit: always },
  { id: 'drift', name: 'falling leaves in autumn and snowflakes in winter', line: "Air feels like it is fixin' to change.", isFit: months(8, 9, 10, 11, 0, 1) },
  { id: 'afterrain', name: 'puddles after rain, and a rainbow after a storm', line: "Rain always leaves somethin' pretty behind. Wait on it.", isFit: always },
  { id: 'shootingstar', name: 'a shooting star, now and then', line: 'Clear night. Make a wish if you catch one.', isFit: always },
  { id: 'mug', name: 'a mug of coffee on the sill in the morning', line: "Mornin' goes down easier with somethin' warm.", isFit: always },
  { id: 'lunch', name: 'a pepperoni roll on the sill at noon', line: 'Noon. Mama always said never work hungry.', isFit: always },
  { id: 'napchair', name: 'a nap in the rocking chair after lunch', line: 'A body can rest his eyes a minute after dinner.', isFit: (_now, farm) => farm.upgrades.includes('chair') },
  { id: 'porchlight', name: 'the porch light in the evening', line: "Left a light on. Folks like findin' their way home.", isFit: always },
  { id: 'sundayhat', name: "Jeb's Sunday-best hat", line: 'Sunday ought to feel a little different.', isFit: always },
  { id: 'washday', name: 'clothes on the line every Monday', line: 'Monday means a clean start, the way Granny did it.', isFit: always },
  { id: 'postcard', name: 'a postcard from kinfolk on weekdays', line: 'Kinfolk think of us now and again.', isFit: always },
  {
    id: 'anniversary',
    name: "a little cake on the farm's anniversary",
    line: 'We have been at this a good while, you and me.',
    isFit: (now, farm) => farm.unlockDay.since !== '' && daysBetween(farm.unlockDay.since, now) >= 14,
  },
  { id: 'midnightcoffee', name: 'a cup of coffee past midnight, once a night', line: 'I will look in on you if you are up late.', isFit: always },
]

export const unlockOf = (id: string) => UNLOCKABLES.find(entry => entry.id === id)

export const hasUnlock = (unlocks: readonly string[], id: UnlockId) => unlocks.includes(id)

// The day's plan on the stored farm: a new local day draws how many unlock (3 to
// 5) and starts the count over; the first scheduling also marks the day the farm
// began.
export const planDay = (old: UnlockDay, now: Date, rng: () => number): UnlockDay => {
  const key = dateKeyOf(now)
  if (old.d === key) {
    return old.since === '' ? { ...old, since: key } : old
  }

  return {
    d: key,
    n: DAY_MIN + Math.floor(rng() * (DAY_MAX - DAY_MIN + 1)),
    done: 0,
    next: 0,
    since: old.since === '' ? key : old.since,
    coffee: old.coffee,
  }
}

export type Step = { unlocks: string[]; unlockDay: UnlockDay; found?: UnlockId; retryAt: number }

// One look at whether something unlocks now, decided on the farm as stored (so two
// sessions never unlock past the day's count nor within the gap). `retryAt` is
// when to look again.
export const stepUnlock = (farm: UnlockFarm, nowMs: number, rng: () => number): Step => {
  const now = new Date(nowMs)
  const day = planDay(farm.unlockDay, now, rng)
  const keep = (found?: UnlockId, retryAt = nowMs + RETRY_UNLOCK_MS): Step => ({
    unlocks: farm.unlocks as string[],
    unlockDay: day,
    found,
    retryAt,
  })
  if (day.done >= day.n) {
    return keep(undefined, nextDayAt(now, rng))
  }
  if (day.next > nowMs) {
    return keep(undefined, day.next)
  }
  const view = { ...farm, unlockDay: day }
  const fits = UNLOCKABLES.filter(entry => !farm.unlocks.includes(entry.id) && entry.isFit(now, view))
  const pick = fits[Math.floor(rng() * fits.length)]
  if (!pick) {
    return keep()
  }
  const next = nowMs + span(GAP_UNLOCK_MS, rng)
  const done = day.done + 1

  return {
    unlocks: [...farm.unlocks, pick.id].slice(-UNLOCKS_MAX),
    unlockDay: { ...day, done, next },
    found: pick.id,
    retryAt: done >= day.n ? nextDayAt(now, rng) : next,
  }
}

// ---- what is on show, by the hour ----


export type LookId =
  | 'birdhouse'
  | 'bluebird'
  | 'woodpile'
  | 'garden'
  | 'creek'
  | 'fisher'
  | 'cardinal'
  | 'owl'
  | 'butterflies'
  | 'deer'
  | 'leaves'
  | 'snow'
  | 'rainbow'
  | 'puddles'
  | 'star'
  | 'mug'
  | 'lunch'
  | 'nap'
  | 'porchlight'
  | 'sundayhat'
  | 'washday'
  | 'postcard'
  | 'cake'
  | 'coffee'

// `n` is a variant: the pile's height, the garden's stage, the deer's place.
export type Look = { id: LookId; n: number }


// The woodpile's height from the lumber that stands in the stack: 1 to 4.
export const pileOf = (lumber: number) => 1 + (lumber >= 5 ? 1 : 0) + (lumber >= 20 ? 1 : 0) + (lumber >= 50 ? 1 : 0)





// ---- the unlockables ----


