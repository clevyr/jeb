import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import type { Anim, Farm } from '../types'
import {
  anonymizeFarm,
  hashHex,
  isPlace,
  isToken,
  lineFor,
  liveTokenOf,
  MAX_PLACE_TAGS,
  mintSalt,
  neighborOf,
  PLACES,
  placeFor,
  placeSeen,
  RADIO_LINE,
  sessionKeyOf,
  sipHash,
  TOOL_LINE,
} from '../hooks/anonymize'
import { freshFarm, loadFarm } from '../hooks/homestead'
import { LIVE_FIELDS, LIVE_TTL_MS, liveBody, livePrune, liveRecord, MAX_LIVE } from '../hooks/live'
import { MCP_LINES, mcpKindOf } from '../hooks/mcp'
import { campLabel } from '../hooks/quilt'
import { cowLine } from '../hooks/workday'

// The anonymizer, the farm's migration to it and the live record: one way and
// stable, nothing of the work in what is stored or shown, and a record that is
// written only when it changes.

const MINUTE = 60_000
const HOUR = 60 * MINUTE
// June 2026: the 10th is a Wednesday.
const at = (d: number, h: number, m = 0) => new Date(2026, 5, d, h, m, 0).getTime()
const START = at(10, 9)

const SALT = '0123456789abcdef'
const OTHER_SALT = 'fedcba9876543210'

const lcg = (seed: number) => {
  let x = seed
  return () => {
    x = (x * 1664525 + 1013904223) % 4294967296

    return x / 4294967296
  }
}

const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

// Work names a session could hold.
const NAMES = [
  'glimmerhaust',
  'glimmerhaust-api',
  'fizzlewick',
  'acme-billing',
  'feature/wobblequist',
  'BRKT-86-fix',
  '.claude',
  'camp',
  'api',
  'web',
  'Ünïcødé-répo',
  'x'.repeat(40),
]

// ---- the hash ----

test('AN1 the keyed hash is SipHash-2-4: the reference vectors under the key 00..0f', () => {
  const k0 = 0x0706050403020100n
  const k1 = 0x0f0e0d0c0b0a0908n
  const bytes = (n: number) => Array.from({ length: n }, (_, i) => i)
  expect(sipHash(k0, k1, bytes(0))).toBe(0x726fdb47dd0e0e31n)
  expect(sipHash(k0, k1, bytes(1))).toBe(0x74f839c593dc67fdn)
  expect(sipHash(k0, k1, bytes(15))).toBe(0xa129ca6149be45e5n)
  // Hex of the right length, lower case.
  expect(hashHex(SALT, 'anything', 12)).toMatch(/^[0-9a-f]{12}$/)
  expect(hashHex(SALT, 'anything', 16)).toMatch(/^[0-9a-f]{16}$/)
})

test('AN1 a new salt is 16 hex digits, from the dice it is handed', () => {
  const salt = mintSalt(lcg(7))
  expect(salt).toMatch(/^[0-9a-f]{16}$/)
  expect(mintSalt(lcg(7))).toBe(salt)
  expect(mintSalt(lcg(8))).not.toBe(salt)
  expect(mintSalt(() => 0.999999)).toBe('f'.repeat(16))
})

// ---- places ----

test('AN2 the places: at least 64, all different, short plain names that read as a camp', () => {
  expect(PLACES.length).toBeGreaterThanOrEqual(64)
  expect(new Set(PLACES).size).toBe(PLACES.length)
  for (const place of PLACES) {
    expect(place, place).toMatch(/^[A-Z][A-Za-z ]+[a-z]$/)
    expect(place.length, place).toBeLessThanOrEqual(14)
    expect(campLabel(place)).toBe(`${place} camp`)
    expect(isPlace(place)).toBe(true)
  }
  expect(isPlace('glimmerhaust')).toBe(false)
})

test('AN3 a name always becomes the same place, and two names never share one while the list has room', () => {
  let tags: string[] = []
  const first = new Map<string, string>()
  for (const name of NAMES) {
    const done = placeFor(SALT, name, tags)
    tags = done.tags
    first.set(name, done.place)
    expect(isPlace(done.place), name).toBe(true)
  }
  // Every name its own place.
  expect(new Set(first.values()).size).toBe(NAMES.length)
  // Asked again, in any order, with the registry as it stands: the same places, and nothing new registered.
  for (const name of [...NAMES].reverse()) {
    const again = placeFor(SALT, name, tags)
    expect(again.place, name).toBe(first.get(name))
    expect(again.tags).toBe(tags)
    expect(placeSeen(SALT, name, tags)).toBe(first.get(name))
  }
  // A full registry of 64 camps: 64 different places.
  let many: string[] = []
  const places = new Set<string>()
  for (let i = 0; i < MAX_PLACE_TAGS; i += 1) {
    const done = placeFor(SALT, `repo-${i}`, many)
    many = done.tags
    places.add(done.place)
  }
  expect(many.length).toBe(MAX_PLACE_TAGS)
  expect(places.size).toBe(MAX_PLACE_TAGS)
  // Past the cap a name still gets a stable place, and the registry does not grow.
  const over = placeFor(SALT, 'one-too-many', many)
  expect(over.tags).toBe(many)
  expect(placeFor(SALT, 'one-too-many', many).place).toBe(over.place)
  // The registry holds only short hex tags, never a name.
  for (const tag of many) {
    expect(tag).toMatch(/^[0-9a-f]{6}$/)
  }
})

test('AN4 one way: nothing of a name, key or id survives, and without the salt the same name says nothing', () => {
  const inputs = [...NAMES, 'ZXQ-4242', 'sess-quillobrand-7f3a', 'mcp__claude_ai_Zorbleflux__getJiraIssue']
  for (const input of inputs) {
    const outputs = [
      placeFor(SALT, input, []).place,
      placeSeen(SALT, input, []),
      sessionKeyOf(SALT, input),
      liveTokenOf(SALT, '2026-06-10', sessionKeyOf(SALT, input)),
      String(neighborOf(SALT, input)),
      hashHex(SALT, input, 16),
    ]
    for (const out of outputs) {
      const lower = out.toLowerCase()
      // Any run of four characters of the input (letters and digits) is nowhere in what came out.
      const word = input.toLowerCase().replace(/[^a-z0-9]/g, '')
      for (let i = 0; i + 4 <= word.length; i += 1) {
        expect(lower.includes(word.slice(i, i + 4)), `${input} -> ${out}`).toBe(false)
      }
    }
  }
  // The salt is the key: the same id under another salt, or none, hashes to something else.
  let same = 0
  for (let i = 0; i < 200; i += 1) {
    const id = `session-${i}`
    const key = sessionKeyOf(SALT, id)
    expect(isToken(key)).toBe(true)
    expect(sessionKeyOf(SALT, id)).toBe(key)
    if (key === sessionKeyOf(OTHER_SALT, id) || key === sessionKeyOf('', id)) {
      same += 1
    }
  }
  expect(same).toBe(0)
  // Places shift with the salt too: a guessed name hashed without the farm's salt lands elsewhere.
  const moved = NAMES.filter(name => placeFor(SALT, name, []).place !== placeFor(OTHER_SALT, name, []).place)
  expect(moved.length).toBeGreaterThan(NAMES.length / 2)
})

test('AN4 the live token turns over each day, and is never the session id or its key', () => {
  const key = sessionKeyOf(SALT, 'sess-quillobrand-7f3a')
  const today = liveTokenOf(SALT, '2026-06-10', key)
  expect(isToken(today)).toBe(true)
  expect(liveTokenOf(SALT, '2026-06-10', key)).toBe(today)
  expect(liveTokenOf(SALT, '2026-06-11', key)).not.toBe(today)
  expect(today).not.toBe(key)
  expect(liveTokenOf(OTHER_SALT, '2026-06-10', key)).not.toBe(today)
})

test('AN5 a ticket key is a neighbor\'s number from 1 to 99, the same for the same key; the line says the number', () => {
  const keys = ['BRKT-86', 'ZXQ-4242', 'ZXQ-9191', 'AB-1', 'LONGPROJ1-123456']
  for (const key of keys) {
    const n = neighborOf(SALT, key)
    expect(Number.isInteger(n)).toBe(true)
    expect(n).toBeGreaterThanOrEqual(1)
    expect(n).toBeLessThanOrEqual(99)
    expect(neighborOf(SALT, key)).toBe(n)
    const line = cowLine([n])
    expect(line).toBe(`Neighbor's cow got loose: number ${n}.`)
    expect(line).not.toContain(key)
  }
  expect(cowLine([3, 4])).toBe('2 cows loose.')
})

test('AN6 a tool or MCP server Jeb does not know gets a plain line, never its name', () => {
  for (const server of ['claude_ai_Zorbleflux', 'plugin-authoring', 'zxq-internal', 'x'.repeat(80)]) {
    const kind = mcpKindOf(server)
    expect(kind.line).toBe(RADIO_LINE)
    expect(kind.line.toLowerCase()).not.toContain(server.toLowerCase().replace(/^claude_ai_/, ''))
  }
  // The known ones keep their own fixed lines.
  expect(mcpKindOf('claude_ai_Atlassian').line).toBe("Checkin' the work board")
  expect(MCP_LINES).toContain(RADIO_LINE)
  expect(TOOL_LINE).not.toMatch(/\$\{|undefined/)
})

test('AN7 a journal line made over for a place keeps only Jeb\'s own words', () => {
  expect(lineFor('Oct 22 · api camp · 3 loads out, rain twice, 1 sour batch', '2026-10-22', 'Laurel Fork')).toBe(
    'Oct 22 · Laurel Fork camp · 3 loads out, rain twice, 1 sour batch',
  )
  expect(lineFor('Oct 20 · .claude · built the smokehouse', '2026-10-20', 'Sugar Run')).toBe(
    'Oct 20 · Sugar Run camp · built the smokehouse',
  )
  expect(lineFor('Oct 19 · api camp · quiet day, mended a fence', '2026-10-19', 'Elk Lick')).toBe(
    'Oct 19 · Elk Lick camp · quiet day, mended a fence',
  )
  // A camp whose name holds the separator, words that are not Jeb's, a date that is not one.
  const odd = lineFor('fizzlewick · glimmer · haust camp · deployed zxq, 2 hands hired, made the fizzlewick', '2026-06-09', 'Pine Knob')
  expect(odd).toBe('Jun 9 · Pine Knob camp · 2 hands hired')
  expect(lineFor('whatever glimmerhaust said', '2026-06-09', 'Pine Knob')).toBe('Jun 9 · Pine Knob camp · quiet day, mended a fence')
  expect(lineFor('', '2026-06-09', 'Pine Knob')).toBe('Jun 9 · Pine Knob camp · quiet day, mended a fence')
})

// ---- the farm's migration ----

// A farm as a Jeb before the anonymizer left it: real camp names and session ids.
const legacyFarm = () => ({
  ...freshFarm(),
  version: 9,
  anonSalt: undefined,
  anonPlaces: undefined,
  quilt: [
    { c: 'B', d: '2026-06-08', camp: 'glimmerhaust-api' },
    { c: 'G', d: '2026-06-09', camp: 'fizzlewick' },
    { c: 'N', d: '2026-06-09', camp: 'glimmerhaust-api' },
  ],
  journal: [
    { d: '2026-06-08', camp: 'glimmerhaust-api', line: 'Jun 8 · glimmerhaust-api camp · 3 loads out' },
    { d: '2026-06-09', camp: 'fizzlewick', line: 'Jun 9 · fizzlewick camp · rain twice, fizzlewick notes' },
  ],
  busiest: { d: '2026-06-08', camp: 'glimmerhaust-api', score: 17 },
  stitched: ['sess-quillobrand-7f3a', 'sess-other-zxq'],
  sessionsWorked: 3,
})

const RAW = ['glimmerhaust', 'fizzlewick', 'quillobrand', 'zxq']

test('AN8 a farm from before v10 is made over one way: places, rebuilt lines, hashed ids, a salt of its own', () => {
  const farm = loadFarm(legacyFarm(), lcg(3)) as Farm
  expect(farm.version).toBe(10)
  expect(farm.anonSalt).toMatch(/^[0-9a-f]{16}$/)
  expect(farm.anonPlaces.length).toBe(2)
  const text = JSON.stringify(farm).toLowerCase()
  for (const raw of RAW) {
    expect(text.includes(raw), raw).toBe(false)
  }
  // The same camp is the same place everywhere, two camps two places.
  const [a, b, c] = farm.quilt.map(square => square.camp)
  expect(isPlace(a)).toBe(true)
  expect(a).toBe(c)
  expect(b).not.toBe(a)
  expect(farm.journal.map(entry => entry.camp)).toEqual([a, b])
  expect(farm.journal.map(entry => entry.line)).toEqual([`Jun 8 · ${a} camp · 3 loads out`, `Jun 9 · ${b} camp · rain twice`])
  expect(farm.busiest).toEqual({ d: '2026-06-08', camp: a, score: 17 })
  expect(farm.stitched).toEqual([sessionKeyOf(farm.anonSalt, 'sess-quillobrand-7f3a'), sessionKeyOf(farm.anonSalt, 'sess-other-zxq')])
  // The places are the ones the anonymizer gives those names under the farm's salt.
  expect(placeSeen(farm.anonSalt, 'glimmerhaust-api', farm.anonPlaces)).toBe(a)
  expect(placeSeen(farm.anonSalt, 'fizzlewick', farm.anonPlaces)).toBe(b)
  // Read back again it stands as it is: a v10 farm is never made over twice.
  expect(loadFarm(copy(farm), lcg(99))).toEqual(farm)
  // The same dice, the same farm.
  expect(loadFarm(legacyFarm(), lcg(3))).toEqual(farm)
})

test('AN8 a farm with nothing of the work in it keeps no salt until a save makes one; a stored salt is kept', () => {
  const bare = loadFarm({ ...freshFarm(), version: 9 }, lcg(1)) as Farm
  expect(bare.anonSalt).toBe('')
  expect(bare.anonPlaces).toEqual([])
  const kept = loadFarm({ ...freshFarm(), anonSalt: SALT, anonPlaces: ['abc123', 'nothex', 'abc123', 7] }) as Farm
  expect(kept.anonSalt).toBe(SALT)
  expect(kept.anonPlaces).toEqual(['abc123'])
  expect((loadFarm({ ...freshFarm(), anonSalt: 'not-a-salt' }) as Farm).anonSalt).toBe('')
  // The migration on its own: a farm already made over is left as it is by its salt.
  const once = anonymizeFarm({ ...freshFarm(), quilt: [{ c: 'B', d: '2026-06-08', camp: 'api' }] }, lcg(5))
  expect(anonymizeFarm({ ...once, quilt: [...once.quilt] }, lcg(6)).anonSalt).toBe(once.anonSalt)
})

// ---- the live record (pure) ----

const quietAnim = (over: Partial<Anim> = {}): Anim => ({
  frame: 0,
  idleAct: 'banjo',
  pose: 'none',
  truck: null,
  visit: null,
  dogRun: 0,
  isNight: false,
  isDim: false,
  isTalking: false,
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

const input = (anim: Anim, over: object = {}) => ({
  anim,
  mood: 'idle' as const,
  line: 'Howdy.',
  saidAt: START,
  isBusy: false,
  isStill: false,
  talk: 'ambient' as const,
  cows: [] as number[],
  ...over,
})

test('AN9 a quiet record leaves every default out; a busy one carries only the allowed fields, anonymized', () => {
  expect(liveBody(input(quietAnim()))).toEqual({})
  expect(liveRecord({}, START, 7)).toEqual({ v: 1, at: START, frame: 7 })
  const busy = liveBody(
    input(
      quietAnim({
        pose: 'still',
        isTalking: true,
        isDim: true,
        idleAct: 'nap',
        dogRun: 8,
        truck: { t: 3, load: 'jar', sputter: 0, dog: true },
        visit: { kind: 'store', x: 10, facing: 'in', phase: 'arrive' },
        event: { id: 'storm', t: 4, dur: 80, v: 12 },
        wag: true,
        sip: true,
        isGated: true,
        stitch: true,
        weather: { kind: 'rain', plot: 'corn' },
        building: '🌱',
        hands: [{ plot: 'corn', id: 'agent-glimmerhaust-1' }],
        more: { corn: 2, apples: 0 },
        mates: 1,
        cows: ['#12', '#40', '#7'],
        live: 'G',
        rainbow: true,
        wet: true,
        star: 4,
        prop: '📻',
        lanterns: 3,
        isNight: true,
      }),
      { mood: 'working', line: 'Rain on the corn.', isBusy: true, isStill: true, talk: 'chatty', cows: [12, 40, 7, 55] },
    ),
  )
  expect(busy).toEqual({
    pose: 'still',
    mood: 'working',
    line: 'Rain on the corn.',
    saidAt: START,
    dim: true,
    act: 'nap',
    busy: true,
    dogRun: 8,
    still: true,
    truck: { t: 3, load: 'jar', sputter: 0, dog: true },
    visit: { kind: 'store', x: 10, facing: 'in', phase: 'arrive' },
    event: { id: 'storm', t: 4, dur: 80, v: 12 },
    fx: ['wag', 'sip'],
    gated: true,
    stitch: true,
    weather: { kind: 'rain', plot: 'corn' },
    building: 'hot',
    hands: [{ plot: 'corn', look: expect.any(Number) }],
    more: { corn: 2 },
    mates: 1,
    cows: [12, 40, 7],
    moreCows: 1,
    live: 'G',
    rainbow: true,
    wet: true,
    star: 4,
    talk: 'chatty',
  })
  expect(busy.hands?.[0]?.look).toBeGreaterThanOrEqual(0)
  expect(busy.hands?.[0]?.look).toBeLessThan(6)
  // Only allowed keys, and nothing of the agent's id.
  const record = liveRecord(busy, START, 3)
  for (const key of Object.keys(record)) {
    expect(LIVE_FIELDS as readonly string[], key).toContain(key)
  }
  expect(JSON.stringify(record)).not.toContain('glimmerhaust')
  // The line only while the bubble is up.
  expect(liveBody(input(quietAnim({ isTalking: false }), { line: 'Rain on the corn.' }))).toEqual({})
  expect(liveBody(input(quietAnim({ isTalking: true }), { line: 'x'.repeat(300) })).line?.length).toBe(120)
})

test('AN10 pruning: a gone record goes, one a heartbeat names stays however old, never this session\'s, and at most eight in all', () => {
  const now = START
  const old = now - LIVE_TTL_MS - 1
  const records = [
    { token: 'self00000000', at: old },
    { token: 'stale0000000', at: old },
    { token: 'broken000000', at: undefined },
    { token: 'future000000', at: now + 2 * LIVE_TTL_MS },
    { token: 'linked000000', at: old },
    ...Array.from({ length: 10 }, (_, i) => ({ token: `fresh${String(i).padStart(7, '0')}`, at: now - i * MINUTE })),
  ]
  const gone = livePrune(records, new Set(['linked000000']), 'self00000000', now)
  expect(gone).not.toContain('self00000000')
  expect(gone).not.toContain('linked000000')
  expect(gone).toContain('stale0000000')
  expect(gone).toContain('broken000000')
  expect(gone).toContain('future000000')
  // Seven others stay with this session's own: the named one, then the six freshest.
  const left = records.map(r => r.token).filter(token => !gone.includes(token))
  expect(left.length).toBe(MAX_LIVE)
  expect(left).toContain('linked000000')
  expect(left).toEqual(['self00000000', 'linked000000', ...Array.from({ length: 6 }, (_, i) => `fresh${String(i).padStart(7, '0')}`)])
  expect(livePrune([], new Set(), 'self00000000', now)).toEqual([])
})

// ---- the live record in a session ----

const world = {
  db: new Map<string, unknown>(),
  sessionId: 'sess-glimmerhaust-1',
  // Every write of a live record, with the time.
  liveSets: [] as { at: number; key: string; value: any }[],
  deletes: [] as string[],
  sets: 0,
}

const rig = (on: any, entries: Record<string, unknown> = {}, now = START): MockClock => {
  world.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  world.liveSets = []
  world.deletes = []
  world.sets = 0
  world.sessionId = 'sess-glimmerhaust-1'
  const clock = mock.clock(on, { now })
  mock.env(on, { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_CREATIVITY: 'off', JEB_NEWS: 'null' })
  on('fs.read', (_: any, e: any) => {
    throw new Error(`ENOENT ${String(e.path)}`)
  })
  on('store.get', (_: any, e: any) => ({ value: copy(world.db.get(e.key)) }))
  on('store.set', (_: any, e: any) => {
    world.sets += 1
    if (String(e.key).startsWith('live:')) {
      world.liveSets.push({ at: clock.now(), key: e.key, value: copy(e.value) })
    }
    world.db.set(e.key, copy(e.value))

    return { value: undefined }
  })
  on('store.delete', (_: any, e: any) => {
    world.deletes.push(e.key)
    world.db.delete(e.key)

    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...world.db.keys()] }))
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
  on('session.id', () => ({ value: world.sessionId }))
  on('session.root', () => ({ value: '/home/dev/glimmerhaust' }))
  on('session.repo', () => ({ value: { root: '/home/dev/glimmerhaust', remote: null, internal: false, name: 'glimmerhaust' } }))
  on('agent.list', () => ({ value: [] }))

  return clock
}

const start = ($: any) => $.session.start({ cwd: '/home/dev/glimmerhaust', surface: 'terminal', isInteractive: true })

const liveKeys = () => [...world.db.keys()].filter(key => key.startsWith('live:'))

const elapse = async (clock: MockClock, ms: number) => {
  for (let left = ms; left > 0; left -= 20 * MINUTE) {
    await clock.advance(Math.min(left, 20 * MINUTE))
  }
}

test('LV1 a session keeps one live record under a token of its own: only the allowed fields, no work in it', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on, { farm: { ...freshFarm(), anonSalt: SALT } })
  await start($)
  await clock.advance(1_000)
  const keys = liveKeys()
  expect(keys.length).toBe(1)
  const token = (keys[0] as string).slice(5)
  expect(isToken(token)).toBe(true)
  expect(token).toBe(liveTokenOf(SALT, '2026-06-10', sessionKeyOf(SALT, 'sess-glimmerhaust-1')))
  await $.prompt.submit({ text: 'triage glimmerhaust please', command: { name: 'triage', args: 'BRKT-86 glimmerhaust' } })
  await $.turn.start({ text: 'go', turnId: 't1' })
  await $.tool.call({ tool: 'mcp__claude_ai_Zorbleflux__getJiraIssue', issueIdOrKey: 'ZXQ-9191' })
  await $.tool.call({ tool: 'GlimmerTool', input: 'x' })
  await clock.advance(1_000)
  const record = world.db.get(keys[0] as string) as Record<string, unknown>
  for (const key of Object.keys(record)) {
    expect(LIVE_FIELDS as readonly string[], key).toContain(key)
  }
  expect(record.v).toBe(1)
  expect(record.busy).toBe(true)
  expect(record.cows).toEqual([neighborOf(SALT, 'BRKT-86'), neighborOf(SALT, 'ZXQ-9191')])
  for (const { value } of world.liveSets) {
    const text = JSON.stringify(value).toLowerCase()
    for (const raw of ['glimmerhaust', 'brkt', 'zxq', 'zorbleflux', 'glimmertool', 'sess-']) {
      expect(text.includes(raw), `${raw} in ${text}`).toBe(false)
    }
  }
  // The camp in the heartbeat is a place too.
  const sessions = world.db.get('sessions') as Record<string, { name: string }>
  expect(Object.keys(sessions)).toEqual([sessionKeyOf(SALT, 'sess-glimmerhaust-1')])
  expect(isPlace(Object.values(sessions)[0]?.name)).toBe(true)
})

test('LV2 a busy stretch writes the record at most once a tick (2 a second, under 4), and only when it changed', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await clock.advance(1_000)
  await $.prompt.submit({ text: 'work on it' })
  await $.turn.start({ text: 'work on it', turnId: 't1' })
  const from = world.liveSets.length
  // Forty tool calls a second for five seconds, the tool (and Jeb's pose) changing every call.
  const tools = ['Read', 'Edit', 'Bash', 'WebFetch', 'Write', 'Grep', 'mcp__claude_ai_Slack__send']
  for (let i = 0; i < 200; i += 1) {
    await $.tool.call({ tool: tools[i % tools.length], command: 'ls', file_path: '/a', url: 'https://x.test' })
    await clock.advance(25)
  }
  const writes = world.liveSets.slice(from)
  const perSecond = new Map<number, number>()
  for (const write of writes) {
    const second = Math.floor((write.at - START) / 1_000)
    perSecond.set(second, (perSecond.get(second) ?? 0) + 1)
  }
  console.log(`live writes per second while busy: ${[...perSecond.values()].join(', ')} (${writes.length} in 5 s)`)
  // Something changed on nearly every tick, and each tick wrote once at most.
  expect(writes.length).toBeGreaterThanOrEqual(5)
  expect(writes.length).toBeLessThanOrEqual(11)
  for (const n of perSecond.values()) {
    expect(n).toBeLessThanOrEqual(2)
  }
  // Every write differs from the one before it in something but the time and the frame.
  const strip = (value: any) => JSON.stringify({ ...value, at: 0, frame: 0 })
  for (let i = 1; i < writes.length; i += 1) {
    expect(strip(writes[i]?.value)).not.toBe(strip(writes[i - 1]?.value))
  }
})

test('LV3 a quiet tick writes nothing: ten still minutes leave the record as it was', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await elapse(clock, 3 * MINUTE)
  const record = world.db.get(liveKeys()[0] as string) as Record<string, unknown>
  expect(record.still).toBe(true)
  const from = world.liveSets.length
  const sets = world.sets
  await elapse(clock, 10 * MINUTE)
  console.log(`live writes in ten still minutes: ${world.liveSets.length - from}; store writes in all: ${world.sets - sets}`)
  expect(world.liveSets.length - from).toBe(0)
  // The heartbeat is all that is written: once a minute.
  expect(world.sets - sets).toBeLessThanOrEqual(10)
  // A poke wakes it: one write, on the next tick.
  await $.prompt.submit({ text: '', isMeta: true })
  await clock.advance(500)
  expect(world.liveSets.length - from).toBe(1)
  expect((world.liveSets[world.liveSets.length - 1]?.value as any).still).toBeUndefined()
})

test('LV4 the heartbeat prunes the others\' gone records and keeps eight at most; one a heartbeat names stays', { timeoutMs: 60_000 }, async ($, on) => {
  const old = START - LIVE_TTL_MS - MINUTE
  const otherKey = sessionKeyOf(SALT, 'sess-other')
  const named = liveTokenOf(SALT, '2026-06-10', otherKey)
  const entries: Record<string, unknown> = {
    farm: { ...freshFarm(), anonSalt: SALT },
    sessions: { [otherKey]: { name: 'Laurel Fork', lastSeen: START - 30_000 } },
    [`live:${named}`]: { v: 1, at: old, frame: 0, isStill: true },
    'live:stale0000000': { v: 1, at: old, frame: 0 },
    'live:broken': { nope: true },
  }
  for (let i = 0; i < 9; i += 1) {
    entries[`live:fresh${String(i).padStart(7, '0')}`] = { v: 1, at: START - i * 1_000, frame: 0 }
  }
  const clock = rig(on, entries)
  await start($)
  await clock.settle()
  const keys = liveKeys()
  expect(keys).toContain(`live:${named}`)
  expect(keys).not.toContain('live:stale0000000')
  expect(keys).not.toContain('live:broken')
  // Seven of the others are left, the named one and the six freshest.
  expect(keys.length).toBe(MAX_LIVE - 1)
  expect(keys).toContain('live:fresh0000000')
  expect(keys).not.toContain('live:fresh0000008')
  // With this session's own record, eight in all.
  await clock.advance(1_000)
  expect(liveKeys()).toContain(`live:${liveTokenOf(SALT, '2026-06-10', sessionKeyOf(SALT, 'sess-glimmerhaust-1'))}`)
  expect(liveKeys().length).toBe(MAX_LIVE)
})

test('LV5 the record goes when the session ends; after a /clear the new conversation writes its own', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on, { farm: { ...freshFarm(), anonSalt: SALT } })
  await start($)
  await clock.advance(1_000)
  const first = `live:${liveTokenOf(SALT, '2026-06-10', sessionKeyOf(SALT, world.sessionId))}`
  expect(liveKeys()).toEqual([first])
  world.sessionId = 'sess-glimmerhaust-2'
  const id = world.sessionId
  await $.session.end({ reason: 'clear', sessionId: 'sess-glimmerhaust-1', resume: { id: 'sess-glimmerhaust-1' } })
  await clock.settle()
  expect(world.deletes).toContain(first)
  expect(liveKeys()).toEqual([])
  await clock.advance(1_000)
  const second = `live:${liveTokenOf(SALT, '2026-06-10', sessionKeyOf(SALT, id))}`
  expect(liveKeys()).toEqual([second])
  // An exit takes it out for good: no tick writes it back.
  await $.session.end({ reason: 'prompt_input_exit', sessionId: id, resume: { id } })
  await clock.settle()
  await clock.advance(5_000)
  expect(liveKeys()).toEqual([])
})

test('LV6 at midnight the token turns over: the day\'s record goes and the next day\'s takes its place', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on, { farm: { ...freshFarm(), anonSalt: SALT } }, at(10, 23, 59))
  await start($)
  await clock.advance(1_000)
  const key = sessionKeyOf(SALT, 'sess-glimmerhaust-1')
  expect(liveKeys()).toEqual([`live:${liveTokenOf(SALT, '2026-06-10', key)}`])
  // Keep the scene awake across midnight.
  await $.prompt.submit({ text: 'work on it' })
  await $.turn.start({ text: 'work on it', turnId: 't1' })
  await clock.advance(HOUR / 60)
  expect(liveKeys()).toEqual([`live:${liveTokenOf(SALT, '2026-06-11', key)}`])
})
