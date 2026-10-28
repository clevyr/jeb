import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import { AREA_DAILY_CAP, areaSystemPrompt, areaTakenOf, reserveAreaAs } from '../hooks/areas'
import { MODEL_DAILY_CAP, modelTakenOf, reserveModelAs } from '../hooks/drops'
import { freshFarm, loadFarm } from '../hooks/homestead'

// The daily caps and their nonces: each reservation of a model call carries a
// nonce, and a session reads it back before it calls, so two sessions that wrote
// the same count can be told apart. The store has no compare-and-set; a rival
// session is played by the store handlers below, which replace what was written
// at a chosen read.

const MINUTE = 60_000
const at = (d: number, h: number, m = 0, s = 0) => new Date(2026, 5, d, h, m, s).getTime()
const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))
const nonceOf = (i: number) => `a000000${i}`
const RIVAL = 'bbbbbbbb'
const NONCE = /^[0-9a-f]{8}$/

// ---- the pure parts ----

test('CP1 the model nonces: kept once each, 8 hex digits, at most the cap; an old farm without them loads empty', () => {
  const fresh = freshFarm()
  expect(fresh.modelTaken).toEqual([])
  const { modelTaken: _gone, ...old } = fresh
  const loaded = loadFarm({ ...old, modelCalls: { day: '2026-06-10', n: 2 } }) as any
  expect(loaded.modelTaken).toEqual([])
  expect(loaded.modelCalls).toEqual({ day: '2026-06-10', n: 2 })
  expect(modelTakenOf(['abcdef12', 'abcdef12', 'ABCDEF12', 'xyz', 7, 'abcdef1', 'abcdef123', '12345678'], MODEL_DAILY_CAP)).toEqual(['abcdef12', '12345678'])
  const many = Array.from({ length: 20 }, (_, i) => `1000000${(i % 16).toString(16)}`)
  expect(modelTakenOf(many, 3).length).toBe(3)
  expect(modelTakenOf('nope', MODEL_DAILY_CAP)).toEqual([])
  const kept = loadFarm({ ...fresh, modelTaken: ['abcdef12', 'bad', 5, ...many] }) as any
  expect(kept.modelTaken.length).toBe(MODEL_DAILY_CAP)
  expect(kept.modelTaken.every((n: string) => NONCE.test(n))).toBe(true)
})

test('CP1 reserveModelAs: one nonce per call, the cap holds, the same nonce twice counts once, a new day starts over', () => {
  let farm = freshFarm()
  const nowMs = at(10, 9)
  for (let i = 1; i <= MODEL_DAILY_CAP; i += 1) {
    const taken = reserveModelAs(farm, nowMs, nonceOf(i))
    expect(taken.ok).toBe(true)
    farm = taken.farm
    expect(farm.modelCalls.n).toBe(i)
    expect(farm.modelTaken.length).toBe(i)
  }
  // The cap: nothing is added, the farm is the same.
  const over = reserveModelAs(farm, nowMs, RIVAL)
  expect(over.ok).toBe(false)
  expect(over.farm.modelTaken).toEqual(farm.modelTaken)
  expect(over.farm.modelCalls).toEqual(farm.modelCalls)
  // A re-apply onto a farm that already holds the nonce adds nothing.
  const again = reserveModelAs(farm, nowMs, nonceOf(2))
  expect(again.ok).toBe(true)
  expect(again.farm).toBe(farm)
  // The next day: the nonces start over, with the new one only.
  const next = reserveModelAs(farm, nowMs + 24 * 60 * MINUTE, RIVAL)
  expect(next.ok).toBe(true)
  expect(next.farm.modelCalls).toEqual({ day: '2026-06-11', n: 1 })
  expect(next.farm.modelTaken).toEqual([RIVAL])
  // The change leaves the old nonces on a day that has passed out of a refused call too.
  const full = { ...farm, modelCalls: { day: '2026-06-09', n: MODEL_DAILY_CAP } }
  expect(reserveModelAs(full, nowMs, RIVAL).farm.modelTaken).toEqual([RIVAL])
})

test('CP4 reserveAreaAs: nonces beside the count, the cap holds, the same nonce counts once, a new day starts over', () => {
  const nowMs = at(10, 9)
  let saved: unknown
  for (let i = 1; i <= AREA_DAILY_CAP; i += 1) {
    const taken = reserveAreaAs(saved, nowMs, nonceOf(i))
    expect(taken.ok).toBe(true)
    expect(taken.taken.ids.length).toBe(i)
    saved = taken.taken
  }
  expect(reserveAreaAs(saved, nowMs, RIVAL)).toEqual({ taken: saved, ok: false })
  expect(reserveAreaAs(saved, nowMs, nonceOf(1))).toEqual({ taken: saved, ok: true })
  expect(reserveAreaAs(saved, nowMs + 24 * 60 * MINUTE, RIVAL)).toEqual({ taken: { day: '2026-06-11', ids: [RIVAL] }, ok: true })
  expect(areaTakenOf({ day: '2026-06-10', ids: ['abcdef12', 'abcdef12', 'bad', 3, '12345678', '23456789', '34567890', '45678901'] })).toEqual({
    day: '2026-06-10',
    ids: ['abcdef12', '12345678', '23456789'],
  })
  expect(areaTakenOf(undefined)).toEqual({ day: '', ids: [] })
})

// ---- an engine to run it in ----

const db = new Map<string, unknown>()
const modelCalls: { system: string; prompt: string }[] = []
let clk: MockClock
// A rival session's write at a read: the nth get of `key` after the first write to it that holds
// something new (a nonce the store did not have) returns, and leaves in the store, what `make` gives.
type Race = { key: string; onGet: number; make: (stored: any) => unknown; seen: number; fired: boolean; armed: boolean }
let race: Race | undefined

const arm = (key: string, onGet: number, make: (stored: any) => unknown) => {
  race = { key, onGet, make, seen: 0, fired: false, armed: false }
}

const takenIn = (key: string, value: any): string[] => (key === 'farm' ? value?.modelTaken : value?.ids) ?? []

const answered = (reply: string) => ({
  isAnswered: true,
  text: reply,
  usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
})

const GENERIC = (n: number) => JSON.stringify({ kind: 'saying', name: `generic-${n}`, lines: [`Nothin much, say number ${n}.`], summary: `A quiet saying ${n}` })

const areaReplyFor = (prompt: string) => {
  const pick = (name: string) => new RegExp(`^${name}: (.+)$`, 'm').exec(prompt)?.[1] ?? ''
  const prop = pick('props').split(', ')[0] ?? ''

  return [
    `TERRAIN: ${pick('terrain')}`,
    `PALETTE: ${pick('palette')}`,
    `WEATHER: ${pick('weather')}`,
    `MOOD: ${pick('mood')}`,
    `PROPS: ${pick('props')}`,
    'LORE: Mist sits low where the old road bends.',
    'LORE: The spring runs sweet even in a dry year.',
    `BEAT: sky | ${prop} | Something small goes over, unhurried.`,
    'BEAT: yard | - | A gate swings slow in the breeze.',
    'BEAT: road | - | Gravel crunches under a steady pair of boots.',
    'END',
  ].join('\n')
}

const rig = (on: any, entries: Record<string, unknown>, now: number): MockClock => {
  db.clear()
  for (const [key, value] of Object.entries(entries)) {
    db.set(key, copy(value))
  }
  modelCalls.length = 0
  race = undefined
  const clock = mock.clock(on, { now })
  clk = clock
  mock.env(on, { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_NEWS: 'null' })
  on('fs.read', (_: any, e: any) => {
    throw new Error(`ENOENT ${(e as { path: string }).path}`)
  })
  on('store.get', (_: any, e: any) => {
    if (race && race.armed && !race.fired && e.key === race.key) {
      race.seen += 1
      if (race.seen === race.onGet) {
        race.fired = true
        db.set(e.key, copy(race.make(db.get(e.key))))
      }
    }

    return { value: copy(db.get(e.key)) }
  })
  on('store.set', (_: any, e: any) => {
    // The first write that holds a nonce the store did not have starts the count of reads.
    if (race && !race.armed && e.key === race.key) {
      const before = takenIn(e.key, db.get(e.key))
      race.armed = takenIn(e.key, e.value).some(nonce => !before.includes(nonce))
    }
    db.set(e.key, copy(e.value))

    return { value: undefined }
  })
  on('state.set', (_: any, e: any, next: any) => next(e))
  on('tool.list', () => ({ value: [] }))
  on('command.list', () => ({ value: [] }))
  on('model.complete', (_: any, e: any) => {
    modelCalls.push({ system: String(e.system ?? ''), prompt: String(e.prompt) })
    const isArea = String(e.system ?? '') === areaSystemPrompt()

    return { value: answered(isArea ? areaReplyFor(String(e.prompt)) : GENERIC(modelCalls.length)) }
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
  on('tool.call', () => ({ result: {} }))
  on('prompt.submit', (_: any, e: any) => e)
  on('turn.start', (_: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.end', (_: any, e: any) => ({ sessionId: e.sessionId }))

  return clock
}

const start = ($: any) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
const farmNow = () => db.get('farm') as any
const isAreaCall = (call: { system: string }) => call.system === areaSystemPrompt()

const AREA_CALLS = [
  { tool: 'Edit', tool_use_id: 'tu-a1', file_path: '/w/api/src/widget.ts', old_string: 'a', new_string: 'b' },
  { tool: 'Write', tool_use_id: 'tu-a2', file_path: '/w/api/Dockerfile', content: 'FROM x' },
  { tool: 'Read', tool_use_id: 'tu-a3', file_path: '/w/api/resources/js/Thing.tsx' },
  { tool: 'Read', tool_use_id: 'tu-a4', file_path: '/w/api/tests/Unit/ThingTest.php' },
  { tool: 'Bash', tool_use_id: 'tu-a5', command: 'git checkout -b feature/x' },
  { tool: 'Bash', tool_use_id: 'tu-a6', command: 'npm run build' },
  { tool: 'Bash', tool_use_id: 'tu-a7', command: 'psql -d x -c "select 1"' },
]

// Thirty counted events and some housekeeping on top.
const areaWork = async ($: any) => {
  for (let i = 0; i < 6; i += 1) {
    for (const input of AREA_CALLS) {
      await $.tool.call(copy(input))
    }
    await clk.settle()
  }
  for (let left = 3 * MINUTE; left > 0; left -= MINUTE) {
    await clk.advance(MINUTE)
  }
}

// A weekday morning just before the 9:00 drop; a Saturday (no drops) for the areas.
const DROP_TIME = at(10, 8, 59, 40)
const SATURDAY = at(13, 10)

const takenFarm = (n: number, day = '2026-06-10') => ({
  ...freshFarm(),
  modelCalls: { day, n },
  modelTaken: Array.from({ length: n }, (_, i) => nonceOf(i)),
})

// ---- the model cap ----

test('CP2 a session that wrote the same count as another and was written over reads its nonce missing and makes no call', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, DROP_TIME)
  // The other session's write lands after this one's own save has settled, at the same count.
  arm('farm', 2, stored => ({ ...stored, modelTaken: [RIVAL] }))
  await start($)
  await clock.advance(3 * MINUTE)
  expect(race?.fired).toBe(true)
  // Exactly one call was reserved (it is the other session's), and this one made none.
  expect(modelCalls.length).toBe(0)
  expect(farmNow().modelCalls).toEqual({ day: '2026-06-10', n: 1 })
  expect(farmNow().modelTaken).toEqual([RIVAL])
})

test('CP2 with no other session the same reservation is made: one call, one nonce, the count and the nonces agree', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, DROP_TIME)
  await start($)
  await clock.advance(3 * MINUTE)
  expect(modelCalls.length).toBe(1)
  expect(farmNow().modelCalls).toEqual({ day: '2026-06-10', n: 1 })
  expect(farmNow().modelTaken.length).toBe(1)
  expect(farmNow().modelTaken[0]).toMatch(NONCE)
})

test('CP2 with one call left and two sessions racing, the total never passes the cap: the same-count write loses', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, { farm: takenFarm(MODEL_DAILY_CAP - 1) }, DROP_TIME)
  arm('farm', 2, stored => ({ ...stored, modelTaken: [...stored.modelTaken.slice(0, MODEL_DAILY_CAP - 1), RIVAL] }))
  await start($)
  await clock.advance(3 * MINUTE)
  expect(race?.fired).toBe(true)
  expect(modelCalls.length).toBe(0)
  expect(farmNow().modelCalls.n).toBe(MODEL_DAILY_CAP)
  expect(farmNow().modelTaken.length).toBe(MODEL_DAILY_CAP)
  expect(farmNow().modelTaken).toContain(RIVAL)
})

test('CP2 with one call left, the other session takes it first (same rev, other contents): the re-apply keeps the cap and the call is not made', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, { farm: takenFarm(MODEL_DAILY_CAP - 1) }, DROP_TIME)
  // The write is replaced as saveNow reads it back: the other session took the last call.
  arm('farm', 1, stored => ({ ...stored, modelCalls: { day: '2026-06-10', n: MODEL_DAILY_CAP }, modelTaken: [...stored.modelTaken.slice(0, MODEL_DAILY_CAP - 1), RIVAL] }))
  await start($)
  await clock.advance(3 * MINUTE)
  expect(race?.fired).toBe(true)
  expect(modelCalls.length).toBe(0)
  expect(farmNow().modelCalls.n).toBe(MODEL_DAILY_CAP)
  expect(farmNow().modelTaken.length).toBe(MODEL_DAILY_CAP)
  expect(farmNow().modelTaken.every((n: string) => NONCE.test(n))).toBe(true)
})

test('CP2 with room for both, the re-apply onto the other session\'s write keeps this one\'s nonce, adds one call and makes it', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, { farm: takenFarm(2) }, DROP_TIME)
  arm('farm', 1, stored => ({ ...stored, modelCalls: { day: '2026-06-10', n: 3 }, modelTaken: [...stored.modelTaken.slice(0, 2), RIVAL] }))
  await start($)
  await clock.advance(3 * MINUTE)
  expect(race?.fired).toBe(true)
  expect(modelCalls.length).toBe(1)
  expect(farmNow().modelCalls.n).toBe(4)
  expect(farmNow().modelTaken.length).toBe(4)
  expect(farmNow().modelTaken).toContain(RIVAL)
})

test('CP3 an old farm without nonces loads and reserves as it did', { timeoutMs: 120_000 }, async ($, on) => {
  const { modelTaken: _gone, ...old } = takenFarm(2)
  const clock = rig(on, { farm: old }, DROP_TIME)
  await start($)
  await clock.advance(3 * MINUTE)
  expect(modelCalls.length).toBe(1)
  expect(farmNow().modelCalls).toEqual({ day: '2026-06-10', n: 3 })
  expect(farmNow().modelTaken.length).toBe(1)
  expect(farmNow().modelTaken[0]).toMatch(NONCE)
})

test('CP4 a new day empties the model nonces: yesterday\'s are gone, today\'s is the only one', { timeoutMs: 120_000 }, async ($, on) => {
  const farm = takenFarm(MODEL_DAILY_CAP, '2026-06-09')
  const clock = rig(on, { farm }, DROP_TIME)
  await start($)
  await clock.advance(3 * MINUTE)
  expect(modelCalls.length).toBe(1)
  expect(farmNow().modelCalls).toEqual({ day: '2026-06-10', n: 1 })
  expect(farmNow().modelTaken.length).toBe(1)
  for (const old of farm.modelTaken) {
    expect(farmNow().modelTaken).not.toContain(old)
  }
})

// ---- the area cap ----

const areaTakenNow = () => db.get('areaTaken') as { day: string; ids: string[] } | undefined

test('CP2 areas: no other session, the reservation is made: one call, a nonce, areaCalls as its count', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, SATURDAY)
  await start($)
  await areaWork($)
  expect(clock.now()).toBeGreaterThan(SATURDAY)
  expect(modelCalls.filter(isAreaCall).length).toBe(1)
  expect(areaTakenNow()?.day).toBe('2026-06-13')
  expect(areaTakenNow()?.ids.length).toBe(1)
  expect(areaTakenNow()?.ids[0]).toMatch(NONCE)
  expect(db.get('areaCalls')).toEqual({ day: '2026-06-13', n: 1 })
})

test('CP2 areas: a session that wrote the same count as another and was written over makes no call', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on, {}, SATURDAY)
  arm('areaTaken', 1, () => ({ day: '2026-06-13', ids: [RIVAL] }))
  await start($)
  await areaWork($)
  expect(race?.fired).toBe(true)
  expect(modelCalls.filter(isAreaCall).length).toBe(0)
  expect(areaTakenNow()).toEqual({ day: '2026-06-13', ids: [RIVAL] })
  expect(db.get('areaCalls')).toEqual({ day: '2026-06-13', n: 1 })
})

test('CP2 areas: with one call left and the other session writing first, the total never passes the cap', { timeoutMs: 120_000 }, async ($, on) => {
  const ids = [nonceOf(1), nonceOf(2)]
  rig(on, { areaTaken: { day: '2026-06-13', ids }, areaCalls: { day: '2026-06-13', n: 2 } }, SATURDAY)
  arm('areaTaken', 1, () => ({ day: '2026-06-13', ids: [...ids, RIVAL] }))
  await start($)
  await areaWork($)
  expect(race?.fired).toBe(true)
  expect(modelCalls.filter(isAreaCall).length).toBe(0)
  expect(areaTakenNow()?.ids.length).toBe(AREA_DAILY_CAP)
  expect(db.get('areaCalls')).toEqual({ day: '2026-06-13', n: AREA_DAILY_CAP })
})

test('CP2 areas: with one call left and the other session writing over it at the same count, only one of them has it', { timeoutMs: 120_000 }, async ($, on) => {
  const ids = [nonceOf(1), nonceOf(2)]
  rig(on, { areaTaken: { day: '2026-06-13', ids }, areaCalls: { day: '2026-06-13', n: 2 } }, SATURDAY)
  arm('areaTaken', 1, () => ({ day: '2026-06-13', ids: [...ids, RIVAL] }))
  await start($)
  await areaWork($)
  expect(modelCalls.filter(isAreaCall).length).toBe(0)
  expect(areaTakenNow()?.ids).toEqual([...ids, RIVAL])
})

test('CP4 areas: a new day empties the area nonces', { timeoutMs: 120_000 }, async ($, on) => {
  const ids = [nonceOf(1), nonceOf(2), nonceOf(3)]
  rig(on, { areaTaken: { day: '2026-06-12', ids }, areaCalls: { day: '2026-06-12', n: 3 } }, SATURDAY)
  await start($)
  await areaWork($)
  expect(modelCalls.filter(isAreaCall).length).toBe(1)
  expect(areaTakenNow()?.day).toBe('2026-06-13')
  expect(areaTakenNow()?.ids.length).toBe(1)
  for (const old of ids) {
    expect(areaTakenNow()?.ids).not.toContain(old)
  }
  expect(db.get('areaCalls')).toEqual({ day: '2026-06-13', n: 1 })
})
