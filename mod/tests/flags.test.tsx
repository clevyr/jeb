import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import { FLAGS_MAX_BYTES, flagsPathOf, isDropsOffByApp } from '../hooks/flags'
import { freshFarm } from '../hooks/homestead'

// The desktop app's creative-drops flag: the plugin reads the app's flags file at
// decision points only, and either the app or the plugin option turns the drops off.
// The model and the clock are mocked; nothing real is read or called.

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const START = new Date(2026, 5, 10, 8, 50).getTime()
const FLAGS = '/home/jeb/Library/Application Support/Jeb/flags.json'
const SALT = '0123456789abcdef'

const world = {
  db: new Map<string, unknown>(),
  model: [] as string[],
  reads: [] as string[],
  // What the flags file answers: text, or undefined for a missing file.
  flags: undefined as string | undefined,
}
const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))
const GENERIC = (n: number) => ({ kind: 'saying', name: `generic-${n}`, lines: [`Nothin much, say number ${n}.`], summary: `A quiet saying ${n}` })

const rig = (on: any, flags: string | undefined, entries: Record<string, unknown> = {}, now = START, env: Record<string, string> = {}): MockClock => {
  world.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  world.model = []
  world.reads = []
  world.flags = flags
  const clock = mock.clock(on, { now })
  mock.env(on, { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_NEWS: 'null', ...env })
  on('fs.read', (_: any, e: any) => {
    world.reads.push(String(e.path))
    if (world.flags === undefined) {
      throw new Error(`ENOENT ${String(e.path)}`)
    }

    return { value: world.flags }
  })
  on('store.get', (_: any, e: any) => ({ value: copy(world.db.get(e.key)) }))
  on('store.set', (_: any, e: any) => {
    world.db.set(e.key, copy(e.value))

    return { value: undefined }
  })
  on('store.delete', (_: any, e: any) => {
    world.db.delete(e.key)

    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...world.db.keys()] }))
  on('model.complete', (_: any, e: any) => {
    world.model.push(String(e.prompt))

    return {
      value: {
        isAnswered: true,
        text: JSON.stringify(GENERIC(world.model.length)),
        usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
      },
    }
  })
  on('config.set', (_: any, e: any) => ({ value: e.value }))
  on('tool.list', () => ({ value: [] }))
  on('command.list', () => ({ value: [] }))
  on('mcp.call', () => ({ deny: 'no such tool' }))
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

const elapse = async (clock: MockClock, ms: number) => {
  for (let left = ms; left > 0; left -= 20 * MINUTE) {
    await clock.advance(Math.min(left, 20 * MINUTE))
  }
}
const start = ($: any) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
const surprises = () => ((world.db.get('farm') as { surprises?: unknown[] } | undefined)?.surprises ?? []).length
const flagReads = () => world.reads.filter(path => path === FLAGS).length

test('FL1 the flags path is JEB_HOME when set, else the app folder under the home, else none', () => {
  expect(flagsPathOf('/scratch/jeb', '/home/jeb')).toBe('/scratch/jeb/flags.json')
  expect(flagsPathOf('/scratch/jeb/', undefined)).toBe('/scratch/jeb/flags.json')
  expect(flagsPathOf(undefined, '/home/jeb')).toBe('/home/jeb/Library/Application Support/Jeb/flags.json')
  expect(flagsPathOf('', '/home/jeb/')).toBe('/home/jeb/Library/Application Support/Jeb/flags.json')
  expect(flagsPathOf(undefined, undefined)).toBeUndefined()
})

test('FL1 the app has the drops off only for an object with creativeDrops false', () => {
  expect(isDropsOffByApp('{"creativeDrops":false}')).toBe(true)
  expect(isDropsOffByApp('{"creativeDrops":false,"later":1}')).toBe(true)
  for (const text of ['{"creativeDrops":true}', '{}', '{"creativeDrops":"false"}', '{"creativeDrops":0}', '[false]', 'false', 'null', 'not json', '', undefined, { creativeDrops: false }]) {
    expect(isDropsOffByApp(text), String(text)).toBe(false)
  }
  const big = `{"creativeDrops":false,"pad":"${'x'.repeat(FLAGS_MAX_BYTES)}"}`
  expect(isDropsOffByApp(big)).toBe(false)
})

test('FL2 with the app flag off, a weekday stretch makes no surprise, no model call and no place', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":false}')
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(surprises()).toBe(0)
  expect(world.model).toEqual([])
  expect(world.db.get('areas')).toBeUndefined()
  // Read at the start and when a slot is due (again every ten minutes while it is held back), never on a tick.
  expect(flagReads()).toBeLessThanOrEqual(50)
  expect(world.reads.filter(path => path !== FLAGS)).toEqual([])
})

test('FL2 a garbage flags file leaves the drops on', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{not json')
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(surprises()).toBeGreaterThan(0)
  expect(world.model.length).toBeGreaterThan(0)
})

test('FL2 a flags file with another value for the flag leaves the drops on', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":"no"}')
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(surprises()).toBeGreaterThan(0)
})

test('FL2 a missing flags file (the read fails) leaves the drops on', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, undefined)
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(surprises()).toBeGreaterThan(0)
  expect(world.model.length).toBeGreaterThan(0)
})

test('FL3 the flags file is read at decision points, about once a slot, not on every tick', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":true}')
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(surprises()).toBe(3)
  // Start, three slots, and the makeDrop of each slot reads nothing further.
  expect(flagReads()).toBeGreaterThanOrEqual(4)
  expect(flagReads()).toBeLessThanOrEqual(8)
})

test('FL4 turning the flag back on is noticed at the next slot', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":false}')
  await start($)
  await elapse(clock, 3 * HOUR + 30 * MINUTE)
  expect(surprises()).toBe(0)
  world.flags = '{"creativeDrops":true}'
  await elapse(clock, 4 * HOUR)
  expect(surprises()).toBeGreaterThan(0)
})

test('FL5 the live record says drops off when the plugin option is off, and not when it is on', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on, undefined, { farm: { ...freshFarm(), anonSalt: SALT } })
  const live = () => [...world.db.entries()].filter(([key]) => key.startsWith('live:')).map(([, value]) => value as Record<string, unknown>)
  await start($)
  await clock.advance(2_000)
  expect(live().length).toBe(1)
  expect(live()[0]?.drops).toBeUndefined()
  await $.config.set({ key: 'jeb.creativity', value: false })
  await clock.advance(2_000)
  expect(live()[0]?.drops).toBe('off')
  await $.config.set({ key: 'jeb.creativity', value: true })
  await clock.advance(2_000)
  expect(live()[0]?.drops).toBeUndefined()
})

// JEB_DROP_NOW=1 (dev/run --surprise): one forced surprise per session, at any hour or day,
// through the same gates, and never recorded against a real slot.
const SATURDAY_7 = new Date(2026, 5, 13, 7, 0).getTime()
const DROP_NOW = { JEB_DROP_NOW: '1' }
const droppedSlots = () => (world.db.get('farm') as { drops?: { done: number[]; claims: unknown[] } } | undefined)?.drops

test('FL6 JEB_DROP_NOW=1 on a Saturday at 07:00 makes exactly one surprise, marks no slot and makes no second', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, undefined, {}, SATURDAY_7, DROP_NOW)
  await start($)
  await clock.advance(30_000)
  expect(surprises()).toBe(1)
  expect(world.model.length).toBe(1)
  expect(droppedSlots()?.done ?? []).toEqual([])
  expect(droppedSlots()?.claims ?? []).toEqual([])
  await elapse(clock, 20 * HOUR)
  expect(surprises()).toBe(1)
  expect(world.model.length).toBe(1)
})

test('FL6 JEB_DROP_NOW=1 on a weekday leaves the 09:00 slot to run later', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, undefined, {}, new Date(2026, 5, 10, 7, 0).getTime(), DROP_NOW)
  await start($)
  await clock.advance(30_000)
  expect(surprises()).toBe(1)
  expect(droppedSlots()?.done ?? []).toEqual([])
  await elapse(clock, 2 * HOUR + 30 * MINUTE)
  expect(surprises()).toBe(2)
  expect(droppedSlots()?.done).toEqual([9])
})

test('FL6 JEB_DROP_NOW=1 with the app flag off makes no surprise and no model call, and runs once it is turned on', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":false}', {}, SATURDAY_7, DROP_NOW)
  await start($)
  await elapse(clock, 5 * MINUTE)
  expect(surprises()).toBe(0)
  expect(world.model).toEqual([])
  world.flags = '{"creativeDrops":true}'
  await elapse(clock, 15 * MINUTE)
  expect(surprises()).toBe(1)
})

test('FL6 JEB_DROP_NOW=1 with the plugin option off makes none', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, undefined, {}, SATURDAY_7, DROP_NOW)
  await start($)
  await $.config.set({ key: 'jeb.creativity', value: false })
  await elapse(clock, HOUR)
  expect(surprises()).toBe(0)
  expect(world.model).toEqual([])
})

test('FL6 JEB_DROP_NOW=1 stops at the daily call cap', { timeoutMs: 120_000 }, async ($, on) => {
  const day = '2026-06-13'
  const clock = rig(on, undefined, { farm: { ...freshFarm(), modelCalls: { day, n: 6 } } }, SATURDAY_7, DROP_NOW)
  await start($)
  await clock.advance(30_000)
  expect(world.model).toEqual([])
})

test('FL6 without JEB_DROP_NOW a Saturday makes no surprise', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, undefined, {}, SATURDAY_7)
  await start($)
  await elapse(clock, 5 * HOUR)
  expect(surprises()).toBe(0)
})

// ---- the project's area and the app's flag ----

const liveRecords = () => [...world.db.entries()].filter(([key]) => key.startsWith('live:')).map(([, value]) => value as Record<string, unknown>)
// Thirty counted events: reads of files, each one a kind of work.
const earnWork = async ($: any, clock: MockClock) => {
  for (let i = 0; i < 36; i += 1) {
    await $.tool.call({ tool: 'Read', tool_use_id: `tu-${i}`, file_path: `/w/api/src/f${i}.ts` })
    await clock.settle()
  }
}

test('FL7 a session that starts with the app flag off still gets its project key, and the live record shows the area only once the flag is on again', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":false}', { farm: { ...freshFarm(), anonSalt: SALT } })
  await start($)
  await clock.advance(2_000)
  // The key was made (its secret is stored) although the app flag is off.
  expect(typeof world.db.get('areaSecret')).toBe('string')
  expect(liveRecords().length).toBe(1)
  expect(liveRecords()[0]?.area).toBeUndefined()
  world.flags = '{"creativeDrops":true}'
  // The 9:00 slot reads the flag again.
  await elapse(clock, 25 * MINUTE)
  expect(liveRecords()[0]?.area).toMatch(/^[0-9a-f]{8}$/)
})

test('FL7 with the app flag read as off at makeArea time, no area is made (no model call, none stored) and the claim is released', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":true}', { farm: { ...freshFarm(), anonSalt: SALT } })
  await start($)
  await clock.advance(2_000)
  await earnWork($, clock)
  // The app's flag is turned off after the session last read it on: the cached value still says on.
  world.flags = '{"creativeDrops":false}'
  await clock.advance(2 * MINUTE)
  expect(world.model).toEqual([])
  expect(world.db.get('areas')).toBeUndefined()
  // makeArea did run (a claim was taken, so the area key's claims were written) and let it go.
  const claims = (world.db.get('areaClaims') ?? {}) as Record<string, unknown>
  expect(Object.keys(claims)).toEqual([])
})

test('FL7 the same work with the app flag on makes an area', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, '{"creativeDrops":true}', { farm: { ...freshFarm(), anonSalt: SALT } })
  await start($)
  await clock.advance(2_000)
  await earnWork($, clock)
  await clock.advance(2 * MINUTE)
  expect(Object.keys((world.db.get('areas') ?? {}) as object).length).toBe(1)
})

test('FL7 the flags file counts UTF-8 bytes: multibyte text under 4096 characters but over 4096 bytes is on, under 4096 bytes is off', () => {
  const head = '{"creativeDrops":false,"pad":"'
  const tail = '"}'
  const pad = (n: number) => `${head}${'é'.repeat(n)}${tail}`
  const over = pad(2100)
  expect(over.length).toBeLessThan(FLAGS_MAX_BYTES)
  expect(new TextEncoder().encode(over).length).toBeGreaterThan(FLAGS_MAX_BYTES)
  expect(isDropsOffByApp(over)).toBe(false)
  const under = pad(1900)
  expect(new TextEncoder().encode(under).length).toBeLessThanOrEqual(FLAGS_MAX_BYTES)
  expect(isDropsOffByApp(under)).toBe(true)
})
