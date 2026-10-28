import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import type { Anim } from '../types'
import { DURATIONS, durationOf } from '../hooks/events'
import { freshFarm, loadFarm } from '../hooks/homestead'
import { dateKey } from '../hooks/quilt'
import { dayKeyOf, spanOf } from '../hooks/visits'
import { dateKeyOf } from '../hooks/util'

// Fixes from the high review of the pixel band: each test fails without its fix.

const MINUTE = 60_000

const START = new Date(2026, 5, 10, 10, 0, 0).getTime()

const anim = (over: Partial<Anim> = {}): Anim => ({
  frame: 0,
  idleAct: 'banjo',
  pose: 'none',
  truck: null,
  visit: null,
  dogRun: 0,
  isNight: false,
  isDim: false,
  isTalking: true,
  event: null,
  wag: false,
  wink: false,
  puff: false,
  sip: false,
  hands: [],
  more: {},
  mates: 0,
  lanterns: 0,
  isGated: false,
  prop: '',
  weather: { kind: 'none', plot: 'all' },
  building: '',
  cows: [],
  moreCows: 0,
  stitch: false,
  live: 'N',
  rainbow: false,
  wet: false,
  star: 0,
  ...over,
})


// ---- 1. the ridges are behind the sky things ----


// ---- 2. no bubble frozen into still-life ----

const tally = {
  frames: [] as { at: number; anim: any }[],
  lastAnim: undefined as any,
  lines: [] as string[],
  db: new Map<string, unknown>(),
}
const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

const rig = (on: any, entries: Record<string, unknown> = {}, draw?: string, now = START): MockClock => {
  tally.frames = []
  tally.lastAnim = undefined
  tally.lines = []
  tally.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  const clock = mock.clock(on, { now })
  mock.env(
    on,
    draw === undefined
      ? { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_CREATIVITY: 'off', JEB_NEWS: 'null' }
      : { HOME: '/home/jeb', JEB_VISITS: draw, JEB_CREATIVITY: 'off', JEB_NEWS: 'null' },
  )
  on('fs.read', (_: any, e: any) => {
    throw new Error(`ENOENT ${(e as { path: string }).path}`)
  })
  on('store.get', (_: any, e: any) => ({ value: copy(tally.db.get(e.key)) }))
  on('store.set', (_: any, e: any) => {
    tally.db.set(e.key, copy(e.value))

    return { value: undefined }
  })
  on('state.set', (_: any, e: any, next: any) => {
    if (e.key === 'anim') {
      tally.lastAnim = e.value
      tally.frames.push({ at: clock.now(), anim: e.value })
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
  on('tool.call', () => ({ result: {} }))
  on('prompt.submit', (_: any, e: any) => e)
  on('turn.start', (_: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))

  return clock
}

const MS = 1000
const elapse = async (clock: MockClock, ms: number) => {
  for (let left = ms; left > 0; left -= 20 * MINUTE) {
    await clock.advance(Math.min(left, 20 * MINUTE))
  }
}
const start = ($: any) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
const stored = () => tally.db.get('farm') as ReturnType<typeof freshFarm>
const kinds = (from = 0) => tally.frames.slice(from).map(f => f.anim.visit?.kind as string | undefined)

test('FX2 a remark on the very tick the scene would go still leaves no bubble up, then or for ten minutes', { options: { talk: 'chatty' }, timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  // The idle remark comes at tick 240 (two minutes), the count to still-life reaches its end on the same tick.
  await clock.advance(2 * MINUTE + 4 * MS)
  expect(tally.lines.length).toBeGreaterThan(1)
  await clock.advance(30 * MS)
  await clock.settle()
  expect(tally.lastAnim.isTalking).toBe(false)
  const frames = tally.frames.length
  await elapse(clock, 10 * MINUTE)
  expect(tally.frames.length).toBe(frames)
  expect(tally.lastAnim.isTalking).toBe(false)
})


test('FX3 no visit starts while Jeb is busy, and one comes once he is not', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, '0')
  await start($)
  await $.prompt.submit({ text: 'work on it' })
  await $.turn.start({ text: 'work on it', turnId: 't1' })
  await elapse(clock, 8 * MINUTE)
  expect(kinds().some(kind => kind !== undefined)).toBe(false)
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
  await clock.settle()
  await elapse(clock, 4 * MINUTE)
  expect(kinds().some(kind => kind !== undefined)).toBe(true)
})


// ---- 6. the mail comes once a day, and counts when it is delivered ----

test('FX6 a second session the same day gets no second mail', { timeoutMs: 120_000 }, async ($, on) => {
  const farm = { ...freshFarm(), upgrades: ['mailbox'] }
  const clock = rig(on, { farm }, '0')
  await start($)
  await elapse(clock, 5 * MINUTE)
  expect(kinds()).toContain('mail')
  expect(stored().mailDay).toBe('2026-06-10')
  await start($)
  await elapse(clock, 15 * MINUTE)
})

test('FX6 a mail visit called off before it arrives is not counted, and still comes later that day', { timeoutMs: 120_000 }, async ($, on) => {
  const farm = { ...freshFarm(), upgrades: ['mailbox'] }
  const clock = rig(on, { farm }, '0')
  await start($)
  await clock.advance(2 * MINUTE + 2 * MS)
  expect(kinds()).toContain('mail')
  expect(stored()?.mailDay ?? '').toBe('')
  // A push sends the truck, and the road is the truck's: the mail goes home.
  await $.tool.call({ tool: 'Bash', command: 'git push' })
  await clock.settle()
  expect(stored()?.mailDay ?? '').toBe('')
  await elapse(clock, 8 * MINUTE)
  expect(stored().mailDay).toBe('2026-06-10')
})

test('FX6 the mail day is read back bounded: a real date or nothing, and older farms start with none', () => {
  expect(freshFarm().mailDay).toBe('')
  expect(loadFarm({ ...freshFarm(), mailDay: '2026-06-10' })?.mailDay).toBe('2026-06-10')
  expect(loadFarm({ ...freshFarm(), mailDay: '2026-6-10' })?.mailDay).toBe('')
  expect(loadFarm({ ...freshFarm(), mailDay: 7 })?.mailDay).toBe('')
  expect(loadFarm({ ...freshFarm(), version: 7, mailDay: undefined })?.mailDay).toBe('')
})


// ---- 9. one day key, one span ----

test('FX9 one zero-padded day key everywhere, and the happenings draw their length the way visits draw theirs', () => {
  const day = new Date(2026, 0, 5, 3)
  expect(dateKeyOf(day)).toBe('2026-01-05')
  expect(dayKeyOf(day)).toBe('2026-01-05')
  expect(dateKey(day)).toBe('2026-01-05')
  expect(dateKeyOf(new Date(2026, 11, 31, 23, 59))).toBe('2026-12-31')
  expect(dayKeyOf).toBe(dateKeyOf)
  for (const id of Object.keys(DURATIONS) as (keyof typeof DURATIONS)[]) {
    for (const r of [0, 0.3, 0.77, 0.9999999]) {
      expect(durationOf(id, () => r)).toBe(spanOf(DURATIONS[id], () => r))
    }
  }
  expect(durationOf('storm', () => 0)).toBe(72)
  expect(durationOf('storm', () => 0.9999999)).toBe(120)
})


