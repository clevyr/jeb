import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import type { Anim, EventId, Material, SquareCode } from '../types'
import { dateLines, isThanksgiving, isThirdSaturdayOfOctober, moonNight, moonPhase, nthWeekday, SYNODIC } from '../hooks/almanac'
import { addHired, hireOf, MAX_AGENTS } from '../hooks/agents'
import { neighborOf, placeSeen, RADIO_LINE, sessionKeyOf } from '../hooks/anonymize'
import { beat, loadCamps, staleOf } from '../hooks/camps'
import { BUILDS, buySupplies, craftAll, mashFull, KEEPSAKES, noteEdit, queuedBuild, stackColumns, twistsPerBale } from '../hooks/crafting'
import { markGate, MAX_GATES, sweptLine, takeGate } from '../hooks/chores'
import { classify, denyRuleOf, workOf } from '../hooks/classify'
import { mcpKindOf, mcpServerOf } from '../hooks/mcp'
import { CROP_BARN, CROP_NAMES, RIPE } from '../hooks/crops'
import {
  beatsOf,
  durationOf,
  eligibleEvents,
  restOf,
  EVENT_IDS,
  pickEvent,
  weightOf,
} from '../hooks/events'
import {
  freshFarm,
  PLANTS,
  isFutureFarm,
  JAR_PRICE,
  loadFarm,
  newUnlocks,
  raidCorn,
  sellOne,
  UPGRADES,
} from '../hooks/homestead'
import {
  APPLE_KEEP,
  applySale,
  CORN_KEEP,
  CUSTOMER_IDS,
  eligibleCustomers,
  fillSale,
  FAIR_WEIGHT,
  loadFor,
  pickCustomer,
  planSale,
  PRODUCTS,
  reserveBales,
  sellTo,
  STICKS_PER_BALE,
  surplusOf,
  wantsOf,
} from '../hooks/market'
import { readOptions } from '../hooks/options'
import { freshSession, journalLine, squareFor, stitchFarm, stitchFromBeat, stitchOf } from '../hooks/quilt'
import type { SessionRec, Stitch } from '../hooks/quilt'
import { limitCrossings, limitLevel, reactTo } from '../hooks/reactions'
import { bagPick, MONTH_CATEGORIES, SAYINGS } from '../hooks/sayings'
import type { SayingCategory } from '../hooks/sayings'
import { isShip, stripQuoted } from '../hooks/ship'
import {
  DEAL_TICKS,
  FIRST_VISIT_MS,
  isMailDue,
  NEXT_VISIT_MS,
  pickVisit,
  sellVisit,
  spanOf,
  VISIT_SPECS,
  visitorsFor,
} from '../hooks/visits'
import { cleanText, pickWeighted, plural } from '../hooks/util'
import {
  BAD_BATCH_LINE,
  buildingOf,
  CLEAN_LINE,
  COUNTY_RAIN_LINE,
  cowLine,
  DENY_LINES,
  DROUGHT_LINE,
  FIRST_RAIN_LINE,
  HAND_WATER_LINE,
  HOED_LINE,
  PHPSTAN_LINE,
  plotFor,
  RAIN_LINE,
  RUN_LINE,
  STREAK_LINE,
  TEST_RUN_LINE,
  ticketKeys,
  UP_LINE,
  WEEDS_LINE,
  WORKDAY_LINES,
} from '../hooks/workday'

// Most of the older tests read the bubble after a call: they run at today's level, chatty.
const CHATTY = { options: { talk: 'chatty' } } as const
// The hooks a security plugin may skip are registered only with this option on.
const HOOKS = { options: { hookReactions: true } } as const
const CHATTY_HOOKS = { options: { talk: 'chatty', hookReactions: true } } as const


const usage = (output: number, input: number) => ({
  model: 'm',
  input_tokens: input,
  output_tokens: output,
  cache_read_input_tokens: 0,
  cache_creation_input_tokens: 0,
})

// A turn's end, then whatever Jeb left running behind it.
const finish = async ($: any, u: ReturnType<typeof usage>, agentId?: string) => {
  await $.turn.complete({
    answer: '',
    durationMs: 1,
    isAborted: false,
    turnId: 't',
    reason: 'answer',
    usage: u,
    ...(agentId ? { agentId } : {}),
  })
  await clk.settle()
}

// The turn begins (main loop unless an agent id is given).
const begin = async ($: any, agentId?: string) => {
  await $.turn.start({ text: '', turnId: 't', ...(agentId ? { agentId } : {}) })
  await clk.settle()
}

// Jeb's hooks do their bookkeeping after the call has gone back, so each act
// is followed by the clock settling what it left running.
const call = async ($: any, input: object) => {
  const result = await $.tool.call(input)
  await clk.settle()

  return result
}

const submit = async ($: any, event: object) => {
  const result = await $.prompt.submit(event)
  await clk.settle()

  return result
}

// Stands for the engine beneath the mod; the clock moves only when told.
// A fixed Wednesday afternoon in June, so the date-driven bits hold still.
// Ambient visits arrive at random: off (JEB_VISITS=off) unless a test sets `visits.on`
// before it builds the engine (a test that does sets it back when it is done).
const visits = { on: false, draw: '' }

const JUNE_NOON = new Date(2026, 5, 10, 14, 0, 0).getTime()

// The anonymizer under a known salt (see anonymize.ts): a farm seeded with it, and
// what a session id, a camp's name and a ticket key become under it.
const SALT = '0123456789abcdef'
const saltFarm = (over: object = {}) => ({ ...freshFarm(), anonSalt: SALT, ...over })
const keyOf = (id: string) => sessionKeyOf(SALT, id)
const placeOf = (name: string) => placeSeen(SALT, name, [])
const cowOf = (key: string) => neighborOf(SALT, key)
// Another session's heartbeat as this Jeb writes them: a hashed key and a place.
const OTHER = 'a1a1a1a1a1a1'
const OTHER2 = 'b2b2b2b2b2b2'

// Every line Jeb put in the bubble (the `say` atom's writes), oldest first.
const spoken: string[] = []

// Watchers of every atom write, one at a time in the order they were added, for the test running now.
// The hook module takes one state.set handler, so the engine owns it and the helpers add to this list.
const stateTaps: Array<(e: any) => void | Promise<void>> = []
const tap = (watcher: (e: any) => void | Promise<void>) => {
  stateTaps.push(watcher)
}

// The mock clock of the test running now.
let clk: MockClock

// The store beneath the plugins, kept here so a test can read it and slow it.
const world = {
  db: new Map<string, unknown>(),
  isStoreSlow: false,
  isStoreFailing: false,
  // A store key whose writes fail, and what runs right after a write lands (the
  // other session of a race writing at the same moment).
  failKey: undefined as string | undefined,
  afterSet: undefined as ((key: string) => void) | undefined,
}

const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

const engine = (
  on: Parameters<Parameters<typeof test>[1]>[1],
  answer: object | ((_: unknown, e: any) => unknown) = { result: {} },
  entries: Record<string, unknown> = {},
  now: number = JUNE_NOON,
) => {
  spoken.length = 0
  stateTaps.length = 0
  world.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  world.isStoreSlow = false
  world.isStoreFailing = false
  world.failKey = undefined
  world.afterSet = undefined
  on('store.get', (_, e) => ({ value: copy(world.db.get((e as { key: string }).key)) }))
  on('store.set', async (_, e) => {
    if (world.isStoreSlow) {
      await clk.sleep(10_000)
    }
    if (world.isStoreFailing) {
      throw new Error('disk full')
    }
    const { key, value } = e as { key: string; value: unknown }
    if (world.failKey === key) {
      throw new Error('disk full')
    }
    world.db.set(key, copy(value))
    world.afterSet?.(key)

    return { value: undefined }
  })
  on('store.delete', (_, e) => {
    world.db.delete((e as { key: string }).key)

    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...world.db.keys()] }))
  const clock = mock.clock(on, { now })
  clk = clock
  // The little things (JEB_UNLOCKS) are left out of these older tests: one turning up at a random moment says a line.
  mock.env(
    on,
    visits.on
      ? { HOME: '/home/jeb', JEB_VISITS: visits.draw, JEB_UNLOCKS: 'off', JEB_CREATIVITY: 'off', JEB_NEWS: 'null' }
      : { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_CREATIVITY: 'off', JEB_NEWS: 'null' },
  )
  // The bubble's every line, as Jeb writes it; the write goes on as it came.
  on('state.set', async (_, e, next) => {
    if ((e as { key?: string }).key === 'say') {
      spoken.push(String(((e as { value?: { line?: unknown } }).value)?.line ?? ''))
    }
    for (const watcher of stateTaps) {
      await watcher(e)
    }

    return next(e)
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('tool.call', typeof answer === 'function' ? (answer as any) : () => answer)
  on('turn.start', (_, e) => ({ turnId: (e as { turnId: string }).turnId }))
  on('turn.complete', () => ({ text: '' }))

  return clock
}

// Wakes the scene the way a touch of the person's did: a meta prompt reaches the hook, which says nothing.
const poke = ($: any) => submit($, { text: '', isMeta: true })

const start = ($: any) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

const PRODUCT_NAMES = {
  appleCinnamon: 'apple cinnamon',
  whiteLightning: 'white lightning',
  tobacco: 'tobacco',
  apples: 'apples',
  corn: 'corn',
  appleButter: 'apple butter',
  twists: 'tobacco twists',
  agedWhiskey: 'aged whiskey',
}

// The farm as the store holds it, in the words the older tests read it in.
const tally = async (_$?: unknown) => {
  const farm = (world.db.get('farm') ?? freshFarm()) as ReturnType<typeof freshFarm>
  const { barn, shelf, still, lifetime, ledger } = farm
  const fields = CROP_NAMES.map(
    crop => `${crop} ${farm.crops[crop].reduce((sum, stage) => sum + stage, 0)}/${PLANTS * RIPE}`,
  ).join(', ')
  const products = (Object.entries(ledger.byProduct) as [keyof typeof PRODUCT_NAMES, number][])
    .filter(([, dollars]) => dollars > 0)
    .map(([product, dollars]) => `${PRODUCT_NAMES[product]} $${dollars}`)
    .join(', ')

  return (
    `barn holds ${plural(barn.bales, 'bale')} of tobacco, ${barn.corn} bu corn, ` +
    `${barn.apples} bu apples and ${plural(barn.sticks, 'cinnamon stick')}. ` +
    `Shelf: ${shelf.lightning} white lightning, ${shelf.appleCinnamon} apple cinnamon. ` +
    `Tobacco: ${plural(lifetime.bales, 'bale')} cut, ${lifetime.balesTraded} traded for cinnamon, ` +
    `${barn.bales} in the barn. ` +
    `Still: batch ${still.steps}/${mashFull(farm)}. Fields (growth stages): ${fields}. ` +
    `Deliveries: ${plural(ledger.deliveries, 'trip')}, ${plural(ledger.jarsSold, 'jar')} sold, $${ledger.total}. ` +
    `Cash: $${ledger.cash} on hand of $${ledger.total} earned, $${ledger.spent} spent` +
    `${ledger.spent > 0 ? ` (sugar $${ledger.byPurchase.sugar}, copper $${ledger.byPurchase.copper})` : ''}. ` +
    `By product: ${products || 'none'}. ` +
    `${ledger.ribbons > 0 ? `Ribbons: 🎀x${ledger.ribbons}. ` : ''}` +
    `Lifetime: ${lifetime.outputTokens} output tokens, ${lifetime.inputTokens} input tokens, ` +
    `${Math.round(lifetime.workMs / 60_000)} min of working time.` +
    (farm.upgrades.length > 0 ? ` Homestead: ${farm.upgrades.join(', ')}.` : '')
  )
}

// The last line Jeb put in the bubble.
const quip = async (_$?: unknown, _ui?: unknown) => spoken.at(-1) ?? ''

const said = (category: SayingCategory, line: string) =>
  (SAYINGS[category] as readonly string[]).some(candidate => line.startsWith(candidate))

const farmWith = (shelf: { lightning: number; appleCinnamon: number }) => ({
  version: 3,
  crops: {
    tobacco: Array(8).fill(0),
    corn: Array(8).fill(0),
    apples: Array(8).fill(0),
  },
  progress: { tobacco: 0, corn: 0, apples: 0 },
  barn: { bales: 0, corn: 0, apples: 0, sticks: 0 },
  still: { steps: 0, hasBatch: false },
  shelf,
  lifetime: { outputTokens: 0, inputTokens: 0, workMs: 0 },
  delivery: { deliveries: 0, jarsSold: 0, dollars: 0 },
})

test('turn usage grows corn and apples, and fractions carry over', async ($, on) => {
  engine(on)
  await start($)

  // 1000 output = 2 corn stages (+200 left); 150000 input = 6 apple stages.
  await finish($, usage(1000, 150_000))
  let text = await tally($)
  expect(text).toContain('corn 2/24')
  expect(text).toContain('apples 6/24')

  // The 200 carried over plus 200 more is one more stage.
  await finish($, usage(200, 0))
  text = await tally($)
  expect(text).toContain('corn 3/24')
  expect(text).toContain('1200 output tokens')

  // A subagent's usage counts too.
  await finish($, usage(400, 0), 'agent-1')
  expect(await tally($)).toContain('corn 4/24')
})

test('busy time grows tobacco', async ($, on) => {
  const clock = engine(on)
  await start($)
  await begin($)
  await call($, { tool: 'Read', file_path: '/a' })

  await clock.advance(19_000)
  expect(await tally($)).toContain('tobacco 0/24')
  await clock.advance(1_000)
  expect(await tally($)).toContain('tobacco 1/24')

  // Idle once the turn ends: no more growth.
  await finish($, usage(0, 0))
  await clock.advance(60_000)
  expect(await tally($)).toContain('tobacco 1/24')
})

test('the still stays dry without corn, makes lightning from it and sours on failure', CHATTY, async ($, on) => {
  engine(on)
  await start($)

  await call($, { tool: 'Bash', command: 'ls' })
  expect(said('dry', await quip($))).toBe(true)

  // 9600 output tokens = 24 stages = one bushel of corn.
  await finish($, usage(9600, 0))
  expect(await tally($)).toContain('0 bu apples')
  expect(await tally($)).toContain('1 bu corn')

  for (let i = 0; i < 6; i += 1) {
    await call($, { tool: 'Bash', command: 'ls' })
  }
  const text = await tally($)
  expect(text).toContain('0 bu corn')
  expect(text).toContain('1 white lightning')
  expect(text).toContain('batch 0/6')
})

test('a failed run sours the batch and spends the corn', CHATTY, async ($, on) => {
  const answer = { result: {}, isError: false }
  engine(on, answer)
  await start($)
  await finish($, usage(9600, 0))
  await call($, { tool: 'Bash', command: 'ls' })
  expect(await tally($)).toContain('batch 1/6')

  answer.isError = true
  await call($, { tool: 'Bash', command: 'false' })
  const text = await tally($)
  expect(text).toContain('batch 0/6')
  expect(text).toContain('0 bu corn')
  expect(said('sour', await quip($))).toBe(true)
})

test('lightning, apples and a traded bale make apple cinnamon', async ($, on) => {
  const clock = engine(on)
  await start($)

  // 24 stages of tobacco at 20s each = one bale, earned while busy.
  await begin($)
  await call($, { tool: 'Read', file_path: '/a' })
  await clock.advance(480_000)
  // One bushel of corn and one of apples.
  await finish($, usage(9600, 600_000))
  expect(await tally($)).toContain('1 bale of tobacco')

  for (let i = 0; i < 6; i += 1) {
    await call($, { tool: 'Bash', command: 'ls' })
  }
  const text = await tally($)
  expect(text).toContain('0 bales of tobacco')
  expect(text).toContain('7 cinnamon sticks')
  expect(text).toContain('0 white lightning, 1 apple cinnamon')

})


test('isShip knows what ships', () => {
  for (const command of [
    'git push',
    'git commit -m x',
    'gh pr create',
    'gh pr merge 12',
    'npm publish',
    './deploy.sh',
    'docker push img',
    'cd app && git push origin main',
    'fly deploy',
    'vercel --prod',
    'rtk git commit -m x',
    'rtk proxy git push',
  ]) {
    expect(isShip(command)).toBe(true)
  }
  for (const command of ['git status', 'git log', 'npm test', 'gh pr view', 'echo "git push"', 'rtk git status']) {
    expect(isShip(command)).toBe(false)
  }
})

test('a successful push sends the truck; a failed one does not; it sells to one buyer', async ($, on) => {
  const answer = { result: {}, isError: true }
  const clock = engine(on, answer, { farm: farmWith({ lightning: 0, appleCinnamon: 1 }) })
  await start($)

  await call($, { tool: 'Bash', command: 'git push' })

  // With one jar only Miss Opal will buy (the store wants two): a run now sells
  // to one buyer, not "up to two jars" to the town.
  answer.isError = false
  await call($, { tool: 'Bash', command: 'git push' })

  await clock.advance(9_000)
  const text = await tally($)
  expect(text).toContain('1 trip, 1 jar sold, $25')
  expect(text).toContain('0 apple cinnamon')
})

test('a second ship while the truck is out queues another load', async ($, on) => {
  // A Saturday afternoon: the store is shut, so Miss Opal is the only buyer, a jar a run.
  const clock = engine(on, { result: {} }, { farm: farmWith({ lightning: 0, appleCinnamon: 4 }) }, new Date(2026, 5, 13, 14).getTime())
  await start($)

  await call($, { tool: 'Bash', command: 'git commit -m x' })
  await call($, { tool: 'Bash', command: 'git push' })
  await clock.advance(9_000)
  expect(await tally($)).toContain('1 trip, 1 jar sold, $25')
  await clock.advance(9_000)
  expect(await tally($)).toContain('2 trips, 2 jars sold, $50')
})

test('bagPick deals every line before repeating', () => {
  for (const category of ['denied', 'deliveryOut', 'idle'] as const) {
    const size = SAYINGS[category].length
    for (let round = 0; round < 2; round += 1) {
      const dealt = Array.from({ length: size }, () => bagPick(category))
      expect(new Set(dealt).size).toBe(size)
    }
  }
})


test('a v1 store migrates, keeping bales and jars', async ($, on) => {
  engine(on, { result: {} }, { farm: { plants: Array(18).fill(1), bales: 3, mash: 2, jars: 4 } })
  await start($)

  const text = await tally($)
  expect(text).toContain('3 bales of tobacco')
  expect(text).toContain('4 apple cinnamon')
  expect(text).toContain('tobacco 0/24')
  expect(text).toContain('$0')
})

test('a v2 store migrates with an empty delivery book', async ($, on) => {
  const { delivery, ...v2 } = farmWith({ lightning: 1, appleCinnamon: 2 })
  void delivery
  engine(on, { result: {} }, { farm: { ...v2, version: 2, barn: { ...v2.barn, bales: 5 } } })
  await start($)

  const text = await tally($)
  expect(text).toContain('5 bales of tobacco')
  expect(text).toContain('1 white lightning, 2 apple cinnamon')
  expect(text).toContain('0 trips, 0 jars sold, $0')
})

// ---------------------------------------------------------------- v4 ----

const DAY = 86_400_000


// A time near a new or full moon whose local hour is 23.
const moonNightAt = (kind: 'dark' | 'full') => {
  const base = Date.UTC(2000, 0, 6, 14, 24) + (kind === 'full' ? 14.765 * DAY : 0) + 400 * SYNODIC * DAY
  for (const off of [0, -1, 1, -2, 2]) {
    const d = new Date(base + off * DAY)
    d.setHours(23, 0, 0, 0)
    if (moonNight(d) === kind) {
      return d
    }
  }
  throw new Error('no moon night found')
}

test('almanac: the moon phase follows the mean lunation', () => {
  const newMoon = new Date(Date.UTC(2000, 0, 6, 18, 14))
  const phase = moonPhase(newMoon).phase
  expect(Math.min(phase, 1 - phase)).toBeLessThan(0.03)
  expect(moonPhase(newMoon).name).toBe('new')
  expect(moonPhase(newMoon).emoji).toBe('🌑')

  const full = moonPhase(new Date(newMoon.getTime() + 14.77 * DAY))
  expect(Math.abs(full.phase - 0.5)).toBeLessThan(0.03)
  expect(full.name).toBe('full')
  expect(full.emoji).toBe('🌕')

})


test('almanac: new-moon and full-moon nights, third Saturday and Thanksgiving', () => {
  expect(moonNight(moonNightAt('dark'))).toBe('dark')
  expect(moonNight(moonNightAt('full'))).toBe('full')
  const noon = moonNightAt('dark')
  noon.setHours(13)
  expect(moonNight(noon)).toBeUndefined()

  expect(nthWeekday(2026, 10, 4, 4)).toBe(26)
  expect(isThanksgiving(new Date(2026, 10, 26))).toBe(true)
  expect(isThirdSaturdayOfOctober(new Date(2026, 9, 17))).toBe(true)
  expect(isThirdSaturdayOfOctober(new Date(2026, 9, 10))).toBe(false)
})


// A ui.render hook beneath the plugin that records the props it is handed.
const recorder = (on: any) => {
  const got: { props?: any } = {}
  on('ui.render', ($: any, e: any) => {
    got.props = e.props
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  return got
}


const hint = (extra: object = {}) =>
  ({
    plugin: 'jeb',
    component: 'PromptHint',
    surface: 'terminal',
    props: { isDraft: false, isWorking: false, hint: '? for shortcuts', ...extra },
  }) as const

const modes = (labels: string[]) =>
  ({ plugin: 'jeb', component: 'SessionMode', surface: 'terminal', props: { modes: labels } }) as const


test('userConfig defaults: creativity and talk on, hook reactions off, each read from the options', () => {
  expect(readOptions(undefined)).toEqual({ creativity: true, talk: 'ambient', hookReactions: false })
  expect(readOptions({ creativity: false, talk: 'silent', hookReactions: true })).toEqual({
    creativity: false,
    talk: 'silent',
    hookReactions: true,
  })
  // Only a real true turns the hook reactions on.
  expect(readOptions({ hookReactions: 'yes' }).hookReactions).toBe(false)
  // A talk level outside the three counts as unset.
  expect(readOptions({ talk: 'shouting' }).talk).toBe('ambient')
})

test('the options menu: a change to talk or creativity is kept in the overrides store, and nothing else is', async ($, on) => {
  engine(on, { result: {} })
  menu(on)
  await start($)
  await $.config.set({ key: 'jeb.talk', value: 'silent' })
  await $.config.set({ key: 'jeb.creativity', value: false })
  await $.config.set({ key: 'jeb.talk', value: 'shouting' })
  await $.config.set({ key: 'jeb.hookReactions', value: true })
  expect(world.db.get('overrides')).toEqual({ talk: 'silent', creativity: false })
})

test('random events: weighted by month, hour, weekday and moon, with cooldowns', () => {
  const ctx = (now: Date, extra: object = {}) => ({ now, isBusy: false, errorStreak: 0, ...extra })
  const ids = (now: Date, extra: object = {}, blocked = new Set<EventId>()) =>
    eligibleEvents(ctx(now, extra), blocked).map(entry => entry.id)

  const june = new Date(2026, 5, 10, 14)
  for (const id of ['revenuer', 'neighbor', 'whistlepig', 'storm']) {
    expect(ids(june)).toContain(id)
  }
  expect(ids(june)).not.toContain('bear')
  expect(ids(june)).not.toContain('mothman')
  expect(ids(new Date(2026, 5, 10, 22))).toContain('bugs')
  expect(ids(new Date(2026, 5, 10, 22))).toContain('mothman')
  expect(ids(new Date(2026, 9, 14, 12))).toContain('bear')
  expect(ids(new Date(2026, 9, 14, 12))).not.toContain('applebutter')
  expect(ids(new Date(2026, 9, 17, 12))).toContain('applebutter')
  expect(ids(new Date(2026, 9, 17, 12))).toContain('parachute')
  expect(ids(new Date(2026, 9, 24, 12))).not.toContain('parachute')
  expect(ids(new Date(2026, 5, 14, 10))).toContain('bells')
  expect(ids(new Date(2026, 5, 13, 10))).not.toContain('bells')
  expect(ids(new Date(2026, 7, 5, 7))).toContain('fog')
  expect(ids(new Date(2026, 3, 8, 12))).toContain('turkeys')
  expect(ids(new Date(2026, 6, 8, 12))).toContain('hornworm')
  expect(ids(new Date(2026, 3, 8, 12))).toContain('bees')
  expect(ids(new Date(2026, 4, 20, 9))).toContain('bees')
  expect(ids(new Date(2026, 4, 20, 22))).not.toContain('bees')
  expect(ids(new Date(2026, 5, 10, 12))).not.toContain('bees')
  expect(ids(new Date(2026, 8, 19, 12))).toContain('sorghum')
  expect(ids(new Date(2026, 9, 14, 12))).toContain('sorghum')
  expect(ids(new Date(2026, 9, 14, 22))).not.toContain('sorghum')
  expect(ids(new Date(2026, 5, 10, 12))).not.toContain('sorghum')
  expect(ids(new Date(2026, 9, 14, 18))).toContain('track')
  expect(ids(new Date(2026, 0, 14, 12), { errorStreak: 3 })).toContain('storm')
  expect(ids(new Date(2026, 0, 14, 12))).not.toContain('storm')
  expect(ids(june, {}, new Set<EventId>(['revenuer']))).not.toContain('revenuer')

  const halloween = ctx(new Date(2026, 9, 31, 23))
  const plain = ctx(new Date(2026, 9, 14, 23))
  expect(weightOf('mothman', halloween)).toBeGreaterThan(weightOf('mothman', plain))
  expect(weightOf('mothman', ctx(new Date(2026, 8, 25, 23)))).toBeGreaterThan(
    weightOf('mothman', plain),
  )

  // Weighted draws are deterministic given the dice.
  expect(pickEvent(ctx(june), new Set(), () => 0)).toBe('revenuer')
  expect(pickEvent(ctx(june), new Set(), () => 0.9999)).toBeDefined()
  for (const id of EVENT_IDS) {
    const length = durationOf(id, () => 0.5)
    // 500 ms ticks: 8 to 20 seconds.
    expect(length * 500).toBeGreaterThanOrEqual(8_000)
    expect(length * 500).toBeLessThanOrEqual(60_000)
  }
})


test('an event starts after three idle minutes, speaks, and the band stays W wide through it', CHATTY, async ($, on) => {
  const clock = engine(on)
  on('prompt.submit', (_, e) => e)
  await start($)

  const firstLines = EVENT_IDS.flatMap(id => [
    beatsOf(id, false)[0]?.line ?? '',
    beatsOf(id, true)[0]?.line ?? '',
  ])
  // The scene goes still after two idle minutes and no happening rolls then, so a
  // /jeb tally (activity) comes at 100 s to keep the farm awake.
  await clock.advance(100_000)
  await poke($)
  await clock.advance(81_000)
  expect(firstLines).toContain(await quip($))

  await clock.advance(21_000)
})

test('a neighbor buys a jar and a whistle pig takes a stage of corn', () => {
  const full = { ...freshFarm(), shelf: { lightning: 0, appleCinnamon: 2 } }
  const sold = sellOne(full, new Date(JUNE_NOON))
  expect(sold.shelf.appleCinnamon).toBe(1)
  expect(sold.ledger.jarsSold).toBe(1)
  expect(sold.ledger.total).toBe(25)
  expect(sold.ledger.byCustomer.opal).toBe(25)
  const empty = freshFarm()
  expect(sellOne(empty, new Date(JUNE_NOON))).toBe(empty)

  const ripe = { ...freshFarm(), crops: { ...freshFarm().crops, corn: [3, 3, 3, 3, 3, 3, 3, 3] } }
  const raided = raidCorn(ripe, () => 0.5)
  expect(raided.crops.corn.reduce((a, b) => a + b, 0)).toBe(23)
  const bare = raidCorn(freshFarm(), () => 0)
  expect(bare.crops.corn.every(stage => stage === 0)).toBe(true)
  expect(beatsOf('neighbor', true)[1]?.effect).toBe('sell')
  expect(beatsOf('neighbor', false)[1]?.line).toBe('Next batch, Miss Opal.')
  expect(beatsOf('whistlepig', true)[1]?.effect).toBe('raid')
  expect(beatsOf('mothman', true)[0]?.line).toBe("Saw red eyes on the ridge. Probably nothin'.")
  expect(beatsOf('bees', false).map(beat => beat.line)).toEqual([
    "Tellin' the bees the news, same as Granny did.",
    "Hummin' back. Reckon they heard.",
  ])
  expect(beatsOf('sorghum', false).map(beat => beat.line)).toEqual([
    "Sorghum's a-boilin'. Keep her stirred.",
    'Skim that green off. Syrup is near.',
  ])
  expect(beatsOf('revenuer', true).map(beat => beat.line)).toEqual([
    'Revenuer on the road. Tarp on the still!',
    'Just tomatoes, officer.',
    'Coast is clear.',
  ])
})

test('the truck coughs for a second on a cold winter morning, then goes', async ($, on) => {
  const clock = engine(
    on,
    { result: {} },
    { farm: farmWith({ lightning: 0, appleCinnamon: 2 }) },
    new Date(2026, 0, 12, 7, 0, 0).getTime(),
  )
  await start($)
  await call($, { tool: 'Bash', command: 'git push' })
  expect(await quip($)).toBe('Gotta mash the pedal three times.')
  await clock.advance(500)
  await clock.advance(1_500)
  await clock.advance(9_000)
  expect(await tally($)).toContain('1 trip')
})


test('holidays: pumpkins, turkey, Christmas, Groundhog Day and the date lines', () => {

  const ripeApples = { ...freshFarm(), crops: { ...freshFarm().crops, apples: Array(8).fill(3) } }


  expect(dateLines(new Date(2026, 0, 1, 12))).toContain('New year. Same holler.')
  expect(dateLines(new Date(2026, 5, 20, 12)).join(' ')).toContain('Montani Semper Liberi')
  expect(dateLines(new Date(2026, 1, 2, 12))[0]).toMatch(/shadow/)
  expect(dateLines(new Date(2026, 3, 8, 12)).join(' ')).toContain("Smell'll clear a church.")
  expect(dateLines(new Date(2026, 2, 8, 19)).join(' ')).toContain('Spring peepers')
  expect(dateLines(new Date(2026, 2, 8, 12)).join(' ')).not.toContain('Spring peepers')
})

test('the New Year line greets the day', async ($, on) => {
  engine(on, { result: {} }, {}, new Date(2027, 0, 1, 12).getTime())
  await start($)
  expect(await quip($)).toBe('New year. Same holler.')
})

test('farm v6: migrations from v3, v2 and v1, and the upgrade thresholds', () => {
  const v3 = loadFarm({
    ...farmWith({ lightning: 0, appleCinnamon: 1 }),
    barn: { bales: 4, corn: 0, apples: 0, sticks: 0 },
  })
  expect(v3?.version).toBe(10)
  expect(v3?.upgrades).toEqual([])
  expect(v3?.milestones).toEqual([])
  expect(v3?.lastProof).toBe(0)
  expect(v3?.bestProof).toBe(0)
  expect(v3?.lifetime.bales).toBe(4)
  expect(loadFarm({ plants: Array(18).fill(0), bales: 2, jars: 3 })?.version).toBe(10)
  expect(loadFarm(undefined)).toBeUndefined()

  const dollars = (n: number, upgrades: string[] = []) => ({
    ...freshFarm(),
    upgrades,
    ledger: { ...freshFarm().ledger, total: n },
  })
  expect(newUnlocks(dollars(49)).upgrades.length).toBe(0)
  expect(newUnlocks(dollars(50)).upgrades.map(u => u.id)).toEqual(['mailbox'])
  expect(newUnlocks(dollars(150, ['mailbox'])).upgrades.map(u => u.id)).toEqual(['chair'])
  expect(UPGRADES.map(u => u.at)).toEqual([50, 150, 300, 500, 1000, 2000])
  expect(newUnlocks(dollars(5000)).upgrades.length).toBe(6)

  const bales = { ...freshFarm(), lifetime: { ...freshFarm().lifetime, bales: 10 } }
  expect(newUnlocks(bales).milestones.map(m => m.id)).toEqual(['bale10'])
  expect(newUnlocks({ ...bales, milestones: ['bale10'] }).milestones.length).toBe(0)
})

test('crossing a dollar mark toasts exactly once and Jeb says so', async ($, on) => {
  const farm = {
    ...freshFarm(),
    shelf: { lightning: 0, appleCinnamon: 4 },
    ledger: { ...freshFarm().ledger, jarsSold: 8, total: 40 },
  }
  // A Saturday afternoon: Miss Opal is the only buyer, a jar a run.
  const clock = engine(on, { result: {} }, { farm }, new Date(2026, 5, 13, 14).getTime())
  await start($)
  await call($, { tool: 'Bash', command: 'git push' })
  await clock.advance(9_000)
  await call($, { tool: 'Bash', command: 'git push' })
  await clock.advance(9_000)

  expect(await tally($)).toContain('Homestead: mailbox')

  await call($, { tool: 'Bash', command: 'git push' })
  await clock.advance(9_000)
})


test('prompt reactions read the prompt and never change it', () => {
  expect(reactTo('Thanks a lot').line).toBe("Don't mention it.")
  expect(reactTo('thank you!').line).toBe("Don't mention it.")
  expect(reactTo('well damn').line).toBe("Language! Mamaw'd wash your mouth out with lye soap.")
  expect(reactTo('what is moonshine').wink).toBe(true)
  expect(reactTo('Shine on').wink).toBe(true)
  expect(reactTo('good boy').wag).toBe(true)
  expect(reactTo('where is BLUE').wag).toBe(true)
  expect(reactTo('hey Jeb').line).toBe("That's my name, don't wear it out.")
  expect(reactTo('deploy it').puff).toBe(true)
  expect(reactTo('ship it').puff).toBe(true)
  expect(reactTo('deploy this friday').line).toBe("Deployin' on a Friday? Bless your heart.")
  expect(reactTo('fix the shell script')).toEqual({})
})

test('every prompt.submit hook returns the event unchanged', async ($, on) => {
  engine(on)
  let heardAtEngine: unknown
  on('prompt.submit', (_, e) => {
    heardAtEngine = e

    return e
  })
  await start($)

  for (const text of [
    'thanks',
    'damn it',
    'make some moonshine',
    'good boy, blue',
    'jeb, please deploy on friday',
    'plain old prompt',
  ]) {
    const event = { text }
    const result = await submit($, event)
    expect(heardAtEngine).toEqual({ text })
    expect(result).toEqual({ text })
    expect(event).toEqual({ text })
  }
})

test('prompts shape the bubble, the wink and the truck warm-up only', async ($, on) => {
  engine(on)
  on('prompt.submit', (_, e) => e)
  await start($)
  await submit($, { text: 'Thanks!' })
  expect(await quip($)).toBe("Don't mention it.")
  await submit($, { text: 'deploy on friday' })
  expect(await quip($)).toBe("Deployin' on a Friday? Bless your heart.")
  await submit($, { text: 'moonshine?' })
  await submit($, { text: 'good boy' })
  // Nothing was delivered by the warm-up.
  expect(await tally($)).toContain('0 trips')
})

test('usage reactions: once per crossing of 80 and 95 percent', async ($, on) => {
  engine(on)
  on('session.measure', (_, e) => ({ changed: e.changed }))
  await start($)
  const measure = (percentUsed: number) =>
    $.session.measure({
      context: { window: 200_000 },
      rateLimits: [{ kind: 'five_hour', percentUsed }],
      changed: ['rateLimits'],
    })

  const low = "Mash barrel's gettin' low, partner."
  const lows = () => spoken.filter(line => line === low).length
  await measure(40)
  expect(lows()).toBe(0)
  await measure(81)
  expect(lows()).toBe(1)
  await measure(83)
  expect(lows()).toBe(1)
  await measure(96)
  expect(lows()).toBe(2)
  await measure(97)
  expect(lows()).toBe(2)
  // Dropping back under and crossing again counts as a new crossing.
  await measure(10)
  await measure(85)
  expect(lows()).toBe(3)

  expect(limitLevel(79.9)).toBe(0)
  expect(limitLevel(80)).toBe(1)
  expect(limitLevel(95)).toBe(2)
  expect(limitCrossings({}, [{ kind: 'seven_day', percentUsed: 99 }]).isCrossed).toBe(true)
})


test('the new bags: seasons and more, 70 lines and up', () => {
  const fresh: SayingCategory[] = [...MONTH_CATEGORIES, 'idleMore']
  const count = fresh.reduce((sum, category) => sum + SAYINGS[category].length, 0)
  expect(count).toBeGreaterThanOrEqual(70)
  expect(MONTH_CATEGORIES.length).toBe(12)
  for (const category of MONTH_CATEGORIES) {
    expect(SAYINGS[category].length).toBeGreaterThanOrEqual(4)
  }
})


// ------------------------------------------------------------- v4.1 ----
// Review fixes (A1-A15), toggles (C) and the Do Not Disturb mute (D).

test('A1 busy is a main-loop turn: turn.start sets it, a main turn.complete clears it, a tool call does not', async ($, on) => {
  const clock = engine(on)
  await start($)

  // A tool call alone does not make Jeb busy: no tobacco grows.
  await call($, { tool: 'Read', file_path: '/a' })
  await clock.advance(40_000)
  expect(await tally($)).toContain('tobacco 0/24')

  await begin($)
  await clock.advance(20_000)
  expect(await tally($)).toContain('tobacco 1/24')

  // A subagent's turn ends without ending Jeb's.
  await finish($, usage(0, 0), 'agent-1')
  await clock.advance(20_000)
  expect(await tally($)).toContain('tobacco 2/24')

  await finish($, usage(0, 0))
  await clock.advance(60_000)
  expect(await tally($)).toContain('tobacco 2/24')

  // A subagent's turn starting does not make him busy either.
  await begin($, 'agent-2')
  await clock.advance(40_000)
  expect(await tally($)).toContain('tobacco 2/24')
})


test('A2 prompt.submit ignores slash commands and meta prompts, and a mid-turn submit keeps the turn', CHATTY, async ($, on) => {
  const clock = engine(on)
  on('prompt.submit', (_, e) => e)
  const got = recorder(on)
  await start($)
  await begin($)

  // /jeb thanks: no reaction, the bubble stays as it was.
  const before = await quip($)
  await submit($, { text: '/jeb thanks damn', command: { name: 'jeb', args: 'thanks damn' } })
  expect(await quip($)).toBe(before)
  await submit($, { text: 'thanks', isMeta: true })
  expect(await quip($)).toBe(before)
  await submit($, { text: 'thanks' })
  expect(await quip($)).toBe("Don't mention it.")

  // Prompts landing mid-turn leave the turn running.
  for (let i = 0; i < 12; i += 1) {
    await submit($, { text: 'carry on', turnId: 't' })
  }

  // And the clock of the turn keeps running: the long-turn line still comes at two minutes.
  await clock.advance(110_000)
  await submit($, { text: 'one more', turnId: 't' })
  await clock.advance(11_000)
  expect(said('long', await quip($))).toBe(true)
})

test('A3 the idle line comes every 60 idle seconds whatever the phase of the clock', CHATTY, async ($, on) => {
  const clock = engine(on)
  await start($)
  await begin($)
  await clock.advance(500)
  await finish($, usage(0, 0))
  expect(said('done', await quip($))).toBe(true)

  await clock.advance(60_500)
  expect(said('done', await quip($))).toBe(false)
})

// Every character past ASCII that a bubble can carry: a wide glyph is in WIDE,
// the rest are known one-column symbols.


test('A5 two sessions on one store: progress from the other session survives a save', async ($, on) => {
  engine(on)
  await start($)
  // Another session earned this since this one loaded.
  const other = {
    ...freshFarm(),
    barn: { ...freshFarm().barn, corn: 5 },
    lifetime: { ...freshFarm().lifetime, outputTokens: 1000 },
  }
  world.db.set('farm', other)

  await finish($, usage(500, 0))
  const text = await tally($)
  expect(text).toContain('5 bu corn')
  expect(text).toContain('1500 output tokens')
  const stored = world.db.get('farm') as typeof other
  expect(stored.barn.corn).toBe(5)
  expect(stored.lifetime.outputTokens).toBe(1500)
})

test('A6 a farm from a newer version is never overwritten and never read', async ($, on) => {
  const future = { version: 11, barn: { bales: 7 }, brand: 'new' }
  engine(on, { result: {} }, { farm: future })
  await start($)
  expect(isFutureFarm(future)).toBe(true)
  expect(loadFarm(future)).toBeUndefined()

  await finish($, usage(9600, 0))
  await call($, { tool: 'WebFetch', url: 'https://x.test' })
  expect(world.db.get('farm')).toEqual(future)
})

test('A6 a damaged farm is normalized field by field: no NaN, arrays of eight, objects filled', () => {
  const farm = loadFarm({
    version: 4,
    crops: { tobacco: [1, 'x', Number.NaN, 7, -2], corn: [], apples: Array(20).fill(2) },
    progress: { tobacco: 'abc', corn: -5 },
    barn: { bales: -3, corn: 'abc', apples: 2.7 },
    lifetime: { workMs: Number.NaN, outputTokens: Infinity },
    delivery: null,
    upgrades: ['mailbox', 'bogus', 'mailbox'],
    milestones: 'nope',
    lastProof: 'x',
  })
  expect(farm).toBeDefined()
  const walk = (value: unknown) => {
    if (typeof value === 'number') {
      expect(Number.isFinite(value)).toBe(true)
      expect(value).toBeGreaterThanOrEqual(0)
    } else if (Array.isArray(value)) {
      value.forEach(walk)
    } else if (value && typeof value === 'object') {
      Object.values(value).forEach(walk)
    }
  }
  walk(farm)
  expect(farm?.crops.tobacco).toEqual([1, 0, 0, 3, 0, 0, 0, 0])
  expect(farm?.crops.corn).toEqual(Array(8).fill(0))
  expect(farm?.crops.apples).toEqual(Array(8).fill(2))
  expect(farm?.barn).toEqual({ bales: 0, corn: 0, apples: 2, sticks: 0 })
  expect(farm?.upgrades).toEqual(['mailbox'])
  expect(farm?.milestones).toEqual([])
  expect(farm?.ledger).toEqual(freshFarm().ledger)
})

test('A7 ticks never overlap and a tick that fails is dropped', async ($, on) => {
  const clock = engine(on)
  let active = 0
  let most = 0
  let isBroken = false
  let writes = 0
  // A slow write of the anim atom, in real time so the next tick falls due first.
  tap(async e => {
    if ((e as { key: string }).key !== 'anim') {
      return
    }
    if (isBroken) {
      throw new Error('boom')
    }
    active += 1
    most = Math.max(most, active)
    await new Promise(resolve => setTimeout(resolve, 15))
    active -= 1
    writes += 1
  })
  await start($)
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await clock.advance(3_000)
  await new Promise(resolve => setTimeout(resolve, 100))
  expect(most).toBe(1)
  expect(writes).toBeGreaterThan(0)

  isBroken = true
  await clock.advance(2_000)
  isBroken = false
  await new Promise(resolve => setTimeout(resolve, 50))
  const before = writes
  await clock.advance(3_000)
  await new Promise(resolve => setTimeout(resolve, 100))
  expect(writes).toBeGreaterThan(before)
})

test('A8 an upgrade is toasted once even when two saves ask at the same moment', async ($, on) => {
  const farm = { ...freshFarm(), ledger: { ...freshFarm().ledger, total: 60 } }
  engine(on, { result: {} }, { farm })
  await start($)
  await Promise.all([finish($, usage(10, 0)), finish($, usage(10, 0))])
  await clk.settle()
  expect((await tally($)).match(/mailbox/g)?.length).toBe(1)
})


test('A9 a negative shelf is clamped on load and a sale never goes below zero', () => {
  const clamped = loadFarm({ ...farmWith({ lightning: -2, appleCinnamon: -4 }) })
  expect(clamped?.shelf).toEqual({ lightning: 0, appleCinnamon: 0 })
  const sold = sellOne({ ...freshFarm(), shelf: { lightning: 0, appleCinnamon: 1 } }, new Date(JUNE_NOON))
  expect(sold.shelf.appleCinnamon).toBe(0)
})


test('A11 isShip: a deploy argument is not a deploy, quoted text and heredocs do not ship', () => {
  for (const command of [
    'npm run deploy',
    'yarn deploy',
    'make deploy',
    'make deploy ENV=prod',
    'pnpm run deploy',
    './scripts/deploy.sh',
    'git commit -m "x && y"',
    'cd app && git push',
  ]) {
    expect(isShip(command)).toBe(true)
  }
  for (const command of [
    'npm run build -- --deploy-preview',
    'npm run build:deploy-docs',
    'composer install --no-deploy',
    'make deploy-docs',
    'yarn lint deploy.js',
    'echo "x && git push"',
    "echo 'git push && make deploy'",
    'cat <<EOF\ngit push\nnpm publish\nEOF',
    "cat <<'EOF' > notes.txt\ngh pr merge 3\nEOF\nls",
    'git log --grep="git push"',
  ]) {
    expect(isShip(command)).toBe(false)
  }
  expect(isShip("cat <<'EOF' > f\nhello\nEOF\ngit push")).toBe(true)
  expect(stripQuoted('echo "a" \'b\'')).toBe('echo "" \'\'')
})

test('A12 the storm comes once, when the third error in a row lands, never on a denied call', CHATTY, async ($, on) => {
  const answer: Record<string, unknown> = { result: {}, isError: true }
  const setAnswer = (next: Record<string, unknown>) => {
    for (const key of Object.keys(answer)) {
      delete answer[key]
    }
    Object.assign(answer, next)
  }
  const clock = engine(on, answer)
  await start($)
  await begin($)

  await call($, { tool: 'Read', file_path: '/a' })
  await call($, { tool: 'Read', file_path: '/a' })
  expect(await quip($)).not.toBe("Storm's buildin' over the ridge.")
  await call($, { tool: 'Read', file_path: '/a' })
  expect(await quip($)).toBe("Storm's buildin' over the ridge.")

  // Let it blow over, then a denied call at streak 3 and a fourth error start nothing.
  await clock.advance(25_000)
  setAnswer({ deny: 'no' })
  await call($, { tool: 'Read', file_path: '/a' })
  expect(said('denied', await quip($))).toBe(true)
  setAnswer({ result: {}, isError: true })
  await call($, { tool: 'Read', file_path: '/a' })
  expect(await quip($)).not.toBe("Storm's buildin' over the ridge.")
})


test('A14 a tool call and a turn end go back at once, with the bookkeeping left running', async ($, on) => {
  const clock = engine(on, { result: {} })
  on('prompt.submit', (_, e) => e)
  await start($)
  // Every store write now takes ten seconds of the mock clock.
  world.isStoreSlow = true

  // Neither call waits for the write (a call that did would never come back).
  await $.tool.call({ tool: 'WebFetch', url: 'https://x.test' })
  await $.turn.complete({
    answer: '',
    durationMs: 1,
    isAborted: false,
    turnId: 't',
    reason: 'answer',
    usage: usage(400, 0),
  })
  await $.prompt.submit({ text: 'thanks' })

  await clock.advance(30_000)
  await clock.settle()
  const text = await tally($)
  expect(text).toContain('1 cinnamon stick')
  expect(text).toContain('corn 1/24')
})

test('A15 one source for the jar price and the crop-to-barn mapping', () => {
  expect(JAR_PRICE).toBe(25)
  expect(beatsOf('neighbor', true)[1]?.line).toBe(`Sold Miss Opal a jar. $${JAR_PRICE}.`)
  const sold = sellOne({ ...freshFarm(), shelf: { lightning: 0, appleCinnamon: 1 } }, new Date(JUNE_NOON))
  expect(sold.ledger.total).toBe(JAR_PRICE)
  expect(CROP_NAMES).toEqual(['tobacco', 'corn', 'apples'])
  expect(CROP_BARN).toEqual({ tobacco: 'bales', corn: 'corn', apples: 'apples' })
})

// -------------------------------------------------------- C: toggles ----

const configRows = (value = true) =>
  ['porchSounds', 'jebVoice', 'flavor', 'pixels'].map(name => ({
    key: `jeb.${name}`,
    label: name,
    kind: 'boolean',
    value,
    provider: { plugin: 'jeb', tier: 'user' },
    isLocked: false,
  }))

// The /config menu as a test stands for it.
const menu = (on: any, answerWith: (e: any) => object = e => ({ value: e.value })) => {
  const sets: { key: string; value: unknown }[] = []
  on('config.list', () => ({ value: configRows() }))
  on('config.set', (_: any, e: any) => {
    sets.push({ key: e.key, value: e.value })

    return answerWith(e)
  })

  return sets
}

test('V5 fix: bales traded for cinnamon are counted, eight sticks a bale, and the tally splits them', async ($, on) => {
  const clock = engine(on)
  await start($)
  await begin($)
  await call($, { tool: 'Read', file_path: '/a' })
  await clock.advance(480_000)
  await finish($, usage(9600, 600_000))
  for (let i = 0; i < 6; i += 1) {
    await call($, { tool: 'Bash', command: 'ls' })
  }
  const text = await tally($)
  expect(text).toContain('Tobacco: 1 bale cut, 1 traded for cinnamon, 0 in the barn.')
  expect(text).toContain('7 cinnamon sticks')
})

test('V5 fix: balesTraded is normalized, bounded by bales cut, and derived for an older farm', () => {
  const base = freshFarm()
  const old = { ...base, barn: { ...base.barn, bales: 1 }, lifetime: { outputTokens: 0, inputTokens: 0, workMs: 0, bales: 4 } }
  expect(loadFarm(old)?.lifetime.balesTraded).toBe(3)
  expect(loadFarm({ ...base, lifetime: { ...base.lifetime, bales: 2, balesTraded: 99 } })?.lifetime.balesTraded).toBe(2)
  expect(loadFarm({ ...base, lifetime: { ...base.lifetime, bales: 2, balesTraded: -5 } })?.lifetime.balesTraded).toBe(0)
  expect(loadFarm({ ...base, lifetime: { ...base.lifetime, bales: 2, balesTraded: 'x' } })?.lifetime.balesTraded).toBe(0)
})


// ---- v5: agents, parallel sessions, other plugins and MCP, settings hooks, compaction ----

// What stands beneath Jeb for the v5 tests: the engine's agents, session and
// compaction answers, kept here so a test can change them.
const v5world = {
  ids: 0,
  list: [] as { id: string; status: string; type?: string; name?: string; teammateId?: string }[],
  listCalls: 0,
  sessionId: 'me',
  root: '/work/api',
  denyTools: false,
  // A test's own say over a call before the settings hooks (a decision, or nothing).
  onPre: undefined as undefined | ((e: any) => Promise<object | undefined>),
  compact: { messages: [{ role: 'user', text: 'sum', toolUses: [] }], tokensBefore: 140_000, tokensAfter: 22_000 } as object,
  hold: undefined as Promise<void> | undefined,
}

const v5 = (on: any) => {
  v5world.ids = 0
  v5world.list = []
  v5world.sessionId = 'me'
  v5world.root = '/work/api'
  v5world.denyTools = false
  v5world.onPre = undefined
  v5world.hold = undefined
  v5world.listCalls = 0
  v5world.compact = { messages: [{ role: 'user', text: 'sum', toolUses: [] }], tokensBefore: 140_000, tokensAfter: 22_000 }
  on('session.id', () => ({ value: v5world.sessionId }))
  on('session.root', () => ({ value: v5world.root }))
  on('session.repo', () => ({
    value: { root: '/work/main', remote: null, internal: false, name: null },
  }))
  on('agent.spawn', () => ({ model: 'm', agentId: `a${(v5world.ids += 1)}` }))
  on('agent.list', () => {
    v5world.listCalls += 1

    return {
      value: v5world.list.map(info => ({ description: '', type: 'general-purpose', ...info })),
    }
  })
  on('session.compact', async () => {
    if (v5world.hold) {
      await v5world.hold
    }

    return v5world.compact as never
  })
  on('classic.SessionStart', () => ({}))
  on('classic.SubagentStop', () => ({}))
  on('classic.TeammateIdle', () => ({}))
  on('session.end', (_: any, e: any) => ({ sessionId: e.sessionId }))
  on('classic.PreToolUse', async (_: any, e: any) => {
    const own = await v5world.onPre?.(e)

    return own ?? (v5world.denyTools ? { deny: 'not on my farm' } : {})
  })
}

const spawn = async ($: any, over: object = {}) => {
  const result = await $.agent.spawn({
    tool_use_id: 'tu',
    prompt: 'p',
    description: 'd',
    subagentType: 'general-purpose',
    provider: { plugin: 'engine', tier: 'core' },
    parentModel: 'm',
    background: false,
    fork: false,
    ...over,
  })
  await clk.settle()

  return result as { agentId: string }
}

const agentDone = async ($: any, agentId: string, reason = 'answer') => {
  await $.turn.complete({
    answer: '',
    durationMs: 1,
    isAborted: false,
    turnId: `t-${agentId}`,
    reason,
    agentId,
  })
  await clk.settle()
}


test('V5 a background hand tends a plot like any other, never walks the road, and says how it went when done', CHATTY, async ($, on) => {
  engine(on)
  v5(on)
  await start($)

  const a = await spawn($, { background: true, subagentType: 'Explore' })
  expect(await quip($)).toBe('Got a hired hand in the tobacco.')

  // A second one on the same plot is a +N; a third on another plot is drawn.
  await spawn($, { background: true, subagentType: 'Explore' })
  await spawn($, { background: true, subagentType: 'Plan' })
  await spawn($, { background: true })

  await agentDone($, a.agentId)
  expect(await quip($)).toBe("Hired hand's back from town.")
  const f = await spawn($, { background: true })
  await agentDone($, f.agentId, 'error')
  expect(await quip($)).toBe('Hand come back empty-handed.')
})

test('V5 a workflow puts a hand in every plot, counts +N and says the whole holler is workin', async ($, on) => {
  engine(on)
  v5(on)
  await start($)

  const ids: string[] = []
  for (let i = 1; i <= 4; i += 1) {
    ids.push((await spawn($, { workflow: { runId: 'wf_1', agentIndex: i } })).agentId)
  }
  expect(await quip($)).toBe("Got the whole holler workin'.")

  for (const id of ids) {
    await agentDone($, id)
  }
})

test('V5 a teammate stands at the sign while awake and leaves when idle', HOOKS, async ($, on) => {
  engine(on)
  v5(on)
  await start($)

  const a = await spawn($, { isTeammate: true, background: true, name: 'scout' })
  expect(await quip($)).toBe("Neighbor's come by to help out.")

  await $.classic.TeammateIdle({ teammate_name: 'scout', team_name: 't' })
  await clk.settle()

  // Its next turn wakes it; a turn's end rests it; the stop ends it.
  await $.turn.start({ text: '', turnId: 'x', agentId: a.agentId })
  await clk.settle()
  await agentDone($, a.agentId)
  await $.turn.start({ text: '', turnId: 'y', agentId: a.agentId })
  await clk.settle()
  await $.classic.SubagentStop({
    agent_id: a.agentId,
    agent_type: 'scout',
    agent_transcript_path: '',
    stop_hook_active: false,
  })
  await clk.settle()
})

test('V5 an engine fork that was never spawned is ignored on the canvas, its tokens still count', async ($, on) => {
  engine(on)
  v5(on)
  await start($)
  await $.turn.start({ text: '', turnId: 'f', agentId: 'fork-1' })
  await finish($, usage(400, 0), 'fork-1')
  expect(await tally($)).toContain('corn 1/24')
})


test('V5 hands the engine lists as running are taken back on after a reload, on the 30 s beat, at most eight', async ($, on) => {
  const clock = engine(on)
  v5(on)
  // Agents that were spawned before the module reloaded.
  v5world.list = [
    { id: 'old1', status: 'running', type: 'Explore' },
    { id: 'done1', status: 'completed', type: 'Plan' },
  ]
  await start($)
  expect(v5world.listCalls).toBe(1)

  // Later ones appear on the beat, one list call each 30 s and no more.
  v5world.list = [
    { id: 'old1', status: 'running', type: 'Explore' },
    { id: 'old2', status: 'waiting', type: 'Plan', name: 'planner' },
    { id: 'mate', status: 'running', type: 'teammate', teammateId: 'scout@t', name: 'scout' },
  ]
  const before = v5world.listCalls
  await clock.advance(31_000)
  expect(v5world.listCalls - before).toBe(1)
  await clock.advance(20_000)
  expect(v5world.listCalls - before).toBe(1)

  // Past eight the oldest are dropped.
  v5world.list = Array.from({ length: 12 }, (_, i) => ({ id: `n${i}`, status: 'running' }))
  await clock.advance(31_000)
  for (let i = 0; i < 12; i += 1) {
    await spawn($, { background: true })
  }
  await agentDone($, 'n11')
  await clock.advance(31_000)
})


test('V5 the heartbeat merges, prunes and is removed on session.end; lanterns light for other camps', { timeoutMs: 30_000 }, async ($, on) => {
  const old = 'c3c3c3c3c3c3'
  const clock = engine(on, { result: {} }, {
    farm: saltFarm(),
    sessions: {
      [OTHER]: { name: 'Laurel Fork', lastSeen: JUNE_NOON - 30_000 },
      [old]: { name: 'Sugar Run', lastSeen: JUNE_NOON - 10 * 60_000 },
      junk: { name: 5, lastSeen: 'x' },
    },
  })
  v5(on)
  await start($)

  // The heartbeats are keyed by a keyed hash of the session id, and the camp is a place.
  const stored = world.db.get('sessions') as Record<string, { name: string; lastSeen: number }>
  expect(Object.keys(stored).sort()).toEqual([keyOf('me'), OTHER].sort())
  expect(stored[keyOf('me')]?.name).toBe(placeOf('api'))
  expect(await quip($)).toBe('Lanterns lit over at the Laurel Fork camp.')

  // Another camp lights up on the next minute's beat.
  const second = world.db.get('sessions') as Record<string, unknown>
  world.db.set('sessions', { ...second, [OTHER2]: { name: 'Pine Knob', lastSeen: JUNE_NOON + 60_000 } })
  await clock.advance(61_000)
  expect(Object.keys(world.db.get('sessions') as object).sort()).toEqual([OTHER, OTHER2, keyOf('me')].sort())

  await $.session.end({ reason: 'prompt_input_exit', sessionId: 'me', resume: { id: 'me' } })
  await clk.settle()
  expect(Object.keys(world.db.get('sessions') as object).sort()).toEqual([OTHER, OTHER2].sort())
})

test('V5 a heartbeat from a Jeb before the anonymizer lights a lantern under a place, and is never written back', { timeoutMs: 30_000 }, async ($, on) => {
  engine(on, { result: {} }, {
    farm: saltFarm(),
    sessions: {
      'sess-web-1': { name: 'web', lastSeen: JUNE_NOON - 30_000 },
      'sess-old-1': { name: 'old', lastSeen: JUNE_NOON - 10 * 60_000 },
    },
  })
  v5(on)
  await start($)
  expect(await quip($)).toBe(`Lanterns lit over at the ${placeOf('web')} camp.`)
  expect(Object.keys(world.db.get('sessions') as object)).toEqual([keyOf('me')])
  expect(JSON.stringify(world.db.get('sessions'))).not.toContain('web')
})

test('V5 sessions in the store stay at eight and each name at 24 characters', async ($, on) => {
  const many: Record<string, unknown> = {}
  for (let i = 0; i < 20; i += 1) {
    many[keyOf(`s${i}`)] = { name: `camp-${i}-${'x'.repeat(40)}`, lastSeen: JUNE_NOON - i * 1000 }
  }
  engine(on, { result: {} }, { farm: saltFarm(), sessions: many })
  v5(on)
  await start($)
  const stored = world.db.get('sessions') as Record<string, { name: string }>
  expect(Object.keys(stored).length).toBe(8)
  expect(stored[keyOf('me')]).toBeTruthy()
  for (const camp of Object.values(stored)) {
    expect(camp.name.length).toBeLessThanOrEqual(24)
  }
})

test('V5 a worktree session is named by its folder, a plain one by its repository', async ($, on) => {
  engine(on, { result: {} }, { farm: saltFarm() })
  v5(on)
  v5world.root = '/work/web-wt'
  await start($)
  expect((world.db.get('sessions') as Record<string, { name: string }>)[keyOf('me')]?.name).toBe(placeOf('web-wt'))
})

test('V5 a session in the main tree is named by its repository folder', async ($, on) => {
  engine(on, { result: {} }, { farm: saltFarm() })
  v5(on)
  v5world.root = '/work/main'
  await start($)
  expect((world.db.get('sessions') as Record<string, { name: string }>)[keyOf('me')]?.name).toBe(placeOf('main'))
  expect(placeOf('main')).not.toBe(placeOf('web-wt'))
})

test('V5 MCP servers: parsed from the tool name, matched by table, the rest on the radio', async ($, on) => {
  engine(on)
  v5(on)
  await start($)
  expect(mcpServerOf('mcp__claude_ai_Atlassian__getJiraIssue')).toBe('claude_ai_Atlassian')
  expect(mcpServerOf('mcp__a__b__c')).toBe('a')
  expect(mcpServerOf('Bash')).toBeUndefined()
  const cases: [string, string][] = [
    ['claude_ai_Atlassian', '📋'],
    ['claude_ai_Sentry', '🐛'],
    ['claude_ai_Slack', '📞'],
    ['claude-in-chrome', '🔭'],
    ['claude_ai_Figma', '🎨'],
    ['claude_ai_Gmail', '📫'],
    ['claude_ai_Google_Calendar', '📫'],
    ['claude_ai_Google_Drive', '📜'],
    ['claude_ai_Claude_Docs', '📜'],
    ['plugin-authoring', '📻'],
  ]
  for (const [server, glyph] of cases) {
    expect(mcpKindOf(server).glyph).toBe(glyph)
  }
  // A server Jeb does not know is never named.
  expect(mcpKindOf('plugin-authoring').line).toBe(RADIO_LINE)
  expect(mcpKindOf('claude_ai_Sentry').line).toBe("Huntin' bugs in the corn")

  // In the band: the glyph in Jeb's hands, the line in the bubble, no still.
  await call($, { tool: 'mcp__claude_ai_Slack__slack_send', text: 'hi' })
  expect(await quip($)).toBe('On the party line…')
  expect(await tally($)).toContain('batch 0/6')
  await finish($, usage(0, 0))
})

test('V5 a settings hook that denies a call puts up a gate; the call still errors as it does today', CHATTY_HOOKS, async ($, on) => {
  engine(on, { result: {}, isError: true })
  v5(on)
  v5world.denyTools = true
  await start($)
  await call($, { tool: 'Edit', file_path: '/a', old_string: 'a', new_string: 'b' })
  expect(await quip($)).toBe('Somebody put up a gate.')

  // Not denied: no gate.
  v5world.denyTools = false
  await call($, { tool: 'Read', file_path: '/a' })
  expect(await quip($)).not.toBe('Somebody put up a gate.')
})

test('V5 compaction: Jeb holds the broom while it runs and says what came off; auto says the barn got full', CHATTY_HOOKS, async ($, on) => {
  const clock = engine(on)
  v5(on)
  let release: () => void = () => undefined
  const hold = () => {
    v5world.hold = new Promise<void>(resolve => {
      release = resolve
    })
  }
  await start($)

  hold()
  const running = $.session.compact({ trigger: 'manual', messages: [{ role: 'user', text: 'hi', toolUses: [] }] })
  await clock.settle()
  expect(await quip($)).toBe("Sweepin' out the barn…")
  release()
  await running
  await clock.settle()
  expect(await quip($)).toBe('Swept the barn out: 140k down to 22k.')

  hold()
  const auto = $.session.compact({ trigger: 'auto', messages: [{ role: 'user', text: 'hi', toolUses: [] }] })
  await clock.settle()
  expect(await quip($)).toBe('Barn got full, had to sweep.')
  release()
  await auto
  await clock.settle()

  // A subagent's compaction is not Jeb's barn.
  hold()
  const other = $.session.compact({ trigger: 'auto', messages: [{ role: 'user', text: 'hi', toolUses: [] }], agentId: 'a9' })
  await clock.settle()
  release()
  await other
})

test('V5 compaction lines come from the engine tokens, and none when it does not say', async () => {
  expect(sweptLine(140_000, 22_000)).toBe('Swept the barn out: 140k down to 22k.')
  expect(sweptLine(1_200_000, 900)).toBe('Swept the barn out: 1.2M down to 900.')
  expect(sweptLine(undefined, 5)).toBeUndefined()
})

test('V5 /clear starts the day over and keeps the farm and the lanterns', async ($, on) => {
  engine(on, { result: {} }, { farm: saltFarm(), sessions: { [OTHER]: { name: 'Laurel Fork', lastSeen: JUNE_NOON - 1000 } } })
  v5(on)
  await start($)
  await finish($, usage(1000, 0))
  await begin($)
  await call($, { tool: 'Read', file_path: '/a' })
  await spawn($, { subagentType: 'Explore' })
  const before = await tally($)

  v5world.sessionId = 'me2'
  await $.session.end({ reason: 'clear', sessionId: 'me', resume: { id: 'me' } })
  await clk.settle()
  expect(await quip($)).toBe('Fresh start. Same holler.')
  // The tally is the same but for the session just stitched onto the quilt.
  expect(await tally($)).toBe(
    before.replace('Sessions worked: 0 (0 shipped).', `Sessions worked: 1 (0 shipped). Busiest: Jun 10, ${placeOf('api')} camp.`),
  )
  expect(Object.keys(world.db.get('sessions') as object)).not.toContain(keyOf('me'))

  // The new conversation's id shows up on the next beat.
  await clk.advance(61_000)
  expect(Object.keys(world.db.get('sessions') as object)).toContain(keyOf('me2'))
})

test('V5 resume and fork lines, long and short', HOOKS, async ($, on) => {
  engine(on)
  v5(on)
  await start($)
  await $.classic.SessionStart({ source: 'resume', seconds_since_last_response: 12 * 60 })
  await clk.settle()
  expect(await quip($)).toBe('Back already? Been 12 minutes.')
  await $.classic.SessionStart({ source: 'resume', seconds_since_last_response: 3 * 3600 })
  await clk.settle()
  expect(await quip($)).toBe('Back already? Been 3 hours.')
  await $.classic.SessionStart({ source: 'resume', seconds_since_last_response: 3 * 86_400 })
  await clk.settle()
  expect(await quip($)).toBe("Been a far piece. Crops kept growin'.")
  await $.classic.SessionStart({ source: 'fork' })
  await clk.settle()
  expect(await quip($)).toBe('Somebody split the firewood.')
  await $.classic.SessionStart({ source: 'clear' })
  await clk.settle()
  expect(await quip($)).toBe('Somebody split the firewood.')
})

test('hook reactions off (the default): the skippable hooks are not registered, so a resume says nothing', async ($, on) => {
  engine(on)
  v5(on)
  await start($)
  await clk.settle()
  const before = await quip($)
  await $.classic.SessionStart({ source: 'resume', seconds_since_last_response: 12 * 60 })
  await $.classic.SessionStart({ source: 'fork' })
  await clk.settle()
  expect(await quip($)).toBe(before)
})


test('V5 the agents list keeps eight at most, dropping the oldest, and an id twice is one hand', () => {
  let list = [] as ReturnType<typeof hireOf>[]
  for (let i = 0; i < 30; i += 1) {
    list = addHired(list, hireOf({ agentId: `a${i}` }, i))
  }
  expect(list.length).toBe(MAX_AGENTS)
  expect(list[0]?.id).toBe('a22')
  expect(list[7]?.id).toBe('a29')
  list = addHired(list, hireOf({ agentId: 'a25' }, 99))
  expect(list.length).toBe(MAX_AGENTS)
  expect(list.filter(hand => hand.id === 'a25').length).toBe(1)
})


// ---- v5.1 live streaming ----

const stepInput = (extra: object = {}) => ({ turnId: 't', index: 0, model: 'm', messageCount: 1, ...extra })

const stepResult = (u: ReturnType<typeof usage> | null = null, extra: object = {}) => ({
  turnId: 't',
  index: 0,
  answer: '',
  toolUses: [],
  stopReason: 'end_turn' as const,
  usage: u,
  ...extra,
})

// The engine beneath Jeb streams the plan's chunks and returns its result (or
// fails after the chunks); a test changes the plan between steps.
type Plan = { chunks: any[]; result: object; fails: boolean }

const streams = (on: any, chunks: any[], result: object = stepResult()): Plan => {
  const plan: Plan = { chunks, result, fails: false }
  on('turn.step', async function* () {
    for (const chunk of plan.chunks) {
      yield chunk
    }
    if (plan.fails) {
      throw new Error('connection reset')
    }

    return plan.result
  })

  return plan
}

const drain = async ($: any, input: object = stepInput()) => {
  const stream = $.turn.step(input)
  const out: any[] = []
  let step = await stream.next()
  while (!step.done) {
    out.push(step.value)
    step = await stream.next()
  }
  const result = step.value
  await clk.settle()

  return { out, result }
}

const mixed = (count: number) => {
  const chunks: any[] = []
  for (let i = 0; i < count; i += 1) {
    const ref = i
    switch (i % 6) {
      case 0:
        chunks.push({ kind: 'text', index: 0, text: `a${i}`, ref })
        break
      case 1:
        chunks.push({ kind: 'thinking', index: 0, text: `t${i}`, ref })
        break
      case 2:
        chunks.push({ kind: 'text', index: 1, text: `w${i}`, ref })
        break
      case 3:
        chunks.push({ kind: 'tool', index: 2, id: `tu${i}`, name: i % 12 === 3 ? 'Read' : 'mcp__sentry__x', ref })
        break
      case 4:
        chunks.push({ kind: 'input', index: 2, json: '{"a":', ref })
        break
      default:
        chunks.push({ kind: 'stop', stopReason: 'end_turn', usage: null, ref })
    }
  }

  return chunks
}

// Counts the writes to one atom while a test runs.
const counted = (_on: any) => {
  const writes = { anim: 0, say: 0 }
  tap((e: any) => {
    if (e.key === 'anim') {
      writes.anim += 1
    } else if (e.key === 'say') {
      writes.say += 1
    }
  })

  return writes
}

test('S1 the turn.step hook passes 1000 mixed chunks and the result through unchanged', async ($, on) => {
  engine(on)
  const chunks = mixed(1000)
  const result = stepResult(usage(10, 20), { answer: 'hello', toolUses: [{ name: 'Read', input: {} }] })
  streams(on, chunks, result)
  await start($)
  await begin($)

  const got = await drain($)
  expect(got.out.length).toBe(1000)
  expect(got.out).toEqual(chunks)
  for (let i = 0; i < chunks.length; i += 1) {
    expect(got.out[i]).toEqual(chunks[i])
  }
  expect(got.result).toEqual(result)
})

test('S1 an observer that throws still passes every chunk through, and keeps watching', async ($, on) => {
  engine(on)
  // A tool named like an inherited property: looking it up in the saying table
  // makes the observer throw. The stream shows the failure never reaches it.
  const chunks: any[] = [
    { kind: 'thinking', index: 0, text: 'a' },
    { kind: 'tool', index: 1, id: 'x', name: 'constructor' },
    { kind: 'input', index: 1, json: '{}' },
    { kind: 'text', index: 2, text: 'c' },
    { kind: 'stop', stopReason: 'tool_use', usage: null },
  ]
  streams(on, chunks)
  await start($)
  await begin($)

  const got = await drain($)
  expect(got.out).toEqual(chunks)
  expect(got.result).toEqual(stepResult())
})

test('S2 thinking, then writing, then a tool set Jeb pose and line in order', CHATTY, async ($, on) => {
  engine(on)
  streams(on, [
    { kind: 'thinking', index: 0, text: 'hm' },
    { kind: 'text', index: 1, text: 'ok' },
    { kind: 'tool', index: 2, id: 'tu1', name: 'Read' },
  ])
  await start($)
  await begin($)

  const stream = $.turn.step(stepInput())
  await stream.next()
  await stream.next()
  await clk.settle()
  expect(said('thinking', await quip($))).toBe(true)

  await stream.next()
  await clk.settle()
  expect(said('writing', await quip($))).toBe(true)

  await stream.next()
  await clk.settle()
  expect(said('read', await quip($))).toBe(true)
  for await (const chunk of stream) {
    void chunk
  }
})

test('S2 an MCP tool chunk takes the server glyph and line', async ($, on) => {
  engine(on)
  streams(on, [{ kind: 'tool', index: 0, id: 'tu1', name: 'mcp__claude_ai_Sentry__search_issues' }])
  await start($)
  await begin($)
  await drain($)
  expect(await quip($)).toBe("Huntin' bugs in the corn…")
})

test('S2 a 200-chunk run of text makes exactly one transition', async ($, on) => {
  engine(on)
  const writes = counted(on)
  streams(
    on,
    Array.from({ length: 200 }, (_, i) => ({ kind: 'text', index: 0, text: `w${i}` })),
  )
  await start($)
  await begin($)
  await clk.advance(2_000)
  writes.anim = 0
  writes.say = 0

  await drain($)
  expect(writes.say).toBe(1)
  expect(writes.anim).toBe(1)
})

test('S2 a burst of transitions writes at most 4 times a second and the last one wins', CHATTY, async ($, on) => {
  engine(on)
  const writes = counted(on)
  const kinds = ['thinking', 'text', 'tool'] as const
  const chunks = Array.from({ length: 31 }, (_, i) => {
    const kind = kinds[i % 3]

    return kind === 'tool'
      ? { kind, index: i, id: `tu${i}`, name: i % 2 ? 'Read' : 'Edit' }
      : { kind, index: i, text: 'x' }
  })
  // The last chunk is a Bash tool call.
  chunks.push({ kind: 'tool', index: 99, id: 'last', name: 'Bash' } as any)
  streams(on, chunks)
  await start($)
  await begin($)
  await clk.advance(2_000)
  writes.anim = 0
  writes.say = 0

  await drain($)
  expect(writes.anim).toBeLessThanOrEqual(4)
  expect(writes.say).toBeLessThanOrEqual(4)

  // The rest of the burst goes out on the next beats, never more than 4 a second.
  const before = writes.anim
  await clk.advance(1_000)
  expect(writes.anim - before).toBeLessThanOrEqual(4)
  expect(said('bash', await quip($))).toBe(true)
})

test('S2 subagent steps do not move Jeb', async ($, on) => {
  engine(on)
  const writes = counted(on)
  streams(on, [
    { kind: 'thinking', index: 0, text: 'hm' },
    { kind: 'text', index: 1, text: 'ok' },
    { kind: 'tool', index: 2, id: 'tu1', name: 'Read' },
  ])
  await start($)
  await begin($)
  await clk.advance(2_000)
  writes.anim = 0
  writes.say = 0

  await drain($, stepInput({ agentId: 'a1' }))
  expect(writes.anim).toBe(0)
  expect(writes.say).toBe(0)
})

test('S3 each step with usage grows the crops before the turn ends', async ($, on) => {
  engine(on)
  const plan = streams(on, [{ kind: 'text', index: 0, text: 'x' }])
  await start($)
  await begin($)

  for (let step = 1; step <= 3; step += 1) {
    plan.result = stepResult(usage(400, 25_000), { index: step - 1 })
    await drain($, stepInput({ index: step - 1 }))
    const text = await tally($)
    expect(text).toContain(`corn ${step}/24`)
    expect(text).toContain(`apples ${step}/24`)
  }
})

test('S3 turn.complete does not count again what the steps counted, but a turn with no step usage still counts', async ($, on) => {
  engine(on)
  streams(on, [{ kind: 'text', index: 0, text: 'x' }], stepResult(usage(400, 25_000)))
  await start($)
  await begin($)
  await drain($)
  expect(await tally($)).toContain('corn 1/24')

  await finish($, usage(400, 25_000))
  const text = await tally($)
  expect(text).toContain('corn 1/24')
  expect(text).toContain('apples 1/24')
  expect(text).toContain('400 output tokens')

  // Another turn that streamed no usage counts at its end.
  await $.turn.complete({
    answer: '',
    durationMs: 1,
    isAborted: false,
    turnId: 'other',
    reason: 'answer',
    usage: usage(400, 25_000),
  })
  await clk.settle()
  expect(await tally($)).toContain('corn 2/24')
})

test('S3 a subagent step counts too, and an interrupted turn keeps the steps that finished', async ($, on) => {
  engine(on)
  const plan = streams(on, [{ kind: 'text', index: 0, text: 'x' }], stepResult(usage(400, 0), { turnId: 'sub', agentId: 'a1' }))
  await start($)
  await begin($)
  await drain($, stepInput({ turnId: 'sub', agentId: 'a1' }))
  expect(await tally($)).toContain('corn 1/24')

  // Step 0 finishes; step 1 is cut off mid-stream.
  plan.result = stepResult(usage(400, 0))
  await drain($)
  expect(await tally($)).toContain('corn 2/24')
  plan.fails = true
  let failed = false
  try {
    await drain($, stepInput({ index: 1 }))
  } catch {
    failed = true
  }
  expect(failed).toBe(true)
  await $.turn.complete({
    answer: '',
    durationMs: 1,
    isAborted: true,
    turnId: 't',
    reason: 'aborted',
    usage: usage(800, 0),
  } as any)
  await clk.settle()
  expect(await tally($)).toContain('corn 2/24')
})

test('S4 a tool.call after its stream chunk does not speak or pose twice, and one with no chunk still does', async ($, on) => {
  engine(on)
  const writes = counted(on)
  streams(on, [{ kind: 'tool', index: 0, id: 'tu1', name: 'Read' }])
  await start($)
  await begin($)
  await drain($)
  const line = await quip($)
  expect(said('read', line)).toBe(true)
  writes.say = 0
  writes.anim = 0

  await call($, { tool: 'Read', file_path: '/a', tool_use_id: 'tu1' })
  expect(writes.say).toBe(0)
  expect(writes.anim).toBe(0)
  expect(await quip($)).toBe(line)

  // A call the stream never announced speaks as before.
  await call($, { tool: 'Edit', file_path: '/a', tool_use_id: 'tu2' })
  expect(writes.say).toBe(1)
  expect(said('edit', await quip($))).toBe(true)
})


// ------------------------------------------------ W: the real workday ----

const segs = (command: string) => classify(command)

test('W classify: Docker unwrapping, wrappers, pipes, quoted text, filters and the deny patterns', () => {
  expect(
    segs('docker compose exec -T -u root -e A=B -w /app app php artisan test --filter=Foo'),
  ).toEqual([
    { kind: 'test', svc: 'app', tool: 'artisan', sub: 'test', filtered: true, isLast: true },
  ])
  expect(segs('rtk docker compose exec app vendor/bin/pest')[0]).toMatchObject({
    kind: 'test',
    svc: 'app',
    filtered: false,
    tool: 'pest',
  })
  expect(segs('sudo FOO=1 rtk proxy php artisan test --parallel')[0]).toMatchObject({
    kind: 'test',
    filtered: false,
  })
  expect(segs('docker-compose exec app ./vendor/bin/phpunit tests/Feature/A.php')[0]).toMatchObject({
    kind: 'test',
    filtered: true,
  })
  expect(segs('composer test -- --group=slow')[0]).toMatchObject({ kind: 'test', filtered: true })
  expect(segs('php artisan test --parallel --filter=x')[0]?.filtered).toBe(false)

  // Only the last segment owns the exit code.
  const piped = segs('php artisan test | tail -5')
  expect(piped.map(seg => [seg.kind, seg.isLast])).toEqual([['test', false], ['none', true]])
  expect(segs('cd app && php artisan test').map(seg => seg.isLast)).toEqual([false, true])
  expect(segs('php artisan test || true')[0]?.isLast).toBe(false)
  expect(segs('php artisan test &')[0]?.isLast).toBe(false)

  // Quoted text and heredocs are not commands.
  expect(segs('echo "php artisan test"')[0]?.kind).toBe('none')
  expect(segs("git commit -m 'git reset --hard'")[0]?.deny).toBeUndefined()
  expect(segs('cat <<EOF\nphp artisan test\nEOF')[0]?.kind).toBe('none')

  // Lint, with pint's two faces.
  expect(segs('vendor/bin/pint --test')[0]).toMatchObject({ kind: 'lint', tool: 'pint', sub: 'test' })
  expect(segs('vendor/bin/pint --test')[0]?.fixes).toBeUndefined()
  expect(segs('vendor/bin/pint')[0]).toMatchObject({ kind: 'lint', tool: 'pint', fixes: true })
  expect(segs('docker compose exec app vendor/bin/phpstan analyse')[0]).toMatchObject({
    kind: 'lint',
    tool: 'phpstan',
    svc: 'app',
  })
  expect(segs('composer analyse')[0]).toMatchObject({ kind: 'lint', tool: 'composer:analyse' })
  expect(segs('npm run lint')[0]).toMatchObject({ kind: 'lint', tool: 'npm:lint' })
  expect(segs('pnpm run typecheck')[0]?.kind).toBe('lint')
  expect(segs('npx eslint .')[0]).toMatchObject({ kind: 'lint', tool: 'eslint' })
  expect(segs('prettier --check .')[0]?.kind).toBe('lint')
  expect(segs('prettier --write .')[0]?.kind).toBe('none')
  expect(segs('vue-tsc --noEmit')[0]?.kind).toBe('lint')
  expect(segs('npm run build')[0]?.kind).toBe('none')

  // migrate:status is not a plowing run, and neither is anything else of artisan's.
  expect(segs('php artisan migrate:status')[0]).toMatchObject({ kind: 'none', sub: 'migrate:status' })
  expect(segs('php artisan migrate')[0]).toMatchObject({ kind: 'none', sub: 'migrate' })

  // Compose verbs.
  expect(segs('docker compose exec database psql -U x')[0]).toMatchObject({ kind: 'exec', svc: 'database' })
  expect(segs('docker compose up -d')[0]).toMatchObject({ kind: 'exec', sub: 'up', detached: true })
  expect(segs('docker compose up app')[0]).toMatchObject({ kind: 'exec', sub: 'up', detached: false, svc: 'app' })
  expect(segs('docker compose run --rm app php artisan test')[0]).toMatchObject({
    kind: 'test',
    svc: 'app',
    rm: true,
  })
  expect(segs('docker compose run --rm -e A=B app php artisan migrate')[0]).toMatchObject({
    kind: 'exec',
    svc: 'app',
    rm: true,
  })
  expect(workOf(segs('vendor/bin/pint && php artisan test'))?.kind).toBe('test')

  // The five deny patterns, and what is not one.
  const denied = (command: string) => denyRuleOf(segs(command))
  expect(denied('git reset --hard HEAD~1')).toBe('reset')
  expect(denied('git -C app reset')).toBe('reset')
  expect(denied('git push --force origin main')).toBe('force')
  expect(denied('git push -f')).toBe('force')
  expect(denied('docker compose down')).toBe('down')
  expect(denied('rm -rf node_modules')).toBe('rmrf')
  expect(denied('rm -fr x')).toBe('rmrf')
  expect(denied('git clean -fd')).toBe('clean')
  expect(denied('git restore .')).toBe('clean')
  expect(denied('git checkout -- .')).toBe('clean')
  expect(denied('rtk git reset --soft HEAD^')).toBe('reset')
  expect(denied('docker compose exec app rm -rf storage/x')).toBe('rmrf')
  for (const fine of [
    'git push origin main',
    'git push -u origin feature',
    'git clean -n',
    'git restore --staged .',
    'git restore file.php',
    'git checkout main',
    'rm -r dir',
    'rm file',
    'docker compose up -d',
    'echo "git reset --hard"',
  ]) {
    expect(denied(fine)).toBeUndefined()
  }
})

test('W ticket keys: only keys, at most five, none from other text', () => {
  expect(ticketKeys('BRKT-86')).toEqual(['BRKT-86'])
  expect(ticketKeys('fix BRKT-86 and ab-12 then PROJ-7 PROJ-7')).toEqual(['BRKT-86', 'PROJ-7'])
  expect(ticketKeys('A-1 a1-2 X-9')).toEqual([])
  expect(ticketKeys('AB-1 AB-2 AB-3 AB-4 AB-5 AB-6 AB-7')).toEqual(['AB-1', 'AB-2', 'AB-3', 'AB-4', 'AB-5'])
  expect(ticketKeys('AB-12345678901234567')).toEqual([])
  expect(ticketKeys(undefined)).toEqual([])
  expect(ticketKeys({ key: 'BRKT-1' })).toEqual([])
})

// What the bubble, the anim atom and the store carried, for the tests that care.
const seenState = { says: [] as string[], atoms: {} as Record<string, string> }
const watch = (_on: any) => {
  seenState.says = []
  seenState.atoms = {}
  tap((e: any) => {
    if (e.key === 'say') {
      seenState.says.push(e.value.line)
    }
    seenState.atoms[e.key] = JSON.stringify(e.value)
  })
}

const bash = (command: string, extra: object = {}) => ({ tool: 'Bash', command, ...extra })


const TEST_FILTERED = 'php artisan test --filter=Foo'

test('W tests as weather: a filtered pass rains on one plot, a fail dries it, the first pass after a fail says so', CHATTY, async ($, on) => {
  const answer = { result: {}, isError: false }
  const clock = engine(on, answer)
  await start($)
  await begin($)
  const plot = CROP_NAMES.indexOf(plotFor(TEST_FILTERED))

  await call($, bash(TEST_FILTERED))
  expect(await quip($)).toBe(RAIN_LINE)
  // The rain lasts about six seconds.
  await clock.advance(7_000)

  // A fail: that plot drawn dry, "Bad batch."
  await clock.advance(46_000)
  answer.isError = true
  await call($, bash(TEST_FILTERED))
  expect(await quip($)).toBe(BAD_BATCH_LINE)

  // The first pass after a fail, even inside the 45 s cap.
  answer.isError = false
  await call($, bash(TEST_FILTERED))
  expect(await quip($)).toBe(FIRST_RAIN_LINE)
  // A second pass inside the cap is quiet: the bubble keeps what it had.
  await call($, { tool: 'Read', file_path: '/a' })
  const before = await quip($)
  await call($, bash(TEST_FILTERED))
  expect(await quip($)).toBe(before)
  await clock.advance(46_000)
  await call($, bash(TEST_FILTERED))
  expect(await quip($)).toBe(RAIN_LINE)
})

test('W tests as weather: the whole suite rains or droughts every plot; a streak line comes once at three fails', CHATTY, async ($, on) => {
  const answer = { result: {}, isError: false }
  const clock = engine(on, answer)
  await start($)
  await begin($)

  await call($, bash('php artisan test'))
  expect(await quip($)).toBe(COUNTY_RAIN_LINE)
  await call($, bash('php artisan test --parallel'))
  await clock.advance(46_000)

  answer.isError = true
  await call($, bash('docker compose exec app php artisan test'))
  expect(await quip($)).toBe(DROUGHT_LINE)
  await clock.advance(46_000)
  await call($, bash('php artisan test'))
  expect(await quip($)).toBe(DROUGHT_LINE)
  // The third in a row: the streak line, though the cap is not up.
  await call($, bash('php artisan test'))
  expect(await quip($)).toBe(STREAK_LINE)
  // A fourth is not another streak line.
  await clock.advance(46_000)
  await call($, bash('php artisan test'))
  expect(await quip($)).toBe(DROUGHT_LINE)
  // A pass ends the streak, and the next streak gets its line again.
  answer.isError = false
  await call($, bash('php artisan test'))
  expect(await quip($)).toBe(FIRST_RAIN_LINE)
})

test('W tests as weather: no verdict for a piped, backgrounded or chained-away run', CHATTY, async ($, on) => {
  const answer = { result: {}, isError: true }
  const clock = engine(on, answer)
  await start($)
  await begin($)

  for (const extra of [
    bash('php artisan test --filter=Foo | tail -5'),
    bash('php artisan test --filter=Foo || true'),
    bash('php artisan test --filter=Foo', { run_in_background: true }),
    bash('php artisan test --filter=Foo &'),
  ]) {
    answer.isError = true
    await call($, extra)
    // In progress, no verdict, no weather, and no generic error line.
    expect(await quip($)).toBe(TEST_RUN_LINE)
    answer.isError = false
    await call($, { tool: 'Read', file_path: '/a' })
    await clock.advance(46_000)
  }
  // A failed run that could not be judged does not start the hush or the streak.
  await call($, bash('php artisan test'))
  expect(await quip($)).toBe(COUNTY_RAIN_LINE)
})

test('W a subagent runs the whole suite and its hand waters the county; a filtered run has no line of its own', CHATTY, async ($, on) => {
  const clock = engine(on)
  await start($)
  await begin($)

  await call($, { tool: 'Read', file_path: '/a' })
  await call($, bash('php artisan test --filter=Foo', { agentId: 'a1' }))
  expect(said('read', await quip($))).toBe(false)
  await call($, bash('php artisan test', { agentId: 'a1' }))
  expect(await quip($)).toBe(HAND_WATER_LINE)
  await clock.advance(1_000)
})

test('W lint as weeding: a hoe pose, clean rows or weeds, the phpstan line, pint without --test, a cap per tool', CHATTY, async ($, on) => {
  const answer = { result: {}, isError: false }
  const clock = engine(on, answer)
  await start($)
  await begin($)

  await call($, bash('vendor/bin/pint --test'))
  expect(await quip($)).toBe(CLEAN_LINE)
  // The same tool again inside 90 s is quiet; another tool is not.
  await call($, { tool: 'Read', file_path: '/a' })
  const before = await quip($)
  await call($, bash('docker compose exec app vendor/bin/pint --test'))
  expect(await quip($)).toBe(before)
  await call($, bash('npx eslint .'))
  expect(await quip($)).toBe(CLEAN_LINE)
  await clock.advance(91_000)

  // pint without --test rewrites files: it hoed, it did not pass.
  await call($, bash('vendor/bin/pint'))
  expect(await quip($)).toBe(HOED_LINE)
  await clock.advance(91_000)

  answer.isError = true
  await call($, bash('vendor/bin/pint --test'))
  expect(await quip($)).toBe(WEEDS_LINE)
  await clock.advance(91_000)
  await call($, bash('docker compose exec app vendor/bin/phpstan analyse'))
  expect(await quip($)).toBe(PHPSTAN_LINE)
})

test('W lint in a pipeline has no verdict: the generic line stands', CHATTY, async ($, on) => {
  engine(on, { result: {}, isError: true })
  await start($)
  await begin($)

  await call($, bash('npm run lint | tail'))
  expect(said('error', await quip($))).toBe(true)
})

test('W the Compose service is a building by the house, on every call; up -d and run --rm have lines', CHATTY, async ($, on) => {
  const clock = engine(on)
  await start($)
  await begin($)

  for (const [service, glyph] of [['app', '🛖'], ['hot', '🌱'], ['database', '🥔']] as const) {
    await call($, bash(`docker compose exec ${service} echo hi`))
  }
  // An unknown service has no building, and a call outside one takes it away.
  await call($, bash('docker compose exec redis redis-cli ping'))
  await call($, bash('docker compose exec app php artisan migrate:status'))
  await call($, { tool: 'Read', file_path: '/a' })
  expect(buildingOf('app')).toBe('🛖')
  expect(buildingOf('constructor')).toBe('')

  await call($, bash('docker compose up -d'))
  expect(await quip($)).toBe(UP_LINE)
  await call($, { tool: 'Read', file_path: '/a' })
  const before = await quip($)
  await call($, bash('docker compose up -d'))
  expect(await quip($)).toBe(before)
  await clock.advance(601_000)
  await call($, bash('docker compose up -d'))
  expect(await quip($)).toBe(UP_LINE)

  await call($, bash('docker compose run --rm app php artisan migrate'))
  expect(await quip($)).toBe(RUN_LINE)
  await call($, { tool: 'Read', file_path: '/a' })
  const kept = await quip($)
  await call($, bash('docker compose run --rm app php artisan migrate'))
  expect(await quip($)).toBe(kept)
  // The building goes home with the turn.
  await call($, bash('docker compose exec app echo hi'))
  await finish($, usage(0, 0))
})

const submitTriage = (args: string) =>
  ({ text: `/triage ${args}`, command: { name: 'triage', args } })

test('W /triage KEY lets a cow loose as a neighbor\'s number; not even the key is kept', CHATTY, async ($, on) => {
  engine(on, { result: {} }, { farm: saltFarm() })
  on('prompt.submit', (_, e) => e)
  watch(on)
  await start($)

  const secret = 'PRIVATE-NOTES-ABOUT-THE-CLIENT'
  await submit($, submitTriage(`BRKT-86 ${secret} ${'x'.repeat(4000)}`))
  expect(await quip($)).toBe(`Neighbor's cow got loose: number ${cowOf('BRKT-86')}.`)
  // Raw arguments never reach the store, the atoms or the bubble.
  expect(JSON.stringify([...world.db.values()])).not.toContain('PRIVATE')
  expect(Object.values(seenState.atoms).join('')).not.toContain('PRIVATE')
  expect(seenState.says.join('')).not.toContain('PRIVATE')
  expect(Object.values(seenState.atoms).join('')).not.toContain('BRKT')
  expect(seenState.says.join('')).not.toContain('BRKT')
  expect(JSON.stringify([...world.db.values()])).not.toContain('BRKT')
  expect(Object.values(seenState.atoms).join('')).toContain(`#${cowOf('BRKT-86')}`)

  const before = await quip($)
  await submit($, submitTriage('BRKT-86'))
  expect(await quip($)).toBe(before)

  // A command that is not /triage is left alone.
  await submit($, { text: '/jeb x', command: { name: 'jeb', args: 'AB-1 CD-2' } })

  // Several keys: a count; at most three cows are drawn, then +N.
  await submit($, submitTriage('AB-1 CD-22 EF-333 GH-4'))
  expect(await quip($)).toBe('4 cows loose.')
  expect(cowLine([1, 2])).toBe('2 cows loose.')
})

test('W a getJiraIssue call through the work board is a cow too, and the next successful ship leads them home', CHATTY, async ($, on) => {
  engine(on, { result: {} }, { farm: saltFarm() })
  await start($)
  await begin($)

  await call($, { tool: 'mcp__claude_ai_Atlassian__getJiraIssue', cloudId: 'x', issueIdOrKey: 'BRKT-99' })
  expect(await quip($)).toBe(`Neighbor's cow got loose: number ${cowOf('BRKT-99')}.`)
  // A key that is not one, or a tool that is not it, brings no cow.
  await call($, { tool: 'mcp__claude_ai_Atlassian__getJiraIssue', cloudId: 'x', issueIdOrKey: '10042' })
  await call($, { tool: 'mcp__claude_ai_Atlassian__getConfluencePage', pageId: 'BRKT-5' })

  await call($, bash('git push'))
})


test('W deny rules in Jeb\'s voice: each pattern, a cap per rule, and the generic line otherwise', async ($, on) => {
  const clock = engine(on, { deny: 'no' })
  await start($)

  for (const [command, rule] of [
    ['git reset --hard HEAD~1', 'reset'],
    ['git push --force origin main', 'force'],
    ['docker compose down', 'down'],
    ['rm -rf node_modules', 'rmrf'],
    ['git clean -fd', 'clean'],
  ] as const) {
    await call($, bash(command))
    expect(await quip($)).toBe(DENY_LINES[rule])
  }
  // The rule that just spoke is capped for ten minutes: the generic line instead.
  await call($, bash('git reset --hard'))
  expect(said('denied', await quip($))).toBe(true)
  await call($, bash('ls'))
  expect(said('denied', await quip($))).toBe(true)
  await clock.advance(601_000)
  await call($, bash('git reset --hard'))
  expect(await quip($)).toBe(DENY_LINES.reset)
  expect(WORKDAY_LINES).toContain(DENY_LINES.reset)
})

test('W a settings hook that refuses a matching command gets the rule line, with the gate still up', CHATTY_HOOKS, async ($, on) => {
  engine(on, { result: {}, isError: true })
  v5(on)
  v5world.denyTools = true
  await start($)

  await call($, bash('git push --force'))
  expect(await quip($)).toBe(DENY_LINES.force)
  await call($, bash('git push --force'))
  expect(await quip($)).toBe('Somebody put up a gate.')
})

test('W a settings hook that refuses a command no deny rule names gets the gate line', CHATTY_HOOKS, async ($, on) => {
  engine(on, { result: {}, isError: true })
  v5(on)
  v5world.denyTools = true
  await start($)

  await call($, bash('ls'))
  expect(await quip($)).toBe('Somebody put up a gate.')
})

// Counts the lines a busy stretch of thirty calls spoke.
const busyStretch = async ($: any, clock: MockClock, calls = 30) => {
  await begin($)
  const start = seenState.says.length
  for (let i = 0; i < calls; i += 1) {
    await call($, { tool: ['Read', 'Edit', 'Grep'][i % 3], file_path: '/a', old_string: 'a', new_string: 'b' })
    await clock.advance(1_000)
  }

  return seenState.says.length - start
}

test('W talk ambient (the default): a busy turn of thirty calls speaks twice, ships and milestones still speak', async ($, on) => {
  const clock = engine(on, { result: {} }, { farm: farmWith({ lightning: 0, appleCinnamon: 3 }) })
  watch(on)
  await start($)

  const lines = await busyStretch($, clock)
  console.log(`ambient: ${lines} lines in a busy turn of 30 tool calls`)
  expect(lines).toBeLessThanOrEqual(2)
  expect(lines).toBeGreaterThanOrEqual(1)

  // A delivery speaks, so does a harvest, and a refused command.
  await call($, bash('git push'))
  expect(said('deliveryOut', await quip($))).toBe(true)
  await finish($, usage(9600, 0))
  expect(said('harvestCorn', await quip($))).toBe(true)
})

test('W talk ambient: the prompt speaks first, one more line follows, then the turn is quiet; idle is five minutes', async ($, on) => {
  const clock = engine(on, { result: {} })
  on('prompt.submit', (_, e) => e)
  watch(on)
  await start($)

  const greeted = seenState.says.length
  await submit($, { text: 'please carry on' })
  const opening = seenState.says.length
  expect(opening - greeted).toBe(1)
  await begin($)
  for (let i = 0; i < 12; i += 1) {
    await call($, { tool: 'Read', file_path: '/a' })
    await clock.advance(1_000)
  }
  expect(seenState.says.length - opening).toBe(1)
  // Ten minutes on, the next busy line is allowed again.
  await clock.advance(600_000)
  await call($, { tool: 'Edit', file_path: '/a', old_string: 'a', new_string: 'b' })
  // (a harvest from the ten minutes of work is a milestone and speaks on its own)
  expect(said('edit', seenState.says[seenState.says.length - 1] ?? '')).toBe(true)

  // Idle: the idle line comes at most every five minutes, not every minute.
  await finish($, usage(0, 0))
  const idleFrom = seenState.says.length
  await clock.advance(290_000)
  expect(seenState.says.length - idleFrom).toBeLessThanOrEqual(1)
  const after = seenState.says.length
  await clock.advance(600_000)
  expect(seenState.says.length - after).toBeLessThanOrEqual(3)
})

test('W talk chatty keeps every line', CHATTY, async ($, on) => {
  const clock = engine(on, { result: {} })
  watch(on)
  await start($)

  expect(await busyStretch($, clock)).toBeGreaterThanOrEqual(30)
})

test('W talk silent: no new lines but replies, the bubble dimmed, the scene still moves', { options: { talk: 'silent' } }, async ($, on) => {
  const clock = engine(on, { result: {} }, { farm: farmWith({ lightning: 0, appleCinnamon: 3 }) })
  watch(on)
  await start($)
  const greeting = seenState.says.length
  expect(greeting).toBe(0)

  expect(await busyStretch($, clock)).toBe(0)
  await call($, bash('git push'))
  await finish($, usage(9600, 0))
  await clock.advance(30_000)
  expect(seenState.says.length).toBe(0)
  expect(JSON.parse(seenState.atoms.anim ?? '{}').isDim).toBe(true)
})

test('W the hush: a writing burst of more than twenty chunks silences the chatter for a moment', CHATTY, async ($, on) => {
  const clock = engine(on, { result: {} })
  const text = (count: number) =>
    Array.from({ length: count }, (_, i) => ({ kind: 'text', index: 0, text: `w${i}` }))
  const plan = streams(on, text(25))
  watch(on)
  await start($)
  await begin($)

  await drain($)
  expect(said('writing', await quip($))).toBe(true)
  // Inside the burst only poses change: no new line.
  const said1 = seenState.says.length
  await call($, { tool: 'Read', file_path: '/a' })
  expect(seenState.says.length).toBe(said1)
  // A milestone is not chatter.
  await call($, bash('git push'))
  expect(seenState.says.length).toBeGreaterThan(said1)

  // Two seconds on the burst is over.
  await clock.advance(3_000)
  await call($, { tool: 'Edit', file_path: '/a', old_string: 'a', new_string: 'b' })
  expect(said('edit', await quip($))).toBe(true)

  // Twenty chunks is not a burst.
  plan.chunks = text(20)
  await drain($)
  await clock.advance(3_000)
  const before = seenState.says.length
  await call($, { tool: 'Read', file_path: '/a' })
  expect(seenState.says.length).toBeGreaterThan(before)
})

test('W the hush: after a failed test or lint run only verdicts and milestones speak for five minutes', CHATTY, async ($, on) => {
  const answer = { result: {}, isError: true }
  const clock = engine(on, answer)
  on('prompt.submit', (_, e) => e)
  watch(on)
  await start($)
  await begin($)

  await call($, bash('php artisan test'))
  expect(await quip($)).toBe(DROUGHT_LINE)
  const fails = seenState.says.length
  await call($, { tool: 'Read', file_path: '/a' })
  await call($, { tool: 'Edit', file_path: '/a', old_string: 'a', new_string: 'b' })
  await poke($)
  expect(seenState.says.length).toBe(fails)
  // A lint verdict speaks, and so does a delivery.
  await call($, bash('npx eslint .'))
  expect(await quip($)).toBe(WEEDS_LINE)
  answer.isError = false
  await call($, bash('git push'))
  expect(said('deliveryOut', await quip($))).toBe(true)
  // Still hushed for the rest (the truck's coming home is a milestone).
  await clock.advance(10_000)
  const mid = seenState.says.length
  await clock.advance(200_000)
  await call($, { tool: 'Read', file_path: '/a' })
  expect(seenState.says.length).toBe(mid)
  // Five minutes after the last failure the chatter is back.
  await clock.advance(100_000)
  await call($, { tool: 'Read', file_path: '/a' })
  expect(seenState.says.length).toBeGreaterThan(mid)
})

test('W a lint failure hushes too, in ambient as in chatty', async ($, on) => {
  const answer = { result: {}, isError: true }
  const clock = engine(on, answer)
  watch(on)
  await start($)
  await begin($)

  await call($, bash('vendor/bin/pint --test'))
  expect(await quip($)).toBe(WEEDS_LINE)
  await clock.advance(1_000)
  expect(seenState.says.length).toBeGreaterThan(0)
})


// ------------------------------------------------------------ v5.3 market ----

const at = (month: number, day: number, hour: number, minute = 0) => new Date(2026, month, day, hour, minute)

const WED = at(5, 10, 14)
const SAT = at(5, 13, 14)
const NIGHT = at(5, 10, 22)
const PREDAWN = at(5, 11, 3)
const OCT_WED = at(9, 14, 14)
const AUG_WED = at(7, 5, 14)
const JAN_WED = at(0, 14, 14)

// A farm with everything for sale, and changes to it.
const stocked = (over: object = {}) => ({
  ...freshFarm(),
  shelf: { lightning: 10, appleCinnamon: 6 },
  barn: { bales: 10, corn: 10, apples: 50, sticks: 0 },
  ...over,
})

const buyers = (now: Date, farm = stocked()) => eligibleCustomers(now, farm).map(entry => entry.id)

test('M1 pickCustomer: who is open on a weekday, at night, on Saturday, Sep-Nov, in August and in winter', () => {
  // A Wednesday afternoon in June: the store, Opal, the warehouse and the mill.
  expect(buyers(WED)).toEqual(['opal', 'store', 'warehouse', 'mill'])
  // Saturday: the store shuts, the farmers market opens.
  expect(buyers(SAT)).toEqual(['opal', 'warehouse', 'market', 'mill'])
  // Night: the tripper, and no store.
  expect(buyers(NIGHT)).toEqual(['opal', 'tripper', 'warehouse', 'mill'])
  expect(buyers(PREDAWN)).toContain('tripper')
  expect(buyers(at(5, 11, 5))).not.toContain('tripper')
  expect(buyers(at(5, 10, 17, 59))).not.toContain('tripper')
  expect(buyers(at(5, 10, 18))).toContain('tripper')
  // Store hours: weekdays 08:00 to 18:00.
  expect(buyers(at(5, 10, 7, 59))).not.toContain('store')
  expect(buyers(at(5, 10, 8))).toContain('store')
  expect(buyers(at(5, 10, 17, 59))).toContain('store')
  expect(buyers(at(5, 10, 18))).not.toContain('store')
  expect(buyers(at(5, 14, 12))).not.toContain('store')
  // September to November: the market is open every day, not in June.
  expect(buyers(OCT_WED)).toContain('market')
  expect(buyers(at(8, 2, 10))).toContain('market')
  expect(buyers(at(10, 18, 10))).toContain('market')
  expect(buyers(at(11, 9, 14))).not.toContain('market')
  expect(buyers(WED)).not.toContain('market')
  // August: the county fair, once a year.
  expect(buyers(AUG_WED)).toContain('fair')
  expect(buyers(at(6, 8, 14))).not.toContain('fair')
  expect(buyers(AUG_WED, stocked({ ledger: { ...freshFarm().ledger, fairYear: 2026 } }))).not.toContain('fair')
  expect(buyers(AUG_WED, stocked({ ledger: { ...freshFarm().ledger, fairYear: 2025 } }))).toContain('fair')
  // The warehouse is always open: the winter bale price is the one bump.
  expect(buyers(JAN_WED)).toContain('warehouse')
  expect(wantsOf('warehouse', JAN_WED, stocked())[0]?.price).toBe(55)
  expect(wantsOf('warehouse', at(1, 25, 9), stocked())[0]?.price).toBe(55)
  expect(wantsOf('warehouse', at(11, 20, 9), stocked())[0]?.price).toBe(55)
  expect(wantsOf('warehouse', at(2, 1, 9), stocked())[0]?.price).toBe(40)
  expect(wantsOf('warehouse', at(10, 30, 9), stocked())[0]?.price).toBe(40)
  expect(wantsOf('warehouse', WED, stocked())[0]?.price).toBe(40)
  // Nobody comes with nothing to buy, and nobody buys for the legacy bucket.
  expect(buyers(WED, freshFarm())).toEqual([])
  expect(pickCustomer(WED, freshFarm(), () => 0)).toBeUndefined()
  expect(CUSTOMER_IDS.filter(id => wantsOf(id, WED, stocked()).length > 0)).not.toContain('town')
})

test('M2 pickCustomer: weighted by what each buyer could pay, deterministic given the dice', () => {
  const farm = stocked({ barn: { bales: 0, corn: 0, apples: 0, sticks: 0 }, shelf: { lightning: 0, appleCinnamon: 3 } })
  // Opal could pay $25, the store $60 (three jars at $20): 85 in all.
  expect(eligibleCustomers(WED, farm)).toEqual([
    { id: 'opal', weight: 25 },
    { id: 'store', weight: 60 },
  ])
  expect(pickCustomer(WED, farm, () => 0)).toBe('opal')
  expect(pickCustomer(WED, farm, () => 25 / 85 - 0.001)).toBe('opal')
  expect(pickCustomer(WED, farm, () => 25 / 85 + 0.001)).toBe('store')
  expect(pickCustomer(WED, farm, () => 0.9999)).toBe('store')
  // The more surplus, the likelier: the warehouse with nine bales dwarfs Opal.
  const bales = stocked({ barn: { bales: 9, corn: 0, apples: 0, sticks: 0 }, shelf: { lightning: 0, appleCinnamon: 1 } })
  expect(eligibleCustomers(WED, bales).find(entry => entry.id === 'warehouse')?.weight).toBe(360)
  // The fair, open once a year, is never passed up: it is listed at 1000 and always drawn.
  const fair = eligibleCustomers(AUG_WED, stocked()).find(entry => entry.id === 'fair')
  expect(fair?.weight).toBe(FAIR_WEIGHT)
  expect(pickCustomer(AUG_WED, stocked(), () => 0)).toBe('fair')
  expect(pickCustomer(AUG_WED, stocked(), () => 0.9999)).toBe('fair')
  // The live farm on a Thursday afternoon in October.
  const live = {
    ...freshFarm(),
    shelf: { lightning: 26, appleCinnamon: 32 },
    barn: { bales: 0, corn: 5, apples: 118, sticks: 0 },
  }
  expect(eligibleCustomers(at(9, 22, 14), live)).toEqual([
    { id: 'opal', weight: 25 },
    { id: 'store', weight: 180 },
    { id: 'market', weight: 180 },
    { id: 'mill', weight: 8 },
  ])
  expect(eligibleCustomers(at(9, 22, 20), live).map(entry => entry.id)).toEqual(['opal', 'tripper', 'market', 'mill'])
})

test('M3 reserves: bales wait for the lightning on the shelf, apples and corn keep their floors', () => {
  const farm = (bales: number, lightning: number) =>
    stocked({ barn: { bales, corn: 0, apples: 0, sticks: 0 }, shelf: { lightning, appleCinnamon: 0 } })
  // Eight sticks to a bale: ceil(lightning waiting / 8) bales stay in the barn.
  expect(STICKS_PER_BALE).toBe(8)
  expect(reserveBales(farm(5, 0))).toBe(0)
  expect(reserveBales(farm(5, 1))).toBe(1)
  expect(reserveBales(farm(5, 8))).toBe(1)
  expect(reserveBales(farm(5, 9))).toBe(2)
  expect(reserveBales(farm(5, 26))).toBe(4)
  expect(surplusOf(farm(5, 0)).bales).toBe(5)
  expect(surplusOf(farm(5, 17)).bales).toBe(2)
  expect(surplusOf(farm(2, 26)).bales).toBe(0)
  expect(wantsOf('warehouse', WED, farm(2, 26))).toEqual([])
  expect(wantsOf('warehouse', WED, farm(5, 17))[0]).toMatchObject({ product: 'tobacco', min: 2, max: 2 })

  // Ten bushels of apples and three of corn stay: one more and the rest may go.
  const barn = (apples: number, corn: number) => stocked({ shelf: { lightning: 0, appleCinnamon: 0 }, barn: { bales: 0, corn, apples, sticks: 0 } })
  expect(APPLE_KEEP).toBe(10)
  expect(CORN_KEEP).toBe(3)
  expect(wantsOf('market', SAT, barn(10, 3))).toEqual([])
  expect(wantsOf('store', WED, barn(10, 3))).toEqual([])
  expect(wantsOf('mill', WED, barn(10, 3))).toEqual([])
  expect(wantsOf('market', SAT, barn(11, 3))[0]).toMatchObject({ product: 'apples', max: 1 })
  expect(wantsOf('mill', WED, barn(10, 4))[0]).toMatchObject({ product: 'corn', max: 1 })

  // Sell until nobody wants anything: no floor is ever crossed, with any dice.
  for (const dice of [0, 0.3, 0.99]) {
    let now = SAT
    let state = stocked({ shelf: { lightning: 17, appleCinnamon: 0 }, barn: { bales: 5, corn: 9, apples: 80, sticks: 0 } }) as ReturnType<typeof freshFarm>
    for (let i = 0; i < 20; i += 1) {
      const out = sellTo(state, undefined, now, () => dice)
      if (!out.sale) {
        break
      }
      state = out.next
      expect(state.barn.apples).toBeGreaterThanOrEqual(APPLE_KEEP)
      expect(state.barn.corn).toBeGreaterThanOrEqual(CORN_KEEP)
      expect(state.barn.bales).toBeGreaterThanOrEqual(reserveBales(state))
    }
    expect(state.barn).toEqual({ bales: 3, corn: 3, apples: 10, sticks: 0 })
    now = SAT
  }
})

test('M4 each buyer: lots, prices, the seasonal bump, the fair once a year and its ribbon', () => {
  const sale = (id: Parameters<typeof planSale>[0], now: Date, dice: number, farm = stocked()) =>
    planSale(id, now, farm as ReturnType<typeof freshFarm>, () => dice)

  // Miss Opal: one jar, $25.
  expect(sale('opal', WED, 0.7)).toMatchObject({ total: 25, lines: [{ product: 'appleCinnamon', qty: 1, dollars: 25 }] })
  // Tolliver's: 2 to 4 jars at $20, and up to 20 bushels of apples at $5.
  expect(sale('store', WED, 0)?.lines).toEqual([
    { product: 'appleCinnamon', qty: 2, dollars: 40 },
    { product: 'apples', qty: 20, dollars: 100 },
  ])
  expect(sale('store', WED, 0.99)).toMatchObject({ total: 180 })
  expect(sale('store', WED, 0.5)?.lines[0]).toMatchObject({ qty: 3, dollars: 60 })
  // Fewer jars than the lot: it takes what there is, and one jar is none for the store.
  expect(sale('store', WED, 0.99, stocked({ shelf: { lightning: 0, appleCinnamon: 3 }, barn: { bales: 0, corn: 0, apples: 0, sticks: 0 } }))?.lines).toEqual([
    { product: 'appleCinnamon', qty: 3, dollars: 60 },
  ])
  expect(sale('store', WED, 0, stocked({ shelf: { lightning: 0, appleCinnamon: 1 }, barn: { bales: 0, corn: 0, apples: 12, sticks: 0 } }))?.lines).toEqual([
    { product: 'apples', qty: 2, dollars: 10 },
  ])
  // The tripper: 4 to 6 jars of white lightning at $15, after dark.
  expect(sale('tripper', NIGHT, 0)?.lines).toEqual([{ product: 'whiteLightning', qty: 4, dollars: 60 }])
  expect(sale('tripper', NIGHT, 0.99)?.lines).toEqual([{ product: 'whiteLightning', qty: 6, dollars: 90 }])
  expect(sale('tripper', NIGHT, 0.99, stocked({ shelf: { lightning: 5, appleCinnamon: 0 } }))?.lines[0]).toMatchObject({ qty: 5, dollars: 75 })
  expect(sale('tripper', NIGHT, 0, stocked({ shelf: { lightning: 3, appleCinnamon: 0 } }))).toBeUndefined()
  expect(sale('tripper', WED, 0)).toBeUndefined()
  // The warehouse: every surplus bale, $40, or $55 from December to February.
  expect(sale('warehouse', WED, 0)?.lines).toEqual([{ product: 'tobacco', qty: 8, dollars: 320 }])
  expect(sale('warehouse', JAN_WED, 0)?.lines).toEqual([{ product: 'tobacco', qty: 8, dollars: 440 }])
  // The farmers market: up to 30 bushels of surplus apples at $6.
  expect(sale('market', SAT, 0)?.lines).toEqual([{ product: 'apples', qty: 30, dollars: 180 }])
  expect(sale('market', SAT, 0, stocked({ barn: { bales: 0, corn: 0, apples: 25, sticks: 0 } }))?.lines).toEqual([
    { product: 'apples', qty: 15, dollars: 90 },
  ])
  // The feed mill: surplus corn at $4.
  expect(sale('mill', WED, 0)?.lines).toEqual([{ product: 'corn', qty: 7, dollars: 28 }])

  // The fair: one best jar, $50, and a ribbon; once a year.
  const fair = sale('fair', AUG_WED, 0)
  expect(fair).toMatchObject({ total: 50, isRibbon: true, lines: [{ product: 'appleCinnamon', qty: 1, dollars: 50 }] })
  const after = applySale(stocked() as ReturnType<typeof freshFarm>, fair as NonNullable<typeof fair>, AUG_WED)
  expect(after.ledger.ribbons).toBe(1)
  expect(after.ledger.fairYear).toBe(2026)
  expect(after.shelf.appleCinnamon).toBe(5)
  expect(buyers(AUG_WED, after)).not.toContain('fair')
  expect(buyers(at(7, 20, 9), after)).not.toContain('fair')
  expect(buyers(new Date(2027, 7, 5, 14), after)).toContain('fair')
  const again = applySale(after, sale('fair', new Date(2027, 7, 5, 14), 0, after) as NonNullable<typeof fair>, new Date(2027, 7, 5, 14))
  expect(again.ledger.ribbons).toBe(2)
  expect(again.ledger.fairYear).toBe(2027)
  expect(again.ledger.byCustomer.fair).toBe(100)
  // A sale never takes the shelf or barn below zero.
  const thin = applySale(freshFarm(), { customer: 'opal', lines: [{ product: 'appleCinnamon', qty: 1, dollars: 25 }], total: 25, isRibbon: false }, WED)
  expect(thin.shelf.appleCinnamon).toBe(0)
})

test('M5 the ledger: totals, month rollover, best sale, by customer and by product', () => {
  let farm = stocked() as ReturnType<typeof freshFarm>
  const sell = (id: Parameters<typeof planSale>[0], now: Date, dice = 0) => {
    const made = planSale(id, now, farm, () => dice)
    farm = applySale(farm, made as NonNullable<typeof made>, now)

    return made
  }
  sell('opal', at(5, 10, 14))
  expect(farm.ledger).toMatchObject({ total: 25, month: { key: '2026-06', amount: 25 }, jarsSold: 1 })
  expect(farm.ledger.best).toEqual({ amount: 25, customer: 'opal', product: 'appleCinnamon' })

  // The store's mixed sale: the best product is the one that paid most, apples.
  sell('store', at(5, 17, 10))
  expect(farm.ledger.total).toBe(25 + 140)
  expect(farm.ledger.jarsSold).toBe(3)
  expect(farm.ledger.month).toEqual({ key: '2026-06', amount: 165 })
  expect(farm.ledger.best).toEqual({ amount: 140, customer: 'store', product: 'apples' })

  // A smaller sale does not take the record; an equal one does not either.
  sell('opal', at(5, 18, 10))
  expect(farm.ledger.best?.amount).toBe(140)

  // A new month starts the month's amount over; the lifetime total goes on.
  sell('mill', at(6, 1, 10))
  expect(farm.ledger.month).toEqual({ key: '2026-07', amount: 28 })
  expect(farm.ledger.total).toBe(165 + 25 + 28)
  // Another year, the same month number is another month.
  farm = { ...farm, barn: { ...farm.barn, corn: 6 } }
  sell('mill', new Date(2027, 6, 1, 10))
  expect(farm.ledger.month.key).toBe('2027-07')

  const { ledger } = farm
  expect(ledger.byCustomer).toMatchObject({ opal: 50, store: 140, mill: 28 + 12 })
  expect(ledger.byProduct.appleCinnamon).toBe(50 + 40)
  expect(ledger.byProduct.apples).toBe(100)
  expect(ledger.byProduct.corn).toBe(28 + 12)
  // The parts always add up to the whole.
  const sum = (record: Record<string, number>) => Object.values(record).reduce((a, b) => a + b, 0)
  expect(sum(ledger.byCustomer)).toBe(ledger.total)
  expect(sum(ledger.byProduct)).toBe(ledger.total)
  // Fixed key sets only.
  expect(Object.keys(ledger.byCustomer).sort()).toEqual([...CUSTOMER_IDS].sort())
  expect(Object.keys(ledger.byProduct).sort()).toEqual([...PRODUCTS].sort())
  // A bigger sale takes the record.
  farm = { ...farm, barn: { ...farm.barn, apples: 50 } }
  sell('market', at(9, 14, 10))
  expect(farm.ledger.best).toEqual({ amount: 180, customer: 'market', product: 'apples' })
})

test('M6 migration: a v4 farm becomes v6 books (cash = what it earned), the live numbers included', () => {
  const live = {
    version: 4,
    crops: { tobacco: Array(8).fill(1), corn: Array(8).fill(2), apples: Array(8).fill(3) },
    progress: { tobacco: 5, corn: 6, apples: 7 },
    barn: { bales: 0, corn: 5, apples: 118, sticks: 0 },
    still: { steps: 2, hasBatch: true },
    shelf: { lightning: 26, appleCinnamon: 32 },
    lifetime: { outputTokens: 10, inputTokens: 20, workMs: 30, bales: 12, balesTraded: 12 },
    delivery: { deliveries: 2, jarsSold: 13, dollars: 325 },
    upgrades: ['mailbox', 'chair', 'hen'],
    lastProof: 100,
    bestProof: 120,
    milestones: ['jar10'],
  }
  const farm = loadFarm(live)
  expect(farm?.version).toBe(10)
  // Everything but the books is as it was.
  expect(farm?.shelf).toEqual({ lightning: 26, appleCinnamon: 32 })
  expect(farm?.barn).toEqual({ bales: 0, corn: 5, apples: 118, sticks: 0 })
  expect(farm?.upgrades).toEqual(['mailbox', 'chair', 'hen'])
  expect(farm?.milestones).toEqual(['jar10'])
  expect(farm).not.toHaveProperty('delivery')
  // The books: $325 in all; two runs sold four jars at most, so at least nine of
  // the thirteen were Miss Opal's ($225); the other $100 cannot be told apart.
  expect(farm?.ledger).toEqual({
    deliveries: 2,
    jarsSold: 13,
    total: 325,
    month: { key: '', amount: 0 },
    best: null,
    byCustomer: { opal: 225, store: 0, tripper: 0, warehouse: 0, market: 0, mill: 0, fair: 0, town: 100 },
    byProduct: { appleCinnamon: 325, whiteLightning: 0, tobacco: 0, apples: 0, corn: 0, appleButter: 0, twists: 0, agedWhiskey: 0 },
    ribbons: 0,
    fairYear: 0,
    // The v6 books: the $325 it earned is all still in hand.
    cash: 325,
    spent: 0,
    byPurchase: { sugar: 0, copper: 0 },
  })
  // A farm that cannot tell Opal apart (no neighbor sales: all runs) puts it all in town.
  expect(loadFarm({ ...live, delivery: { deliveries: 5, jarsSold: 8, dollars: 200 } })?.ledger.byCustomer).toMatchObject({ opal: 0, town: 200 })
  // Older farms had no book at all.
  const { delivery, ...v2 } = live
  void delivery
  expect(loadFarm({ ...v2, version: 2 })?.ledger).toEqual(freshFarm().ledger)
  // Reading a v5 farm again changes nothing, and a damaged ledger is normalized.
  expect(loadFarm(farm)).toEqual(farm)
  const damaged = loadFarm({
    ...(farm as object),
    ledger: {
      total: -4,
      jarsSold: 'x',
      month: { key: 'June', amount: 99 },
      best: { amount: 5, customer: 'nobody', product: 'corn' },
      byCustomer: { opal: Number.NaN, mill: 7.9, bogus: 5 },
      byProduct: null,
      ribbons: Infinity,
      fairYear: -1,
    },
  })
  expect(damaged?.ledger).toEqual({
    ...freshFarm().ledger,
    byCustomer: { ...freshFarm().ledger.byCustomer, mill: 7 },
  })
  // Upgrades and milestones read the books.
  const unlocks = newUnlocks(farm as NonNullable<typeof farm>)
  expect(unlocks.upgrades).toEqual([])
  expect(unlocks.milestones.map(m => m.id)).toEqual(['bale10'])
  expect(newUnlocks({ ...(farm as NonNullable<typeof farm>), ledger: { ...(farm as NonNullable<typeof farm>).ledger, total: 500 } }).upgrades.map(u => u.id)).toEqual(['pup'])
})

test('M6 migration: the live store becomes v6 when a session starts, and the tally reads the books', async ($, on) => {
  const live = {
    ...farmWith({ lightning: 26, appleCinnamon: 32 }),
    version: 4,
    barn: { bales: 0, corn: 5, apples: 118, sticks: 0 },
    delivery: { deliveries: 2, jarsSold: 13, dollars: 325 },
  }
  engine(on, { result: {} }, { farm: live }, at(9, 22, 14).getTime())
  await start($)
  const stored = world.db.get('farm') as ReturnType<typeof freshFarm>
  expect(stored.version).toBe(10)
  expect(stored.ledger.total).toBe(325)
  expect(stored.ledger.byCustomer).toMatchObject({ opal: 225, town: 100 })
  expect(stored).not.toHaveProperty('delivery')
  const text = await tally($)
  expect(text).toContain('Deliveries: 2 trips, 13 jars sold, $325.')
  expect(stored.ledger.byProduct).toMatchObject({ appleCinnamon: 325, whiteLightning: 0, tobacco: 0 })
  expect(text).toContain('26 white lightning, 32 apple cinnamon')
})

test('M7 two sessions selling at once: a sale is decided on the stored farm, never oversold or counted twice', async ($, on) => {
  // Pure: the second of two sales on one jar finds the shelf bare.
  const one = { ...freshFarm(), shelf: { lightning: 0, appleCinnamon: 1 } }
  const first = sellTo(one, 'opal', WED, () => 0)
  expect(first.sale?.total).toBe(25)
  const second = sellTo(first.next, 'opal', WED, () => 0)
  expect(second.sale).toBeUndefined()
  expect(second.next).toBe(first.next)
  expect(first.next.shelf.appleCinnamon).toBe(0)
  expect(first.next.ledger.total).toBe(25)

  // Through the store: while the truck is out another session sells the last
  // jar; when this one gets home it sells nothing and counts nothing twice.
  const clock = engine(on, { result: {} }, { farm: farmWith({ lightning: 0, appleCinnamon: 1 }) })
  await start($)
  await call($, { tool: 'Bash', command: 'git push' })
  const other = loadFarm(world.db.get('farm')) as ReturnType<typeof freshFarm>
  world.db.set(
    'farm',
    applySale(other, planSale('opal', WED, other, () => 0) as NonNullable<ReturnType<typeof planSale>>, WED),
  )
  await clock.advance(9_000)
  const text = await tally($)
  expect(text).toContain('1 trip, 1 jar sold, $25.')
  expect(text).toContain('0 apple cinnamon')
  const stored = world.db.get('farm') as ReturnType<typeof freshFarm>
  expect(stored.ledger.total).toBe(25)
  expect(stored.ledger.deliveries).toBe(1)
  expect(stored.shelf.appleCinnamon).toBe(0)
})

// Each farm has exactly one buyer open, so the run is not left to the dice.
const EMPTY_BARN = { bales: 0, corn: 0, apples: 0, sticks: 0 }
const EMPTY_SHELF = { lightning: 0, appleCinnamon: 0 }

const truckSells = (label: string, farm: object, now: Date, glyph: string, what: RegExp, totals: RegExp) =>
  test(`M8 the truck: ${label}`, CHATTY, async ($, on) => {
    const clock = engine(on, { result: {} }, { farm }, now.getTime())
    watch(on)
    await start($)
    await call($, { tool: 'Bash', command: 'git push' })
    await clock.advance(9_000)
    expect(await tally($)).toMatch(totals)
    // The sale is named in the bubble (an upgrade it earned may speak after it).
    expect(seenState.says.some(line => what.test(line))).toBe(true)
  })

truckSells('jars go to Miss Opal (one jar: the store wants two)', { ...freshFarm(), shelf: { lightning: 0, appleCinnamon: 1 } }, WED, '🫙', /Miss Opal/, /1 trip, 1 jar sold, \$25/)
truckSells('bales go to the warehouse, the bed carries the leaf', { ...freshFarm(), shelf: EMPTY_SHELF, barn: { ...EMPTY_BARN, bales: 9 } }, WED, '🌿', /warehouse/i, /tobacco \$360/)
truckSells('apples go to the farmers market on a Saturday', { ...freshFarm(), shelf: EMPTY_SHELF, barn: { ...EMPTY_BARN, apples: 40 } }, SAT, '🍎', /market|tailgate/i, /apples \$180/)
// (the push is a Bash call: the still takes one bushel of corn, leaving nine, six above the floor)
truckSells('corn goes to the feed mill', { ...freshFarm(), shelf: EMPTY_SHELF, barn: { ...EMPTY_BARN, corn: 10 } }, WED, '🌽', /mill/i, /corn \$24/)
truckSells('white lightning goes to the tripper at night', { ...freshFarm(), shelf: { lightning: 4, appleCinnamon: 0 } }, NIGHT, '🫙', /tripper/i, /white lightning \$60/)
truckSells('the county fair in August pays the prize and a ribbon', { ...freshFarm(), shelf: { lightning: 0, appleCinnamon: 2 } }, AUG_WED, '🫙', /🎀/u, /Ribbons: 🎀x1/)

test('M8 the truck: with nothing to sell it carries a box and the old line, and counts the trip', CHATTY, async ($, on) => {
  const clock = engine(on, { result: {} }, { farm: freshFarm() }, WED.getTime())
  await start($)
  await call($, { tool: 'Bash', command: 'git push' })
  await clock.advance(9_000)
  expect(said('deliveryBack', await quip($))).toBe(true)
  expect(await tally($)).toContain('1 trip, 0 jars sold, $0.')
  expect(loadFor(undefined, WED, freshFarm())).toBe('box')
  expect(loadFor('tripper', NIGHT, stocked() as ReturnType<typeof freshFarm>)).toBe('jar')
})

test('M9 sale lines: no-repeat bags per buyer, the sale named, money and goods filled in', () => {
  for (const category of ['saleOpal', 'saleStore', 'saleTripper', 'saleWarehouse', 'saleMarket', 'saleMill', 'saleFair'] as const) {
    const size = SAYINGS[category].length
    expect(size).toBeGreaterThanOrEqual(3)
    for (const line of SAYINGS[category]) {
      expect(line).toContain('{money}')
    }
    for (let round = 0; round < 2; round += 1) {
      const dealt = Array.from({ length: size }, () => bagPick(category))
      expect(new Set(dealt).size).toBe(size)
    }
  }
  const store = planSale('store', WED, stocked({ shelf: { lightning: 0, appleCinnamon: 3 }, barn: { bales: 0, corn: 0, apples: 0, sticks: 0 } }) as ReturnType<typeof freshFarm>, () => 0.5) as NonNullable<ReturnType<typeof planSale>>
  expect(fillSale('Tolliver took {what}. {money}.', store)).toBe('Tolliver took three jars. $60.')
  expect(SAYINGS.saleStore).toContain('Tolliver took {what}. {money}.')
  const mixed = planSale('store', WED, stocked() as ReturnType<typeof freshFarm>, () => 0) as NonNullable<ReturnType<typeof planSale>>
  expect(fillSale('{money} for {what}', mixed)).toBe('$140 for two jars, 20 bu apples')
  for (const line of Object.values(SAYINGS).flat()) {
    expect(line.length).toBeLessThan(80)
  }
})

const escapeRe = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const isSale = (category: SayingCategory, line: string) =>
  (SAYINGS[category] as readonly string[]).some(template => {
    const pattern = template
      .split(/(\{what\}|\{money\})/)
      .map(part => (part === '{what}' ? '.+' : part === '{money}' ? '\\$\\d+' : escapeRe(part)))
      .join('')

    return new RegExp(`^${pattern}$`).test(line)
  })

// A delivery in the middle of a busy turn whose two lines of allowance are spent;
// what Jeb said as the truck got home. Saturdays: the store is shut, so only Miss
// Opal (or the fair, in August) buys.
const busyDelivery = async ($: any, on: any, farm: object, now: Date) => {
  const clock = engine(on, { result: {} }, { farm }, now.getTime())
  watch(on)
  await start($)
  await begin($)
  await call($, { tool: 'Read', file_path: '/a' })
  await call($, { tool: 'Read', file_path: '/b' })
  await call($, { tool: 'Bash', command: 'git push' })
  const before = seenState.says.length
  await clock.advance(9_000)

  return seenState.says.slice(before).filter(line => !line.startsWith('Got me') && !line.includes('Rockin'))
}

const JARS_ONLY = { lightning: 0, appleCinnamon: 4 }
const AUG_SAT = at(7, 8, 14)

test('M10 talk: a new buyer first sale is news, so ambient says it even on a spent busy allowance', async ($, on) => {
  const lines = await busyDelivery($, on, { ...freshFarm(), shelf: JARS_ONLY }, SAT)
  expect(lines.length).toBe(1)
  expect(isSale('saleOpal', lines[0] ?? '')).toBe(true)
})

test('M10 talk: any other sale is ordinary busy chatter, held back by the busy allowance', async ($, on) => {
  const old = {
    ...freshFarm(),
    shelf: JARS_ONLY,
    ledger: { ...freshFarm().ledger, byCustomer: { ...freshFarm().ledger.byCustomer, opal: 25 } },
  }
  expect(await busyDelivery($, on, old, SAT)).toEqual([])
  // ...and still lands in the books.
  expect(await tally($)).toContain('1 trip, 1 jar sold, $25.')
})

test('M10 talk: the fair always speaks, though its buyer was met before', async ($, on) => {
  const old = {
    ...freshFarm(),
    shelf: JARS_ONLY,
    ledger: { ...freshFarm().ledger, fairYear: 2025, byCustomer: { ...freshFarm().ledger.byCustomer, fair: 50 } },
  }
  const lines = await busyDelivery($, on, old, AUG_SAT)
  expect(lines.length).toBe(1)
  expect(isSale('saleFair', lines[0] ?? '')).toBe(true)
  expect(lines[0]).toContain('🎀')
})


// ------------------------------------------- v5.4 materials, crafting, the stack ----

type Farm6 = ReturnType<typeof freshFarm>

const farm6 = (over: Partial<Farm6> = {}): Farm6 => ({ ...freshFarm(), ...over })
const stuff = (over: Partial<Record<Material, number>>) => ({ ...freshFarm().materials, ...over })
const parts = (over: Partial<Farm6['components']>) => ({ ...freshFarm().components, ...over })
const goodsOf = (over: Partial<Farm6['goods']>) => ({ ...freshFarm().goods, ...over })
const withLedger = (over: Partial<Farm6['ledger']>) => ({ ...freshFarm().ledger, ...over })
const storedFarm = () => loadFarm(world.db.get('farm')) as Farm6

const NOW = new Date(JUNE_NOON)
const DAYS3 = 3 * DAY

test('K1 lumber: one piece for every third successful edit, from the main loop or a subagent, none for a failed one', async ($, on) => {
  const answer = { result: {}, isError: false }
  engine(on, answer)
  await start($)
  await call($, { tool: 'Edit', file_path: '/a' })
  await call($, { tool: 'Write', file_path: '/b', agentId: 'sub' })
  expect(storedFarm().counters.edits).toBe(2)
  expect(storedFarm().materials.lumber).toBe(0)
  // A failed edit counts for nothing.
  answer.isError = true
  await call($, { tool: 'Edit', file_path: '/a' })
  expect(storedFarm().counters.edits).toBe(2)
  answer.isError = false
  await call($, { tool: 'NotebookEdit', file_path: '/n' })
  expect(storedFarm().counters.edits).toBe(3)
  expect(storedFarm().materials.lumber).toBe(1)
  // A read is not an edit.
  await call($, { tool: 'Read', file_path: '/a' })
  expect(storedFarm().counters.edits).toBe(3)
  for (let i = 0; i < 3; i += 1) {
    await call($, { tool: 'Edit', file_path: '/a' })
  }
  expect(storedFarm().materials.lumber).toBe(2)
  // Pure: the counter alone decides.
  expect(noteEdit(farm6()).materials.lumber).toBe(0)
  expect(noteEdit(farm6({ counters: { edits: 2, mothmanSeen: 0 } })).materials.lumber).toBe(1)
})

test('K2 stone for every passing test run, iron for the first pass after a failed test or lint run', async ($, on) => {
  const answer = { result: {}, isError: false }
  engine(on, answer)
  await start($)
  const test = 'php artisan test'
  const lint = 'docker compose exec app vendor/bin/pint --test'

  await call($, bash(test))
  expect(storedFarm().materials).toMatchObject({ stone: 1, iron: 0 })
  answer.isError = true
  await call($, bash(test))
  expect(storedFarm().materials).toMatchObject({ stone: 1, iron: 0 })
  answer.isError = false
  await call($, bash(test))
  expect(storedFarm().materials).toMatchObject({ stone: 2, iron: 1 })
  // The next pass is not a fix.
  await call($, bash(test))
  expect(storedFarm().materials).toMatchObject({ stone: 3, iron: 1 })

  // A lint run: stone is for tests only; the first clean run after a failure gives iron.
  answer.isError = true
  await call($, bash(lint))
  answer.isError = false
  await call($, bash(lint))
  expect(storedFarm().materials).toMatchObject({ stone: 3, iron: 2 })
  await call($, bash(lint))
  expect(storedFarm().materials.iron).toBe(2)
  // A run that rewrites files has passed nothing: no iron, and the failure stays owed.
  answer.isError = true
  await call($, bash('docker compose exec app vendor/bin/pint'))
  answer.isError = false
  await call($, bash('docker compose exec app vendor/bin/pint'))
  expect(storedFarm().materials.iron).toBe(2)
  await call($, bash(lint))
  expect(storedFarm().materials.iron).toBe(3)
})

test('K3 straw: two for a tobacco harvest, one for a corn harvest', async ($, on) => {
  const clock = engine(on)
  await start($)
  // 9600 output tokens: one bushel of corn.
  await finish($, usage(9600, 0))
  expect(storedFarm().materials.straw).toBe(1)
  // 24 stages of tobacco at 20 s each: one bale (kept: there are no sticks, so one bale stays back).
  await begin($)
  await call($, { tool: 'Read', file_path: '/a' })
  await clock.advance(480_000)
  expect(storedFarm().lifetime.bales).toBe(1)
  expect(storedFarm().materials.straw).toBe(3)
  // Apples give none.
  await finish($, usage(0, 600_000))
  expect(storedFarm().materials.straw).toBe(3)
})

test('K4 purchases: sugar at $8 and copper at $30 only with the cash, spending cash and never the lifetime total', { timeoutMs: 30_000 }, async ($, on) => {
  const apples = { barn: { bales: 0, corn: 0, apples: 15, sticks: 2 } }
  const rich = farm6({ ...apples, ledger: withLedger({ total: 500, cash: 100 }) })
  const bought = buySupplies(rich)
  expect(bought.sugar).toBe(3)
  expect(bought.copper).toBe(1)
  expect(bought.next.materials).toMatchObject({ sugar: 3, copper: 1 })
  // $24 + $30 spent from the cash; the earnings are untouched.
  expect(bought.next.ledger).toMatchObject({ total: 500, cash: 46, spent: 54, byPurchase: { sugar: 24, copper: 30 } })
  // Milestone upgrades read the total: nothing is taken back.
  expect(newUnlocks(bought.next).upgrades.map(u => u.id)).toEqual(newUnlocks(rich).upgrades.map(u => u.id))
  // Cash decides how many: $10 is one sugar and no copper; $7 is nothing at all.
  expect(buySupplies(farm6({ ...apples, ledger: withLedger({ total: 500, cash: 10 }) })).sugar).toBe(1)
  expect(buySupplies(farm6({ ...apples, ledger: withLedger({ total: 500, cash: 10 }) })).copper).toBe(0)
  const poor = farm6({ ...apples, ledger: withLedger({ total: 500, cash: 7 }) })
  expect(buySupplies(poor).next).toBe(poor)
  // Copper waits for the cash even when sugar does not.
  expect(buySupplies(farm6({ ...apples, ledger: withLedger({ total: 500, cash: 29 }) })).copper).toBe(0)
  expect(buySupplies(farm6({ ...apples, ledger: withLedger({ total: 500, cash: 54 }) }))).toMatchObject({ sugar: 3, copper: 1 })
  // Sugar only when the butter lacks only that: apples above the floor, a stick, none in hand already.
  const stillOk = (over: object) => buySupplies(farm6({ ledger: withLedger({ total: 500, cash: 100 }), ...apples, built: ['thumpKeg', 'smokehouse', 'fencedFields', 'copperWorm'], ...over })).sugar
  expect(stillOk({})).toBe(3)
  expect(stillOk({ barn: { bales: 0, corn: 0, apples: 14, sticks: 2 } })).toBe(0)
  expect(stillOk({ barn: { bales: 0, corn: 0, apples: 15, sticks: 0 } })).toBe(0)
  expect(stillOk({ materials: stuff({ sugar: 1 }) })).toBe(0)
  // Copper only for the queued upgrade: none for the smokehouse, two coils' worth for the worm.
  const copperFor = (built: string[], over: object = {}) => buySupplies(farm6({ ledger: withLedger({ total: 500, cash: 500 }), built, ...over })).copper
  expect(copperFor(['thumpKeg'])).toBe(0)
  expect(copperFor(['thumpKeg', 'smokehouse', 'fencedFields'])).toBe(2)
  expect(copperFor(['thumpKeg', 'smokehouse', 'fencedFields'], { components: parts({ coil: 1 }) })).toBe(1)
  expect(copperFor(['thumpKeg', 'smokehouse', 'fencedFields'], { materials: stuff({ copper: 2 }) })).toBe(0)
  // With the four built, the next keepsake that wants copper is what it buys for.
  expect(copperFor(BUILDS.map(b => b.id))).toBe(1)

  // Through a truck run: the supplies come first, then the sale, then the books agree.
  const farm = farm6({
    barn: { bales: 0, corn: 0, apples: 30, sticks: 2 },
    shelf: { lightning: 0, appleCinnamon: 0 },
    ledger: withLedger({ total: 100, cash: 100 }),
  })
  const clock = engine(on, { result: {} }, { farm }, WED.getTime())
  await start($)
  await call($, bash('git push'))
  await clock.advance(9_000)
  const after = storedFarm()
  // Three sugar for $24 and a copper for $30 (the keg is queued), then the store's twenty bushels at $5.
  expect(after.materials).toMatchObject({ sugar: 3, copper: 1 })
  expect(after.ledger).toMatchObject({ spent: 54, total: 200, cash: 146, byPurchase: { sugar: 24, copper: 30 } })
  const text = await tally($)
  expect(text).toContain('Cash: $146 on hand of $200 earned, $54 spent (sugar $24, copper $30).')
})

test('K5 recipes: apple butter, twists and aged whiskey, each with its inputs and the reserves', () => {
  // Apple butter: 5 apples above the floor of ten, a sugar and a stick.
  const butter = (over: object = {}) => craftAll(farm6({ barn: { bales: 0, corn: 0, apples: 15, sticks: 1 }, materials: stuff({ sugar: 1 }), ...over }), NOW)
  const one = butter()
  expect(one.made.map(m => m.id)).toEqual(['appleButter'])
  expect(one.next.goods.appleButter).toBe(1)
  expect(one.next.barn).toMatchObject({ apples: 10, sticks: 0 })
  expect(one.next.materials.sugar).toBe(0)
  expect(butter({ barn: { bales: 0, corn: 0, apples: 14, sticks: 1 } }).made).toEqual([])
  expect(butter({ barn: { bales: 0, corn: 0, apples: 15, sticks: 0 } }).made).toEqual([])
  expect(butter({ materials: stuff({}) }).made).toEqual([])

  // Tobacco twist: a bale makes four; the smokehouse makes it six.
  const twist = (over: object = {}) => craftAll(farm6({ barn: { bales: 1, corn: 0, apples: 0, sticks: 1 }, ...over }), NOW)
  expect(twist().next.goods.twists).toBe(4)
  expect(twist().next.barn.bales).toBe(0)
  expect(twist({ built: ['smokehouse'] }).next.goods.twists).toBe(6)
  expect(twistsPerBale(farm6({ built: ['smokehouse'] }))).toBe(6)
  expect(twistsPerBale(farm6())).toBe(4)
  // ...only from bales above the cinnamon reserve: eight sticks a bale, so ceil(lightning / 8) stay.
  const held = (lightning: number, bales: number) =>
    craftAll(farm6({ barn: { bales, corn: 0, apples: 0, sticks: 1 }, shelf: { lightning, appleCinnamon: 0 } }), NOW).next.barn.bales
  expect(held(8, 2)).toBe(1)
  expect(held(9, 2)).toBe(2)
  expect(held(0, 2)).toBe(0)
  // ...and with no sticks one bale more stays back for the next jar.
  expect(twist({ barn: { bales: 1, corn: 0, apples: 0, sticks: 0 } }).made).toEqual([])
  expect(twist({ barn: { bales: 2, corn: 0, apples: 0, sticks: 0 } }).next.barn.bales).toBe(1)

  // Aged whiskey: a white lightning and a barrel, ready in three days.
  const aged = craftAll(farm6({ shelf: { lightning: 2, appleCinnamon: 0 }, components: parts({ barrel: 1 }), built: ['thumpKeg'] }), NOW)
  expect(aged.made.map(m => m.id)).toEqual(['whiskey'])
  expect(aged.next.goods.aged).toEqual([{ readyAt: NOW.getTime() + DAYS3 }])
  expect(aged.next.shelf.lightning).toBe(1)
  expect(aged.next.components.barrel).toBe(0)
  // Its barrel is not given back, and the jar is not for sale yet.
  expect(aged.next.goods.whiskey).toBe(0)
  // With no barrel it coopers one, but only above the reserve of two lumber and two iron.
  const coopered = (lumber: number, iron: number) =>
    craftAll(farm6({ shelf: { lightning: 1, appleCinnamon: 0 }, materials: stuff({ lumber, iron }), built: ['thumpKeg'] }), NOW).made.map(m => m.id)
  expect(coopered(5, 3)).toEqual(['barrel', 'whiskey'])
  expect(coopered(4, 3)).toEqual([])
  expect(coopered(5, 2)).toEqual([])
  // Fifty jars is the most the barrels hold.
  const full = farm6({ shelf: { lightning: 1, appleCinnamon: 0 }, components: parts({ barrel: 1 }), goods: goodsOf({ aged: Array.from({ length: 50 }, (_, i) => ({ readyAt: NOW.getTime() + i })) }) })
  expect(craftAll(full, NOW).made).toEqual([])
})

test('K6 auto-crafting: the queued upgrade first, then keepsakes, then goods, at most three a change, and the reserves', () => {
  const rich = farm6({
    materials: stuff({ lumber: 20, iron: 5, straw: 10, sugar: 1 }),
    barn: { bales: 0, corn: 0, apples: 15, sticks: 1 },
  })
  // The queued keg wants two barrels first; the quilt follows; the butter must wait.
  expect(queuedBuild(rich)?.id).toBe('thumpKeg')
  const first = craftAll(rich, NOW)
  expect(first.made.map(m => m.id)).toEqual(['barrel', 'barrel', 'quilt'])
  expect(first.made.map(m => m.kind)).toEqual(['component', 'component', 'keepsake'])
  expect(first.next.goods.appleButter).toBe(0)
  // The next change makes the butter (the coil needs copper, which only a truck brings).
  const second = craftAll(first.next, NOW)
  expect(second.made.map(m => m.id)).toEqual(['appleButter'])
  expect(craftAll(second.next, NOW).made).toEqual([])
  // Never more than three, however much there is.
  const plenty = farm6({
    materials: stuff({ lumber: 99, stone: 99, iron: 99, straw: 99, copper: 99, sugar: 9 }),
    barn: { bales: 9, corn: 9, apples: 90, sticks: 9 },
    shelf: { lightning: 9, appleCinnamon: 0 },
  })
  expect(craftAll(plenty, NOW).made.length).toBe(3)
  // Parts of the queued upgrade are not eaten by the goods: its barrels stay for the keg.
  const barrels = craftAll(farm6({ shelf: { lightning: 3, appleCinnamon: 0 }, components: parts({ barrel: 1 }) }), NOW)
  expect(barrels.next.components.barrel).toBe(1)
  expect(barrels.made).toEqual([])
  // Sellables never dip a material below two; a keepsake or an upgrade may.
  const lean = craftAll(farm6({ materials: stuff({ lumber: 3, iron: 1 }), shelf: { lightning: 1, appleCinnamon: 0 }, built: ['thumpKeg'] }), NOW)
  expect(lean.made).toEqual([])
  const banjo = craftAll(farm6({ materials: stuff({ lumber: 3, iron: 1, copper: 1 }), built: BUILDS.map(b => b.id) }), NOW)
  expect(banjo.made.map(m => m.id)).toEqual(['banjo'])
  expect(banjo.next.materials).toMatchObject({ lumber: 0, iron: 0, copper: 0 })
})

test('K7 built upgrades: each one builds from its parts and has its effect', async ($, on) => {
  // The keg: two barrels and a coil.
  const keg = craftAll(farm6({ components: parts({ barrel: 2, coil: 1 }) }), NOW)
  expect(keg.made.map(m => m.id)).toEqual(['thumpKeg'])
  expect(keg.made[0]?.kind).toBe('build')
  expect(keg.next.built).toEqual(['thumpKeg'])
  expect(keg.next.components).toMatchObject({ barrel: 0, coil: 0 })
  // The smokehouse: six lumber, four stone and an iron (queued after the keg).
  const house = craftAll(farm6({ built: ['thumpKeg'], materials: stuff({ lumber: 6, stone: 4, iron: 1 }) }), NOW)
  expect(house.made.map(m => m.id)).toEqual(['smokehouse'])
  expect(house.next.materials).toMatchObject({ lumber: 0, stone: 0, iron: 0 })
  // Fenced fields: eight posts, made three at a time.
  let fence = farm6({ built: ['thumpKeg', 'smokehouse'], materials: stuff({ lumber: 16, stone: 8 }) })
  const steps: string[][] = []
  for (let i = 0; i < 4; i += 1) {
    const done = craftAll(fence, NOW)
    steps.push(done.made.map(m => m.id))
    fence = done.next
  }
  expect(steps).toEqual([['post', 'post', 'post'], ['post', 'post', 'post'], ['post', 'post', 'fencedFields'], []])
  expect(fence.built).toContain('fencedFields')
  // The worm: two coils.
  const worm = craftAll(farm6({ built: ['thumpKeg', 'smokehouse', 'fencedFields'], components: parts({ coil: 2 }) }), NOW)
  expect(worm.next.built).toContain('copperWorm')
  // Each is built once.
  expect(craftAll(worm.next, NOW).made).toEqual([])

  // Fenced fields stop the whistle pig.
  const ripe = { ...farm6(), crops: { ...freshFarm().crops, corn: Array(8).fill(3) } }
  expect(raidCorn(ripe, () => 0.5).crops.corn.reduce((a, b) => a + b, 0)).toBe(23)
  const fenced = { ...ripe, built: ['fencedFields'] }
  expect(raidCorn(fenced, () => 0.5)).toBe(fenced)

  // The keg: four good runs make the lightning, not six.
  engine(on, { result: {} }, { farm: farm6({ built: ['thumpKeg'], barn: { bales: 0, corn: 3, apples: 0, sticks: 0 } }) })
  await start($)
  for (let i = 0; i < 3; i += 1) {
    await call($, bash('ls'))
  }
  expect(await tally($)).toContain('batch 3/4')
  await call($, bash('ls'))
  const text = await tally($)
  expect(text).toContain('1 white lightning')
  expect(text).toContain('batch 0/4')
})

test('K7 the copper worm draws two jars from a lightning when the apples and sticks allow, and one when they do not', async ($, on) => {
  engine(on, { result: {} }, { farm: farm6({ built: ['copperWorm'], shelf: { lightning: 2, appleCinnamon: 0 }, barn: { bales: 0, corn: 0, apples: 3, sticks: 3 } }) })
  await start($)
  await finish($, usage(1, 0))
  // Two lightnings: the first makes two jars, the second the one jar the last apple allows.
  expect(await tally($)).toContain('0 white lightning, 3 apple cinnamon')
  expect(storedFarm().barn).toMatchObject({ apples: 0, sticks: 0 })
})

test('K7 without the worm a lightning makes one jar', async ($, on) => {
  engine(on, { result: {} }, { farm: farm6({ shelf: { lightning: 1, appleCinnamon: 0 }, barn: { bales: 0, corn: 0, apples: 3, sticks: 3 } }) })
  await start($)
  await finish($, usage(1, 0))
  expect(await tally($)).toContain('0 white lightning, 1 apple cinnamon')
})

test('K8 keepsakes: each made once and never sold; the Mothman carving only after a sighting', () => {
  const recipes: [string, Partial<Record<Material, number>>, object][] = [
    ['quilt', { straw: 10, lumber: 2 }, {}],
    ['weathervane', { iron: 3, copper: 1 }, {}],
    ['banjo', { lumber: 3, iron: 1, copper: 1 }, {}],
    ['doll', { straw: 5 }, { barn: { bales: 0, corn: 2, apples: 0, sticks: 0 } }],
  ]
  for (const [id, materials, over] of recipes) {
    const farm = farm6({ built: BUILDS.map(b => b.id), materials: stuff(materials), ...over })
    const done = craftAll(farm, NOW)
    expect(done.made.map(m => m.id)).toEqual([id])
    expect(done.made[0]?.kind).toBe('keepsake')
    expect(done.next.keepsakes).toEqual([id])
    // Never twice, even with the stock for a second.
    const again = craftAll({ ...done.next, materials: stuff({ lumber: 99, straw: 99, iron: 99, copper: 99 }), barn: { bales: 0, corn: 9, apples: 0, sticks: 0 } }, NOW)
    expect(again.next.keepsakes.filter(k => k === id).length).toBe(1)
  }
  expect(KEEPSAKES.length).toBe(5)
  // The Mothman: two lumber, once one has been seen.
  const lumber = farm6({ built: BUILDS.map(b => b.id), materials: stuff({ lumber: 2 }) })
  expect(craftAll(lumber, NOW).made).toEqual([])
  // Keepsakes are never for sale: no buyer wants one, and they sit in no stock.
  const kept = farm6({ keepsakes: ['quilt', 'banjo'], goods: goodsOf({}) })
  expect(CUSTOMER_IDS.filter(id => wantsOf(id, NIGHT, kept).length > 0)).toEqual([])
  expect(stackColumns(kept, NOW)).toEqual([])
})

test('K8 a Mothman sighting counts, and the carving follows when there is lumber', async ($, on) => {
  // Halloween night, when the Mothman is the likeliest visitor: idle three minutes at a time until he
  // comes (an hour and a half at the very most; each roll is better than one in three). The scene goes
  // still after two idle minutes and no happening rolls then, so a /jeb tally (activity) comes
  // in the middle of each three minutes.
  const clock = engine(on, { result: {} }, { farm: farm6({ built: BUILDS.map(b => b.id), materials: stuff({ lumber: 2 }) }) }, at(9, 31, 23).getTime())
  on('prompt.submit', (_, e) => e)
  await start($)
  for (let i = 0; i < 30 && (world.db.get('farm') as Farm6).counters.mothmanSeen < 1; i += 1) {
    await clock.advance(100_000)
    await poke($)
    await clock.advance(81_000)
  }
  expect(storedFarm().counters.mothmanSeen).toBeGreaterThanOrEqual(1)
  expect(storedFarm().keepsakes).toContain('mothman')
  expect(storedFarm().materials.lumber).toBe(0)
})


test('K10 the market buys apple butter, twists and aged whiskey at the listed prices from the listed buyers', () => {
  const goods = farm6({ goods: goodsOf({ appleButter: 3, twists: 8, whiskey: 2 }) })
  const priced = (id: Parameters<typeof wantsOf>[0], now: Date) => wantsOf(id, now, goods).map(w => `${w.product}@${w.price}`)
  // The store, in store hours: butter $30, twists $16, whiskey $60.
  expect(priced('store', WED)).toEqual(['appleButter@30', 'twists@16', 'agedWhiskey@60'])
  // The farmers market: butter $28 and nothing else of these.
  expect(priced('market', SAT)).toEqual(['appleButter@28'])
  expect(priced('market', WED)).toEqual([])
  // The tripper, at night: twists $18 and whiskey $60.
  expect(priced('tripper', NIGHT)).toEqual(['twists@18', 'agedWhiskey@60'])
  expect(priced('tripper', WED)).toEqual([])
  for (const id of ['opal', 'warehouse', 'mill', 'fair', 'town'] as const) {
    expect(priced(id, WED)).toEqual([])
  }
  // A lot: butter one to three, twists two to six, whiskey one to two.
  const lot = (id: Parameters<typeof wantsOf>[0], now: Date, product: string) =>
    wantsOf(id, now, farm6({ goods: goodsOf({ appleButter: 9, twists: 9, whiskey: 9 }) })).find(w => w.product === product)
  expect(lot('store', WED, 'appleButter')).toMatchObject({ min: 1, max: 3 })
  expect(lot('store', WED, 'twists')).toMatchObject({ min: 2, max: 6 })
  expect(lot('store', WED, 'agedWhiskey')).toMatchObject({ min: 1, max: 2 })
  // One twist is too few for anyone.
  expect(wantsOf('store', WED, farm6({ goods: goodsOf({ twists: 1 }) }))).toEqual([])
  // Selling takes them from the stack and puts the money in the books.
  const sale = planSale('store', WED, goods, () => 0) as NonNullable<ReturnType<typeof planSale>>
  expect(sale.lines.map(l => [l.product, l.qty, l.dollars])).toEqual([['appleButter', 1, 30], ['twists', 2, 32], ['agedWhiskey', 1, 60]])
  expect(fillSale('{what}', sale)).toBe('one crock of apple butter, two tobacco twists, one jar of aged whiskey')
  const sold = applySale(goods, sale, WED)
  expect(sold.goods).toMatchObject({ appleButter: 2, twists: 6, whiskey: 1 })
  expect(sold.ledger).toMatchObject({ total: 122, cash: 122, jarsSold: 1 })
  expect(sold.ledger.byProduct).toMatchObject({ appleButter: 30, twists: 32, agedWhiskey: 60 })
  // The truck's bed carries the glyph of what the buyer would pay the most for.
  const only = (g: Partial<Farm6['goods']>) => farm6({ goods: goodsOf(g) })
  expect(loadFor('store', WED, only({ appleButter: 1 }))).toBe('butter')
  expect(loadFor('tripper', NIGHT, only({ twists: 2 }))).toBe('twist')
  expect(loadFor('tripper', NIGHT, only({ whiskey: 1 }))).toBe('whiskey')
  // The ledger's key sets stay fixed.
  expect(Object.keys(sold.ledger.byProduct).sort()).toEqual([...PRODUCTS].sort())
})

test('K10 aged whiskey is for sale three days after it was laid down, and not a moment before', async ($, on) => {
  const ready = NIGHT.getTime() + 10_000
  const farm = farm6({ goods: goodsOf({ aged: [{ readyAt: ready }] }) })
  // Not yet: the tripper wants nothing; one second later he does, and the jar comes out of its barrel.
  expect(wantsOf('tripper', NIGHT, farm)).toEqual([])
  expect(wantsOf('tripper', new Date(ready - 1), farm)).toEqual([])
  const later = new Date(ready)
  expect(wantsOf('tripper', later, farm).map(w => [w.product, w.price])).toEqual([['agedWhiskey', 60]])
  const sale = planSale('tripper', later, farm, () => 0) as NonNullable<ReturnType<typeof planSale>>
  const sold = applySale(farm, sale, later)
  expect(sold.goods).toMatchObject({ aged: [], whiskey: 0 })
  expect(sold.ledger.byProduct.agedWhiskey).toBe(60)

  // On the clock: Jeb lays a jar down now and it is due to the minute three days on.
  const clock = engine(on, { result: {} }, { farm: farm6({ shelf: { lightning: 1, appleCinnamon: 0 }, components: parts({ barrel: 1 }), built: ['thumpKeg'] }) }, NIGHT.getTime())
  await start($)
  await finish($, usage(1, 0))
  expect(storedFarm().goods.aged).toEqual([{ readyAt: NIGHT.getTime() + DAYS3 }])
  expect(storedFarm().shelf.lightning).toBe(0)
  void clock
})

const butterFarm = (goods: Partial<Farm6['goods']>) => farm6({ shelf: EMPTY_SHELF, barn: EMPTY_BARN, goods: goodsOf(goods) })
truckSells('apple butter goes to the store, a crock at $30', butterFarm({ appleButter: 1 }), WED, '🥫', /crock of apple butter/, /apple butter \$30/)
truckSells('twists go to the store, two at $16', butterFarm({ twists: 2 }), WED, '🪢', /two tobacco twists/, /tobacco twists \$32/)
truckSells('twists go to the tripper at night, two at $18', butterFarm({ twists: 2 }), NIGHT, '🪢', /tripper/i, /tobacco twists \$36/)
truckSells('ready whiskey goes to the tripper at night, a jar at $60', butterFarm({ aged: [{ readyAt: NIGHT.getTime() - 1 }] }), NIGHT, '🥃', /aged whiskey/, /aged whiskey \$60/)
truckSells('apple butter goes to the farmers market on a Saturday, at $28', butterFarm({ appleButter: 1 }), SAT, '🥫', /apple butter/, /apple butter \$28/)

// What the band shows of the stack at a width, as plain rows.


test('K12 migration v5 to v6: the live farm keeps every number, cash is what it earned, the new stock starts empty', async ($, on) => {
  const live = {
    version: 5,
    crops: { tobacco: Array(8).fill(1), corn: Array(8).fill(2), apples: Array(8).fill(3) },
    progress: { tobacco: 5, corn: 6, apples: 7 },
    barn: { bales: 0, corn: 5, apples: 118, sticks: 0 },
    still: { steps: 2, hasBatch: true },
    shelf: { lightning: 26, appleCinnamon: 32 },
    lifetime: { outputTokens: 10, inputTokens: 20, workMs: 30, bales: 12, balesTraded: 12 },
    ledger: {
      deliveries: 2,
      jarsSold: 13,
      total: 325,
      month: { key: '2026-10', amount: 100 },
      best: { amount: 200, customer: 'opal', product: 'appleCinnamon' },
      byCustomer: { opal: 225, store: 0, tripper: 0, warehouse: 0, market: 0, mill: 0, fair: 0, town: 100 },
      byProduct: { appleCinnamon: 325, whiteLightning: 0, tobacco: 0, apples: 0, corn: 0 },
      ribbons: 0,
      fairYear: 0,
    },
    upgrades: ['mailbox', 'chair', 'hen'],
    lastProof: 100,
    bestProof: 120,
    milestones: ['jar10'],
  }
  const farm = loadFarm(live) as Farm6
  expect(farm.version).toBe(10)
  expect(farm.shelf).toEqual(live.shelf)
  expect(farm.barn).toEqual(live.barn)
  expect(farm.lifetime).toEqual(live.lifetime)
  expect(farm.upgrades).toEqual(live.upgrades)
  expect(farm.milestones).toEqual(['jar10'])
  expect(farm.ledger).toEqual({
    ...live.ledger,
    byProduct: { ...live.ledger.byProduct, appleButter: 0, twists: 0, agedWhiskey: 0 },
    cash: 325,
    spent: 0,
    byPurchase: { sugar: 0, copper: 0 },
  })
  expect(farm.materials).toEqual(stuff({}))
  expect(farm.components).toEqual({ barrel: 0, post: 0, coil: 0 })
  expect(farm.goods).toEqual({ appleButter: 0, twists: 0, aged: [], whiskey: 0 })
  expect(farm.built).toEqual([])
  expect(farm.keepsakes).toEqual([])
  expect(farm.counters).toEqual({ edits: 0, mothmanSeen: 0 })
  // Reading it again changes nothing, and a v8 farm is a stranger.
  expect(loadFarm(farm)).toEqual(farm)
  expect(isFutureFarm({ ...farm, version: 11 })).toBe(true)

  // A damaged v6 farm is normalized field by field with fixed key sets.
  const damaged = loadFarm({
    ...farm,
    materials: { lumber: -4, stone: 'x', straw: 7.9, iron: Number.NaN, sugar: 1e12, copper: 2, bogus: 9 },
    components: { barrel: 3, bogus: 1 },
    goods: { appleButter: -1, twists: 5, whiskey: 'x', aged: [{ readyAt: 5 }, { readyAt: -1 }, null, { readyAt: 'x' }, ...Array.from({ length: 80 }, (_, i) => ({ readyAt: 100 + i }))] },
    built: ['thumpKeg', 'nonsense', 'smokehouse'],
    keepsakes: ['quilt', 'quilt', '__proto__'],
    counters: { edits: -3, mothmanSeen: 2.9 },
    ledger: { ...live.ledger, cash: 99_999, spent: -5, byPurchase: { sugar: 4, copper: 'x', bogus: 1 } },
  }) as Farm6
  expect(damaged.materials).toEqual(stuff({ straw: 7, sugar: 99_999, copper: 2 }))
  expect(Object.keys(damaged.materials).sort()).toEqual(['copper', 'iron', 'lumber', 'stone', 'straw', 'sugar'])
  expect(damaged.components).toEqual({ barrel: 3, post: 0, coil: 0 })
  expect(damaged.goods).toMatchObject({ appleButter: 0, twists: 5, whiskey: 0 })
  expect(damaged.goods.aged.length).toBe(50)
  expect(damaged.goods.aged[0]).toEqual({ readyAt: 5 })
  expect(damaged.built).toEqual(['thumpKeg', 'smokehouse'])
  expect(damaged.keepsakes).toEqual(['quilt'])
  expect(damaged.counters).toEqual({ edits: 0, mothmanSeen: 2 })
  // Cash can never exceed what was earned.
  expect(damaged.ledger).toMatchObject({ cash: 325, spent: 0, byPurchase: { sugar: 4, copper: 0 } })

  // A v4 farm lands on v6 books with all it earned in hand.
  const v4 = loadFarm({ ...farmWith({ lightning: 0, appleCinnamon: 1 }), version: 4, delivery: { deliveries: 2, jarsSold: 13, dollars: 325 } }) as Farm6
  expect(v4.version).toBe(10)
  expect(v4.ledger).toMatchObject({ total: 325, cash: 325, spent: 0 })

  // Through the store when a session starts.
  engine(on, { result: {} }, { farm: live }, at(9, 22, 14).getTime())
  await start($)
  // The migration is a write like any other: it counts in `rev`. The first save gives the farm its salt.
  expect(world.db.get('farm')).toEqual({ ...farm, rev: 1, anonSalt: expect.stringMatching(/^[0-9a-f]{16}$/) })
  const text = await tally($)
  expect(text).toContain('Cash: $325 on hand of $325 earned, $0 spent.')
  expect(text).toContain('Deliveries: 2 trips, 13 jars sold, $325.')
})

test('K12 crafting and buying twice from one farm never go negative or build twice', () => {
  const farm = farm6({ components: parts({ barrel: 2, coil: 1 }), materials: stuff({ lumber: 1 }) })
  // The same craft run again on its own result finds the keg built and makes nothing more.
  const once = craftAll(farm, NOW)
  expect(once.next.built).toEqual(['thumpKeg'])
  expect(once.next.components).toEqual({ barrel: 0, post: 0, coil: 0 })
  expect(craftAll(once.next, NOW).made).toEqual([])

  // The barrels the keg needs: the materials are spent once, never below zero, and nothing is made twice.
  const barrels = craftAll(farm6({ components: parts({ barrel: 1 }), materials: stuff({ lumber: 3, iron: 1 }) }), NOW)
  expect(barrels.made.map(m => m.id)).toEqual(['barrel'])
  expect(barrels.next.components.barrel).toBe(2)
  expect(Object.values(barrels.next.materials).every(n => n >= 0)).toBe(true)
  expect(barrels.next.materials).toMatchObject({ lumber: 0, iron: 0 })
  expect(craftAll(barrels.next, NOW).made).toEqual([])

  // The money too: a purchase is decided on the stored farm, so cash is spent once.
  const rich = farm6({ ledger: withLedger({ total: 30, cash: 30 }), built: ['thumpKeg', 'smokehouse', 'fencedFields'] })
  const first = buySupplies(rich)
  expect(first.copper).toBe(1)
  const second = buySupplies({ ...first.next, components: parts({ coil: 0 }) })
  expect(second.copper).toBe(0)
  expect(second.next.ledger.cash).toBe(0)
  expect(second.next.ledger.total).toBe(30)
})


const craftLines = () => {
  const rich = farm6({
    materials: stuff({ lumber: 99, stone: 99, iron: 99, straw: 99, copper: 99, sugar: 9 }),
    barn: { bales: 9, corn: 9, apples: 90, sticks: 9 },
    shelf: { lightning: 9, appleCinnamon: 0 },
    counters: { edits: 0, mothmanSeen: 1 },
    components: parts({ coil: 2 }),
  })
  const out: string[] = []
  let farm = rich
  for (let i = 0; i < 40; i += 1) {
    const done = craftAll(farm, NOW)
    out.push(...done.made.map(m => m.line))
    farm = done.next
  }

  return out
}

test('K13 the craft lines Jeb says are all of them, each said once a make', () => {
  const lines = new Set(craftLines())
  expect(lines.size).toBeGreaterThanOrEqual(10)
})

// ---------------------------------------- v5.5 the session quilt and the journal ----

const Q = {
  rec: (over: Partial<SessionRec> = {}): SessionRec => ({ ...freshSession(0, 'api'), calls: 1, ...over }),
}
const squares = (codes: string) =>
  codes.split('').map(c => ({ c: c as SquareCode, d: '2026-06-09', camp: 'api' }))

const end = async ($: any, reason = 'prompt_input_exit', sessionId = 'me') => {
  await $.session.end({ reason, sessionId, resume: { id: sessionId } })
  await clk.settle()
}
const sessionsStore = () => world.db.get('sessions') as Record<string, { name: string; sq?: string; ln?: string }>

test('Q1 the square: each color, the tie rules, and none for an idle session', () => {
  expect(squareFor(freshSession(0, 'api'))).toBeNull()
  expect(squareFor(Q.rec({ calls: 0, turns: 1 }))).toBe('N')
  // Shipping always wins.
  expect(squareFor(Q.rec({ ships: 1, rough: 50, testsPassed: 9, agents: 9 }))).toBe('B')
  // A rough day needs five and more than passes plus ships.
  expect(squareFor(Q.rec({ rough: 5, testsPassed: 4 }))).toBe('R')
  expect(squareFor(Q.rec({ rough: 4 }))).toBe('N')
  expect(squareFor(Q.rec({ rough: 5, testsPassed: 5 }))).toBe('G')
  expect(squareFor(Q.rec({ rough: 6, testsPassed: 5, edits: 9 }))).toBe('R')
  // The top count wins; ties go to the earlier: tests, agents, weeding, then edits.
  expect(squareFor(Q.rec({ testsPassed: 3, agents: 2, lintRuns: 1, edits: 3 }))).toBe('G')
  expect(squareFor(Q.rec({ testsPassed: 1, agents: 2, lintRuns: 1, edits: 2 }))).toBe('P')
  expect(squareFor(Q.rec({ testsPassed: 1, agents: 1, lintRuns: 4, edits: 4 }))).toBe('Y')
  expect(squareFor(Q.rec({ testsPassed: 1, agents: 1, lintRuns: 1, edits: 5 }))).toBe('N')
  // A quiet session with a tool call is field work.
  expect(squareFor(Q.rec())).toBe('N')
  expect(squareFor(Q.rec({ testsFailed: 9 }))).toBe('N')
})


test('Q3 journalLine joins only what is not zero, never leaks content and stays within 120 characters', () => {
  const day = new Date(2026, 9, 22, 12)
  expect(journalLine(Q.rec({ ships: 3, testsPassed: 2, sours: 1 }), day)).toBe('Oct 22 · api camp · 3 loads out, rain twice, 1 sour batch')
  expect(journalLine(Q.rec({ lintRuns: 8, lintFailed: 1, camp: 'web' }), new Date(2026, 9, 21))).toBe('Oct 21 · web camp · weeded all day, found blight')
  expect(journalLine(Q.rec({ camp: '.claude', built: ['built the smokehouse'] }), new Date(2026, 9, 20))).toBe('Oct 20 · .claude · built the smokehouse')
  expect(journalLine(Q.rec(), new Date(2026, 9, 19))).toBe('Oct 19 · api camp · quiet day, mended a fence')
  expect(journalLine(Q.rec({ ships: 1, lintRuns: 3, testsPassed: 1 }), day, true)).toBe('today · api camp · 1 load out, rain once, 3 rows hoed')
  expect(journalLine(Q.rec({ ships: 1, jars: 2, harvests: 1, agents: 1, sales: 40 }), day)).toBe('Oct 22 · api camp · 1 load out, 1 harvest in, 2 jars put up, 1 hand hired')
  // A camp name with control characters and a huge one still gives one clean short line.
  const messy = journalLine(Q.rec({ camp: `x\n${'y'.repeat(200)}`, ships: 99_999, testsPassed: 99_999, built: ['built the a', 'made the b', 'built the c'] }), day)
  expect(messy.length).toBeLessThanOrEqual(120)
  expect(messy).not.toMatch(/[\u0000-\u001f]/)
  // Only counts and names: the record has no field a command or path could ride in.
  expect(Object.keys(freshSession()).sort()).toEqual(
    ['agents', 'built', 'calls', 'camp', 'edits', 'harvests', 'jars', 'lintFailed', 'lintRuns', 'rough', 'sales', 'sours', 'ships', 'startedAt', 'testsFailed', 'testsPassed', 'turns'].sort(),
  )
})

test('Q4 bounds: 500 stitches leave 200 squares, 60 lines and 64 session ids; a session stitches once', () => {
  let farm = freshFarm()
  for (let i = 0; i < 500; i += 1) {
    const stitch = stitchOf(Q.rec({ ships: i % 7 === 0 ? 1 : 0, edits: i }), new Date(2026, 5, 1 + (i % 28)), `s${i}`) as Stitch
    farm = stitchFarm(farm, [stitch]).next
  }
  expect(farm.quilt.length).toBe(200)
  expect(farm.journal.length).toBe(60)
  expect(farm.stitched.length).toBe(64)
  expect(farm.sessionsWorked).toBe(500)
  expect(farm.sessionsShipped).toBe(72)
  expect(farm.busiest?.score).toBe(5 + 497)
  expect(JSON.stringify(farm).length).toBeLessThan(40_000)
  // The same session again, or a bad code or date, adds nothing.
  const again = stitchOf(Q.rec(), new Date(2026, 5, 1), 's499') as Stitch
  expect(stitchFarm(farm, [again]).added).toEqual([])
  expect(stitchFarm(farm, [{ ...again, id: 'new', c: 'Z' as SquareCode }]).added).toEqual([])
  expect(stitchFarm(farm, [{ ...again, id: 'new', d: '2026-02-31' }]).added).toEqual([])
  expect(stitchFarm(farm, [stitchFromBeat({ id: 'new', name: 'web', lastSeen: JUNE_NOON, sq: 'G3', ln: 'Jun 10 · web camp · rain once' })]).added.length).toBe(1)
})

test('Q5 farm v7: v6 migrates with an empty, zeroed quilt, and every field of a damaged one is normalized', async ($, on) => {
  const live = { ...freshFarm(), version: 6, shelf: { lightning: 26, appleCinnamon: 32 }, barn: { bales: 0, corn: 5, apples: 118, sticks: 0 } } as Record<string, unknown>
  for (const key of ['quilt', 'journal', 'sessionsWorked', 'sessionsShipped', 'busiest', 'stitched']) {
    delete live[key]
  }
  const farm = loadFarm(live) as Farm6
  expect(farm.version).toBe(10)
  expect(farm.shelf).toEqual({ lightning: 26, appleCinnamon: 32 })
  expect(farm.barn).toEqual({ bales: 0, corn: 5, apples: 118, sticks: 0 })
  expect(farm).toMatchObject({ quilt: [], journal: [], sessionsWorked: 0, sessionsShipped: 0, busiest: null, stitched: [] })
  // A v6 farm's cash stays its cash (the ledger is read as a v6 one).
  const rich = loadFarm({ ...live, ledger: { ...freshFarm().ledger, total: 100, cash: 40 } }) as Farm6
  expect(rich.ledger.cash).toBe(40)
  expect(loadFarm(farm)).toEqual(farm)

  const damaged = loadFarm({
    ...farm,
    anonSalt: SALT,
    quilt: [
      { c: 'B', d: '2026-06-01', camp: 'api' },
      { c: 'Z', d: '2026-06-01', camp: 'x' },
      { c: 'G', d: '2026-13-01', camp: 'x' },
      { c: 'G', d: 'junk', camp: 'x' },
      null,
      7,
      { c: 'P', d: '2026-06-02', camp: `a\n${'b'.repeat(80)}` },
      ...Array.from({ length: 300 }, () => ({ c: 'N', d: '2026-06-03', camp: 'web' })),
    ],
    journal: [
      { d: '2026-06-01', camp: 'api', line: '' },
      { d: 'nope', camp: 'api', line: 'x' },
      { d: '2026-06-01', camp: 'api', line: `l\n${'x'.repeat(300)}` },
      ...Array.from({ length: 90 }, (_, i) => ({ d: '2026-06-03', camp: 'web', line: `line ${i}` })),
    ],
    sessionsWorked: 'x',
    sessionsShipped: 99,
    busiest: { d: '2026-06-03', camp: 'web', score: -5 },
    stitched: ['a', 'a', '', 5, 'x'.repeat(70), ...Array.from({ length: 100 }, (_, i) => `id${i}`)],
  }) as Farm6
  expect(damaged.quilt.length).toBe(200)
  expect(damaged.quilt.every(sq => 'BRGPYN'.includes(sq.c) && /^\d{4}-\d{2}-\d{2}$/.test(sq.d) && sq.camp.length <= 24)).toBe(true)
  expect(damaged.journal.length).toBe(60)
  expect(damaged.journal.every(entry => entry.line.length <= 120 && entry.line !== '')).toBe(true)
  expect(damaged.journal[59]?.line).toBe('line 89')
  expect(damaged.busiest).toBeNull()
  expect(damaged.stitched.length).toBe(64)
  expect(new Set(damaged.stitched).size).toBe(64)
  expect(damaged.stitched[63]).toBe('id99')
  // Shipped sessions never exceed the sessions worked, which never trail the squares.
  expect(damaged.sessionsWorked).toBe(200)
  expect(damaged.sessionsShipped).toBe(99)
  const few = loadFarm({ ...farm, sessionsWorked: 3, sessionsShipped: 9, quilt: squares('BG') }) as Farm6
  expect(few.sessionsWorked).toBe(3)
  expect(few.sessionsShipped).toBe(3)

  // Through the store when a session starts: the live farm keeps its numbers (and the first save gives it a salt).
  engine(on, { result: {} }, { farm: live }, at(9, 22, 14).getTime())
  await start($)
  expect(world.db.get('farm')).toEqual({ ...farm, rev: 1, anonSalt: expect.stringMatching(/^[0-9a-f]{16}$/) })
})

test('Q6 heartbeats carry a bounded square and line; only well-formed ones count, and the dead are found once each', () => {
  const now = JUNE_NOON
  const beaten = beat({}, 'me', 'api', now, { sq: 'B12', ln: 'x'.repeat(300) })
  expect(beaten.me?.sq).toBe('B12')
  expect(beaten.me?.ln?.length).toBe(120)
  expect(beat({}, 'me', 'api', now, { sq: 'Q9', ln: 'ok' }).me).toEqual({ name: 'api', lastSeen: now })
  expect(beat({}, 'me', 'api', now).me).toEqual({ name: 'api', lastSeen: now })
  const saved = {
    me: { name: 'api', lastSeen: now - 600_000, sq: 'G3', ln: 'mine' },
    live: { name: 'web', lastSeen: now - 1000, sq: 'B1', ln: 'live' },
    dead: { name: 'docs', lastSeen: now - 600_000, sq: 'P7', ln: 'Jun 10 · docs camp · 2 hands hired' },
    plain: { name: 'old', lastSeen: now - 600_000 },
    odd: { name: 'odd', lastSeen: now - 600_000, sq: 'zz', ln: 'bad' },
    future: { name: 'f', lastSeen: now + 600_000, sq: 'B1', ln: 'f' },
  }
  expect(staleOf(saved, 'me', now).map(item => item.id)).toEqual(['dead'])
  expect(staleOf('junk', 'me', now)).toEqual([])
  expect(Object.keys(loadCamps(saved, now))).toEqual(['live'])
  expect(loadCamps(saved, now).live).toEqual({ name: 'web', lastSeen: now - 1000, sq: 'B1', ln: 'live' })
})

test('Q7 session.end stitches the day once; /clear counts, a resume does not, an idle session leaves nothing', async ($, on) => {
  engine(on, { result: {} }, { farm: saltFarm() })
  v5(on)
  await start($)
  await begin($)
  await call($, bash('git push'))
  await call($, { tool: 'Read', file_path: '/a' })
  await end($)
  let stored = storedFarm()
  // The camp is a place, registered on the farm as it is stitched; the session's id is hashed.
  const api = placeOf('api')
  expect(stored.quilt).toEqual([{ c: 'B', d: '2026-06-10', camp: api }])
  expect(stored.journal.map(entry => entry.line)).toEqual([`Jun 10 · ${api} camp · 1 load out`])
  expect(stored).toMatchObject({ sessionsWorked: 1, sessionsShipped: 1, stitched: [keyOf('me')], busiest: { d: '2026-06-10', camp: api, score: 5 } })
  expect(stored.anonPlaces.length).toBe(1)
  expect(sessionsStore()).not.toHaveProperty(keyOf('me'))
  // The same session ending again stitches nothing more.
  await end($)
  expect(storedFarm().quilt.length).toBe(1)

})

test('Q7 a resume stitches nothing', async ($, on) => {
  engine(on)
  v5(on)
  await start($)
  await call($, { tool: 'Read', file_path: '/a' })
  await end($, 'resume')
  expect(world.db.get('farm')).toBeUndefined()
  expect(Object.keys(sessionsStore())).toEqual([])
})

test('Q7 an idle session leaves no square and no line', async ($, on) => {
  engine(on)
  v5(on)
  await start($)
  await end($, 'logout')
  expect(world.db.get('farm')).toBeUndefined()
  expect(Object.keys(sessionsStore())).toEqual([])
})

test('Q8 /clear stitches the day and starts a new one, and the new clothesline shows the square just stitched', async ($, on) => {
  engine(on)
  v5(on)
  await start($)
  await call($, { tool: 'Read', file_path: '/a' })
  v5world.sessionId = 'me2'
  await end($, 'clear')
  expect(storedFarm().quilt.map(sq => sq.c)).toEqual(['N'])
  expect(await quip($)).toBe('Fresh start. Same holler.')
  // The new session starts empty: another clear with nothing done adds nothing.
  await end($, 'clear', 'me2')
  expect(storedFarm().quilt.length).toBe(1)
  expect(storedFarm().sessionsWorked).toBe(1)
})

test('Q9 a stale heartbeat is stitched by another session, once, even when two prune it', async ($, on) => {
  const ghost = { name: 'Laurel Fork', lastSeen: JUNE_NOON - 10 * 60_000, sq: 'B12', ln: 'Jun 10 · Laurel Fork camp · 2 loads out' }
  const clock = engine(on, { result: {} }, { sessions: { [OTHER]: ghost } })
  v5(on)
  await start($)
  let stored = storedFarm()
  expect(stored.quilt).toEqual([{ c: 'B', d: '2026-06-10', camp: 'Laurel Fork' }])
  expect(stored.journal[0]?.line).toBe('Jun 10 · Laurel Fork camp · 2 loads out')
  expect(stored).toMatchObject({ sessionsWorked: 1, sessionsShipped: 1, stitched: [OTHER], busiest: { score: 12, camp: 'Laurel Fork' } })
  expect(sessionsStore()).not.toHaveProperty(OTHER)
  expect(await quip($)).toBe('Granny stitched a blue square. Shipped!')

  // A second session read the same dead heartbeat before it was removed: nothing doubles.
  world.db.set('sessions', {
    ...sessionsStore(),
    [OTHER]: ghost,
    [OTHER2]: { name: 'Sugar Run', lastSeen: JUNE_NOON - 10 * 60_000, sq: 'G5', ln: 'Jun 10 · Sugar Run camp · rain 5 times' },
  })
  await clock.advance(61_000)
  stored = storedFarm()
  expect(stored.quilt.map(sq => sq.c)).toEqual(['B', 'G'])
  expect(stored.stitched).toEqual([OTHER, OTHER2])
  const mine = Object.keys(sessionsStore())
  expect(mine.length).toBe(1)
  expect(mine).not.toContain(OTHER)

  // A heartbeat that was alive a moment ago is not touched.
  world.db.set('sessions', { ...sessionsStore(), c3c3c3c3c3c3: { name: 'Elk Lick', lastSeen: clock.now() - 1000, sq: 'B3', ln: 'x' } })
  await clock.advance(61_000)
  expect(storedFarm().quilt.length).toBe(2)
})

test('Q9 a dead heartbeat from a Jeb before the anonymizer is stitched under a place, its id hashed and its line rebuilt', async ($, on) => {
  engine(on, { result: {} }, {
    farm: saltFarm(),
    sessions: { 'sess-ghost-1': { name: 'glimmer', lastSeen: JUNE_NOON - 10 * 60_000, sq: 'B12', ln: 'Jun 10 · glimmer camp · 2 loads out, glimmer notes' } },
  })
  v5(on)
  await start($)
  const stored = storedFarm()
  expect(stored.quilt).toEqual([{ c: 'B', d: '2026-06-10', camp: placeOf('glimmer') }])
  expect(stored.journal[0]?.line).toBe(`Jun 10 · ${placeOf('glimmer')} camp · 2 loads out`)
  expect(stored.stitched).toEqual([keyOf('sess-ghost-1')])
  expect(JSON.stringify([...world.db.values()])).not.toContain('glimmer')
  expect(JSON.stringify([...world.db.values()])).not.toContain('sess-ghost')
})

test('Q10 the heartbeat carries this session\'s square and line so far, and a session that could not stitch leaves it behind', async ($, on) => {
  const clock = engine(on, { result: {} }, { farm: saltFarm() })
  v5(on)
  await start($)
  const me = keyOf('me')
  expect(sessionsStore()[me]?.sq).toBeUndefined()
  await begin($)
  await call($, { tool: 'Edit', file_path: '/a' })
  await clock.advance(61_000)
  expect(sessionsStore()[me]?.sq).toBe('N1')
  expect(sessionsStore()[me]?.ln).toBe(`Jun 10 · ${placeOf('api')} camp · quiet day, mended a fence`)
  // A store that cannot write when the session ends: no square, the heartbeat stays for another to stitch.
  world.isStoreFailing = true
  await end($)
  expect(sessionsStore()[me]?.sq).toBe('N1')
})

test('Q11 the counters: ships, tests, weeding, agents, edits, sours and refusals decide the square', async ($, on) => {
  const answer = { result: {}, isError: false }
  engine(on, answer, { farm: saltFarm() })
  v5(on)
  await start($)
  await begin($)
  await call($, bash(TEST_FILTERED))
  await call($, bash(TEST_FILTERED))
  await call($, bash('docker compose exec hot npm run lint'))
  await spawn($)
  await call($, { tool: 'Edit', file_path: '/a' })
  await end($)
  const farm = storedFarm()
  expect(farm.quilt.map(sq => sq.c)).toEqual(['G'])
  expect(farm.journal[0]?.line).toBe(`Jun 10 · ${placeOf('api')} camp · rain twice, 1 row hoed, 1 hand hired`)
})

test('Q12 five refusals and errors make a rough day; a sour batch counts for itself', async ($, on) => {
  const answer = { result: {}, isError: true }
  engine(on, answer, { farm: saltFarm() })
  v5(on)
  await start($)
  for (let i = 0; i < 5; i += 1) {
    await call($, { tool: 'Read', file_path: '/a' })
  }
  await end($)
  expect(storedFarm().quilt.map(sq => sq.c)).toEqual(['R'])
  expect(storedFarm().journal[0]?.line).toBe(`Jun 10 · ${placeOf('api')} camp · quiet day, mended a fence`)
})

test('Q13 the live square follows the counters on the slow beat and only when its color changes', async ($, on) => {
  const clock = engine(on)
  v5(on)
  const writes = { n: 0 }
  tap((e: any) => {
    if (e.key === 'anim') {
      writes.n += 1
    }
  })
  await start($)
  await begin($)
  await call($, bash(TEST_FILTERED))
  await clock.advance(3_100)
  // Counters that do not change the color write nothing extra: a quiet minute stays within the idle frame budget.
  await finish($, usage(0, 0))
  await call($, { tool: 'Read', file_path: '/a' })
  await clock.advance(20_000)
  writes.n = 0
  await clock.advance(60_000)
  expect(writes.n).toBeLessThanOrEqual(20)
  await call($, bash('git push'))
  await clock.advance(3_100)
})


// A time whose half-hour slot lands on the journal crumb (the sixth of six).


test('Q23 the greeting may recall the last session once, through the talk gate', async ($, on) => {
  const farm = { ...saltFarm(), journal: [{ d: '2026-10-22', camp: 'api', line: 'Oct 22 · api camp · 3 loads out' }] }
  engine(on, { result: {} }, { farm })
  await start($)
  expect(await quip($)).toBe('Last time: Oct 22 · api camp · 3 loads out')
})

test('Q23 a silent Jeb does not recall the last session', { options: { talk: 'silent' } }, async ($, on) => {
  const farm = { ...saltFarm(), journal: [{ d: '2026-10-22', camp: 'api', line: 'Oct 22 · api camp · 3 loads out' }] }
  engine(on, { result: {} }, { farm })
  await start($)
  expect(await quip($)).not.toContain('Last time')
})

test('Q24 a quilt on a farm from the future is never written; the session plays on its own', async ($, on) => {
  const future = { version: 11, brand: 'new' }
  engine(on, { result: {} }, { farm: future })
  v5(on)
  await start($)
  await call($, { tool: 'Read', file_path: '/a' })
  await end($)
  expect(world.db.get('farm')).toEqual(future)
})

// ------------------------------------------ RV: the code-review fixes ----

const HOUR_MS = 3_600_000
// How many microtask hops the Read waits after it is released: tuned so it finishes
// between the Edit's gate going up and the Edit's own call unwinding.
const GAP = 8

// The engine, with a machine clock the test can set ahead (the machine sleeping):
// every `$.clock.now()` answers the mock clock plus `machine.skew`.
const skewed = (on: any, entries: Record<string, unknown> = {}) => {
  const answers: Record<string, any> = {}
  const aside = ((event: string, ...rest: any[]) => {
    if (event === 'clock.now') {
      answers[event] = rest[rest.length - 1]

      return undefined
    }

    return on(event, ...rest)
  }) as typeof on
  const clock = engine(aside, { result: {} }, entries)
  const machine = { skew: 0 }
  on('clock.now', async (hooked: any, e: any, next: any) => {
    const result = await answers['clock.now'](hooked, e, next)

    return { ...result, value: result.value + machine.skew }
  })

  return { clock, machine }
}

const GHOST = { name: 'Laurel Fork', lastSeen: JUNE_NOON, sq: 'B12', ln: 'Jun 10 · Laurel Fork camp · 2 loads out' }

test('RV1 the session clock follows the machine every 30 s, Focus check or not; a jump re-bases it and holds that beat back', async ($, on) => {
  // The Focus files cannot be read here, so the Focus check gives up after three
  // tries: the clock must not depend on it.
  const { clock, machine } = skewed(on, { sessions: { [OTHER]: GHOST } })
  v5(on)
  await start($)
  await clock.advance(31_000)
  // The machine sleeps for eight hours; the next 30 s round finds the jump and
  // does not judge which camps are dead on a clock that was just wrong.
  machine.skew = 8 * HOUR_MS
  await clock.advance(30_000)
  expect(world.db.get('farm')).toBeUndefined()
  expect(sessionsStore()).toHaveProperty(OTHER)
  // The next beat is on the machine's time: the camp that was alive eight hours
  // ago is dead, stitched once, and this session's own heartbeat is dated now.
  await clock.advance(60_000)
  expect(storedFarm().stitched).toEqual([OTHER])
  expect(sessionsStore()).not.toHaveProperty(OTHER)
  // This session's own heartbeat is the one left (its key is a hash under a salt only the session holds yet).
  expect(Object.keys(sessionsStore()).length).toBe(1)
})

test('RV2 a farm a newer Jeb wrote after the session began is never overwritten, and saving stops', async ($, on) => {
  engine(on, { result: {} }, { farm: farm6() })
  await start($)
  await finish($, usage(400, 0))
  expect(storedFarm().lifetime.outputTokens).toBe(400)

  const future = { version: 11, brand: 'new' }
  world.db.set('farm', future)
  await finish($, usage(400, 0))
  expect(world.db.get('farm')).toEqual(future)
  await finish($, usage(400, 0))
  expect(world.db.get('farm')).toEqual(future)
})

test('RV3 a reload keeps the session record and does not greet again; another session id is a new session', CHATTY, async ($, on) => {
  engine(on, { result: {} }, { farm: saltFarm() })
  menu(on)
  v5(on)
  await start($)
  await begin($)
  await call($, bash('git push'))
  const before = spoken.length
  // A change in the options menu reloads the plugin: the hook runs session.start again.
  await $.config.set({ key: 'jeb.talk', value: 'ambient' })
  await start($)
  expect(spoken.length).toBe(before)
  await end($)
  expect(storedFarm().quilt.map(sq => sq.c)).toEqual(['B'])
  expect(storedFarm().journal.map(entry => entry.line)).toEqual([`Jun 10 · ${placeOf('api')} camp · 1 load out`])

  // The same process under another session id is not the session that was kept.
  v5world.sessionId = 'me2'
  await start($)
  expect(spoken.length).toBeGreaterThan(before)
  await end($, 'prompt_input_exit', 'me2')
  expect(storedFarm().quilt.length).toBe(1)
})

test('RV4 a resume drops the old heartbeat, carries the record to the new session id and counts it once', async ($, on) => {
  const clock = engine(on, { result: {} }, { farm: saltFarm() })
  v5(on)
  await start($)
  await begin($)
  await call($, bash('git push'))
  await clock.advance(61_000)
  expect(sessionsStore()[keyOf('me')]?.sq).toBe('B5')

  v5world.sessionId = 'me2'
  await end($, 'resume', 'me')
  await clock.advance(61_000)
  expect(Object.keys(sessionsStore())).toEqual([keyOf('me2')])
  expect(sessionsStore()[keyOf('me2')]?.sq).toBe('B5')

  await end($, 'prompt_input_exit', 'me2')
  expect(storedFarm().stitched).toEqual([keyOf('me2')])
  expect(storedFarm().quilt.length).toBe(1)
  // Nothing of the old id is left to be stitched a second time.
  await clock.advance(10 * 60_000)
  expect(storedFarm().quilt.length).toBe(1)
})

test('RV5 a call a settings hook refused counts for nothing: no sour batch, no storm, no failed test, no square', CHATTY_HOOKS, async ($, on) => {
  const batch = farm6({ still: { steps: 1, hasBatch: true } })
  engine(on, { result: {}, isError: true }, { farm: batch })
  v5(on)
  v5world.denyTools = true
  await start($)
  for (let i = 0; i < 3; i += 1) {
    await call($, bash(TEST_FILTERED))
  }
  // The batch is not soured and the third refusal is not a storm.
  expect(storedFarm().still).toEqual({ steps: 1, hasBatch: true })
  expect(await quip($)).toBe('Somebody put up a gate.')
  // Nothing was done in the session: no square, no line.
  await end($)
  expect(storedFarm().quilt).toEqual([])
  expect(storedFarm().journal).toEqual([])
})

test('RV6 a dead session\'s heartbeat stays in the store until its square is on the quilt', async ($, on) => {
  const clock = engine(on, { result: {} }, { sessions: { [OTHER]: { ...GHOST, lastSeen: JUNE_NOON - 10 * 60_000 } } })
  v5(on)
  world.failKey = 'farm'
  await start($)
  // The farm could not be saved: the square is not lost with the heartbeat.
  expect(sessionsStore()).toHaveProperty(OTHER)
  expect(world.db.get('farm')).toBeUndefined()

  world.failKey = undefined
  await clock.advance(61_000)
  expect(storedFarm().stitched).toEqual([OTHER])
  expect(storedFarm().quilt.map(sq => sq.c)).toEqual(['B'])
  expect(sessionsStore()).not.toHaveProperty(OTHER)
})

test('RV7 a farm save another session raced re-applies its change onto theirs', async ($, on) => {
  engine(on, { result: {} }, { farm: farm6() })
  await start($)
  const snapshot = copy(world.db.get('farm')) as Farm6
  const rev = snapshot.rev
  let sets = 0
  world.afterSet = key => {
    // The other session read the farm before this write and writes the same moment.
    if (key === 'farm' && (sets += 1) === 1) {
      world.db.set('farm', copy({ ...snapshot, rev: rev + 1, barn: { ...snapshot.barn, sticks: 3 } }))
    }
  }
  await finish($, usage(400, 0))
  // Both changes are there, on a rev one past the other session's.
  expect(storedFarm().barn.sticks).toBe(3)
  expect(storedFarm().lifetime.outputTokens).toBe(400)
  expect(storedFarm().rev).toBe(rev + 2)
  expect(sets).toBe(2)
})

test('RV7 a save raced every time gives up after applying its change twice more', async ($, on) => {
  engine(on, { result: {} }, { farm: farm6() })
  await start($)
  let sets = 0
  world.afterSet = key => {
    if (key === 'farm') {
      sets += 1
      const written = world.db.get('farm') as Farm6
      world.db.set('farm', copy({ ...written, barn: { ...written.barn, sticks: sets } }))
    }
  }
  await finish($, usage(400, 0))
  expect(sets).toBe(3)
})

test('RV7 the rev counts every write and a farm without one reads as rev 0', async ($, on) => {
  expect(loadFarm({ ...freshFarm(), rev: undefined }) as Farm6).toMatchObject({ rev: 0 })
  expect(loadFarm({ ...freshFarm(), rev: 'x' })).toMatchObject({ rev: 0 })
  expect(loadFarm({ ...freshFarm(), rev: -3.7 })).toMatchObject({ rev: 0 })
  engine(on, { result: {} }, { farm: farm6() })
  await start($)
  const first = storedFarm().rev
  await finish($, usage(400, 0))
  await finish($, usage(400, 0))
  expect(storedFarm().rev).toBe(first + 2)
})

test('RV8 a gate belongs to the call it refused: kept by tool_use_id, used up once, at most sixteen', () => {
  const gates = new Map<string, true>()
  markGate(gates, 'a')
  expect(takeGate(gates, 'b')).toBe(false)
  expect(takeGate(gates, 'a')).toBe(true)
  expect(takeGate(gates, 'a')).toBe(false)
  for (let i = 0; i < MAX_GATES + 5; i += 1) {
    markGate(gates, `t${i}`)
  }
  expect(gates.size).toBe(MAX_GATES)
  expect(takeGate(gates, 't0')).toBe(false)
  expect(takeGate(gates, `t${MAX_GATES + 4}`)).toBe(true)
})

test('RV8 a call finishing while another call\'s gate is up is not credited with it', CHATTY_HOOKS, async ($, on) => {
  // The refused call lets a second call finish just as it denies: the second
  // call, which ran, is still the success it was, and the refused one is still
  // the refused one (its batch is not soured).
  let release: () => void = () => undefined
  const held = new Promise<void>(resolve => {
    release = resolve
  })
  engine(
    on,
    async (_: unknown, e: any) => {
      if (e.command === 'git push') {
        await held
        for (let i = 0; i < GAP; i += 1) {
          await Promise.resolve()
        }
      }

      return { result: {}, isError: e.command !== 'git push' }
    },
    { farm: farm6({ still: { steps: 1, hasBatch: true } }) },
  )
  v5(on)
  v5world.onPre = async e => {
    if (e.command === TEST_FILTERED) {
      release()

      return { deny: 'not on my farm' }
    }

    return undefined
  }
  await start($)
  await Promise.all([$.tool.call(bash('git push')), $.tool.call(bash(TEST_FILTERED))])
  await clk.settle()
  // The push ran the still one step further; the refused run did not sour it.
  expect(storedFarm().still).toEqual({ steps: 2, hasBatch: true })
  await end($)
  // The push counted as a call of the session, the refused test run for nothing.
  expect(storedFarm().quilt.map(sq => sq.c)).toEqual(['B'])
})

test('RV9 a run nobody is at (-p, the SDK) sets up nothing periodic, stitches nothing and says nothing, but the crops grow', async ($, on) => {
  const clock = engine(on, { result: {} }, { sessions: { ghost: { ...GHOST, lastSeen: JUNE_NOON - 10 * 60_000 } } })
  v5(on)
  await $.session.start({ cwd: '/', surface: null, isInteractive: false })
  await clock.advance(5 * 60_000)
  // No heartbeat (the dead camp is left alone too).
  expect(Object.keys(sessionsStore())).toEqual(['ghost'])
  await begin($)
  await call($, bash('git push'))
  await call($, { tool: 'Edit', file_path: '/a' })
  // 9600 output tokens are a bushel of corn: a harvest that would pluck a banjo.
  await finish($, usage(9600, 0))
  expect(await tally($)).toContain('1 bu corn')
  await clock.advance(5 * 60_000)
  await end($)
  expect(storedFarm().quilt).toEqual([])
  expect(storedFarm().journal).toEqual([])
  expect(Object.keys(sessionsStore())).toEqual(['ghost'])
})

test('RV10 a workflow hand with no step or tool call of its own for half an hour leaves; one that works stays', async ($, on) => {
  const clock = engine(on)
  v5(on)
  await start($)
  const quiet = await spawn($, { workflow: { runId: 'wf_1', agentIndex: 1 } })
  const busy = await spawn($, { workflow: { runId: 'wf_1', agentIndex: 2 } })

  await clock.advance(20 * 60_000)
  await call($, { tool: 'Read', file_path: '/a', agentId: busy.agentId })
  await clock.advance(11 * 60_000)
  expect(quiet.agentId).not.toBe(busy.agentId)

  await clock.advance(20 * 60_000)
})

test('RV11 only a script called deploy or deploy.sh ships; undeploy.sh, deploy-check and preview-deploy-cleanup do not', () => {
  for (const command of ['./deploy.sh', 'scripts/deploy', 'bin/deploy.sh --prod', 'sudo ./deploy', 'make deploy']) {
    expect(isShip(command)).toBe(true)
  }
  for (const command of ['./undeploy.sh', 'scripts/deploy-check', './preview-deploy-cleanup', 'bin/redeploy.sh', 'ls deploy', './deploy.py']) {
    expect(isShip(command)).toBe(false)
  }
})

// The neighbor comes by: on a January morning only the revenuer and the neighbor
// can come, and the revenuer is not asked back for ten minutes, so the neighbor
// is the first or the second visitor. The jar is on the shelf of the stored farm
// when she sets out or not, and again when she gets there or not.
const opalVisit = async ($: any, on: any, jarAtStart: boolean, jarAtSale: boolean) => {
  const jar = (count: number) => farm6({ shelf: { lightning: 0, appleCinnamon: count } })
  const clock = engine(on, { result: {} }, { farm: jar(jarAtStart ? 1 : 0) }, at(0, 14, 10).getTime())
  on('prompt.submit', (_: any, e: any) => e)
  await start($)
  let isHere = false
  for (let seconds = 0; seconds < 900 && !isHere; seconds += 3) {
    // The scene goes still after two idle minutes and no visitor comes then: a
    // meta prompt (activity) every minute keeps the farm awake.
    if (seconds % 60 === 0) {
      await poke($)
    }
    await clock.advance(3_000)
    isHere = (await quip($)) === "Miss Opal's comin' up the road."
  }
  expect(isHere).toBe(true)
  // Another session sold the jar, or put one up, before she gets here.
  world.db.set('farm', copy({ ...storedFarm(), shelf: { lightning: 0, appleCinnamon: jarAtSale ? 1 : 0 } }))
  await clock.advance(40_000)

  return quip($)
}

test('RV12 Miss Opal\'s line is decided by the sale: a jar gone before she came says next batch', CHATTY, async ($, on) => {
  expect(await opalVisit($, on, true, false)).toBe('Next batch, Miss Opal.')
  expect(storedFarm().ledger.total).toBe(0)
})

test('RV12 Miss Opal buying the jar says so', CHATTY, async ($, on) => {
  expect(await opalVisit($, on, true, true)).toBe('Sold Miss Opal a jar. $25.')
  expect(storedFarm().ledger.total).toBe(25)
})

test('RV12 Miss Opal buying a jar that was not there when she set out says so too', CHATTY, async ($, on) => {
  expect(await opalVisit($, on, false, true)).toBe('Sold Miss Opal a jar. $25.')
  expect(storedFarm().ledger.byCustomer.opal).toBe(25)
})


test('RV14 a growth that earns an upgrade is one save of the farm, not two', async ($, on) => {
  engine(on, { result: {} }, { farm: farm6({ ledger: withLedger({ total: 60, cash: 60 }) }) })
  await start($)
  let sets = 0
  world.afterSet = key => {
    sets += key === 'farm' ? 1 : 0
  }
  await finish($, usage(400, 0))
  expect(sets).toBe(1)
  expect(storedFarm().upgrades).toEqual(['mailbox'])
  expect(storedFarm().lifetime.outputTokens).toBe(400)
})

test('RV15 the shared helpers: one pluralizer, one text cleaner, one weighted draw', () => {
  expect(plural(1, 'jar')).toBe('1 jar')
  expect(plural(2, 'jar')).toBe('2 jars')
  expect(plural(0, 'batch', 'batches')).toBe('0 batches')
  expect(cleanText('  a\u0000b\u007fc  ', 5)).toBe('a b c')
  expect(cleanText(undefined, 5)).toBe('')
  expect(cleanText('abcdefgh', 3)).toBe('abc')
  const pool = [
    { id: 'a', weight: 1 },
    { id: 'b', weight: 3 },
  ]
  expect(pickWeighted(pool, () => 0)?.id).toBe('a')
  expect(pickWeighted(pool, () => 0.24)?.id).toBe('a')
  expect(pickWeighted(pool, () => 0.26)?.id).toBe('b')
  expect(pickWeighted(pool, () => 0.999)?.id).toBe('b')
  expect(pickWeighted([], () => 0.5)).toBeUndefined()
  expect(pickWeighted([{ id: 'z', weight: 0 }], () => 0.5)).toBeUndefined()
  // Hired hands' text goes through the same cleaner.
  expect(hireOf({ agentId: ' a\u0000b ', description: 'x'.repeat(50) }, 0)).toMatchObject({
    id: 'a b',
    description: 'x'.repeat(32),
  })
})

test('RV16 npm run format rewrites files like pint without --test: no pass verdict', () => {
  const lint = (command: string) => workOf(classify(command))
  expect(lint('npm run format')).toMatchObject({ kind: 'lint', tool: 'npm:format', fixes: true })
  expect(lint('yarn format')).toMatchObject({ kind: 'lint', fixes: true })
  expect(lint('docker compose exec hot npm run format')).toMatchObject({ kind: 'lint', fixes: true })
  expect(lint('npm run lint')?.fixes).toBeUndefined()
  expect(lint('npm run types')?.fixes).toBeUndefined()
})


// ---- the composer ----


test('VI2 the gaps are drawn inside their ranges: two to four minutes, then four to nine', () => {
  for (const r of [0, 0.25, 0.5, 0.75, 0.9999999]) {
    const first = spanOf(FIRST_VISIT_MS, () => r)
    expect(first).toBeGreaterThanOrEqual(120_000)
    expect(first).toBeLessThanOrEqual(240_000)
    const next = spanOf(NEXT_VISIT_MS, () => r)
    expect(next).toBeGreaterThanOrEqual(240_000)
    expect(next).toBeLessThanOrEqual(540_000)
  }
})

const stockedFor = (over: Partial<Farm6> = {}) => farm6({ shelf: { lightning: 0, appleCinnamon: 0 }, ...over })

test('VI3 kinds: the buyer needs stock, the tripper only comes at night, the mail only with a mailbox at midday once a day', () => {
  const noon = new Date(2026, 5, 10, 11, 0)
  const night = new Date(2026, 5, 10, 22, 0)
  const empty = stockedFor()
  // Nothing in stock: no buyer, so a non-buyer visit (the tractor, as no mailbox is up).
  expect(visitorsFor(noon, empty)).toEqual([])
  for (const r of [0, 0.3, 0.6, 0.99]) {
    expect(pickVisit(noon, empty, '', () => r)).toEqual({ kind: 'tractor' })
  }
  // Lightning on the shelf: the tripper at night, nobody at noon.
  const shine = stockedFor({ shelf: { lightning: 12, appleCinnamon: 0 } })
  expect(visitorsFor(noon, shine).map(entry => entry.id)).toEqual([])
  expect(visitorsFor(night, shine).map(entry => entry.id)).toEqual(['tripper'])
  const kinds = new Set([0, 0.2, 0.5, 0.8, 0.99].map(r => pickVisit(noon, shine, '', () => r).kind))
  expect([...kinds]).toEqual(['tractor'])
  expect(pickVisit(night, shine, '', () => 0)).toEqual({ kind: 'tripper', customer: 'tripper' })
  // The mail: mailbox up, 10:00 to 14:00, once a local day.
  const boxed = stockedFor({ upgrades: ['mailbox'] })
  expect(isMailDue(noon, boxed, '')).toBe(true)
  expect(isMailDue(noon, empty, '')).toBe(false)
  expect(isMailDue(new Date(2026, 5, 10, 9, 59), boxed, '')).toBe(false)
  expect(isMailDue(new Date(2026, 5, 10, 14, 0), boxed, '')).toBe(false)
  expect(isMailDue(noon, boxed, '2026-06-10')).toBe(false)
  expect(isMailDue(new Date(2026, 5, 11, 11, 0), boxed, '2026-06-10')).toBe(true)
  expect(pickVisit(noon, boxed, '', () => 0)).toEqual({ kind: 'mail' })
  expect(pickVisit(noon, boxed, '2026-06-10', () => 0)).toEqual({ kind: 'tractor' })
  // The fair stays a truck run: in August it never comes by on its own.
  const august = new Date(2026, 7, 12, 11, 0)
  const jars = stockedFor({ shelf: { lightning: 0, appleCinnamon: 6 } })
  expect(visitorsFor(august, jars).map(entry => entry.id)).not.toContain('fair')
})

test('VI4 buyers map to their rigs: the store and market one, the mill and warehouse another', () => {
  const day = new Date(2026, 5, 10, 11, 0)
  const apples = stockedFor({ barn: { bales: 0, corn: 3, apples: 60, sticks: 0 } })
  expect(pickVisit(day, apples, '', () => 0)).toEqual({ kind: 'store', customer: 'store' })
  const bales = stockedFor({ barn: { bales: 5, corn: 3, apples: 10, sticks: 0 } })
  expect(pickVisit(day, bales, '', () => 0)).toEqual({ kind: 'mill', customer: 'warehouse' })
  const corn = stockedFor({ barn: { bales: 0, corn: 30, apples: 10, sticks: 0 } })
  expect(pickVisit(day, corn, '', () => 0)).toEqual({ kind: 'mill', customer: 'mill' })
  const saturday = new Date(2026, 5, 13, 11, 0)
  expect(pickVisit(saturday, stockedFor({ barn: { bales: 0, corn: 3, apples: 60, sticks: 0 } }), '', () => 0)).toEqual({
    kind: 'store',
    customer: 'market',
  })
  const jar = stockedFor({ shelf: { lightning: 0, appleCinnamon: 1 } })
  expect(pickVisit(day, jar, '', () => 0)).toEqual({ kind: 'opal', customer: 'opal' })
})

test('VI5 a visiting buyer sells to that buyer only, once, and the books move', () => {
  const day = new Date(2026, 5, 10, 11, 0)
  const old = stockedFor({ shelf: { lightning: 0, appleCinnamon: 3 } })
  const out = sellVisit(old, 'opal', day, () => 0.5)
  expect(out.sale?.customer).toBe('opal')
  expect(out.next.shelf.appleCinnamon).toBe(2)
  expect(out.next.ledger.total).toBe(25)
  expect(out.next.ledger.byCustomer.opal).toBe(25)
  expect(out.isNew).toBe(true)
  // A buyer with nothing to take buys nothing.
  const none = sellVisit(stockedFor(), 'store', day, () => 0.5)
  expect(none.sale).toBeUndefined()
  expect(none.next).toEqual(stockedFor())
})

test('VI6 a visit travels the road slowly: 16 ticks in for a rig, 20 for Miss Opal, 120 across for the tractor, 80 to 120 dealing', () => {
  const ticks = (kind: keyof typeof VISIT_SPECS) => (VISIT_SPECS[kind].reach / VISIT_SPECS[kind].step) * VISIT_SPECS[kind].every
  for (const kind of ['store', 'mill', 'tripper', 'mail'] as const) {
    expect(VISIT_SPECS[kind].step).toBe(2)
    expect(ticks(kind)).toBe(16)
  }
  expect(VISIT_SPECS.opal.step).toBe(1)
  expect(ticks('opal')).toBe(20)
  // Half a unit a tick: one unit every second tick, a minute or more across.
  expect(VISIT_SPECS.tractor.step / VISIT_SPECS.tractor.every).toBe(0.5)
  expect(ticks('tractor')).toBe(120)
  expect(DEAL_TICKS).toEqual([80, 120])
})


// The engine's frames, as they are written.
const watchFrames = (_on: any, clock: MockClock) => {
  const log = { writes: [] as { at: number; anim: Anim }[], says: [] as string[] }
  tap((e: any) => {
    if (e.key === 'anim') {
      log.writes.push({ at: clock.now(), anim: e.value })
    }
    if (e.key === 'say') {
      log.says.push(e.value.line)
    }
  })

  return log
}

// Visits on, drawing the same number every time (see JEB_VISITS in register.tsx), for the length of one test.
const withRandom = async (value: number, run: () => Promise<void>) => {
  visits.on = true
  visits.draw = String(value)
  try {
    await run()
  } finally {
    visits.on = false
  }
}

const firstVisitAt = (log: ReturnType<typeof watchFrames>) => log.writes.find(w => w.anim.visit)?.at

test('VI9 nothing comes before two minutes, and a first visit comes by four', CHATTY, async ($, on) => {
  await withRandom(0.9999999, async () => {
    const clock = engine(on, { result: {} }, {}, JUNE_NOON)
    const log = watchFrames(on, clock)
    await start($)
    const t0 = clock.now()
    await clock.advance(119_000)
    expect(firstVisitAt(log)).toBeUndefined()
    await clock.advance(120_000)
    expect(firstVisitAt(log)).toBeUndefined()
    await clock.advance(2_000)
    const at = firstVisitAt(log)
    expect(at).toBeDefined()
    expect((at as number) - t0).toBeGreaterThanOrEqual(240_000)
    expect((at as number) - t0).toBeLessThanOrEqual(241_000)
  })
})

test('VI9 with the shortest draw the first visit is at two minutes', CHATTY, async ($, on) => {
  await withRandom(0, async () => {
    const clock = engine(on, { result: {} }, {}, JUNE_NOON)
    const log = watchFrames(on, clock)
    await start($)
    const t0 = clock.now()
    await clock.advance(119_000)
    expect(firstVisitAt(log)).toBeUndefined()
    await clock.advance(3_000)
    expect((firstVisitAt(log) as number) - t0).toBeLessThanOrEqual(121_000)
  })
})

test('VI10 no visit overlaps a truck run or a happening, and one blocked tries again later', CHATTY, async ($, on) => {
  await withRandom(0, async () => {
    const clock = engine(on, { result: {} }, {}, JUNE_NOON)
    const log = watchFrames(on, clock)
    await start($)
    // The truck sets out as the first visit falls due.
    await clock.advance(118_000)
    await $.tool.call({ tool: 'Bash', command: 'git push' })
    await clock.advance(60_000)
    const first = firstVisitAt(log)
    expect(first).toBeDefined()
    const truckEnd = log.writes.filter(w => w.anim.truck).pop()?.at as number
    expect(first as number).toBeGreaterThan(truckEnd)
    await clock.advance(25 * 60_000)
    for (const { anim } of log.writes) {
      expect(anim.visit !== null && anim.truck !== null).toBe(false)
      expect(anim.visit !== null && anim.event !== null).toBe(false)
    }
  })
})

test('VI11 a buyer visit sells exactly once, to its own buyer, and the ledger and shelf follow', CHATTY, async ($, on) => {
  await withRandom(0, async () => {
    const clock = engine(on, { result: {} }, { farm: stockedFor({ shelf: { lightning: 0, appleCinnamon: 3 } }) }, JUNE_NOON)
    const log = watchFrames(on, clock)
    await start($)
    await clock.advance(125_000)
    const kinds = new Set(log.writes.flatMap(w => (w.anim.visit ? [w.anim.visit.kind] : [])))
    expect([...kinds]).toEqual(['opal'])
    // She walks in for ten seconds and the sale is made when she stops.
    await clock.advance(15_000)
    expect(storedFarm().ledger.total).toBe(25)
    expect(storedFarm().shelf.appleCinnamon).toBe(2)
    expect(storedFarm().ledger.byCustomer.opal).toBe(25)
    expect(storedFarm().ledger.deliveries).toBe(0)
    expect(log.says.some(line => said('saleOpal', fillSaleFor(line)))).toBe(true)
    // She deals for 40 s and walks back for ten: gone, and the one sale stands.
    await clock.advance(50_000)
    expect(storedFarm().ledger.total).toBe(25)
    expect(log.writes[log.writes.length - 1]?.anim.visit).toBeNull()
  })
})

const fillSaleFor = (line: string) => line.replace(/\$\d+/, '{money}').replace(/\b(one|two|three|no) jars?\b/, '{what}')

test('VI12 a store buyer drives in a store rig, stops, and the barn and ledger update once', CHATTY, async ($, on) => {
  await withRandom(0, async () => {
    const apples = stockedFor({ barn: { bales: 0, corn: 3, apples: 60, sticks: 0 } })
    const clock = engine(on, { result: {} }, { farm: apples }, JUNE_NOON)
    const log = watchFrames(on, clock)
    await start($)
    await clock.advance(190_000)
    const phases = log.writes.flatMap(w => (w.anim.visit ? [w.anim.visit] : []))
    expect(new Set(phases.map(v => v.kind))).toEqual(new Set(['store']))
    expect(phases[0]?.phase).toBe('arrive')
    expect(phases.some(v => v.phase === 'deal')).toBe(true)
    expect(phases.some(v => v.phase === 'leave' && v.facing === 'out')).toBe(true)
    // 16 ticks in and 16 back write a frame each; the 40 s of dealing one every 3 s.
    expect(phases.filter(v => v.phase !== 'deal').length).toBeLessThanOrEqual(40)
    expect(phases.filter(v => v.phase === 'deal').length).toBeLessThanOrEqual(20)
    expect(storedFarm().barn.apples).toBe(40)
    expect(storedFarm().ledger.byCustomer.store).toBe(100)
    expect(storedFarm().ledger.total).toBe(100)
  })
})

test('VI13 the mail stops at the mailbox, says so, sells nothing, and comes once a day', CHATTY, async ($, on) => {
  await withRandom(0, async () => {
    const elevenAm = at(5, 10, 11).getTime()
    const clock = engine(on, { result: {} }, { farm: stockedFor({ upgrades: ['mailbox'] }) }, elevenAm)
    const log = watchFrames(on, clock)
    await start($)
    await clock.advance(180_000)
    const kinds = log.writes.flatMap(w => (w.anim.visit ? [w.anim.visit.kind] : []))
    expect(new Set(kinds)).toEqual(new Set(['mail']))
    expect(log.says).toContain("Mail's here.")
    expect(storedFarm().ledger.total).toBe(0)
    // The same day it does not come again: the tractor goes by instead.
    await clock.advance(20 * 60_000)
    const later = log.writes.flatMap(w => (w.anim.visit ? [w.anim.visit.kind] : []))
    expect(later.filter(kind => kind === 'mail').length).toBe(kinds.length)
    expect(log.says.filter(line => line === "Mail's here.").length).toBe(1)
    expect(later).toContain('tractor')
  })
})

test('VI14 a visit wakes still-life and, when it ends, the two-minute countdown starts over', CHATTY, async ($, on) => {
  await withRandom(0.9999999, async () => {
    const clock = engine(on, { result: {} }, {}, JUNE_NOON)
    const log = watchFrames(on, clock)
    await start($)
    // Still after two quiet minutes: nothing is written until the visit at four.
    await clock.advance(130_000)
    const quiet = log.writes.length
    await clock.advance(100_000)
    expect(log.writes.length).toBe(quiet)
    expect(firstVisitAt(log)).toBeUndefined()
    // The visit wakes it.
    await clock.advance(20_000)
    expect(firstVisitAt(log)).toBeDefined()
    expect(log.writes.length).toBeGreaterThan(quiet)
    // The tractor crosses in a minute; then the two-minute countdown runs again (a
    // happening may come first and wake it once more, as it does after any activity).
    await clock.advance(70_000)
    expect(log.writes[log.writes.length - 1]?.anim.visit).toBeNull()
    let stillAt = 0
    for (let t = 0; t < 12 * 60_000 && stillAt === 0; t += 10_000) {
      await clock.advance(10_000)
      if (clock.now() - (log.writes[log.writes.length - 1]?.at as number) > 15_000) {
        // (the slow idle frame writes every 3 s until the scene freezes)
        stillAt = clock.now()
      }
    }
    expect(stillAt).toBeGreaterThan(0)
    const lastMoving = log.writes.length
    await clock.advance(30_000)
    expect(log.writes.length).toBe(lastMoving)
  })
})

test('VI15 JEB_VISITS=off (the default of these tests) leaves the road and Blue alone', CHATTY, async ($, on) => {
  const clock = engine(on, { result: {} }, {}, JUNE_NOON)
  const log = watchFrames(on, clock)
  await start($)
  await clock.advance(20 * 60_000)
  expect(firstVisitAt(log)).toBeUndefined()
  expect(log.writes.every(w => w.anim.dogRun === 0)).toBe(true)
})

test('VI16 Blue runs the fields on his own every five to eight minutes when it is quiet', CHATTY, async ($, on) => {
  await withRandom(0, async () => {
    const clock = engine(on, { result: {} }, {}, JUNE_NOON)
    const log = watchFrames(on, clock)
    await start($)
    await clock.advance(5 * 60_000 - 2_000)
    expect(log.writes.some(w => w.anim.dogRun > 0)).toBe(false)
    await clock.advance(10_000)
    expect(log.writes.some(w => w.anim.dogRun > 0)).toBe(true)
    // And back: he is home again within the half minute.
    await clock.advance(30_000)
    expect(log.writes[log.writes.length - 1]?.anim.dogRun).toBe(0)
  })
})

test('VI17 a happening stands still for whole stretches: the bear all through, the neighbor while she talks, never the revenuer', () => {
  expect(restOf({ id: 'bear', t: 17, dur: 80 })).toBe(0)
  expect(restOf({ id: 'neighbor', t: 10, dur: 80 })).toBeUndefined()
  expect(restOf({ id: 'neighbor', t: 40, dur: 80 })).toBe(40)
  expect(restOf({ id: 'neighbor', t: 63, dur: 80 })).toBe(40)
  expect(restOf({ id: 'neighbor', t: 64, dur: 80 })).toBeUndefined()
  expect(restOf({ id: 'revenuer', t: 40, dur: 90 })).toBeUndefined()
  expect(restOf({ id: 'storm', t: 40, dur: 90 })).toBeUndefined()
})

test('VI18 ramps: a daytime April happening that stands still, speaks twice and stamps a sprout', () => {
  const ids = (now: Date) => eligibleEvents({ now, isBusy: false, errorStreak: 0 }, new Set()).map(entry => entry.id)
  expect(ids(new Date(2026, 3, 12, 11))).toContain('ramps')
  expect(ids(new Date(2026, 3, 12, 22))).not.toContain('ramps')
  expect(ids(new Date(2026, 4, 12, 11))).not.toContain('ramps')
  expect(beatsOf('ramps', false).map(beat => beat.line)).toEqual([
    'Ramps are up on the north slope.',
    'Smells like spring, and a mite like trouble.',
  ])
  expect(restOf({ id: 'ramps', t: 10, dur: 70 })).toBe(0)
})

test('VI19 sang: a daytime September happening that stands still, speaks twice and stamps a leaf', () => {
  const ids = (now: Date) => eligibleEvents({ now, isBusy: false, errorStreak: 0 }, new Set()).map(entry => entry.id)
  expect(ids(new Date(2026, 8, 12, 11))).toContain('sang')
  expect(ids(new Date(2026, 8, 12, 22))).not.toContain('sang')
  expect(ids(new Date(2026, 9, 12, 11))).not.toContain('sang')
  expect(beatsOf('sang', false).map(beat => beat.line)).toEqual([
    "Sang season's open. Eyes on the ground.",
    'Four prongs, red berries. Plant the seed back.',
  ])
  expect(restOf({ id: 'sang', t: 10, dur: 70 })).toBe(0)
})

test('VI20 quilting: a daytime winter happening that stands still, speaks twice and stamps a spool', () => {
  const ids = (now: Date) => eligibleEvents({ now, isBusy: false, errorStreak: 0 }, new Set()).map(entry => entry.id)
  expect(ids(new Date(2026, 0, 12, 11))).toContain('quilting')
  expect(ids(new Date(2026, 11, 12, 11))).toContain('quilting')
  expect(ids(new Date(2026, 0, 12, 22))).not.toContain('quilting')
  expect(ids(new Date(2026, 5, 12, 11))).not.toContain('quilting')
  expect(beatsOf('quilting', false).map(beat => beat.line)).toEqual([
    "Piecin' a quilt from feed sacks, same as Granny.",
    'Small stitches. These cold nights run long.',
  ])
  expect(restOf({ id: 'quilting', t: 10, dur: 80 })).toBe(0)
})

test('VI21 britches: a daytime midsummer happening that stands still, speaks twice and stamps a bean', () => {
  const ids = (now: Date) => eligibleEvents({ now, isBusy: false, errorStreak: 0 }, new Set()).map(entry => entry.id)
  expect(ids(new Date(2026, 6, 12, 11))).toContain('britches')
  expect(ids(new Date(2026, 7, 12, 11))).toContain('britches')
  expect(ids(new Date(2026, 6, 12, 22))).not.toContain('britches')
  expect(ids(new Date(2026, 0, 12, 11))).not.toContain('britches')
  expect(beatsOf('britches', false).map(beat => beat.line)).toEqual([
    "Stringin' beans for leather britches.",
    'Hang them high and dry. Come winter, we feast.',
  ])
  expect(restOf({ id: 'britches', t: 10, dur: 80 })).toBe(0)
})
