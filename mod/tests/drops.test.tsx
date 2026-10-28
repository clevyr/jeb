import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import type { Anim, DropArt, Surprise } from '../types'
import {
  activeArc,
  almanacLines,
  applyDelivery,
  ARC_STALL_DAYS,
  ART_STORE_MAX,
  CATCHUP_GAP_MS,
  claimSlot,
  CLAIM_TTL_MS,
  creativeOf,
  dropLooks,
  dropsOf,
  dueSlot,
  festivalOf,
  freshCreative,
  freshDrops,
  isDropDay,
  isLive,
  LOG_MAX,
  logOf,
  MAX_DRAWN,
  MODEL_DAILY_CAP,
  newsOf,
  newsSeenOf,
  nextArcStep,
  recentSummaries,
  reserveModel,
  sayingPool,
  STRUCT_MAX,
  SURPRISES_MAX,
  surprisesOf,
  viewOfDrops,
} from '../hooks/drops'
import type { Delivery } from '../hooks/drops'
import { freshFarm, loadFarm } from '../hooks/homestead'
import { CHARACTERS, offlineDrop, seededRng } from '../hooks/offline'
import { PIXEL_COLOUR, PIXEL_SPRITES } from '../hooks/pixel-art'
import { viewOf } from '../hooks/shared'
import {
  artAllowed,
  ART_LEGEND,
  artFrames,
  DROP_SPRITES,
  FESTIVAL_TINTS,
  isClean,
  STORY_SCALE,
  levelOf,
  parseReply,
  promptOf,
  systemPrompt,
  tokenCap,
  validateArt,
  validateDrop,
  ZONES,
} from '../hooks/surprise'
import * as signals from '../hooks/signals'
import { promptInputOf } from '../hooks/signals'

// The creative drops: the schedule, the claim, the budget, what the host is never
// asked, what the model sees, the schema and its level, the art, the offline generator, delivery,
// both bands, and what it all costs the host. The model, the MCP tools, the tool
// and command lists and the clock are all mocked: nothing real is ever called.

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const at = (d: number, h: number, m = 0, s = 0) => new Date(2026, 5, d, h, m, s).getTime()
const ctx = (level: number, over: object = {}) => ({ level, knownArt: [] as string[], isArcOpen: true, ...over })

const saying = (over: object = {}) => ({ kind: 'saying', name: 'porch-talk', lines: ['Nice mornin out here.'], ...over })

// ---- the schedule ----

test('DR1 drops come Monday to Friday only: a weekend slot is never due, missed or not', () => {
  // June 2026: the 12th is a Friday, the 13th and 14th the weekend, the 15th a Monday.
  for (const d of [13, 14]) {
    expect(isDropDay(new Date(at(d, 12)))).toBe(false)
    expect(dueSlot({ drops: freshDrops(), startedAt: at(d, 8), lastAt: 0, nowMs: at(d, 9) })).toBeUndefined()
    expect(dueSlot({ drops: freshDrops(), startedAt: at(d, 16), lastAt: 0, nowMs: at(d, 23, 59) })).toBeUndefined()
  }
  for (const d of [12, 15]) {
    expect(isDropDay(new Date(at(d, 12)))).toBe(true)
    expect(dueSlot({ drops: freshDrops(), startedAt: at(d, 8), lastAt: 0, nowMs: at(d, 9) })).toBe(9)
  }
})

test('DR1 slots are 9, 12 and 15: due once their time has passed and not done, earliest first', () => {
  const base = { drops: freshDrops(), startedAt: at(10, 8), lastAt: 0 }
  expect(dueSlot({ ...base, nowMs: at(10, 8, 59, 59) })).toBeUndefined()
  expect(dueSlot({ ...base, nowMs: at(10, 9) })).toBe(9)
  expect(dueSlot({ ...base, nowMs: at(10, 11, 59), drops: { day: '2026-06-10', done: [9], claims: [] } })).toBeUndefined()
  expect(dueSlot({ ...base, nowMs: at(10, 12), drops: { day: '2026-06-10', done: [9], claims: [] } })).toBe(12)
  expect(dueSlot({ ...base, nowMs: at(10, 15, 1), drops: { day: '2026-06-10', done: [9, 12], claims: [] } })).toBe(15)
  expect(dueSlot({ ...base, nowMs: at(10, 23), drops: { day: '2026-06-10', done: [9, 12, 15], claims: [] } })).toBeUndefined()
  // Yesterday's done slots say nothing about today.
  expect(dueSlot({ ...base, nowMs: at(10, 9, 1), drops: { day: '2026-06-09', done: [9, 12, 15], claims: [] } })).toBe(9)
})

test('DR1 a session that opens late runs the missed slots one every ten minutes; a slot reached while open runs at once', () => {
  const drops = { day: '2026-06-10', done: [] as number[], claims: [] as { slot: number; at: number }[] }
  const startedAt = at(10, 14)
  expect(dueSlot({ drops, nowMs: at(10, 14, 0, 30), startedAt, lastAt: 0 })).toBe(9)
  const first = at(10, 14, 0, 30)
  expect(dueSlot({ drops: { ...drops, done: [9] }, nowMs: first + 9 * MINUTE, startedAt, lastAt: first })).toBeUndefined()
  expect(dueSlot({ drops: { ...drops, done: [9] }, nowMs: first + CATCHUP_GAP_MS, startedAt, lastAt: first })).toBe(12)
  // 15:00 comes while the session is open: no waiting for the gap.
  expect(dueSlot({ drops: { ...drops, done: [9, 12] }, nowMs: at(10, 15), startedAt, lastAt: at(10, 14, 50) })).toBe(15)
})

test('DR1 a fresh claim holds a slot, a stale one lets it go', () => {
  const nowMs = at(10, 9, 5)
  const claims = [{ slot: 9, at: nowMs - 30_000 }]
  const input = { nowMs, startedAt: at(10, 8), lastAt: 0 }
  expect(dueSlot({ ...input, drops: { day: '2026-06-10', done: [], claims } })).toBeUndefined()
  expect(dueSlot({ ...input, drops: { day: '2026-06-10', done: [], claims: [{ slot: 9, at: nowMs - CLAIM_TTL_MS - 1 }] } })).toBe(9)
})

test('DR1 one generation per slot machine-wide: the claim is made on the stored farm, before anything is generated', () => {
  const stored = freshFarm()
  const nowMs = at(10, 9, 0, 10)
  const a = claimSlot(stored, 9, nowMs)
  expect(a.outcome).toBe('claimed')
  // The second session reads what the first wrote: busy, and then done.
  const b = claimSlot(a.farm, 9, nowMs + 1000)
  expect(b.outcome).toBe('busy')
  const delivered = applyDelivery(a.farm, delivery(), nowMs + 2000).farm
  expect(claimSlot(delivered, 9, nowMs + 3000).outcome).toBe('done')
  expect(delivered.drops.claims).toEqual([])
  // A dead claimant's claim is taken over once it is two minutes old.
  const stale = claimSlot(a.farm, 9, nowMs + CLAIM_TTL_MS + 1)
  expect(stale.outcome).toBe('takeover')
  // A new day starts over.
  expect(claimSlot(delivered, 9, nowMs + DAY).outcome).toBe('claimed')
  // A delivery for a slot already done delivers nothing, so nothing is played twice.
  expect(applyDelivery(delivered, delivery(), nowMs + 4000).surprise).toBeUndefined()
})

function delivery(over: Partial<Delivery> = {}): Delivery {
  return {
    slot: 9,
    made: 'local',
    kind: 'saying',
    name: 'porch-talk',
    lines: ['Nice mornin out here.'],
    summary: 'Nice mornin',
    sprites: [],
    window: null,
    lasts: 'today',
    festival: '',
    keep: false,
    art: [],
    arc: null,
    ...over,
  }
}

// ---- the budget ----

test('DR2 the model budget: six calls a day, whatever asks, reset at midnight', () => {
  let farm = freshFarm()
  const nowMs = at(10, 9)
  for (let i = 1; i <= MODEL_DAILY_CAP; i += 1) {
    const taken = reserveModel(farm, nowMs)
    expect(taken.ok).toBe(true)
    farm = taken.farm
    expect(farm.modelCalls.n).toBe(i)
  }
  expect(reserveModel(farm, nowMs + HOUR).ok).toBe(false)
  expect(reserveModel(farm, nowMs + HOUR).farm.modelCalls.n).toBe(MODEL_DAILY_CAP)
  expect(reserveModel(farm, nowMs + DAY).ok).toBe(true)
  expect(reserveModel(farm, nowMs + DAY).farm.modelCalls).toEqual({ day: '2026-06-11', n: 1 })
})

// ---- no host reads ----

test('DR3 signals.ts offers the model call and the prompt input, and no allowlist, no reads of the host', () => {
  expect(Object.keys(signals).sort()).toEqual(['MODEL_TIMEOUT_MS', 'askHaiku', 'askHaikuArea', 'promptInputOf'])
})

test('DR3 no write-like tool can be called: with every kind of tool listed, a day of drops makes no MCP call at all', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  world.tools = [
    ...TOOLS,
    ...['createJiraIssue', 'editJiraIssue', 'update_issue', 'delete_issue', 'send_message', 'post_comment', 'write_file', 'set_assignee', 'searchAndUpdateIssues'].map(tool => ({
      name: `mcp__claude_ai_Atlassian__${tool}`,
      description: tool,
      mcp: true,
    })),
  ]
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(calls.model.length).toBe(3)
  expect(calls.mcp).toEqual([])
  expect(calls.toolList).toBe(0)
  expect(calls.commandList).toBe(0)
})

test('DR3 the prompt input holds the farm and the log only: no servers, commands or counts of the host', () => {
  const made = input() as Record<string, unknown>
  expect(Object.keys(made).sort()).toEqual(['arc', 'artIds', 'farm', 'isArcOpen', 'level', 'now', 'recent', 'season', 'slot', 'total'])
  expect(promptOf(made as unknown as Parameters<typeof promptOf>[0])).not.toMatch(/MCP|servers|Counts from|Skills, plugins/)
})

// ---- the schema ----

const GOOD = {
  kind: 'happening',
  name: 'loose-hen',
  lines: ["A hen's loose on the road.", 'Blue is on the case.'],
  summary: 'A loose hen on the road',
  sprites: [{ sprite: 'hen', zone: 'road', frames: 2 }],
}

test('DR4 a good reply is accepted, a reply with talk around it is read, and bad JSON is nothing', () => {
  const checked = validateDrop(GOOD, ctx(1))
  expect(checked.ok).toBe(true)
  expect(checked.ok && checked.drop.sprites).toEqual([{ sprite: 'hen', zone: 'road', frames: 2 }])
  expect(parseReply(`Sure!\n\`\`\`json\n${JSON.stringify(GOOD)}\n\`\`\``)).toEqual(GOOD)
  for (const bad of ['', 'no json here', '{"kind":', '[1,2]', '{']) {
    const value = parseReply(bad)
    expect(validateDrop(value, ctx(1)).ok, bad).toBe(false)
  }
})

test('DR4 each break of the schema rejects the reply', () => {
  const cases: [string, object][] = [
    ['unknown kind', { ...GOOD, kind: 'parade' }],
    ['no name', { ...GOOD, name: undefined }],
    ['name with capitals', { ...GOOD, name: 'Loose-Hen' }],
    ['name too long', { ...GOOD, name: 'a'.repeat(25) }],
    ['no lines', { ...GOOD, lines: [] }],
    ['four lines', { ...GOOD, lines: ['a', 'b', 'c', 'd'] }],
    ['line too long', { ...GOOD, lines: ['x'.repeat(65)] }],
    ['non-ASCII', { ...GOOD, lines: ['Café time'] }],
    ['emoji', { ...GOOD, lines: ['Hello \u{1f414}'] }],
    ['control character', { ...GOOD, lines: ['tab\there'] }],
    ['four sprites', { ...GOOD, sprites: Array(4).fill({ sprite: 'hen', zone: 'road' }) }],
    ['bad zone', { ...GOOD, sprites: [{ sprite: 'hen', zone: 'moon' }] }],
    ['bad frames', { ...GOOD, sprites: [{ sprite: 'hen', zone: 'road', frames: 3 }] }],
    ['bad window', { ...GOOD, kind: 'decor', window: { from: 20, to: 5 } }],
    ['window out of range', { ...GOOD, kind: 'decor', window: { from: 0, to: 25 } }],
    ['bad lasts', { ...GOOD, lasts: 'forever' }],
    ['keep not a boolean', { ...GOOD, keep: 'yes' }],
  ]
  for (const [name, body] of cases) {
    expect(validateDrop(body, ctx(6)).ok, name).toBe(false)
  }
  expect(validateDrop(null, ctx(1)).ok).toBe(false)
  expect(validateDrop('a string', ctx(1)).ok).toBe(false)
})

test('DR4 banned words reject the reply, wherever they are, and plain words are not caught', () => {
  const banned = [
    'What the hell was that', 'damn hen', 'crap', 'holy shit', 'Vote for Pedro', 'the election is near', 'Trump rally',
    'Praise the Lord', 'Jesus wept', 'the devil you say', 'pray for rain', 'a joint of marijuana', 'meth lab', 'he got shot',
    'a gun in the barn', 'blood everywhere', 'dead as a doornail', 'a drunk hen', 'too much beer', 'a glass of wine', 'vodka',
    'hillbilly', 'redneck', 'naked hens', 'sexy', 'murder most foul', 'the war is on', 'a fight broke out', 'He will kill it',
    'fucking hens', 'Shit', 'GOD', 'Heaven help us',
  ]
  for (const text of banned) {
    expect(isClean(text), text).toBe(false)
    expect(validateDrop({ ...GOOD, lines: [text.slice(0, 64)] }, ctx(1)).ok, text).toBe(false)
  }
  // In the name, the summary and the sprite's art id too.
  expect(validateDrop({ ...GOOD, name: 'drunk-hen' }, ctx(1)).ok).toBe(false)
  expect(validateDrop({ ...GOOD, summary: 'a bloody mess' }, ctx(1)).ok).toBe(false)
  for (const text of ['class act', 'assist the hen', 'Shell game', 'hello there', 'diet of corn', 'Scunthorpe', 'a hickory tree', 'warden', 'the lordly hen', 'pottery', 'passionate', 'Hellebore blooms', 'a cocktail of apples']) {
    expect(isClean(text), text).toBe(true)
  }
  expect(isClean('Moonshine and apple cinnamon')).toBe(true)
})

test('DR4 an unknown sprite is dropped, and with none left a happening is a saying', () => {
  const one = validateDrop({ ...GOOD, sprites: [{ sprite: 'hen', zone: 'road' }, { sprite: 'dragon', zone: 'sky' }, { sprite: 'jeb-idle', zone: 'yard' }, { sprite: 'house', zone: 'yard' }, { sprite: 'still', zone: 'yard' }] }, ctx(1))
  expect(one.ok).toBe(false) // five entries is too many
  const two = validateDrop({ ...GOOD, sprites: [{ sprite: 'hen', zone: 'road' }, { sprite: 'dragon', zone: 'sky' }, { sprite: 'jeb-idle', zone: 'yard' }] }, ctx(1))
  expect(two.ok && two.drop.sprites.map(s => s.sprite)).toEqual(['hen'])
  const none = validateDrop({ ...GOOD, sprites: [{ sprite: 'dragon', zone: 'sky' }] }, ctx(1))
  expect(none.ok && none.drop.kind).toBe('saying')
  expect(none.ok && none.drop.sprites).toEqual([])
  // The tractor only ever stands on the road.
  const tractor = validateDrop({ ...GOOD, sprites: [{ sprite: 'tractor', zone: 'sky' }, { sprite: 'tractor', zone: 'road' }] }, ctx(1))
  expect(tractor.ok && tractor.drop.sprites.map(s => s.zone)).toEqual(['road'])
  // Never Jeb, the house or the still.
  for (const name of Object.keys(DROP_SPRITES)) {
    expect(/^(jeb|house|still|blue-)/.test(DROP_SPRITES[name]?.pixel ?? ''), name).toBe(false)
    expect(PIXEL_SPRITES[DROP_SPRITES[name]?.pixel ?? ''], name).toBeTruthy()
  }
})

// ---- the level ----

test('DR5 the level is 1 + floor(log2(1 + drops / 6)), at most 6', () => {
  const marks: [number, number][] = [[0, 1], [5, 1], [6, 2], [17, 2], [18, 3], [41, 3], [42, 4], [89, 4], [90, 5], [185, 5], [186, 6], [100_000, 6]]
  for (const [total, level] of marks) {
    expect(levelOf(total), `${total}`).toBe(level)
  }
  expect(levelOf(-3)).toBe(1)
  expect(levelOf(NaN)).toBe(1)
  expect(STORY_SCALE).toContain('Let the scale follow the story')
  expect([1, 2, 3, 4, 5, 6].map(tokenCap)).toEqual([1800, 1800, 1800, 1800, 1800, 1800])
})

const VANE: DropArt = {
  id: 'vane',
  w: 6,
  h: 6,
  frames: 2,
  rows: ['..oo..', '.oooo.', '..oo..', '..oo..', '.oooo.', '..oo..', '..rr..', '.rrrr.', '..oo..', '..oo..', '.oooo.', '..oo..'],
}
const ARC = (extra: object = {}) => ({
  kind: 'arc',
  name: 'vane-job',
  summary: 'Cousin Delbert raises a weathervane',
  art: VANE,
  festival: 'gold',
  steps: [
    { day: 1, kind: 'saying', name: 'v1', lines: ['Delbert is fixin to raise a vane.'] },
    { day: 2, kind: 'happening', name: 'v2', lines: ['Boards come down the road.'], sprites: [{ sprite: 'tractor', zone: 'road', frames: 2 }] },
    { day: 3, kind: 'decor', name: 'v3', lines: ['Vane is up.'], sprites: [{ sprite: 'vane', zone: 'yard', frames: 2 }], lasts: 'week', keep: true, festival: 'rose' },
    { day: 4, kind: 'saying', name: 'v4', lines: ['Fine work.'] },
    { day: 5, kind: 'decor', name: 'v5', lines: ['It points east.'], sprites: [{ sprite: 'vane', zone: 'sky', frames: 1 }], keep: true, window: { from: 6, to: 20 } },
    { day: 6, kind: 'saying', name: 'v6', lines: ['Wind turned.'] },
    { day: 7, kind: 'decor', name: 'v7', lines: ['A fine vane.'], sprites: [{ sprite: 'vane', zone: 'yard', frames: 2 }], keep: true },
  ],
  ...extra,
})

test('DR5 every power is open at every level: decor, art, arcs, keep and the festival', () => {
  const decor = { kind: 'decor', name: 'rail-mug', lines: ['A mug on the rail.'], sprites: [{ sprite: 'mug', zone: 'porch' }], window: { from: 5, to: 9 }, lasts: 'week' }
  // Level 1: decor stays decor, with its window and week.
  const d1 = validateDrop(decor, ctx(1))
  expect(d1.ok && d1.drop.kind).toBe('decor')
  expect(d1.ok && d1.drop.window).toEqual({ from: 5, to: 9 })
  expect(d1.ok && d1.drop.lasts).toBe('week')
  const d2 = validateDrop(decor, ctx(2))
  expect(d2.ok && d2.drop.kind).toBe('decor')
  expect(d2.ok && d2.drop.window).toEqual({ from: 5, to: 9 })

  const withArt = { ...GOOD, art: [VANE, { ...VANE, id: 'vane2' }, { ...VANE, id: 'vane3' }], sprites: [{ sprite: 'vane', zone: 'yard' }, { sprite: 'vane2', zone: 'sky' }, { sprite: 'vane3', zone: 'sky' }] }
  const artIds = (level: number) => {
    const r = validateDrop(withArt, ctx(level))

    return r.ok ? r.drop.art.map(a => a.id) : 'rejected'
  }
  expect([1, 2, 3, 4, 5, 6].map(artIds)).toEqual(Array(6).fill(['vane', 'vane2']))
  expect([1, 2, 3, 4, 5, 6].map(artAllowed)).toEqual([2, 2, 2, 2, 2, 2])
  // A sprite that names a picture past the two allowed goes with it; none left, a saying.
  const past = validateDrop({ ...GOOD, art: [VANE, { ...VANE, id: 'vane2' }, { ...VANE, id: 'vane3' }], sprites: [{ sprite: 'vane3', zone: 'sky' }] }, ctx(2))
  expect(past.ok && past.drop.kind).toBe('saying')

  // Arcs: every level allows all 7 steps.
  const steps = (level: number, extra: object = {}) => {
    const r = validateDrop(ARC(extra), ctx(level))

    return r.ok ? (r.drop.kind === 'arc' ? r.drop.steps.length : `plain ${r.drop.kind}`) : 'rejected'
  }
  expect([1, 2, 3, 4, 5, 6].map(l => steps(l))).toEqual([7, 7, 7, 7, 7, 7])
  // With an arc already under way a new one is only its first step.
  expect(validateDrop(ARC(), ctx(6, { isArcOpen: false })).ok && (validateDrop(ARC(), ctx(6, { isArcOpen: false })) as any).drop.kind).toBe('saying')

  // Keep: only the final step, only with a sprite; the festival at any level.
  const l5 = validateDrop(ARC(), ctx(5)) as any
  expect(l5.drop.steps.map((s: any) => s.keep)).toEqual([false, false, false, false, false, false, true])
  const l1 = validateDrop(ARC(), ctx(1)) as any
  expect(l1.drop.steps.map((s: any) => s.keep)).toEqual([false, false, false, false, false, false, true])
  expect(l5.drop.steps.map((s: any) => s.festival)).toEqual(['', '', 'rose', '', '', '', ''])
  const l6 = validateDrop(ARC(), ctx(6)) as any
  expect(l6.drop.steps[2].festival).toBe('rose')
  const fest = (level: number) => (validateDrop({ ...GOOD, festival: 'gold' }, ctx(level)) as any).drop.festival
  expect([1, 5, 6].map(fest)).toEqual(['gold', 'gold', 'gold'])
  expect((validateDrop({ ...GOOD, festival: 'neon' }, ctx(6)) as any).drop.festival).toBe('')
  // An arc breaks if its steps are out of order, few or many.
  expect(validateDrop(ARC({ steps: [(ARC() as any).steps[1], (ARC() as any).steps[0]] }), ctx(6)).ok).toBe(false)
  expect(validateDrop(ARC({ steps: [(ARC() as any).steps[0]] }), ctx(6)).ok).toBe(false)
  expect(validateDrop(ARC({ steps: Array(8).fill((ARC() as any).steps[0]) }), ctx(6)).ok).toBe(false)
  expect(validateDrop(ARC({ steps: [(ARC() as any).steps[0], { ...(ARC() as any).steps[1], lines: ['The hell'] }] }), ctx(6)).ok).toBe(false)
})

test('DR5 a level-1 reply with decor, a picture, a 3-step arc and a festival is accepted with all of them intact', () => {
  const decor = validateDrop({ kind: 'decor', name: 'rail-mug', lines: ['A mug on the rail.'], sprites: [{ sprite: 'mug', zone: 'porch' }], window: { from: 5, to: 9 }, lasts: 'week' }, ctx(1)) as any
  expect(decor.drop.kind).toBe('decor')
  expect(decor.drop.window).toEqual({ from: 5, to: 9 })
  const picture = validateDrop({ ...GOOD, art: VANE, sprites: [{ sprite: 'vane', zone: 'yard', frames: 2 }], festival: 'dusk' }, ctx(1)) as any
  expect(picture.drop.art.map((a: any) => a.id)).toEqual(['vane'])
  expect(picture.drop.festival).toBe('dusk')
  const arc = validateDrop(ARC({ steps: (ARC() as any).steps.slice(0, 3) }), ctx(1)) as any
  expect(arc.drop.kind).toBe('arc')
  expect(arc.drop.steps.map((s: any) => s.kind)).toEqual(['saying', 'happening', 'decor'])
  expect(arc.drop.steps[2].keep).toBe(true)
  expect(arc.drop.steps[2].festival).toBe('rose')
  expect(arc.drop.art.map((a: any) => a.id)).toEqual(['vane'])
})

test('DR5 keep only works on an arc\'s final step: a decor on its own never keeps', () => {
  const decor = { kind: 'decor', name: 'rail-mug', lines: ['A mug on the rail.'], sprites: [{ sprite: 'mug', zone: 'porch' }], keep: true }
  const alone = validateDrop(decor, ctx(5)) as any
  expect(alone.ok && alone.drop.kind).toBe('decor')
  expect(alone.drop.keep).toBe(false)
  const arc = validateDrop(ARC(), ctx(5)) as any
  expect(arc.drop.steps[arc.drop.steps.length - 1].keep).toBe(true)
})

test('DR5 a picture the farm already holds can be named again at any level', () => {
  const r = validateDrop({ ...GOOD, sprites: [{ sprite: 'old-pic', zone: 'yard' }] }, ctx(1, { knownArt: ['old-pic'] }))
  expect(r.ok && r.drop.sprites.map(s => s.sprite)).toEqual(['old-pic'])
})

// ---- the art validator ----

const art = (over: object = {}) => ({ ...VANE, ...over })

test('DR6 the art validator accepts a good picture and rejects each rule broken', () => {
  expect(validateArt(VANE)).toEqual(VANE)
  expect(validateArt({ ...VANE, frames: undefined, rows: VANE.rows.slice(0, 6) })?.frames).toBe(1)
  const bad: [string, object][] = [
    ['id with capitals', art({ id: 'Vane' })],
    ['id too long', art({ id: 'a'.repeat(21) })],
    ['id empty', art({ id: '' })],
    ['id of a built-in sprite', art({ id: 'hen' })],
    ['id with a banned word', art({ id: 'drunk-hen' })],
    ['too wide', art({ w: 25, rows: VANE.rows.map(r => r.padEnd(25, 'o')) })],
    ['too tall', art({ h: 25, frames: 1, rows: Array(25).fill('oooooo') })],
    ['too small', art({ w: 2, h: 2, frames: 1, rows: ['oo', 'oo'] })],
    ['fractional width', art({ w: 6.5 })],
    ['frames 3', art({ frames: 3 })],
    ['width does not match a row', art({ rows: [...VANE.rows.slice(0, 11), '..oo.'] })],
    ['too few rows', art({ rows: VANE.rows.slice(0, 11) })],
    ['too many rows', art({ rows: [...VANE.rows, '......'] })],
    ['a character outside the legend', art({ rows: ['..oz..', ...VANE.rows.slice(1)] })],
    ['a space', art({ rows: ['.. o..', ...VANE.rows.slice(1)] })],
    ['a row that is not a string', art({ rows: [5, ...VANE.rows.slice(1)] })],
    ['under a fifth opaque', art({ frames: 1, rows: ['o.....', '......', '......', '......', '......', '......'] })],
    ['second frame under a fifth', art({ rows: [...VANE.rows.slice(0, 6), '......', '......', '......', '......', '......', '.....o'] })],
    ['no rows', art({ rows: undefined })],
  ]
  for (const [name, body] of bad) {
    expect(validateArt(body), name).toBeUndefined()
  }
  expect(validateArt(null)).toBeUndefined()
  expect(validateArt('picture')).toBeUndefined()
  // Exactly a fifth is enough (8 of 36 is not: 8 < 8 is false at 8, 7 fails).
  const fifth = (n: number) => ({ id: 'fifth', w: 6, h: 6, frames: 1, rows: [...'o'.repeat(n).padEnd(36, '.').match(/.{6}/g)!] })
  expect(validateArt(fifth(8))).toBeTruthy()
  expect(validateArt(fifth(7))).toBeUndefined()
  // Largest picture: 24 x 24 x 2 is within the 2 KB bound; a legend of about two dozen colors, all real.
  const full = { id: 'full', w: 24, h: 24, frames: 2, rows: Array(48).fill('o'.repeat(24)) }
  expect(JSON.stringify(validateArt(full)).length).toBeLessThanOrEqual(2048)
  expect(Object.keys(ART_LEGEND).length).toBe(24)
  for (const name of Object.values(ART_LEGEND)) {
    expect(PIXEL_COLOUR[name], name).toBeTruthy()
  }
  // A clear border is fine (VANE has one).
  expect(VANE.rows[0]?.startsWith('.')).toBe(true)
})

test('DR6 the ink outline is added at runtime around the drawn pixels, never in the picture', () => {
  const frames = artFrames(VANE)
  expect(frames.w).toBe(VANE.w + 2)
  expect(frames.h).toBe(VANE.h + 2)
  expect(frames.frames.length).toBe(2)
  const ink = PIXEL_COLOUR.ink as number
  const first = frames.frames[0] as Uint8Array
  // Corners are clear; the pixel above the top 'oo' is ink; an opaque pixel keeps its own color.
  expect(first[0]).toBe(0)
  expect(first[0 * frames.w + 3]).toBe(ink)
  expect(first[1 * frames.w + 3]).toBe(PIXEL_COLOUR.wood)
  expect(VANE.rows.join('')).not.toContain('k')
})

// ---- the offline generator ----

const offline = (level: number, i: number, over: object = {}) =>
  offlineDrop({
    now: new Date(2026, 5, 1 + (i % 28), [9, 12, 15][i % 3] as number),
    slot: [9, 12, 15][i % 3] as number,
    level,
    total: i,
    labels: ['Sentry', 'Atlassian'],
    counts: { Sentry: 12, Atlassian: 0 },
    recent: [],
    isArcOpen: true,
    knownArt: [],
    ...over,
  })

test('DR7 the offline generator always works, the same for the same slot, and every drop passes the schema', () => {
  for (let level = 1; level <= 6; level += 1) {
    for (let i = 0; i < 300; i += 1) {
      const drop = offline(level, i)
      const raw = JSON.parse(JSON.stringify({ ...drop, steps: drop.steps.map((step, n) => ({ ...step, name: `${drop.name}-${n + 1}` })) }))
      expect(validateDrop(raw, ctx(level)).ok, `level ${level} #${i}`).toBe(true)
      expect(drop.art, 'it draws no pictures').toEqual([])
      expect(offline(level, i)).toEqual(drop)
    }
  }
  expect(seededRng(5)()).toBe(seededRng(5)())
})

test('DR7 the offline range grows with the level: sayings and happenings, decor, arcs of 3, longer arcs that keep, a festival', () => {
  const seen = (level: number, over: object = {}) => {
    const kinds = new Set<string>()
    let longest = 0
    let keeps = 0
    let festivals = 0
    for (let i = 0; i < 600; i += 1) {
      const drop = offline(level, i, over)
      kinds.add(drop.kind)
      if (drop.kind === 'arc') {
        longest = Math.max(longest, drop.steps.length)
        keeps += drop.steps.some(s => s.keep) ? 1 : 0
      }
      festivals += drop.festival !== '' || drop.steps.some(s => s.festival !== '') ? 1 : 0
    }

    return { kinds: [...kinds].sort(), longest, keeps, festivals }
  }
  expect(seen(1).kinds).toEqual(['almanac', 'happening', 'saying'])
  expect(seen(2).kinds).toEqual(['almanac', 'decor', 'happening', 'saying'])
  expect(seen(3).kinds).toEqual(['almanac', 'decor', 'happening', 'saying'])
  const l4 = seen(4)
  expect(l4.kinds).toContain('arc')
  expect(l4.longest).toBe(3)
  expect(l4.keeps).toBe(0)
  const l5 = seen(5)
  expect(l5.longest).toBeGreaterThanOrEqual(4)
  expect(l5.longest).toBeLessThanOrEqual(5)
  expect(l5.keeps).toBeGreaterThan(0)
  expect(l5.festivals).toBe(0)
  expect(seen(6).festivals).toBeGreaterThan(0)
  // While an arc is under way it begins no other.
  expect(seen(6, { isArcOpen: false }).kinds).not.toContain('arc')
})

test('DR7 recurring characters come back by name through the log, and the MCP labels and counts are in the words', () => {
  const lines = new Set<string>()
  for (let i = 0; i < 400; i += 1) {
    lines.add(offline(4, i).lines.join(' '))
  }
  const text = [...lines].join('\n')
  expect(CHARACTERS.some(name => text.includes(name))).toBe(true)
  expect(text).toContain('Sentry has 12 things')
  expect(text).toContain('Heard the Atlassian crew')
  // With a name in the log the same name comes back most of the time.
  let back = 0
  for (let i = 0; i < 100; i += 1) {
    const drop = offline(4, i, { recent: ['2026-06-01 visit: Aunt Pearl came by'], labels: [] })
    const said = [...drop.lines, drop.summary].join(' ')
    back += said.includes('Aunt Pearl') ? 1 : 0
  }
  expect(back).toBeGreaterThan(5)
})

// ---- delivery: the farm's side ----

const sprite = (name: string, zone = 'yard', frames = 1) => ({ sprite: name, zone, frames }) as any

test('DR8 a delivery writes the surprise, the log, the count and the slot, and old surprises expire by lasts', () => {
  let farm = freshFarm()
  const day1 = at(10, 9)
  farm = applyDelivery(farm, delivery({ lasts: 'today', name: 'today-one' }), day1).farm
  farm = applyDelivery(farm, delivery({ slot: 12, lasts: 'week', name: 'week-one', kind: 'almanac', lines: ['Fog means snow.'], summary: 'Fog lore' }), day1 + 3 * HOUR).farm
  expect(farm.surprises.map(s => s.name)).toEqual(['today-one', 'week-one'])
  expect(farm.creative.total).toBe(2)
  expect(farm.drops).toEqual({ day: '2026-06-10', done: [9, 12], claims: [] })
  expect(farm.creativeLog.map(l => l.summary)).toEqual(['Nice mornin', 'Fog lore'])
  // The next day today's has gone, the week's has not (and is still the almanac's).
  farm = applyDelivery(farm, delivery({ name: 'next-day' }), day1 + DAY).farm
  expect(farm.surprises.map(s => s.name)).toEqual(['week-one', 'next-day'])
  expect(isLive({ day: '2026-06-10', lasts: 'week' }, '2026-06-16')).toBe(true)
  expect(isLive({ day: '2026-06-10', lasts: 'week' }, '2026-06-17')).toBe(false)
  expect(almanacLines(farm.surprises, new Date(day1 + DAY))).toEqual(['Fog means snow.'])
  expect(almanacLines(farm.surprises, new Date(day1 + 8 * DAY))).toEqual([])
  // Sayings of the day join the bubble pool for that day only.
  expect(sayingPool(farm.surprises, new Date(day1 + DAY))).toEqual(['Nice mornin out here.'])
  expect(sayingPool(farm.surprises, new Date(day1 + 2 * DAY))).toEqual([])
})

test('DR8 the memory is bounded: 40 log entries, 30 surprises, and only twelve summaries go to the model', () => {
  let farm = freshFarm()
  for (let i = 0; i < 90; i += 1) {
    const now = at(1, 9) + Math.floor(i / 3) * DAY + (i % 3) * 3 * HOUR
    farm = applyDelivery(farm, delivery({ slot: [9, 12, 15][i % 3] as number, name: `drop-${i}`, summary: `Summary number ${i}`, lasts: 'week' }), now).farm
  }
  expect(farm.creativeLog.length).toBe(LOG_MAX)
  expect(farm.creativeLog[LOG_MAX - 1]?.name).toBe('drop-89')
  expect(farm.surprises.length).toBeLessThanOrEqual(SURPRISES_MAX)
  expect(farm.creative.total).toBe(90)
  const recent = recentSummaries(farm.creativeLog)
  expect(recent.length).toBe(12)
  expect(recent[11]).toContain('Summary number 89')
  expect(recent[0]).toContain('Summary number 78')
})

const arcOf = (steps: number, over: object = {}) => {
  const raw = validateDrop(ARC({ steps: (ARC() as any).steps.slice(0, steps), ...over }), ctx(6)) as any

  return raw.drop
}

test('DR9 an arc: one step per drop on its day, one at a time, the last step may keep a structure, and a stalled arc is let go', () => {
  const drop = arcOf(3)
  const arc = { name: drop.name, made: 'haiku' as const, start: '2026-06-10', last: '2026-06-10', at: 0, steps: drop.steps }
  const begin = delivery({ name: 'vane-job-1', kind: 'saying', arc: { name: 'vane-job', step: 1 }, begin: arc })
  let farm = applyDelivery(freshFarm(), begin, at(10, 9)).farm
  expect(farm.creative.arc?.at).toBe(1)
  expect(activeArc(farm, '2026-06-10')?.name).toBe('vane-job')
  // Step 2 is for day 2: not due on day 1, due on day 2.
  expect(nextArcStep(farm.creative.arc, '2026-06-10')).toBeUndefined()
  expect(nextArcStep(farm.creative.arc, '2026-06-11')?.index).toBe(1)
  expect(nextArcStep(farm.creative.arc, '2026-06-30')).toBeUndefined() // stalled
  expect(ARC_STALL_DAYS).toBe(14)
  // Only one at a time: another arc's beginning, while this one is under way, is a plain surprise.
  const other = { ...arc, name: 'other-arc' }
  const second = applyDelivery(farm, delivery({ slot: 12, name: 'other-1', arc: { name: 'other-arc', step: 1 }, begin: other }), at(10, 12))
  expect(second.farm.creative.arc?.name).toBe('vane-job')
  expect(second.surprise?.arc).toBe('')
  // Step 2, then the final step, which keeps a structure and finishes the arc.
  farm = applyDelivery(farm, delivery({ slot: 9, name: 'vane-job-2', kind: 'happening', sprites: [sprite('tractor', 'road')], arc: { name: 'vane-job', step: 2 } }), at(11, 9)).farm
  expect(farm.creative.arc?.at).toBe(2)
  const last = applyDelivery(
    farm,
    delivery({ slot: 9, name: 'vane-job-3', kind: 'decor', sprites: [sprite('vane')], keep: true, art: [VANE], arc: { name: 'vane-job', step: 3 } }),
    at(12, 9),
  ).farm
  expect(last.creative.arc).toBeNull()
  expect(last.creative.structures.map(s => s.name)).toEqual(['vane-job-3'])
  expect(last.creative.art.map(a => a.id)).toEqual(['vane'])
  expect(last.surprises.map(s => [s.arc, s.step])).toEqual([['vane-job', 3]])
})

test('DR9 permanent structures are capped at twelve (the oldest retires) and art at sixteen (least recently used out first)', () => {
  let farm = freshFarm()
  const pics = Array.from({ length: 20 }, (_, i) => ({ ...VANE, id: `pic-${i}` }))
  for (let i = 0; i < 20; i += 1) {
    farm = applyDelivery(
      farm,
      delivery({ slot: [9, 12, 15][i % 3] as number, name: `built-${i}`, kind: 'decor', sprites: [sprite(`pic-${i}`)], keep: true, art: [pics[i] as DropArt] }),
      at(1, 9) + Math.floor(i / 3) * DAY + (i % 3) * 3 * HOUR,
    ).farm
  }
  expect(farm.creative.structures.length).toBe(STRUCT_MAX)
  expect(farm.creative.structures[0]?.name).toBe('built-8')
  expect(farm.creative.structures[11]?.name).toBe('built-19')
  expect(farm.creative.art.length).toBeLessThanOrEqual(ART_STORE_MAX)
  // The pictures structures name are kept before any that nothing names.
  const ids = farm.creative.art.map(a => a.id)
  for (let i = 8; i < 20; i += 1) {
    expect(ids).toContain(`pic-${i}`)
  }
  // Without structures the least recently used goes first, and using one makes it new again.
  let plain = freshFarm()
  for (let i = 0; i < 16; i += 1) {
    plain = applyDelivery(plain, delivery({ slot: [9, 12, 15][i % 3] as number, name: `p-${i}`, art: [pics[i] as DropArt] }), at(1, 9) + Math.floor(i / 3) * DAY + (i % 3) * 3 * HOUR).farm
  }
  plain = applyDelivery(plain, delivery({ slot: 15, name: 'again', kind: 'happening', sprites: [sprite('pic-0')], lasts: 'today' }), at(20, 15)).farm
  plain = applyDelivery(plain, delivery({ slot: 9, name: 'new', art: [pics[16] as DropArt] }), at(21, 9)).farm
  const kept = plain.creative.art.map(a => a.id)
  expect(kept.length).toBe(16)
  expect(kept).toContain('pic-0')
  expect(kept).not.toContain('pic-1')
})

test('DR9 a festival colors the day it came and no other', () => {
  const farm = applyDelivery(freshFarm(), delivery({ festival: 'dusk' }), at(10, 9)).farm
  const view = viewOf(farm).drops
  expect(festivalOf(view, new Date(at(10, 14)))).toBe('dusk')
  expect(festivalOf(view, new Date(at(11, 9)))).toBe('')
  expect(festivalOf(undefined, new Date(at(10, 14)))).toBe('')
})

// ---- the farm: v9, migrated and normalized ----

test('DR10 the farm is v9; older farms start with no drops, and every damaged field reads back sound', () => {
  const fresh = freshFarm()
  expect(fresh.version).toBe(10)
  const v8 = loadFarm({ ...fresh, version: 8, surprises: [{ day: '2026-06-10' }], newsSeen: ['x'], creative: { total: 50 } }) as any
  expect(v8.version).toBe(10)
  expect(v8.surprises).toEqual([])
  expect(v8.creative).toEqual(freshCreative())
  expect(v8.drops).toEqual(freshDrops())
  expect(v8.newsSeen).toEqual([])
  const junk = loadFarm({
    ...fresh,
    drops: { day: 'today', done: [9, 9, 10, 'x', 15], claims: [{ slot: 9, at: -5 }, { slot: 9, at: 5 }, { slot: 7, at: 1 }, 'z'] },
    modelCalls: { day: 5, n: 'many' },
    surprises: ['x', { day: '2026-06-10', slot: 9, kind: 'saying', name: 'ok-one', lines: ['fine'] }, { day: '2026-06-10', slot: 10, kind: 'saying', name: 'bad', lines: ['x'] }, { day: '2026-06-10', slot: 9, kind: 'happening', name: 'no-art', lines: ['x'], sprites: 'none' }],
    creativeLog: [{ day: 'x' }, { day: '2026-06-10', name: 'a', kind: 'saying', summary: 'café \u{1f414} ok' }],
    creative: { total: 'lots', arc: { name: 'Bad Name', steps: [] }, structures: [{ name: 'a', day: '2026-06-10', sprites: [] }], art: [{ id: 'x' }, VANE, VANE], festival: { d: 'x', tint: 'neon' } },
    newsSeen: ['a', 'a', 5, 'bad id!', 'b'],
  }) as any
  expect(junk.drops).toEqual({ day: '', done: [9, 15], claims: [{ slot: 9, at: 0 }] })
  expect(junk.modelCalls).toEqual({ day: '', n: 0 })
  expect(junk.surprises.map((s: Surprise) => s.name)).toEqual(['ok-one', 'no-art'])
  expect(junk.surprises[1].kind).toBe('saying')
  expect(junk.creativeLog.length).toBe(1)
  expect(junk.creativeLog[0].summary).toMatch(/^caf +ok$/)
  expect(junk.creative).toEqual({ total: 0, arc: null, structures: [], art: [VANE], festival: { d: '', tint: '' } })
  expect(junk.newsSeen).toEqual(['a', 'b'])
})

test('DR10 the storage is bounded: 30 surprises, 40 log lines, 12 structures, 16 pictures of at most 2 KB, 20 news ids', () => {
  const surprises = Array.from({ length: 200 }, (_, i) => ({ day: '2026-06-10', slot: 9, kind: 'saying', name: `s-${i}`, lines: ['x'.repeat(64), 'y', 'z', 'w'] }))
  const log = Array.from({ length: 200 }, (_, i) => ({ day: '2026-06-10', name: `l-${i}`, kind: 'saying', summary: 'z'.repeat(200) }))
  const structures = Array.from({ length: 50 }, (_, i) => ({ name: `st-${i}`, day: '2026-06-10', arc: '', sprites: [sprite('hen'), sprite('cow'), sprite('pup'), sprite('owl')] }))
  const pics = Array.from({ length: 50 }, (_, i) => ({ id: `big-${i}`, w: 24, h: 24, frames: 2, rows: Array(48).fill('o'.repeat(24)) }))
  const farm = loadFarm({ ...freshFarm(), surprises, creativeLog: log, creative: { total: 5, structures, art: pics }, newsSeen: Array.from({ length: 80 }, (_, i) => `n${i}`) }) as any
  expect(farm.surprises.length).toBe(30)
  expect(farm.surprises[0].lines.length).toBe(3)
  expect(farm.creativeLog.length).toBe(40)
  expect(farm.creativeLog[0].summary.length).toBe(80)
  expect(farm.creative.structures.length).toBe(12)
  expect(farm.creative.structures[0].sprites.length).toBe(3)
  expect(farm.creative.art.length).toBe(16)
  for (const one of farm.creative.art) {
    expect(JSON.stringify(one).length).toBeLessThanOrEqual(2048)
  }
  expect(farm.newsSeen.length).toBe(20)
  expect(farm.newsSeen[19]).toBe('n79')
  // All of it together stays small enough for one store value.
  expect(JSON.stringify(farm).length).toBeLessThan(120_000)
  expect(dropsOf(null)).toEqual(freshDrops())
  expect(surprisesOf('x')).toEqual([])
  expect(logOf(5)).toEqual([])
  expect(creativeOf(undefined)).toEqual(freshCreative())
  expect(newsSeenOf('x')).toEqual([])
})

// ---- the news ----

test('DR11 a news item is read strictly: an id and a printable ASCII line cut to 80', () => {
  expect(newsOf({ id: 'v6', line: 'New drops today.' })).toEqual({ id: 'v6', line: 'New drops today.' })
  expect(newsOf({ id: 'v6', line: 'x'.repeat(200) })?.line.length).toBe(80)
  for (const bad of [null, undefined, 5, 'news', [], {}, { id: 'v6' }, { line: 'x' }, { id: 5, line: 'x' }, { id: 'has space', line: 'x' }, { id: 'v6', line: 7 }, { id: 'v6', line: '' }, { id: 'v6', line: '   ' }, { id: 'v6', line: 'café' }, { id: 'v6', line: 'tab\tinside' }, { id: 'a'.repeat(33), line: 'x' }]) {
    expect(newsOf(bad), JSON.stringify(bad)).toBeNull()
  }
})

// ---- the prompt: only the farm and the log ----

const input = (farm = freshFarm() as any) =>
  promptInputOf(
    farm,
    new Date(2026, 5, 10, 9),
    9,
    levelOf(farm.creative.total),
    ['2026-06-09 loose-hen: Cousin Delbert lost a hen'],
    true,
  )

test('DR12 the prompt carries the date and slot, the story depth, the farm and the log, and nothing of the host', () => {
  const text = promptOf(input())
  expect(text).toContain('Wednesday 2026-06-10, morning (9:00 local), summer. This is the 9:00 drop.')
  expect(text).toContain('Story depth 1 of 6 after 0 drops.')
  expect(text).toContain('Farm: 0 jars on the shelf;')
  for (const gone of ['MCP servers', 'Atlassian', 'Sentry', 'triage', 'Counts from them', 'Skills, plugins and commands', 'setup']) {
    expect(text, gone).not.toContain(gone)
  }
  expect(systemPrompt(1)).toContain('The farm counts below are optional colour')
  expect(systemPrompt(1)).not.toMatch(/connected tools|commands below/)
  expect(text).toContain('2026-06-09 loose-hen: Cousin Delbert lost a hen')
  expect(systemPrompt(5)).toContain('Story depth 5 of 6')
  expect(systemPrompt(5)).toContain('=clear')
  expect(systemPrompt(1)).toContain('wholesome')
  expect(promptOf(input(), 'RETRY')).toContain('RETRY')
  for (const zone of ZONES) {
    expect(systemPrompt(1)).toContain(zone)
  }
  for (const name of Object.keys(DROP_SPRITES)) {
    expect(systemPrompt(1)).toContain(name)
  }
  expect(Object.keys(FESTIVAL_TINTS).length).toBeGreaterThan(2)
})

// ---- an engine to run it in ----

const START = at(10, 8, 50)

const tally = {
  animWrites: 0,
  storeSets: 0,
  storeGets: 0,
  stateWrites: 0,
  lines: [] as string[],
  db: new Map<string, unknown>(),
}
const calls = {
  model: [] as { model: string; system: string; prompt: string; maxTokens: number; timeoutMs: number }[],
  mcp: [] as { server: string; tool: string; args: Record<string, unknown> }[],
  toolList: 0,
  commandList: 0,
  other: 0,
}
type Reply = unknown
const world = {
  // What the mocked model answers for its nth call (a string is the text itself); 'deny' refuses it; 'throw' throws.
  model: ((_n: number) => 'deny') as (n: number, e: { prompt: string }) => Reply,
  tools: [] as { name: string; description: string; mcp: boolean }[],
  commands: [] as { name: string; description: string; source: string }[],
  mcp: ((_tool: string, _args: Record<string, unknown>): unknown => undefined) as (tool: string, args: Record<string, unknown>) => unknown,
  toolListDelay: 0,
  commandsThrow: false,
}

const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))
let clk: MockClock

const textBlock = (text: string) => ({ content: [{ type: 'text', text }], isError: false })

const TOOLS = [
  { name: 'Read', description: 'read', mcp: false },
  ...['getAccessibleAtlassianResources', 'searchJiraIssuesUsingJql', 'getVisibleJiraProjects', 'getJiraIssue', 'createJiraIssue', 'editJiraIssue', 'transitionJiraIssue'].map(tool => ({ name: `mcp__claude_ai_Atlassian__${tool}`, description: tool, mcp: true })),
  ...['find_organizations', 'search_issues', 'search_logs', 'update_issue'].map(tool => ({ name: `mcp__claude_ai_Sentry__${tool}`, description: tool, mcp: true })),
  { name: 'mcp__claude_ai_Claude_Docs__read', description: 'read', mcp: true },
]
const COMMANDS = [
  { name: 'help', description: 'built in', source: 'builtin' },
  { name: 'commit', description: 'commit', source: 'user' },
  { name: 'jeb', description: 'Jeb', source: 'plugin' },
  { name: 'docs:read', description: 'mcp prompt', source: 'mcp' },
  { name: 'x'.repeat(40), description: 'too long', source: 'user' },
  { name: 'bad name!', description: 'bad', source: 'user' },
]

const GENERIC = (n: number) => ({ kind: 'saying', name: `generic-${n}`, lines: [`Nothin much, say number ${n}.`], summary: `A quiet saying ${n}` })

const answered = (reply: unknown) => ({
  isAnswered: true,
  text: typeof reply === 'string' ? reply : JSON.stringify(reply),
  usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
})

const rig = (on: any, entries: Record<string, unknown> = {}, now = START, env: Record<string, string> = {}): MockClock => {
  tally.animWrites = 0
  tally.storeSets = 0
  tally.storeGets = 0
  tally.stateWrites = 0
  tally.lines = []
  tally.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  calls.model = []
  calls.mcp = []
  calls.toolList = 0
  calls.commandList = 0
  calls.other = 0
  world.model = n => answered(GENERIC(n))
  world.tools = TOOLS
  world.commands = COMMANDS
  world.mcp = tool => {
    switch (tool) {
      case 'getAccessibleAtlassianResources':
        return textBlock(JSON.stringify([{ id: '11111111-2222-3333-4444-555555555555', name: 'ACME Corp Jira', url: 'https://acme.atlassian.net' }]))
      case 'searchJiraIssuesUsingJql':
        return { content: [], isError: false, structuredContent: { total: 7, issues: [{ key: 'ACME-4242', fields: { summary: 'Reset password flow SECRETTITLE' } }] } }
      case 'find_organizations':
        return textBlock(JSON.stringify({ organizations: [{ slug: 'acme-org', name: 'Acme Org' }] }))
      case 'search_issues':
        return { content: [], isError: false, structuredContent: { issues: Array.from({ length: 12 }, (_, i) => ({ shortId: `API-${i}`, title: `Boom number ${i} SENTRYSECRET` })) } }
      default:
        return undefined
    }
  }
  world.toolListDelay = 0
  world.commandsThrow = false
  const clock = mock.clock(on, { now })
  clk = clock
  mock.env(on, { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_NEWS: 'null', ...env })
  on('fs.read', (_: any, e: any) => {
    throw new Error(`ENOENT ${(e as { path: string }).path}`)
  })
  on('store.get', (_: any, e: any) => {
    tally.storeGets += 1

    return { value: copy(tally.db.get(e.key)) }
  })
  on('store.set', (_: any, e: any) => {
    tally.storeSets += 1
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
  on('tool.list', async () => {
    calls.toolList += 1
    if (world.toolListDelay > 0) {
      await clock.sleep(world.toolListDelay)
    }

    return { value: world.tools }
  })
  on('command.list', () => {
    calls.commandList += 1
    if (world.commandsThrow) {
      throw new Error('no commands')
    }

    return { value: world.commands }
  })
  on('mcp.call', (_: any, e: any) => {
    calls.mcp.push({ server: e.server, tool: e.tool, args: e.args })
    const result = world.mcp(e.tool, e.args)

    return result === undefined ? { deny: 'no such tool' } : { value: result }
  })
  on('model.complete', (_: any, e: any) => {
    calls.model.push({ model: e.model, system: String(e.system ?? ''), prompt: String(e.prompt), maxTokens: e.maxTokens, timeoutMs: e.timeoutMs })
    const reply = world.model(calls.model.length, { prompt: String(e.prompt) })
    if (reply === 'deny') {
      return { deny: 'model blocked' }
    }
    if (reply === 'throw') {
      throw new Error('model down')
    }

    return { value: reply }
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

const elapse = async (clock: MockClock, ms: number) => {
  for (let left = ms; left > 0; left -= 20 * MINUTE) {
    await clock.advance(Math.min(left, 20 * MINUTE))
  }
}

const start = ($: any, isInteractive = true) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive })
const stored = () => tally.db.get('farm') as ReturnType<typeof freshFarm>
const levelFarm = (total: number, over: object = {}) => ({ ...freshFarm(), creative: { ...freshCreative(), total }, ...over })

test('DR13 a day: three drops at 9, 12 and 15 by Haiku, no read of the host at all, and the farm keeps them', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  world.model = n => answered({ kind: n === 1 ? 'happening' : 'saying', name: `drop-${n}`, lines: [`Jeb line number ${n}.`], summary: `Summary ${n}`, sprites: n === 1 ? [{ sprite: 'hen', zone: 'road', frames: 2 }] : undefined })
  await start($)
  await clock.advance(5 * MINUTE)
  expect(stored()?.surprises?.length ?? 0).toBe(0)
  expect(calls.model.length).toBe(0)
  await elapse(clock, 10 * MINUTE + 30_000)
  // 9:00 passed: one drop, made by Haiku, said once, claimed and stored.
  expect(calls.model.length).toBe(1)
  expect(stored().surprises.map(s => [s.slot, s.name, s.made])).toEqual([[9, 'drop-1', 'haiku']])
  expect(tally.lines).toContain('Jeb line number 1.')
  expect(stored().drops).toEqual({ day: '2026-06-10', done: [9], claims: [] })
  expect(stored().modelCalls).toEqual({ day: '2026-06-10', n: 1 })
  // The model call is Haiku, capped.
  expect(calls.model[0]).toMatchObject({ model: 'haiku', maxTokens: 1800, timeoutMs: 20_000 })
  // The host is never asked: no MCP call, no tool list, no command list.
  expect(calls.mcp).toEqual([])
  expect(calls.toolList).toBe(0)
  expect(calls.commandList).toBe(0)

  // What the model saw: the farm and the log, no server label, command name or count, though the world offers them.
  const { prompt, system } = calls.model[0] as { prompt: string; system: string }
  console.log(`--- example prompt sent to Haiku (level 1, built from mock data) ---\n${prompt}\n--- end ---`)
  expect(prompt).not.toContain('MCP servers')
  expect(prompt).not.toContain('Counts from them')
  expect(prompt).not.toContain('Skills, plugins and commands')
  for (const name of ['Atlassian', 'Sentry', 'Claude Docs', 'commit', 'docs:read']) {
    expect(prompt, name).not.toContain(name)
  }
  for (const secret of ['SECRETTITLE', 'ACME', 'acme', 'SENTRYSECRET', 'API-', '11111111', 'Boom']) {
    expect(prompt, secret).not.toContain(secret)
    expect(system, secret).not.toContain(secret)
  }
  expect(prompt).not.toContain('x'.repeat(33))
  expect(prompt).not.toContain('bad name')

  // 12:00 and 15:00 on time, one each.
  await elapse(clock, 6 * HOUR)
  expect(stored().surprises.map(s => [s.slot, s.made])).toEqual([[9, 'haiku'], [12, 'haiku'], [15, 'haiku']])
  expect(calls.model.length).toBe(3)
  expect(stored().modelCalls.n).toBe(3)
  expect(stored().creative.total).toBe(3)
  expect(stored().creativeLog.length).toBe(3)
  // The second prompt carries the first drop's summary and no more of it.
  expect((calls.model[1] as { prompt: string }).prompt).toContain('drop-1: Summary 1')
  // Still no tool list, however many drops.
  expect(calls.toolList).toBe(0)
  // The farm counts them.
  expect(stored().surprises.find(s => s.slot === 15)).toMatchObject({ kind: 'saying', name: 'drop-3', lines: ['Jeb line number 3.'] })
})

test('DR13 a quiet tick makes no calls: after the day\'s drops, and with creativity off, the host is asked for nothing', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(stored().surprises.length).toBe(3)
  const before = { ...calls, model: calls.model.length, mcp: calls.mcp.length }
  const sets = tally.storeSets
  const frames = tally.animWrites
  await elapse(clock, 4 * HOUR)
  // Still life: not one frame written in four idle hours, drops or no drops.
  expect(tally.animWrites - frames).toBe(0)
  expect(calls.model.length).toBe(before.model)
  expect(calls.mcp.length).toBe(before.mcp)
  expect(calls.toolList).toBe(before.toolList)
  expect(calls.commandList).toBe(before.commandList)
  // Only the heartbeat writes (one a minute) in four idle hours; no frame once still.
  expect(tally.storeSets - sets).toBeLessThanOrEqual(4 * 60 + 2)
})

test('DR14 creativity off (the option, /jeb, the env dial) and a run nobody is at make no drops and no calls', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, START, { JEB_CREATIVITY: 'off' })
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(stored()?.surprises.length ?? 0).toBe(0)
  expect(calls.model.length + calls.mcp.length + calls.toolList + calls.commandList).toBe(0)
})

test('DR14 the creativity setting switches it and keeps the choice', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  on('config.set', (_: any, e: any) => ({ value: e.value }))
  await start($)
  await $.config.set({ key: 'jeb.creativity', value: false })
  expect(tally.db.get('overrides')).toMatchObject({ creativity: false })
  await elapse(clock, 7 * HOUR)
  expect(calls.model.length + calls.mcp.length).toBe(0)
  expect(stored()?.surprises?.length ?? 0).toBe(0)
  await $.config.set({ key: 'jeb.creativity', value: true })
  expect(tally.db.get('overrides')).toMatchObject({ creativity: true })
  await elapse(clock, 2 * HOUR)
  expect(stored().surprises.length).toBeGreaterThan(0)
})

test('DR14 JEB_CREATIVITY=local makes the day\'s drops offline and asks the host for nothing', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, START, { JEB_CREATIVITY: 'local' })
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(stored().surprises.map(s => s.made)).toEqual(['local', 'local', 'local'])
  expect(calls.model.length + calls.mcp.length + calls.toolList + calls.commandList).toBe(0)
  expect(stored().modelCalls.n).toBe(0)
})

test('DR14 a run nobody is at (the SDK or -p) makes no drops', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($, false)
  await elapse(clock, 7 * HOUR)
  expect(calls.model.length + calls.mcp.length + calls.toolList + calls.commandList).toBe(0)
  expect(stored()?.surprises?.length ?? 0).toBe(0)
})

test('DR15 a session that opens at 14:00 catches up one slot at a time, ten minutes apart, and takes 15:00 on time', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 14))
  await start($)
  await clock.advance(MINUTE)
  expect(stored().surprises.map(s => s.slot)).toEqual([9])
  await clock.advance(8 * MINUTE)
  expect(stored().surprises.map(s => s.slot)).toEqual([9])
  await clock.advance(2 * MINUTE)
  expect(stored().surprises.map(s => s.slot)).toEqual([9, 12])
  await elapse(clock, 50 * MINUTE)
  expect(stored().surprises.map(s => s.slot)).toEqual([9, 12, 15])
  // Missed days are never made up: tomorrow at 9:10 there is one drop, for 9.
  await elapse(clock, 18 * HOUR)
  expect(stored().drops.day).toBe('2026-06-11')
})

test('DR15 two sessions on one store: a fresh claim of another holds the slot; a stale one is taken over offline', { timeoutMs: 120_000 }, async ($, on) => {
  // Another session claimed 9:00 a few seconds ago and is still working on it.
  const farm = { ...freshFarm(), drops: { day: '2026-06-10', done: [], claims: [{ slot: 9, at: at(10, 9, 0, 0) }] } }
  const clock = rig(on, { farm }, at(10, 9, 0, 20))
  await start($)
  await clock.advance(60_000)
  expect(stored().surprises.length).toBe(0)
  expect(calls.model.length).toBe(0)
  // Two minutes on it has gone stale: this session takes the slot, with the offline generator (no model, no host).
  await clock.advance(2 * MINUTE)
  expect(stored().surprises.map(s => [s.slot, s.made])).toEqual([[9, 'local']])
  expect(calls.model.length).toBe(0)
  expect(calls.mcp.length).toBe(0)
})

test('DR15 a slot the other session already finished is not made again', { timeoutMs: 120_000 }, async ($, on) => {
  const farm = { ...freshFarm(), drops: { day: '2026-06-10', done: [9], claims: [] } }
  const clock = rig(on, { farm }, at(10, 9, 0, 20))
  await start($)
  await clock.advance(5 * MINUTE)
  expect(stored().surprises.length).toBe(0)
  expect(calls.model.length).toBe(0)
})

test('DR16 a reply that is invalid is retried once without its text, then the offline generator; the budget caps at six', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 8, 59, 40))
  world.model = n => answered(n === 1 ? 'I cannot do that, here is a poem' : { ...GENERIC(n), lines: ['What the hell'] })
  await start($)
  await clock.advance(3 * MINUTE)
  // Two calls (the first and the retry), both bad: this slot is the offline generator's.
  expect(calls.model.length).toBe(2)
  expect(stored().modelCalls.n).toBe(2)
  expect(stored().surprises.map(s => [s.slot, s.made])).toEqual([[9, 'local']])
  expect((calls.model[1] as { prompt: string }).prompt).toContain('failed the "kind" check')
  expect((calls.model[1] as { prompt: string }).prompt).not.toContain('poem')
  expect((calls.model[1] as { prompt: string }).prompt).not.toContain('hell')
  // A retry that works is Haiku's.
  world.model = n => (n === 3 ? answered('nope') : answered(GENERIC(n)))
  await elapse(clock, 6 * HOUR)
  expect(stored().surprises.map(s => [s.slot, s.made])).toEqual([[9, 'local'], [12, 'haiku'], [15, 'haiku']])
  expect(stored().modelCalls.n).toBe(5)
  expect(stored().modelCalls.n).toBeLessThanOrEqual(6)
})

test('DR16 the retry prompt names the failed check and never carries the rejected reply', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 8, 59, 40))
  world.model = n => answered(n === 1 ? { ...GENERIC(n), lines: ['Zorbleflux the hell'] } : { ...GENERIC(n), lines: ['Quuxwidget the hell'] })
  await start($)
  await clock.advance(3 * MINUTE)
  expect(calls.model.length).toBe(2)
  const first = (calls.model[0] as { prompt: string }).prompt
  const retry = (calls.model[1] as { prompt: string }).prompt
  expect(first).not.toContain('failed the')
  expect(retry).toContain('failed the "words" check')
  expect(retry).not.toContain('Zorbleflux')
  expect(retry).not.toContain('Quuxwidget')
})

test('DR16 a model that errors, is denied or throws, and a spent budget, all fall back to the offline generator', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, { farm: { ...freshFarm(), modelCalls: { day: '2026-06-10', n: 5 } } }, at(10, 8, 59, 40))
  world.model = n => (n === 1 ? { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded', usage: {} } : answered(GENERIC(n)))
  await start($)
  await clock.advance(3 * MINUTE)
  // One call spent (the sixth) on an error, then nothing: no retry after an error.
  expect(calls.model.length).toBe(1)
  expect(stored().surprises.map(s => s.made)).toEqual(['local'])
  expect(stored().modelCalls.n).toBe(6)
  // The budget is spent for the day: the later slots never ask.
  await elapse(clock, 6 * HOUR)
  expect(calls.model.length).toBe(1)
  expect(stored().surprises.map(s => s.made)).toEqual(['local', 'local', 'local'])
  expect(stored().modelCalls.n).toBe(6)
})

test('DR16 a denied model, with MCP tools that would throw, falls back and never calls them', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 8, 59, 40))
  world.model = () => 'deny'
  world.mcp = () => {
    throw new Error('mcp down')
  }
  await start($)
  await clock.advance(3 * MINUTE)
  expect(stored().surprises.map(s => s.made)).toEqual(['local'])
  expect(calls.model.length).toBe(1)
  expect(calls.mcp.length).toBe(0)
  expect(calls.model[0]?.prompt).not.toContain('MCP servers')
  expect(calls.model[0]?.prompt).not.toContain('Counts from them')
})

test('DR16 a model that throws falls back too', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 8, 59, 40))
  world.model = () => 'throw'
  await start($)
  await clock.advance(3 * MINUTE)
  expect(stored().surprises.map(s => s.made)).toEqual(['local'])
  expect(calls.model.length).toBe(1)
})

test('DR16 a world with no server, a bare tool list and a command list that throws changes nothing: generation runs and the host is not asked', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 8, 59, 40))
  world.tools = [{ name: 'Read', description: 'read', mcp: false }]
  world.commandsThrow = true
  await start($)
  await clock.advance(3 * MINUTE)
  expect(calls.mcp.length).toBe(0)
  expect(calls.toolList + calls.commandList).toBe(0)
  expect(calls.model.length).toBe(1)
  expect(calls.model[0]?.prompt).not.toContain('MCP servers')
  expect(calls.model[0]?.prompt).not.toContain('Counts from them')
  expect(stored().surprises.map(s => s.made)).toEqual(['haiku'])
})

test('DR16 a slow tool list costs the drop nothing: it is never asked, so the model is called at once', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 8, 59, 40))
  // The tool list would answer late, but a drop never asks for it.
  world.toolListDelay = 60_000
  await start($)
  await clock.advance(MINUTE)
  expect(calls.model.length).toBe(1)
  expect(calls.toolList).toBe(0)
  expect(calls.commandList).toBe(0)
  expect(calls.mcp.length).toBe(0)
  expect(calls.model[0]?.prompt).not.toContain('Skills, plugins and commands')
})

test('DR17 the model never sees the session: prompts, tool inputs, tickets and replies stay out of what it is sent', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on, {}, at(10, 8, 40))
  await start($)
  const secrets = ['ZEBRA-PROMPT-8841', 'TOPSECRET_TOKEN_abc123', 'ACME-4242 Reset password flow', 'send mail to boss@acme.test']
  await $.prompt.submit({ text: `please fix ${secrets[0]} and ${secrets[3]}` })
  await $.tool.call({ tool: 'Bash', command: `echo ${secrets[1]}` })
  await $.tool.call({ tool: 'mcp__claude_ai_Atlassian__getJiraIssue', issueIdOrKey: 'ACME-4242', summary: secrets[2] })
  await $.turn.start({ text: '', turnId: 't' })
  await clk.settle()
  await elapse(clock, 7 * HOUR)
  expect(calls.model.length).toBe(3)
  for (const one of calls.model) {
    for (const secret of [...secrets, 'ACME-4242', 'boss@acme', 'ZEBRA', 'TOPSECRET', 'echo ', 'fix ']) {
      expect(one.prompt, secret).not.toContain(secret)
      expect(one.system, secret).not.toContain(secret)
    }
  }
  // Nor does anything of the session reach a stored surprise.
  expect(JSON.stringify(stored().surprises)).not.toContain('ZEBRA')
  expect(JSON.stringify(stored().creativeLog)).not.toContain('TOPSECRET')
})

test('DR17 the full prompt, system and user, holds no tool or command name even when the rig offers Jira and Sentry tools and a triage command', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  world.tools = [
    ...TOOLS,
    { name: 'mcp__jira__search_tickets', description: 'tickets', mcp: true },
    { name: 'mcp__sentry__list_projects', description: 'projects', mcp: true },
  ]
  world.commands = [...COMMANDS, { name: 'triage', description: 'triage a ticket', source: 'plugin' }]
  await start($)
  await elapse(clock, 7 * HOUR)
  expect(calls.model.length).toBe(3)
  for (const one of calls.model) {
    const whole = `${one.system}\n${one.prompt}`.toLowerCase()
    for (const name of ['jira', 'atlassian', 'sentry', 'triage', 'search_tickets', 'list_projects', 'claude docs', 'docs:read', 'getaccessibleatlassianresources', 'mcp']) {
      expect(whole, name).not.toContain(name)
    }
  }
  expect(calls.mcp).toEqual([])
})

// ---- a level-5 arc, end to end ----

test('DR18 a level-5 arc drop, end to end: the model draws a picture and a five-step arc, steps arrive on their days, the last keeps a structure', { timeoutMs: 180_000 }, async ($, on) => {
  const arc = {
    kind: 'arc',
    name: 'weathervane-job',
    summary: 'Cousin Delbert is raising a weathervane',
    art: VANE,
    steps: [
      { day: 1, kind: 'saying', name: 'wv-1', lines: ['Cousin Delbert is fixin to raise a weathervane.'] },
      { day: 1, kind: 'happening', name: 'wv-2', lines: ['Delbert hauled iron up the road.'], sprites: [{ sprite: 'tractor', zone: 'road', frames: 2 }] },
      { day: 2, kind: 'happening', name: 'wv-3', lines: ['The vane is on the ground, bein painted.'], sprites: [{ sprite: 'vane', zone: 'yard', frames: 2 }] },
      { day: 2, kind: 'saying', name: 'wv-4', lines: ['Delbert says one more day.'] },
      { day: 3, kind: 'decor', name: 'wv-5', lines: ['The weathervane is up on the barn.'], sprites: [{ sprite: 'vane', zone: 'yard', frames: 2 }], lasts: 'week', keep: true },
    ],
  }
  const clock = rig(on, { farm: levelFarm(90) }, at(10, 8, 59, 40))
  world.model = n => answered(n === 1 ? arc : GENERIC(n))
  await start($)
  await clock.advance(3 * MINUTE)
  // Slot 9: the model began the arc and its first step arrived.
  expect(calls.model[0]?.maxTokens).toBe(1800)
  expect(calls.model[0]?.prompt).toContain('Story depth 5 of 6 after 90 drops.')
  expect(calls.model[0]?.prompt).toContain('No arc is under way')
  expect(stored().creative.arc?.name).toBe('weathervane-job')
  expect(stored().creative.arc?.at).toBe(1)
  expect(stored().creative.art.map(a => a.id)).toEqual(['vane'])
  expect(stored().surprises.map(s => [s.name, s.arc, s.step])).toEqual([['weathervane-job-1', 'weathervane-job', 1]])
  expect(tally.lines).toContain('Cousin Delbert is fixin to raise a weathervane.')
  // Slot 12: step 2 is due (day 1): delivered with no model call.
  await elapse(clock, 3 * HOUR)
  expect(stored().surprises.map(s => s.name)).toEqual(['weathervane-job-1', 'weathervane-job-2'])
  expect(calls.model.length).toBe(1)
  // Slot 15: the next step is for tomorrow, so the model is asked for a plain surprise, and told an arc is under way.
  await elapse(clock, 3 * HOUR)
  expect(stored().surprises.map(s => s.name)).toEqual(['weathervane-job-1', 'weathervane-job-2', 'generic-2'])
  expect(calls.model.length).toBe(2)
  expect(calls.model[1]?.prompt).toContain('An arc is under way ("weathervane-job", step 2 of 5): do not start another.')
  // Day 2: steps 3 and 4 arrive on the 9:00 and 12:00 drops, with no model call.
  await elapse(clock, 18 * HOUR)
  expect(stored().surprises.some(s => s.name === 'weathervane-job-3')).toBe(true)
  await elapse(clock, 3 * HOUR)
  expect(stored().surprises.some(s => s.name === 'weathervane-job-4')).toBe(true)
  expect(stored().creative.arc?.at).toBe(4)
  expect(calls.model.length).toBe(2)
  // Day 2 at 15:00 a plain surprise; day 3 at 9:00 the last step, which keeps a permanent structure.
  await elapse(clock, 3 * HOUR)
  expect(calls.model.length).toBe(3)
  await elapse(clock, 18 * HOUR)
  const farm = stored()
  expect(farm.creative.arc).toBeNull()
  expect(farm.creative.structures.map(s => [s.name, s.arc, s.sprites[0]?.sprite])).toEqual([['weathervane-job-5', 'weathervane-job', 'vane']])
  expect(farm.creativeLog.filter(l => l.arc === 'weathervane-job').length).toBe(5)
  expect(farm.creativeLog[0]?.summary).toBe('Cousin Delbert is raising a weathervane')
  expect(tally.lines).toContain('The weathervane is up on the barn.')
  expect(farm.modelCalls.n).toBeLessThanOrEqual(6)
  console.log(
    `--- level-5 arc, end to end ---\nreply: ${JSON.stringify(arc).slice(0, 220)}...\nstored arc steps delivered: ${farm.surprises.filter(s => s.arc).map(s => `${s.day} ${s.name} (${s.kind})`).join('; ')}\nstructure: ${JSON.stringify(farm.creative.structures)}\nlog: ${farm.creativeLog.map(l => `${l.day} ${l.name}: ${l.summary}`).slice(-3).join(' | ')}\n--- end ---`,
  )
  // Months on the structure still stands, and so does its picture.
  const later = new Date(2026, 8, 1, 14)
  expect(dropLooks(viewOf(farm).drops, later).map(p => p.sprite.sprite)).toEqual(['vane'])
  expect(dropLooks(viewOf(farm).drops, later)[0]?.art?.id).toBe('vane')
})

// ---- the news, in a session ----

const NEWS_ENV = (value: unknown) => ({ JEB_CREATIVITY: 'off', JEB_NEWS: typeof value === 'string' ? value : JSON.stringify(value) })

test('DR21 the news is said once, after the greeting, as a milestone, and recorded in the farm', { timeoutMs: 60_000 }, async ($, on) => {
  rig(on, {}, START, NEWS_ENV({ id: 'creative-v6', line: 'Got a new knack for surprises. Watch the yard.' }))
  await start($)
  await clk.settle()
  expect(tally.lines.filter(line => line.includes('new knack')).length).toBe(1)
  // After the greeting: some other line came before it.
  expect(tally.lines.findIndex(line => line.includes('new knack'))).toBeGreaterThan(0)
  expect(stored().newsSeen).toEqual(['creative-v6'])
  // A second session on the same store says nothing of it.
  await start($)
  await clk.settle()
  expect(tally.lines.filter(line => line.includes('new knack')).length).toBe(1)
  expect(stored().newsSeen).toEqual(['creative-v6'])
})

test('DR21 a silent Jeb keeps to his word, and an id after others is added to the bounded list', { timeoutMs: 60_000 }, async ($, on) => {
  rig(on, { farm: { ...freshFarm(), newsSeen: Array.from({ length: 20 }, (_, i) => `old${i}`) } }, START, NEWS_ENV({ id: 'fresh', line: 'First news item.' }))
  await start($)
  await clk.settle()
  expect(tally.lines.filter(line => line === 'First news item.').length).toBe(1)
  expect(stored().newsSeen.length).toBe(20)
  expect(stored().newsSeen[19]).toBe('fresh')
  expect(stored().newsSeen[0]).toBe('old1')
})

test('DR21 an id already seen is not said again', { timeoutMs: 60_000 }, async ($, on) => {
  rig(on, { farm: { ...freshFarm(), newsSeen: ['seen-one'] } }, START, NEWS_ENV({ id: 'seen-one', line: 'Old news.' }))
  await start($)
  await clk.settle()
  expect(tally.lines).not.toContain('Old news.')
  expect(stored().newsSeen).toEqual(['seen-one'])
})

const MALFORMED: [string, unknown][] = [
  ['not JSON', 'news at eleven'],
  ['null', 'null'],
  ['an array', []],
  ['no line', { id: 'x' }],
  ['a bad id', { id: 'bad id', line: 'x' }],
  ['a non-ASCII line', { id: 'x', line: 'caf\u00e9' }],
  ['a line that is not a string', { id: 'x', line: 9 }],
  ['an empty line', { id: 'x', line: '  ' }],
]
for (const [name, bad] of MALFORMED) {
  test(`DR21 a malformed news (${name}) says nothing and writes nothing`, { timeoutMs: 60_000 }, async ($, on) => {
    rig(on, {}, START, NEWS_ENV(bad))
    await start($)
    await clk.settle()
    expect(stored()?.newsSeen ?? []).toEqual([])
    expect(tally.lines.filter(line => line === 'x' || line.includes('news at eleven'))).toEqual([])
  })
}

test('DR21 a null news says nothing and writes nothing (tests pin JEB_NEWS so live build news never leaks in)', { timeoutMs: 60_000 }, async ($, on) => {
  rig(on, {}, START, { JEB_CREATIVITY: 'off' })
  await start($)
  await clk.settle()
  expect(stored()?.newsSeen ?? []).toEqual([])
})

test('DR21 a long news line is cut to 80 characters', { timeoutMs: 60_000 }, async ($, on) => {
  rig(on, {}, START, NEWS_ENV({ id: 'long', line: 'w'.repeat(200) }))
  await start($)
  await clk.settle()
  expect(tally.lines).toContain('w'.repeat(80))
  expect(tally.lines.some(line => line.length > 80 && line.startsWith('www'))).toBe(false)
})

test('DR21 no news in a run nobody is at', { timeoutMs: 60_000 }, async ($, on) => {
  rig(on, {}, START, NEWS_ENV({ id: 'quiet', line: 'Should not be said.' }))
  await start($, false)
  await clk.settle()
  expect(tally.lines).not.toContain('Should not be said.')
  expect(stored()?.newsSeen ?? []).toEqual([])
})

// ---- the almanac ----

test('DR22 an almanac line is live for its week and gone after it', () => {
  const line = 'Fog in August means snow come winter.'
  const almanac = { day: '2026-06-10', slot: 9, kind: 'almanac', name: 'fog-lore', lines: [line], sprites: [], window: null, lasts: 'week', made: 'haiku', arc: '', step: 0, festival: '' }
  expect(almanacLines([almanac as any], new Date(at(11, 13)))).toEqual([line])
  // A week and a day on it has gone: the almanac is as it was.
  expect(almanacLines([almanac as any], new Date(at(18, 12)))).toEqual([])
})
