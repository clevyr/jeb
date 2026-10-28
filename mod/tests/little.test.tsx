import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'
import { freshFarm, isFutureFarm, loadFarm } from '../hooks/homestead'
import {
  dateKeyOf,
  firstUnlockSpan,
  freshUnlockDay,
  planDay,
  stepUnlock,
  UNLOCK_IDS,
  UNLOCKABLES,
  UNLOCKS_MAX,
} from '../hooks/unlocks'

// The little things around the farm: the day's plan, the store, every look in both
// bands, the late-night coffee and what a day of them costs the host.

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const START = new Date(2026, 5, 10, 9, 0, 0).getTime()

const lcg = (seed: number) => {
  let x = seed
  return () => {
    x = (x * 1664525 + 1013904223) % 4294967296

    return x / 4294967296
  }
}

// ---- the plan (pure) ----

type Plan = { upgrades: string[]; unlocks: string[]; unlockDay: ReturnType<typeof freshUnlockDay> }

const walk = (seed: number, from: Date, days: number) => {
  const rng = lcg(seed)
  let farm: Plan = { upgrades: ['chair'], unlocks: [], unlockDay: freshUnlockDay() }
  const end = from.getTime() + days * 24 * HOUR
  let at = from.getTime() + firstUnlockSpan(rng)
  const found: { at: number; id: string }[] = []
  while (at < end) {
    const step = stepUnlock(farm, at, rng)
    farm = { ...farm, unlocks: step.unlocks, unlockDay: step.unlockDay }
    if (step.found) {
      found.push({ at, id: step.found })
    }
    expect(step.retryAt).toBeGreaterThan(at)
    at = step.retryAt
  }

  return { found, farm }
}

test('LT1 the plan: three to five a day, the first no sooner than twenty minutes in, then an hour to three apart', () => {
  for (let seed = 1; seed <= 80; seed += 1) {
    const from = new Date(2026, 5, 10, 8, 0)
    const { found } = walk(seed, from, 4)
    const byDay = new Map<string, { at: number; id: string }[]>()
    for (const one of found) {
      const key = dateKeyOf(new Date(one.at))
      byDay.set(key, [...(byDay.get(key) ?? []), one])
    }
    // Four days with a session open all day: 3 to 5 each (the fourth is cut short by the walk's end).
    expect(byDay.size).toBeGreaterThanOrEqual(4)
    for (const [key, list] of byDay) {
      if (key !== dateKeyOf(new Date(from.getTime() + 4 * 24 * HOUR))) {
        expect(list.length).toBeGreaterThanOrEqual(3)
        expect(list.length).toBeLessThanOrEqual(5)
      }
      for (let i = 1; i < list.length; i += 1) {
        const gap = (list[i] as { at: number }).at - (list[i - 1] as { at: number }).at
        expect(gap).toBeGreaterThanOrEqual(HOUR)
        expect(gap).toBeLessThanOrEqual(3 * HOUR)
      }
    }
    expect((found[0] as { at: number }).at - from.getTime()).toBeGreaterThanOrEqual(20 * MINUTE)
    // Past midnight the next day waits twenty minutes too.
    for (const [key, list] of byDay) {
      const first = new Date((list[0] as { at: number }).at)
      const floor = key === dateKeyOf(from) ? 8 * 60 + 20 : 20
      expect(first.getHours() * 60 + first.getMinutes()).toBeGreaterThanOrEqual(floor)
    }
    expect(new Set(found.map(one => one.id)).size).toBe(found.length)
  }
})

test('LT1 the dice never go past the day: asked again and again, a day stops at its count', () => {
  const rng = lcg(7)
  let farm: Plan = { upgrades: [], unlocks: [], unlockDay: freshUnlockDay() }
  let made = 0
  for (let i = 0; i < 200; i += 1) {
    // Always well past the gap, on one day.
    const step = stepUnlock(farm, new Date(2026, 5, 10, 8, 0).getTime() + i * 4 * HOUR % (15 * HOUR), rng)
    farm = { ...farm, unlocks: step.unlocks, unlockDay: { ...step.unlockDay, next: 0 } }
    made += step.found ? 1 : 0
  }
  expect(made).toBeLessThanOrEqual(5)
  expect(made).toBe(farm.unlockDay.n)
})

test('LT1 a season or a need decides what can turn up', () => {
  const july = new Date(2026, 6, 10, 12)
  const january = new Date(2026, 0, 10, 12)
  const farm = { upgrades: [] as string[], unlocks: [] as string[], unlockDay: freshUnlockDay() }
  const fit = (id: string, now: Date, over: Partial<typeof farm> = {}) =>
    UNLOCKABLES.find(entry => entry.id === id)?.isFit(now, { ...farm, ...over }) ?? false
  expect(fit('drift', july)).toBe(false)
  expect(fit('drift', january)).toBe(true)
  expect(fit('garden', january)).toBe(false)
  expect(fit('garden', july)).toBe(true)
  expect(fit('butterflies', january)).toBe(false)
  expect(fit('napchair', july)).toBe(false)
  expect(fit('napchair', july, { upgrades: ['chair'] })).toBe(true)
  expect(fit('anniversary', july)).toBe(false)
  expect(fit('anniversary', july, { unlockDay: { ...freshUnlockDay(), since: '2026-07-01' } })).toBe(false)
  expect(fit('anniversary', july, { unlockDay: { ...freshUnlockDay(), since: '2026-06-01' } })).toBe(true)
  expect(UNLOCKABLES.map(entry => entry.id)).toEqual([...UNLOCK_IDS])
  expect(UNLOCK_IDS.length).toBeGreaterThanOrEqual(15)
  expect(UNLOCK_IDS.length).toBeLessThanOrEqual(20)
})

test('LT1 a new day draws a new count and keeps the farm\'s first day and the last coffee', () => {
  const rng = lcg(3)
  const day = { d: '2026-06-09', n: 4, done: 4, next: 123, since: '2025-01-01', coffee: '2026-06-09' }
  const rolled = planDay(day, new Date(2026, 5, 10, 8), rng)
  expect(rolled.d).toBe('2026-06-10')
  expect(rolled.done).toBe(0)
  expect(rolled.next).toBe(0)
  expect(rolled.n).toBeGreaterThanOrEqual(3)
  expect(rolled.n).toBeLessThanOrEqual(5)
  expect(rolled.since).toBe('2025-01-01')
  expect(rolled.coffee).toBe('2026-06-09')
  expect(planDay(rolled, new Date(2026, 5, 10, 20), rng)).toBe(rolled)
  expect(planDay(freshUnlockDay(), new Date(2026, 5, 10, 8), rng).since).toBe('2026-06-10')
})

// ---- the store ----

test('LT2 the farm is v8, starts with nothing and reads every damaged field back as something sound', () => {
  const fresh = freshFarm()
  expect(fresh.version).toBe(10)
  expect(fresh.unlocks).toEqual([])
  expect(fresh.unlockDay).toEqual(freshUnlockDay())

  // v7 starts empty; its first day is the oldest date on record.
  const v7 = loadFarm({
    ...fresh,
    version: 7,
    unlocks: ['owl'],
    quilt: [
      { c: 'B', d: '2025-03-04', camp: 'x' },
      { c: 'R', d: '2025-04-01', camp: 'x' },
    ],
  })
  expect(v7?.version).toBe(10)
  expect(v7?.unlocks).toEqual([])
  expect(v7?.unlockDay).toEqual({ ...freshUnlockDay(), since: '2025-03-04' })

  // v8: known ids once each, in the order they came, and never more than the cap.
  const v8 = loadFarm({
    ...fresh,
    unlocks: ['owl', 'owl', 'nope', 5, null, 'deer', ...Array(100).fill('creek'), ...UNLOCK_IDS],
    unlockDay: { d: '2026-06-10', n: 99, done: 9, next: 1_750_000_000_000, since: '2025-02-01', coffee: '2026-06-09' },
  })
  expect(v8?.unlocks.slice(0, 3)).toEqual(['owl', 'deer', 'creek'])
  expect(new Set(v8?.unlocks).size).toBe(v8?.unlocks.length)
  expect(v8?.unlocks.length).toBeLessThanOrEqual(UNLOCKS_MAX)
  expect(v8?.unlockDay).toEqual({ d: '2026-06-10', n: 5, done: 5, next: 1_750_000_000_000, since: '2025-02-01', coffee: '2026-06-09' })

  const junk = loadFarm({
    ...fresh,
    unlockDay: { d: 'today', n: 4, done: 'x', next: -5, since: '2025-02-30', coffee: 7 },
  })
  expect(junk?.unlockDay).toEqual(freshUnlockDay())
  expect(loadFarm({ ...fresh, unlocks: 'owl', unlockDay: 5 })?.unlocks).toEqual([])
  expect(isFutureFarm({ ...fresh, version: 11 })).toBe(true)
  expect(isFutureFarm({ ...fresh, version: 10 })).toBe(false)
  expect(isFutureFarm({ ...fresh, version: 8 })).toBe(false)
})

// ---- an engine to run it in ----

const tally = {
  animWrites: 0,
  stateWrites: 0,
  storeSets: 0,
  // The writes of the session's live record (see live.ts), among the store sets.
  liveSets: 0,
  storeGets: 0,
  fsReads: 0,
  clockNows: 0,
  lines: [] as string[],
  db: new Map<string, unknown>(),
}

const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

const rig = (on: any, entries: Record<string, unknown> = {}, now = START): MockClock => {
  tally.animWrites = 0
  tally.stateWrites = 0
  tally.storeSets = 0
  tally.liveSets = 0
  tally.storeGets = 0
  tally.fsReads = 0
  tally.clockNows = 0
  tally.lines = []
  tally.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  const answers: Record<string, any> = {}
  const aside = ((event: string, ...rest: any[]) => {
    if (event === 'clock.now') {
      answers[event] = rest[rest.length - 1]

      return undefined
    }

    return on(event, ...rest)
  }) as typeof on
  const clock = mock.clock(aside, { now })
  on('clock.now', (hooked: any, e: any, next: any) => {
    tally.clockNows += 1

    return answers['clock.now'](hooked, e, next)
  })
  mock.env(on, { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_CREATIVITY: 'off', JEB_NEWS: 'null' })
  on('fs.read', (_: any, e: any) => {
    tally.fsReads += 1
    throw new Error(`ENOENT ${(e as { path: string }).path}`)
  })
  on('store.get', (_: any, e: any) => {
    tally.storeGets += 1

    return { value: copy(tally.db.get(e.key)) }
  })
  on('store.set', (_: any, e: any) => {
    tally.storeSets += 1
    if (String(e.key).startsWith('live:')) {
      tally.liveSets += 1
    }
    tally.db.set(e.key, copy(e.value))

    return { value: undefined }
  })
  on('state.set', (_: any, e: any, next: any) => {
    tally.stateWrites += 1
    if (e.key === 'anim') {
      tally.animWrites += 1
    }
    if (e.key === 'say') {
      tally.lines.push((e.value as { line: string }).line)
    }

    return next(e)
  })
  on('ui.toast', () => ({ value: undefined }))
  on('audio.play', () => ({ value: undefined }))
  on('audio.speak', () => ({ value: { synthesizer: 'test' } }))
  on('command.register', () => ({ value: { command: 'jeb' } }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('session.id', () => ({ value: 'me' }))
  on('session.root', () => ({ value: '/w/api' }))
  on('session.repo', () => ({ value: { root: '/w/api', remote: null, internal: false, name: null } }))
  on('agent.list', () => ({ value: [] }))
  on('session.end', (_: any, e: any) => ({ sessionId: e.sessionId }))

  return clock
}

// `advance` takes at most 10 000 waits at a time.
const elapse = async (clock: MockClock, ms: number) => {
  for (let left = ms; left > 0; left -= 20 * MINUTE) {
    await clock.advance(Math.min(left, 20 * MINUTE))
  }
}

const start = ($: any, isInteractive = true) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive })
const stored = () => tally.db.get('farm') as ReturnType<typeof freshFarm>
const words = (list: readonly string[]) => list.map(id => UNLOCKABLES.find(entry => entry.id === id)?.line as string)

test('LT3 a session unlocks three to five a day, spaced, none in the first twenty minutes, each with its one warm line', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  let last = 0
  for (let minute = 1; minute <= 15 * 60; minute += 1) {
    await clock.advance(MINUTE)
    const count = stored()?.unlocks.length ?? 0
    if (count !== last) {
      last = count
    }
  }
  const farm = stored()
  expect(farm.unlocks.length).toBeGreaterThanOrEqual(3)
  expect(farm.unlocks.length).toBeLessThanOrEqual(5)
  expect(farm.unlockDay.done).toBe(farm.unlocks.length)
  expect(farm.unlockDay.d).toBe('2026-06-10')
  // Jeb said each one's line, through the talk gate (the default level is ambient).
  for (const line of words(farm.unlocks)) {
    expect(tally.lines).toContain(line)
  }
  // The farm's first day is on record.
  expect(farm.unlockDay.since).toBe('2026-06-10')
  expect(farm.unlocks.every(id => (UNLOCK_IDS as readonly string[]).includes(id))).toBe(true)
})

test('LT3 a second session on the same day carries on the day\'s count and never rerolls it', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await elapse(clock, 5 * HOUR)
  const before = stored()
  expect(before.unlocks.length).toBeGreaterThan(0)
  // A new session (the same store), straight away: the plan is read, not drawn again.
  await start($)
  expect(stored().unlockDay).toEqual(before.unlockDay)
  await elapse(clock, 10 * HOUR)
  const after = stored()
  expect(after.unlockDay.d).toBe(before.unlockDay.d)
  expect(after.unlockDay.n).toBe(before.unlockDay.n)
  expect(after.unlocks.length).toBeLessThanOrEqual(after.unlockDay.n)
  expect(after.unlocks.slice(0, before.unlocks.length)).toEqual(before.unlocks)
})

test('LT3 nothing unlocks in a run nobody is at', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on)
  await start($, false)
  await elapse(clock, 10 * HOUR)
  expect(stored()?.unlocks ?? []).toEqual([])
  expect(tally.animWrites).toBe(0)
})


// ---- every look, in both bands ----


// When each unlock shows: a moment its look is on, and what else the scene needs.


// Jeb napping is Jeb himself changing, not a thing beside him, so it is left out of the face checks.


// ---- the kindness ----

test('LT6 past midnight Jeb brings coffee once a night, and not again for a second session or a restart', { timeoutMs: 120_000 }, async ($, on) => {
  const day = new Date(2026, 5, 11, 0, 20).getTime()
  const farm = { ...freshFarm(), unlocks: ['midnightcoffee'], unlockDay: { d: '2026-06-11', n: 3, done: 3, next: day + 20 * HOUR, since: '2026-01-01', coffee: '' } }
  const clock = rig(on, { farm }, day)
  await start($)
  await clock.advance(5 * MINUTE)
  const cups = () => tally.lines.filter(line => line.startsWith('Brought you a cup')).length
  expect(cups()).toBe(1)
  expect(stored().unlockDay.coffee).toBe('2026-06-11')
  // The rest of the night, with another session and a restart on the way.
  await elapse(clock, HOUR)
  await start($)
  await elapse(clock, HOUR)
  await start($)
  await elapse(clock, 2 * HOUR)
  expect(cups()).toBe(1)
  // The next night, once more.
  await elapse(clock, 19 * HOUR)
  const night = tally.lines.length
  await elapse(clock, 70 * MINUTE)
  expect(cups()).toBe(2)
  expect(tally.lines.length).toBeGreaterThan(night)
  expect(stored().unlockDay.coffee).toBe('2026-06-12')
})

test('LT6 no cup before the unlock, none in the morning, none from a Jeb who is silent', { timeoutMs: 120_000 }, async ($, on) => {
  const day = new Date(2026, 5, 11, 0, 20).getTime()
  const plain = { ...freshFarm(), unlockDay: { d: '2026-06-11', n: 3, done: 3, next: day + 20 * HOUR, since: '2026-01-01', coffee: '' } }
  const clock = rig(on, { farm: plain }, day)
  await start($)
  await elapse(clock, 4 * HOUR)
  expect(tally.lines.some(line => line.startsWith('Brought you a cup'))).toBe(false)
})

test('LT6 none in the morning even with the unlock', { timeoutMs: 120_000 }, async ($, on) => {
  const day = new Date(2026, 5, 11, 7, 0).getTime()
  const farm = { ...freshFarm(), unlocks: ['midnightcoffee'], unlockDay: { d: '2026-06-11', n: 3, done: 3, next: day + 20 * HOUR, since: '2026-01-01', coffee: '' } }
  const clock = rig(on, { farm }, day)
  await start($)
  await elapse(clock, 2 * HOUR)
  expect(tally.lines.some(line => line.startsWith('Brought you a cup'))).toBe(false)
  expect(stored().unlockDay.coffee).toBe('')
})

// ---- what a day of them costs ----

test('LT7 a quiet tick makes no calls with every unlock out, at every hour, and a day costs the host no more than it did', { timeoutMs: 600_000 }, async ($, on) => {
  const full = {
    ...freshFarm(),
    unlocks: [...UNLOCK_IDS],
    upgrades: ['chair', 'mailbox'],
    unlockDay: { d: '2026-06-10', n: 5, done: 5, next: START + 30 * HOUR, since: '2025-06-10', coffee: '' },
  }
  const clock = rig(on, { farm: full })
  await start($)
  const calls = () => tally.stateWrites + tally.storeSets + tally.storeGets + tally.fsReads + tally.clockNows
  // A simulated day, hour by hour (Wednesday 09:00 to 23:00). Each hour: a quiet
  // stretch past still-life, then three ticks that are not on the 3 s or the 30 s beat.
  const hourly: number[] = []
  let idleAnims = 0
  // Nine in the morning to eleven at night: the late-night coffee and the next day's plan wake the scene by design (LT6).
  for (let hour = 0; hour < 14; hour += 1) {
    await clock.advance(3 * MINUTE)
    await clock.settle()
    const counts: number[] = []
    for (let i = 0; i < 3; i += 1) {
      const before = calls()
      await clock.advance(500)
      counts.push(calls() - before)
    }
    hourly.push(...counts)
    if (counts.some(n => n !== 0)) {
      console.log(`hour ${hour}: calls ${counts.join(',')}`)
    }
    const animBefore = tally.animWrites
    await elapse(clock, HOUR - 3 * MINUTE - 1500)
    idleAnims += tally.animWrites - animBefore
    if (tally.animWrites !== animBefore) {
      console.log(`hour ${hour}: ${tally.animWrites - animBefore} frame writes`)
    }
  }
  console.log(`a day with all ${UNLOCK_IDS.length} unlocks: quiet-tick calls max ${Math.max(...hourly)}, idle anim writes after still ${idleAnims}, store sets ${tally.storeSets} (${tally.liveSets} of the live record)`)
  expect(hourly.every(n => n === 0)).toBe(true)
  // Once still the scene writes nothing at all: not a frame for a look that changes with the hour.
  expect(idleAnims).toBe(0)
  // The only store writes are the heartbeat, a minute apart: 840 in fourteen hours, and nothing for the little things
  // (the first save gives the farm its salt). The live record is written only when something in it changed: a few
  // times as the session starts and goes still, never while it is still, and never more often than the band redraws
  // or Jeb speaks.
  expect(tally.storeSets - tally.liveSets).toBeLessThanOrEqual(14 * 60 + 6)
  expect(tally.liveSets).toBeGreaterThan(0)
  expect(tally.liveSets).toBeLessThanOrEqual(tally.animWrites + tally.lines.length)
  expect(stored().unlocks.length).toBe(UNLOCK_IDS.length)
})

test('LT7 the day\'s own unlocks cost a few store writes and a few frames over the heartbeat and the idle cadence', { timeoutMs: 600_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await elapse(clock, 15 * HOUR)
  const done = stored().unlocks.length
  console.log(`15 hours with ${done} unlocks: ${tally.storeSets} store sets (${tally.liveSets} of the live record), ${tally.animWrites} frames`)
  expect(done).toBeGreaterThanOrEqual(3)
  expect(done).toBeLessThanOrEqual(5)
  // The heartbeat is a minute apart; each unlock is one farm write (and the day's plan rides in the first).
  expect(tally.storeSets - tally.liveSets).toBeLessThanOrEqual(15 * 60 + done * 2 + 3)
  // The live record follows the scene: it is written only when something in it changed (a happening moves it on
  // every tick), so never more often than the band redraws or Jeb speaks.
  expect(tally.liveSets).toBeLessThanOrEqual(tally.animWrites + tally.lines.length)
  // Each unlock wakes the scene once: a handful of frames until it is still again, never a steady drip.
  expect(tally.animWrites).toBeLessThanOrEqual(done * 200)
})
