import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import type { Farm } from '../types'
import { hasCamps, isPlace, isSalt, neighborOf, sessionKeyOf, shieldFarm } from '../hooks/anonymize'
import { freshFarm, loadFarm, readFarm } from '../hooks/homestead'
import { freshSession, stitchFarm, stitchOf } from '../hooks/quilt'
import { freshSettle, SETTLE_MS, settleStep } from '../hooks/settle'

// The anonymizer's salt, settled between sessions that share one store: a farm
// from before the anonymizer (or a v10 one with no salt) is not made over when a
// session loads it. A session writes a salt only, adopts the one that is stored,
// and makes the farm over only when that salt reads the same twice in a row. Two
// sessions end with one salt and one farm; nothing of the work is keyed, stored or
// shown before then.

const MINUTE = 60_000
// June 2026: the 10th is a Wednesday.
const at = (d: number, h: number, m = 0) => new Date(2026, 5, d, h, m, 0).getTime()
const START = at(10, 9)

const SALT = '0123456789abcdef'
const OTHER_SALT = 'fedcba9876543210'

const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

// Names of the camps a farm from before the anonymizer holds, and a session id it stitched.
const RAW = ['glimmerhaust', 'fizzlewick', 'quillobrand', 'zxq']
const OLD_ID = 'sess-quillobrand-7f3a'

const legacyFarm = () => ({
  ...freshFarm(),
  version: 9,
  anonSalt: undefined,
  anonPlaces: undefined,
  quilt: [
    { c: 'B', d: '2026-06-08', camp: 'glimmerhaust-api' },
    { c: 'G', d: '2026-06-09', camp: 'fizzlewick' },
  ],
  journal: [
    { d: '2026-06-08', camp: 'glimmerhaust-api', line: 'Jun 8 · glimmerhaust-api camp · 3 loads out' },
    { d: '2026-06-09', camp: 'fizzlewick', line: 'Jun 9 · fizzlewick camp · rain twice, fizzlewick notes' },
  ],
  busiest: { d: '2026-06-08', camp: 'glimmerhaust-api', score: 17 },
  stitched: [OLD_ID, 'sess-other-zxq'],
  sessionsWorked: 2,
})

// A v10 farm that never got a salt, with real names in it.
const unsaltedFarm = () => ({ ...legacyFarm(), version: 10, anonSalt: '', anonPlaces: [] })

const markersIn = (text: string) => RAW.filter(marker => text.toLowerCase().includes(marker))

// ---- the reading ----

test('ST1 a farm with real names and no salt is read as waiting, never made over; a farm with a salt is read as it was', () => {
  for (const seed of [legacyFarm(), unsaltedFarm()]) {
    const waiting = readFarm(copy(seed)) as Farm
    expect(waiting.anonPending).toBe(true)
    expect(waiting.anonSalt).toBe('')
    expect(waiting.quilt.map(square => square.camp)).toEqual(['glimmerhaust-api', 'fizzlewick'])
    // The one-step loader still makes it over, as it did.
    const made = loadFarm(copy(seed)) as Farm
    expect(made.anonPending).toBeUndefined()
    expect(isSalt(made.anonSalt)).toBe(true)
    expect(markersIn(JSON.stringify(made))).toEqual([])
  }
  // The shield: nothing but the plain place, no ids, no salt.
  const shown = shieldFarm({ ...(readFarm(copy(legacyFarm())) as Farm), anonSalt: SALT })
  expect(markersIn(JSON.stringify(shown))).toEqual([])
  expect(JSON.stringify(shown)).not.toContain(SALT)
  expect(shown.quilt.length).toBe(2)
  // A farm with a salt (the live one) is not waiting, and the shield leaves it be.
  const live = { ...unsaltedFarm(), anonSalt: SALT, anonPlaces: [], quilt: [{ c: 'B', d: '2026-06-08', camp: 'Laurel Fork' }], journal: [], busiest: null, stitched: [] }
  const read = readFarm(copy(live)) as Farm
  expect(read.anonPending).toBeUndefined()
  expect(read.anonSalt).toBe(SALT)
  expect(loadFarm(copy(live))).toEqual(read)
  expect(shieldFarm(read)).toBe(read)
  // A pending mark written by another session is kept while the names are real.
  expect((readFarm({ ...copy(live), quilt: [{ c: 'B', d: '2026-06-08', camp: 'api' }], anonPending: true }) as Farm).anonPending).toBe(true)
  // Nothing of the work in it: nothing to wait for.
  expect(hasCamps(freshFarm())).toBe(false)
  expect((readFarm({ ...freshFarm(), version: 9 }) as Farm).anonPending).toBeUndefined()
})

// ---- two sessions on one store ----

// One store, read and written as the sessions do it: each read and each write is a
// turn of the event loop, so two sessions on the same tick both read before either writes.
const sharedStore = (initial: unknown) => {
  const box = { raw: copy(initial), sets: [] as { at: number; value: any }[] }
  const pause = async () => {
    await Promise.resolve()
    await Promise.resolve()
  }
  const session = (id: string) => {
    const me = { id, salt: '', state: freshSettle(), result: 'wait' as string, step: async (_now: number) => {} }
    me.step = async now => {
      if (me.result !== 'wait') {
        return
      }
      me.result = await settleStep(me.state, {
        now,
        read: async () => {
          await pause()

          return readFarm(copy(box.raw))
        },
        save: async change => {
          const got = copy(box.raw)
          await pause()
          const base = readFarm(got) as Farm
          const next = change(base)
          if (next === base) {
            me.salt = base.anonPending ? '' : base.anonSalt

            return
          }
          await pause()
          box.raw = copy({ ...next, rev: base.rev + 1 })
          box.sets.push({ at: now, value: copy(box.raw) })
          me.salt = next.anonPending ? '' : next.anonSalt
        },
        salt: () => me.salt,
      })
    }

    return me
  }

  return { box, session }
}

const converged = async (seed: unknown) => {
  const { box, session } = sharedStore(seed)
  const a = session('a')
  const b = session('b')
  // Both load the farm on the same tick; a tick is half a second.
  for (let tick = 0; tick < 12 && !(a.result === 'over' && b.result === 'over'); tick += 1) {
    await Promise.all([a.step(START + tick * 500), b.step(START + tick * 500)])
  }

  return { box, a, b }
}

for (const [label, seed] of [
  ['a farm from before v10', legacyFarm],
  ['a v10 farm that has no salt', unsaltedFarm],
] as const) {
  test(`ST2 two sessions that load ${label} on the same tick end with one salt and one farm, and nothing is stitched twice`, async () => {
    const { box, a, b } = await converged(seed())
    expect(a.result).toBe('over')
    expect(b.result).toBe('over')
    // The race really happened: the two sessions wrote different salts, and the last one stands.
    const saltWrites = box.sets.filter(set => set.value.anonPending)
    expect(saltWrites.length).toBe(2)
    expect(new Set(saltWrites.map(set => set.value.anonSalt)).size).toBe(2)
    const loser = saltWrites[0]?.value.anonSalt as string
    const winner = saltWrites[1]?.value.anonSalt as string
    // A salt write changes the salt and the revision only: the names are still the old ones.
    expect(saltWrites[0]?.value.quilt.map((square: { camp: string }) => square.camp)).toEqual(['glimmerhaust-api', 'fizzlewick'])
    // One salt, the stored one, in both sessions.
    expect(a.salt).toBe(winner)
    expect(b.salt).toBe(winner)
    const farm = box.raw as Farm
    expect(farm.anonSalt).toBe(winner)
    expect(farm.anonPending).toBeUndefined()
    expect(farm.version).toBe(10)
    // The farm was not made over before the salt had read the same twice: the salt is
    // written at the first tick, read at the second and read again at the third.
    const made = box.sets.filter(set => !set.value.anonPending)
    expect(made.length).toBeGreaterThan(0)
    expect(Math.min(...made.map(set => set.at))).toBeGreaterThanOrEqual(START + 2 * SETTLE_MS)
    // Every session that made it over made the same farm.
    for (const set of made) {
      expect(set.value).toEqual(made[0]?.value)
    }
    expect(farm).toEqual(made[0]?.value)
    // Made over: places, no real name, the ids hashed under the stored salt.
    expect(markersIn(JSON.stringify(farm))).toEqual([])
    for (const square of farm.quilt) {
      expect(isPlace(square.camp), square.camp).toBe(true)
    }
    expect(farm.stitched).toEqual([sessionKeyOf(winner, OLD_ID), sessionKeyOf(winner, 'sess-other-zxq')])
    // No raw name in any value written but the old ones, as they were: nothing new of the work.
    for (const set of box.sets) {
      for (const marker of markersIn(JSON.stringify(set.value))) {
        expect(set.value.anonPending, `${marker} in a farm that has been made over`).toBe(true)
      }
    }
    // A square both sessions stitch for the session already on the farm goes up no more than before.
    const rec = { ...freshSession(START, 'Laurel Fork'), calls: 3 }
    for (const one of [a, b]) {
      const stitch = stitchOf(rec, new Date(START), sessionKeyOf(one.salt, OLD_ID))
      expect(stitch).toBeDefined()
      expect(stitchFarm(farm, [stitch as NonNullable<typeof stitch>]).added.length).toBe(0)
    }
    // Had a session kept its own salt (the loser's), its square would have gone up a second time.
    const lost = stitchOf(rec, new Date(START), sessionKeyOf(loser, OLD_ID)) as NonNullable<ReturnType<typeof stitchOf>>
    expect(stitchFarm(farm, [lost]).added.length).toBe(1)
  })
}

test('ST3 a salt another session wrote stands: it is adopted, not replaced, and a session that comes late adopts it too', async () => {
  const seed = { ...legacyFarm(), version: 10, anonPending: true, anonSalt: OTHER_SALT, anonPlaces: [] }
  const { box, a, b } = await converged(seed)
  expect(box.raw.anonSalt).toBe(OTHER_SALT)
  // Nothing was written but the made-over farm.
  expect(box.sets.every(set => !set.value.anonPending)).toBe(true)
  expect(a.salt).toBe(OTHER_SALT)
  expect(b.salt).toBe(OTHER_SALT)
  // A session that arrives after it is all over reads a farm with a salt and nothing waiting.
  const late = sharedStore(box.raw).session('late')
  await late.step(START + 20 * MINUTE)
  expect(late.result).toBe('over')
  expect(late.salt).toBe(OTHER_SALT)
})

test('ST3 a salt that changes under a session is read again from the start: the farm is made over only under one that held', async () => {
  const { box, session } = sharedStore(legacyFarm())
  const a = session('a')
  await a.step(START)
  const first = box.raw.anonSalt as string
  expect(isSalt(first)).toBe(true)
  await a.step(START + SETTLE_MS)
  // Another session's write lands between the two reads.
  box.raw = { ...copy(box.raw), anonSalt: OTHER_SALT, rev: box.raw.rev + 1 }
  await a.step(START + 2 * SETTLE_MS)
  expect(box.raw.anonPending).toBe(true)
  expect(a.result).toBe('wait')
  await a.step(START + 3 * SETTLE_MS)
  expect(a.result).toBe('over')
  expect(box.raw.anonSalt).toBe(OTHER_SALT)
  expect(a.salt).toBe(OTHER_SALT)
})

test('ST4 a step is taken at most once a second', async () => {
  const { box, session } = sharedStore(legacyFarm())
  const a = session('a')
  await a.step(START)
  const writes = box.sets.length
  await a.step(START + 500)
  await a.step(START + SETTLE_MS - 1)
  expect(box.sets.length).toBe(writes)
  expect(a.state.seen).toBe('')
  await a.step(START + SETTLE_MS)
  expect(a.state.seen).toBe(box.raw.anonSalt)
})

// ---- a session in the engine ----

const world = {
  db: new Map<string, unknown>(),
  // Every value stored, with its key.
  sets: [] as { key: string; value: unknown }[],
  said: [] as string[],
}

const SESSION_ID = 'sess-zanzibar-1'

const rig = (on: any, entries: Record<string, unknown> = {}): MockClock => {
  world.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  world.sets = []
  world.said = []
  const clock = mock.clock(on, { now: START })
  mock.env(on, { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_CREATIVITY: 'off', JEB_NEWS: 'null' })
  on('fs.read', (_: any, e: any) => {
    throw new Error(`ENOENT ${String(e.path)}`)
  })
  on('store.get', (_: any, e: any) => ({ value: copy(world.db.get(e.key)) }))
  on('store.set', (_: any, e: any) => {
    world.sets.push({ key: String(e.key), value: copy(e.value) })
    world.db.set(e.key, copy(e.value))

    return { value: undefined }
  })
  on('store.delete', (_: any, e: any) => {
    world.db.delete(e.key)

    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...world.db.keys()] }))
  on('state.set', (_: any, e: any, next: any) => {
    if (e.key === 'say') {
      world.said.push(String((e.value as { line?: unknown } | undefined)?.line ?? ''))
    }

    return next(e)
  })
  on('ui.toast', () => ({ value: undefined }))
  on('audio.play', () => ({ value: undefined }))
  on('audio.speak', () => ({ value: { synthesizer: 'test' } }))
  on('command.register', () => ({ value: { command: 'jeb' } }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('session.end', (_: any, e: any) => ({ sessionId: e.sessionId }))
  on('tool.call', () => ({ result: {} }))
  on('prompt.submit', (_: any, e: any) => e)
  on('turn.start', (_: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.id', () => ({ value: SESSION_ID }))
  on('session.root', () => ({ value: '/home/dev/zanzibarworks' }))
  on('session.repo', () => ({ value: { root: '/home/dev/zanzibarworks', remote: null, internal: false, name: 'zanzibarworks' } }))
  on('agent.list', () => ({ value: [] }))

  return clock
}

const start = ($: any) => $.session.start({ cwd: '/home/dev/zanzibarworks', surface: 'terminal', isInteractive: true })

const farmOf = () => world.db.get('farm') as Farm & { anonPending?: boolean }
const liveKeys = () => [...world.db.keys()].filter(key => key.startsWith('live:'))

// Everything stored so far (and said): none of it holds this session's own work.
const expectNoWork = (label: string) => {
  for (const { key, value } of world.sets) {
    expect(`${key} ${JSON.stringify(value)}`.toLowerCase().includes('zanzibar'), `${label}: the session's camp in what was written to ${key}`).toBe(false)
  }
  for (const line of world.said) {
    expect(line.toLowerCase().includes('zanzibar'), `${label}: the session's camp in a line said: ${line}`).toBe(false)
  }
}

for (const [label, seed] of [
  ['a farm from before v10', legacyFarm],
  ['a v10 farm with no salt', unsaltedFarm],
] as const) {
  test(`ST5 a session that loads ${label} writes only a salt, keeps its work to itself and makes the farm over once the salt has settled`, { timeoutMs: 60_000 }, async ($, on) => {
    const clock = rig(on, { farm: seed() })
    await start($)
    await clock.settle()
    // A salt, and the names as they were: nothing made over.
    const first = farmOf()
    expect(first.anonPending).toBe(true)
    expect(isSalt(first.anonSalt)).toBe(true)
    expect(first.quilt.map(square => square.camp)).toEqual(['glimmerhaust-api', 'fizzlewick'])
    expect(first.stitched).toEqual([OLD_ID, 'sess-other-zxq'])
    // Work in the window: a ticket key. It waits, and nothing of the session is keyed or written.
    await $.prompt.submit({ text: 'triage', command: { name: 'triage', args: 'BRKT-86 zanzibar' } })
    await clock.advance(500)
    expect(farmOf().anonPending).toBe(true)
    expect(world.db.has('sessions')).toBe(false)
    expect(liveKeys()).toEqual([])
    expectNoWork('in the window')
    // The farm shown is the shielded one: no old name on the band or in the atom.
    expect(world.said.filter(line => markersIn(line).length > 0)).toEqual([])
    // Once the salt has read the same twice (a second apart), the farm is made over under it.
    const salt = first.anonSalt
    await clock.advance(2_000)
    await clock.settle()
    const farm = farmOf()
    expect(farm.anonPending).toBeUndefined()
    expect(farm.anonSalt).toBe(salt)
    expect(markersIn(JSON.stringify(farm))).toEqual([])
    expect(farm.stitched).toEqual([sessionKeyOf(salt, OLD_ID), sessionKeyOf(salt, 'sess-other-zxq')])
    // And only now is the session keyed: its heartbeat (a place), its live record, its cow.
    await clock.advance(1_000)
    const sessions = world.db.get('sessions') as Record<string, { name: string }>
    expect(Object.keys(sessions)).toEqual([sessionKeyOf(salt, SESSION_ID)])
    expect(isPlace(Object.values(sessions)[0]?.name)).toBe(true)
    expect(liveKeys().length).toBe(1)
    const record = world.db.get(liveKeys()[0] as string) as { cows?: number[] }
    expect(record.cows).toEqual([neighborOf(salt, 'BRKT-86')])
    expectNoWork('after the salt settled')
    // Not one value written after the farm was made over holds an old name.
    const madeAt = world.sets.findIndex(set => set.key === 'farm' && !(set.value as { anonPending?: boolean }).anonPending)
    expect(madeAt).toBeGreaterThan(0)
    for (const { key, value } of world.sets.slice(madeAt)) {
      expect(markersIn(`${key} ${JSON.stringify(value)}`), key).toEqual([])
    }
  })
}

test('ST6 a salt another session writes over this one\'s while it waits is the one adopted', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on, { farm: legacyFarm() })
  await start($)
  await clock.settle()
  expect(farmOf().anonPending).toBe(true)
  // The other session's write lands last.
  world.db.set('farm', { ...copy(farmOf()), anonSalt: OTHER_SALT, rev: farmOf().rev + 1 })
  await clock.advance(5_000)
  await clock.settle()
  expect(farmOf().anonPending).toBeUndefined()
  expect(farmOf().anonSalt).toBe(OTHER_SALT)
  expect(markersIn(JSON.stringify(farmOf()))).toEqual([])
  await clock.advance(1_000)
  expect(Object.keys(world.db.get('sessions') as object)).toEqual([sessionKeyOf(OTHER_SALT, SESSION_ID)])
  expectNoWork('after adopting')
})

test('ST7 a farm with a salt behaves as it did: no waiting, the session is keyed at once and nothing of the farm is rewritten', { timeoutMs: 60_000 }, async ($, on) => {
  const farm = { ...freshFarm(), anonSalt: SALT, anonPlaces: [], quilt: [{ c: 'B', d: '2026-06-08', camp: 'Laurel Fork' }], sessionsWorked: 1 }
  const clock = rig(on, { farm })
  await start($)
  await clock.advance(1_000)
  expect(farmOf().anonSalt).toBe(SALT)
  expect(farmOf().anonPending).toBeUndefined()
  expect(farmOf().quilt).toEqual(farm.quilt)
  expect(Object.keys(world.db.get('sessions') as object)).toEqual([sessionKeyOf(SALT, SESSION_ID)])
  expect(liveKeys().length).toBe(1)
  expectNoWork('a farm with a salt')
})
