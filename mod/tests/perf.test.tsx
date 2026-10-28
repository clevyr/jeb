import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import { classify } from '../hooks/classify'
import { freshFarm } from '../hooks/homestead'
import { stateSize } from '../hooks/register'

// Performance: one timer, bounded state, a quiet idle. The clock is the mock
// one; the world beneath Jeb is counted as it is asked.

// Ambient visits arrive at random: off (JEB_VISITS=off) unless a test sets `visits.on`
// before it builds the engine (a test that does sets it back when it is done).
const visits = { on: false, draw: '' }

const START = new Date(2026, 5, 10, 9, 0, 0).getTime()
const TICK = 500
const MINUTE = 60_000
const HOUR = 60 * MINUTE

const tally = {
  everyPeriods: 0,
  animWrites: 0,
  sayWrites: 0,
  quietWrites: 0,
  stateWrites: 0,
  farmWrites: 0,
  viewWrites: 0,
  storeSets: 0,
  // The live record's writes (see live.ts): how many, when, and the largest one in bytes.
  liveSets: 0,
  liveAt: [] as number[],
  liveMax: 0,
  storeGets: 0,
  fsReads: 0,
  clockNows: 0,
  atoms: {} as Record<string, string>,
  agentIds: 0,
  db: new Map<string, unknown>(),
  // Every frame written, with the time (E17 reads them).
  frames: [] as { at: number; anim: any }[],
}

const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

const usage = (output: number, input: number) => ({
  model: 'm',
  input_tokens: input,
  output_tokens: output,
  cache_read_input_tokens: 0,
  cache_creation_input_tokens: 0,
})

// The Focus files as a quiet machine has them: no assertion, a schedule that is off.
const ASSERTIONS = JSON.stringify({
  data: [{ storeInvalidationRequestRecords: [], storeInvalidationRecords: [] }],
  header: { version: 1, timestamp: 800_000_000 },
})
const MODES = JSON.stringify({
  data: [
    {
      modeConfigurations: {
        'com.apple.donotdisturb.mode.default': {
          triggers: {
            triggers: [
              {
                class: 'DNDModeConfigurationScheduleTrigger',
                timePeriodStartTimeHour: 9,
                timePeriodStartTimeMinute: 0,
                timePeriodEndTimeHour: 17,
                timePeriodEndTimeMinute: 0,
                timePeriodWeekdays: 127,
                enabledSetting: 0,
                creationDate: 800_000_000,
              },
            ],
          },
          mode: { name: 'Do Not Disturb', modeIdentifier: 'com.apple.donotdisturb.mode.default' },
        },
      },
    },
  ],
  header: { version: 1, timestamp: 800_000_000 },
})

const plan = {
  chunks: [] as any[],
  // Runs after each chunk the model beneath has streamed (may move the clock).
  between: undefined as undefined | ((at: number) => Promise<void>),
  result: { turnId: 't', index: 0, answer: '', toolUses: [], stopReason: 'end_turn', usage: null } as object,
}

const rig = (on: any, entries: Record<string, unknown> = {}): MockClock => {
  tally.everyPeriods = 0
  tally.animWrites = 0
  tally.sayWrites = 0
  tally.quietWrites = 0
  tally.stateWrites = 0
  tally.farmWrites = 0
  tally.viewWrites = 0
  tally.storeSets = 0
  tally.liveSets = 0
  tally.liveAt = []
  tally.liveMax = 0
  tally.storeGets = 0
  tally.fsReads = 0
  tally.clockNows = 0
  tally.atoms = {}
  tally.frames = []
  tally.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))

  // One hook per event: the mock clock's own `clock.every` and `clock.now`
  // answers are taken aside and called from counting hooks of the test's, so
  // `every` is counted once per period per live timer.
  const answers: Record<string, any> = {}
  const aside = ((event: string, ...rest: any[]) => {
    if (event === 'clock.every' || event === 'clock.now') {
      answers[event] = rest[rest.length - 1]

      return undefined
    }

    return on(event, ...rest)
  }) as typeof on
  const clock = mock.clock(aside, { now: START })
  on('clock.every', (hooked: any, e: any, next: any) => {
    tally.everyPeriods += 1

    return answers['clock.every'](hooked, e, next)
  })
  on('clock.now', (hooked: any, e: any, next: any) => {
    tally.clockNows += 1

    return answers['clock.now'](hooked, e, next)
  })
  mock.env(
    on,
    visits.on
      ? { HOME: '/home/jeb', JEB_VISITS: visits.draw, JEB_CREATIVITY: 'off', JEB_NEWS: 'null' }
      : { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_CREATIVITY: 'off', JEB_NEWS: 'null' },
  )
  on('fs.read', (_: any, e: any) => {
    tally.fsReads += 1
    const { path } = e as { path: string }

    return { value: path.endsWith('/Assertions.json') ? ASSERTIONS : MODES }
  })
  on('store.get', (_: any, e: any) => {
    tally.storeGets += 1

    return { value: copy(tally.db.get(e.key)) }
  })
  on('store.set', (_: any, e: any) => {
    tally.storeSets += 1
    tally.db.set(e.key, copy(e.value))
    if (isLive(String(e.key))) {
      tally.liveSets += 1
      tally.liveAt.push(clock.now())
      tally.liveMax = Math.max(tally.liveMax, JSON.stringify(e.value).length)
    }

    return { value: undefined }
  })
  on('state.set', (_: any, e: any, next: any) => {
    tally.stateWrites += 1
    if (e.key === 'say') {
      tally.sayWrites += 1
    }
    if (e.key === 'farm') {
      tally.farmWrites += 1
    }
    if (e.key === 'view') {
      tally.viewWrites += 1
    }
    if (e.key === 'anim') {
      tally.animWrites += 1
      tally.frames.push({ at: clock.now(), anim: e.value })
      // A write with nothing going on but the slow idle frame.
      const a = e.value
      if (!a.event && !a.truck && a.dogRun === 0 && !a.wag && !a.puff && !a.wink && !a.sip) {
        tally.quietWrites += 1
      }
    }
    tally.atoms[e.key] = JSON.stringify(e.value)

    return next(e)
  })
  on('ui.toast', () => ({ value: undefined }))
  on('audio.play', () => ({ value: undefined }))
  on('audio.speak', () => ({ value: { synthesizer: 'test' } }))
  on('command.register', () => ({ value: { command: 'jeb' } }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('tool.call', () => ({ result: {} }))
  on('prompt.submit', (_: any, e: any) => e)
  on('turn.start', (_: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  // The model beneath: it streams the plan's chunks and settles with its result.
  on('turn.step', async function* () {
    for (let i = 0; i < plan.chunks.length; i += 1) {
      yield plan.chunks[i]
      await plan.between?.(i)
    }

    return plan.result
  })
  // The session and its agents, as the engine would answer them.
  tally.agentIds = 0
  on('session.id', () => ({ value: 'me' }))
  on('session.root', () => ({ value: '/w/api' }))
  on('session.repo', () => ({ value: { root: '/w/api', remote: null, internal: false, name: null } }))
  on('agent.spawn', () => ({ model: 'm', agentId: `a${(tally.agentIds += 1)}` }))
  on('agent.list', () => ({ value: [] }))
  on('classic.SubagentStop', () => ({}))
  on('classic.TeammateIdle', () => ({}))
  on('session.end', (_: any, e: any) => ({ sessionId: e.sessionId }))

  return clock
}

// `advance` takes at most 10 000 waits at a time.
const elapse = async (clock: MockClock, ms: number) => {
  for (let left = ms; left > 0; left -= 20 * MINUTE) {
    await clock.advance(Math.min(left, 20 * MINUTE))
  }
}

// The same, a minute at a time, with the other session still beating.
const elapseWithCamp = async (clock: MockClock, ms: number) => {
  for (let left = ms; left > 0; left -= MINUTE) {
    await clock.advance(Math.min(left, MINUTE))
    await otherCamp(clock)
  }
}

const start = ($: any) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

const isLive = (key: string) => key.startsWith('live:')

// `store` is the farm and the heartbeats; the session's live record has a budget
// of its own (`live`, see E18).
const sizes = () => ({
  session: stateSize(),
  atoms: Object.values(tally.atoms).reduce((sum, text) => sum + text.length, 0),
  store: [...tally.db].filter(([key]) => !isLive(key)).reduce((sum: number, [, value]) => sum + JSON.stringify(value).length, 0),
  live: [...tally.db].filter(([key]) => isLive(key)).reduce((sum: number, [, value]) => sum + JSON.stringify(value).length, 0),
})

const spawn = (
  $: any,
  over: object = {},
): Promise<{ agentId: string }> =>
  $.agent.spawn({
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

const agentEnd = (
  $: any,
  agentId: string,
) =>
  $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: `t-${agentId}`, reason: 'answer', agentId })

// Another session of the same machine, alive as of now.
const otherCamp = (clock: MockClock) => {
  const now = clock.now()
  tally.db.set('sessions', {
    ...(tally.db.get('sessions') as object),
    other: { name: 'web', lastSeen: now },
  })
}

// A busy stretch: a turn, a tool call every twenty seconds, then the turn's end.
// Agents come and go through it: a foreground hand, a background one, a
// teammate and a workflow of three.
let peak = 0

// The soak's Bash commands: plain and classified (tests, lint, Compose, deny rules, a triage fetch).
const COMMANDS = [
  'ls',
  'php artisan test --filter=Foo',
  'docker compose exec app vendor/bin/pint --test',
  'docker compose up -d',
  'php artisan test | tail',
  'docker compose exec hot npm run lint',
  'git reset --hard',
]

const busy = async ($: any, clock: MockClock, minutes: number, turn: number) => {
  await $.prompt.submit({ text: 'work on it' })
  await $.turn.start({ text: 'work on it', turnId: `t${turn}` })
  const fg = await spawn($, { subagentType: 'Explore' })
  await spawn($, { background: true })
  await spawn($, { background: true, isTeammate: true, name: `mate${turn}` })
  const flow = [] as { agentId: string }[]
  for (let i = 1; i <= 3; i += 1) {
    flow.push(await spawn($, { workflow: { runId: 'wf', agentIndex: i } }))
  }
  const tools = ['Read', 'Edit', 'Bash', 'Grep', 'WebFetch']
  for (let i = 0; i < minutes * 3; i += 1) {
    await $.tool.call({
      tool: tools[i % tools.length],
      command: COMMANDS[i % COMMANDS.length],
      file_path: '/a',
      url: 'https://x.test',
    })
    await clock.advance(20_000)
    await otherCamp(clock)
    peak = Math.max(peak, sizes().atoms)
  }
  await agentEnd($, fg.agentId)
  for (const hand of flow) {
    await agentEnd($, hand.agentId)
  }
  await $.turn.complete({
    answer: '',
    durationMs: minutes * MINUTE,
    isAborted: false,
    turnId: `t${turn}`,
    reason: 'answer',
    usage: usage(2_000, 60_000),
  })
  await clock.settle()
}

test('E1 soak: eight idle hours and two busy ones leave every size flat and one timer running', { timeoutMs: 600_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)

  // Ten hours, each 48 idle minutes and a 12 minute turn of work (a tool call
  // every twenty seconds): eight hours idle and two busy in all.
  const at: Record<number, ReturnType<typeof sizes>> = {}
  for (let hour = 1; hour <= 10; hour += 1) {
    await busy($, clock, 12, hour)
    await elapseWithCamp(clock, 48 * MINUTE)
    at[hour] = sizes()
  }
  const [oneHour, eightHours, tenHours] = [at[1], at[8], at[10]] as ReturnType<typeof sizes>[]
  console.log(
    `soak sizes (bytes) 1h ${JSON.stringify(oneHour)} 8h ${JSON.stringify(eightHours)} 10h ${JSON.stringify(tenHours)}`,
  )

  // Sizes stop growing after warm-up: a few digits of counters at most.
  const slack = 400
  expect(eightHours.session).toBeLessThanOrEqual(oneHour.session + slack)
  expect(eightHours.atoms).toBeLessThanOrEqual(oneHour.atoms + slack)
  expect(eightHours.store).toBeLessThanOrEqual(oneHour.store + slack)
  expect(tenHours.session).toBeLessThanOrEqual(oneHour.session + slack)
  expect(tenHours.atoms).toBeLessThanOrEqual(oneHour.atoms + slack)
  expect(tenHours.store).toBeLessThanOrEqual(oneHour.store + slack)
  expect(tenHours.session).toBeLessThan(6_000)
  expect(tenHours.atoms).toBeLessThan(3_000)
  expect(tenHours.store).toBeLessThan(2_000)
  // Agents never pile up: eight at most, whatever a turn spawns.
  console.log(`soak peak atom size with agents out (stateSize reads only the test's own copy of the module, so the atoms and the store are what is measured): ${peak}`)
  expect(peak).toBeLessThan(3_000)

  // Exactly one live ticker: one dispatch per 500 ms period.
  const before = tally.everyPeriods
  await clock.advance(10 * TICK)
  expect(tally.everyPeriods - before).toBe(10)
})

test('E9 soak with crafting: a stocked farm crafts, builds, ages and buys for ten hours and every size stays flat', { timeoutMs: 600_000 }, async ($, on) => {
  // Plenty of everything, cash for copper and sugar, lightning waiting in the barn:
  // every kind of craft happens, and the aging barrels fill to their fifty.
  const base = freshFarm()
  const farm = {
    ...base,
    materials: { lumber: 400, stone: 120, straw: 60, iron: 60, sugar: 6, copper: 4 },
    barn: { bales: 6, corn: 4, apples: 60, sticks: 20 },
    shelf: { lightning: 200, appleCinnamon: 3 },
    ledger: { ...base.ledger, total: 900, cash: 900 },
  }
  const clock = rig(on, { farm })
  await start($)
  const at: Record<number, ReturnType<typeof sizes>> = {}
  for (let hour = 1; hour <= 10; hour += 1) {
    await busy($, clock, 12, hour)
    await elapseWithCamp(clock, 48 * MINUTE)
    at[hour] = sizes()
  }
  const [twoHours, tenHours] = [at[2], at[10]] as ReturnType<typeof sizes>[]
  const stored = tally.db.get('farm') as any
  console.log(
    `crafting soak sizes (bytes) 2h ${JSON.stringify(twoHours)} 10h ${JSON.stringify(tenHours)}; built ${stored.built.length}, keepsakes ${stored.keepsakes.length}, aging ${stored.goods.aged.length}`,
  )
  // Crafting really happened.
  expect(stored.built.length).toBeGreaterThan(0)
  expect(stored.keepsakes.length).toBeGreaterThan(0)
  expect(stored.goods.aged.length).toBeGreaterThan(0)
  // The jars in the barrels stop at fifty and no stock goes below zero.
  expect(stored.goods.aged.length).toBeLessThanOrEqual(50)
  for (const n of [...Object.values(stored.materials), ...Object.values(stored.components), stored.ledger.cash]) {
    expect(n as number).toBeGreaterThanOrEqual(0)
  }
  // Sizes stop growing once the barrels are full: a few digits of counters at most.
  const slack = 400
  expect(tenHours.session).toBeLessThanOrEqual(twoHours.session + slack)
  expect(tenHours.atoms).toBeLessThanOrEqual(twoHours.atoms + slack)
  expect(tenHours.store).toBeLessThanOrEqual(twoHours.store + slack)
  expect(tenHours.session).toBeLessThan(6_000)
  // The farm atom and the view now carry the little things (unlocks and the day's plan): a few hundred bytes more.
  expect(tenHours.atoms).toBeLessThan(5_200)
  expect(tenHours.store).toBeLessThan(3_500)
  // Still exactly one ticker.
  const before = tally.everyPeriods
  await clock.advance(10 * TICK)
  expect(tally.everyPeriods - before).toBe(10)
})

test('E2 an idle band costs at most 20 frame writes and 2 file reads a minute, and one heartbeat write a minute', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await elapse(clock, 2 * MINUTE)

  const idleStore = tally.storeSets
  const states = tally.stateWrites
  const anims = tally.animWrites
  let quietMax = 0
  let readsMax = 0
  for (let minute = 0; minute < 10; minute += 1) {
    const quiet = tally.quietWrites
    const reads = tally.fsReads
    await clock.advance(MINUTE)
    quietMax = Math.max(quietMax, tally.quietWrites - quiet)
    readsMax = Math.max(readsMax, tally.fsReads - reads)
  }
  console.log(`idle: ${(tally.animWrites - anims) / 10} anim writes/min (quiet max ${quietMax}), ${(tally.stateWrites - states - (tally.animWrites - anims)) / 10} other state writes/min, fs.read max ${readsMax}/min`)
  expect(quietMax).toBeLessThanOrEqual(20)
  expect(readsMax).toBeLessThanOrEqual(2)
  // Apart from frames: Jeb's own remarks and the happenings' lines, a few a minute.
  expect(tally.stateWrites - states - (tally.animWrites - anims)).toBeLessThanOrEqual(60)
  // The sessions heartbeat is the only store write: one a minute.
  expect(tally.storeSets - idleStore).toBeLessThanOrEqual(10)
  expect(tally.storeSets - idleStore).toBeGreaterThanOrEqual(9)
})

test('E3 a second session.start replaces the ticker instead of adding one', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await start($)
  await start($)

  const before = tally.everyPeriods
  await clock.advance(10 * TICK)
  expect(tally.everyPeriods - before).toBe(10)
})

test('E4 a minute with a happening in it costs at most 130 frame writes', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  // The first happening is rolled at three idle minutes and lasts 30 to 60 seconds,
  // standing still for some of it (those stretches draw on the 3 s cadence).
  // The scene goes still after two idle minutes and no happening rolls then, so a
  // meta prompt (a wake and nothing else) comes at 100 s to keep the farm awake.
  await clock.advance(100_000)
  await $.prompt.submit({ text: '', isMeta: true })
  await clock.advance(70_000)
  const before = tally.animWrites
  await clock.advance(MINUTE)
  const writes = tally.animWrites - before
  console.log(`happening minute: ${writes} anim writes`)
  // At least the quiet cadence (one frame every 3 s), at most the moving budget.
  expect(writes).toBeGreaterThanOrEqual(20)
  expect(writes).toBeLessThanOrEqual(130)
})

test('E5 a quiet tick makes no calls to the host at all', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  // Tick 241 to 243: not a slow tick (3 s), not the 30 s Focus check.
  await clock.advance(120_000)
  await clock.settle()
  const calls = () =>
    tally.stateWrites + tally.storeSets + tally.storeGets + tally.fsReads + tally.clockNows
  const counts: number[] = []
  for (let i = 0; i < 3; i += 1) {
    const before = calls()
    await clock.advance(TICK)
    counts.push(calls() - before)
  }
  console.log(`host calls per quiet tick: ${counts.join(', ')}`)
  expect(counts).toEqual([0, 0, 0])
})

test('E6 with agents out and another session alive a quiet tick still makes no calls, and a quiet minute at most 20 frames', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await spawn($, { background: true })
  await spawn($, { isTeammate: true, background: true, name: 'mate' })
  await spawn($, { subagentType: 'Plan' })
  await clock.advance(5 * MINUTE)
  await otherCamp(clock)
  await clock.advance(MINUTE)
  await clock.settle()

  // The list names nobody, so after a minute's grace the hands are let go; the
  // background one has walked home by now. Count what a quiet tick costs.
  await clock.advance(5 * MINUTE)
  await clock.settle()
  const calls = () =>
    tally.stateWrites + tally.storeSets + tally.storeGets + tally.fsReads + tally.clockNows
  const counts: number[] = []
  for (let i = 0; i < 3; i += 1) {
    const before = calls()
    await clock.advance(TICK)
    counts.push(calls() - before)
  }
  console.log(`host calls per quiet tick with agents and a second session: ${counts.join(', ')}`)
  expect(counts).toEqual([0, 0, 0])

  const quiet = tally.quietWrites
  await clock.advance(MINUTE)
  expect(tally.quietWrites - quiet).toBeLessThanOrEqual(20)
})

// A response of `count` chunks: thinking, then text, then a tool call, over and over.
const response = (count: number) =>
  Array.from({ length: count }, (_, i) => {
    switch (i % 4) {
      case 0:
        return { kind: 'thinking', index: 0, text: `t${i}` }
      case 1:
        return { kind: 'text', index: 1, text: `w${i}` }
      case 2:
        return { kind: 'input', index: 2, json: '{"a":1}' }
      default:
        return { kind: 'text', index: 1, text: `w${i}` }
    }
  })

const drain = async ($: any, input: object) => {
  const stream = $.turn.step(input)
  let count = 0
  let step = await stream.next()
  while (!step.done) {
    count += 1
    step = await stream.next()
  }

  return count
}

const stepIn = (extra: object = {}) => ({ turnId: 't', index: 0, model: 'm', messageCount: 1, ...extra })

test('E7 streaming 10k chunks costs under twice what the same chain costs with Jeb not watching', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await $.turn.start({ text: 'go', turnId: 't' })
  await clock.settle()
  plan.between = undefined
  plan.chunks = response(10_000)

  const time = async (run: () => Promise<number>) => {
    const t0 = performance.now()
    const count = await run()

    return { count, ms: performance.now() - t0 }
  }
  // Nothing but the loop reading the same chunks from a bare generator.
  const bare = async function* () {
    for (const chunk of plan.chunks) {
      yield chunk
    }
  }
  const bareRun = await time(async () => {
    let count = 0
    for await (const chunk of bare()) {
      void chunk
      count += 1
    }

    return count
  })
  // The baseline is the chain itself: a subagent's step goes through Jeb's hook
  // but is not watched. The test cannot take Jeb off the chain, so this is the
  // chain's own cost with the hook's watching left out.
  await drain($, stepIn({ agentId: 'a1' }))
  await drain($, stepIn())
  const base: number[] = []
  const hooked: number[] = []
  for (let round = 0; round < 3; round += 1) {
    base.push((await time(() => drain($, stepIn({ agentId: 'a1' })))).ms)
    hooked.push((await time(() => drain($, stepIn()))).ms)
  }
  const baseline = Math.min(...base)
  const withHook = Math.min(...hooked)
  console.log(
    `10k chunks: bare generator ${bareRun.ms.toFixed(1)} ms; chain, hook not watching (baseline) ${baseline.toFixed(1)} ms; chain, hook watching ${withHook.toFixed(1)} ms (x${(withHook / baseline).toFixed(2)})`,
  )
  expect(withHook).toBeLessThan(2 * baseline)
})

test('E7 watching 10k chunks of one activity makes no host calls of its own', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await $.turn.start({ text: 'go', turnId: 't' })
  await clock.settle()
  plan.between = undefined
  plan.chunks = Array.from({ length: 10_000 }, (_, i) => ({ kind: 'text', index: 0, text: `w${i}` }))
  const calls = () => tally.stateWrites + tally.storeSets + tally.storeGets + tally.fsReads + tally.clockNows
  const before = calls()
  await drain($, stepIn())
  await clock.settle()
  const spent = calls() - before
  console.log(`10k text chunks: ${spent} host calls in all (the one change of activity: a bubble and a pose)`)
  // One transition: the bubble and the frame, nothing per chunk.
  expect(spent).toBeLessThanOrEqual(2)
})

test('E7 five seconds of streaming that changes activity every 20 ms writes at most 4 frames a second', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await $.turn.start({ text: 'go', turnId: 't' })
  await clock.advance(5_000)
  const kinds = ['thinking', 'text', 'tool'] as const
  plan.chunks = Array.from({ length: 250 }, (_, i) => {
    const kind = kinds[i % 3]

    return kind === 'tool'
      ? { kind, index: i, id: `tu${i}`, name: ['Read', 'Edit', 'Bash', 'Grep'][i % 4] }
      : { kind, index: i, text: 'x' }
  })
  const perSecond: { anim: number; say: number }[] = []
  let anim = tally.animWrites
  let say = tally.sayWrites
  plan.between = async at => {
    await clock.advance(20)
    if ((at + 1) % 50 === 0) {
      perSecond.push({ anim: tally.animWrites - anim, say: tally.sayWrites - say })
      anim = tally.animWrites
      say = tally.sayWrites
    }
  }
  await drain($, stepIn())
  plan.between = undefined
  console.log(
    `streaming, an activity change every 20 ms: frame writes per second ${perSecond.map(second => second.anim).join(', ')}; bubble writes per second ${perSecond.map(second => second.say).join(', ')}`,
  )
  expect(perSecond.length).toBe(5)
  for (const second of perSecond) {
    expect(second.anim).toBeLessThanOrEqual(4)
    expect(second.say).toBeLessThanOrEqual(4)
  }
})

test('E8 classifying a command is linear in its length', () => {
  const long = `docker compose exec app php artisan test --filter=Foo && ${'echo "x y" | cat; '.repeat(12_000)}`
  const t0 = performance.now()
  const segments = classify(long)
  const ms = performance.now() - t0
  console.log(`classify of ${long.length} characters: ${segments.length} segments in ${ms.toFixed(1)} ms`)
  expect(segments[0]?.kind).toBe('test')
  expect(ms).toBeLessThan(500)
})

test('E10 soak with session ends: 400 sessions are stitched and the quilt, the journal and every size stay bounded', { timeoutMs: 600_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  const at: Record<number, ReturnType<typeof sizes>> = {}
  for (let i = 1; i <= 400; i += 1) {
    await $.tool.call({ tool: i % 5 === 0 ? 'Bash' : 'Read', ...(i % 5 === 0 ? { command: 'git push' } : { file_path: '/a' }) })
    await clock.advance(1_000)
    await $.session.end({ reason: i % 2 === 0 ? 'clear' : 'prompt_input_exit', sessionId: `s${i}`, resume: { id: `s${i}` } })
    await clock.advance(1_000)
    if (i % 2 === 1) {
      // A new process: the session starts again.
      await start($)
    }
    at[i] = sizes()
  }
  const stored = tally.db.get('farm') as any
  expect(stored.quilt.length).toBe(200)
  expect(stored.journal.length).toBe(60)
  expect(stored.stitched.length).toBe(64)
  expect(stored.sessionsWorked).toBe(400)
  expect(stored.sessionsShipped).toBe(80)
  const [early, late] = [at[250], at[400]] as ReturnType<typeof sizes>[]
  console.log(`session-end soak sizes (bytes) 250 ${JSON.stringify(early)} 400 ${JSON.stringify(late)}`)
  const slack = 400
  expect(late.session).toBeLessThanOrEqual(early.session + slack)
  expect(late.atoms).toBeLessThanOrEqual(early.atoms + slack)
  expect(late.store).toBeLessThanOrEqual(early.store + slack)
  expect(late.store).toBeLessThan(30_000)
  // Still exactly one ticker.
  const before = tally.everyPeriods
  await clock.advance(10 * TICK)
  expect(tally.everyPeriods - before).toBe(10)
})

// Still life: after two minutes with no activity the scene freezes on its
// current frame, and the first activity wakes it.
const STILL_AT = 2 * MINUTE

const idleAct = () => JSON.parse(tally.atoms.anim ?? '{}').idleAct as string

// A session left alone until it has gone still, with the counts taken at that point.
const stillRig = async ($: any, on: any, minutes = 3) => {
  const clock = rig(on)
  on('session.measure', (_: any, e: any) => ({ changed: e.changed }))
  await start($)
  await elapse(clock, minutes * MINUTE)
  await clock.settle()

  return clock
}

const hostCalls = () =>
  tally.stateWrites + tally.storeSets + tally.storeGets + tally.fsReads + tally.clockNows

test('S1 ten idle minutes after the two-minute mark write no frames and no lines, and a still tick makes no calls', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await elapse(clock, STILL_AT + 1_000)
  const beforeFrames = tally.animWrites
  const beforeSays = tally.sayWrites
  await elapse(clock, 10 * MINUTE - 1_000)
  // The clock stands at twelve minutes, a 30 s round: the next three ticks are plain ones.
  await clock.settle()
  console.log(`still: ${tally.animWrites - beforeFrames} anim writes in the ten minutes after the two-minute mark`)
  expect(tally.animWrites - beforeFrames).toBe(0)
  expect(tally.sayWrites - beforeSays).toBe(0)
  expect(tally.quietWrites).toBeGreaterThan(0)
  const counts: number[] = []
  for (let i = 0; i < 3; i += 1) {
    const before = hostCalls()
    await clock.advance(TICK)
    counts.push(hostCalls() - before)
  }
  expect(counts).toEqual([0, 0, 0])
  // Still beating for the other sessions: the heartbeat goes on.
  expect(tally.storeSets).toBeGreaterThanOrEqual(10)
})

// Each of these is activity: one write at most, and the frames run again.
const wakeSources: [string, ($: any) => Promise<unknown>][] = [
  ['a turn running', async $ => {
    await $.prompt.submit({ text: 'work on it' })
    await $.turn.start({ text: 'work on it', turnId: 'w1' })
  }],
  ['a main tool call', $ => $.tool.call({ tool: 'Read', file_path: '/a' })],
  ['a subagent tool call', $ => $.tool.call({ tool: 'Read', file_path: '/a', agentId: 'sub1' })],
  ['a turn.step chunk', async $ => {
    plan.chunks = [{ kind: 'thinking', index: 0, text: 't' }]
    await drain($, stepIn())
  }],
  ['a bubble line', $ =>
    $.session.measure({ context: { window: 200_000 }, rateLimits: [{ kind: 'five_hour', percentUsed: 85 }], changed: ['rateLimits'] })],
  ['a dog run', $ => $.tool.call({ tool: 'Agent', description: 'd' })],
  ['an fx effect', $ => $.prompt.submit({ text: 'good boy, Blue, ship it' })],
]

for (const [name, trigger] of wakeSources) {
  test(`S2 ${name} wakes the still scene with at most one frame write`, { timeoutMs: 120_000 }, async ($, on) => {
    if (name === 'a turn.step chunk') {
      // The mock model beneath answers the step.
      plan.result = { turnId: 't', index: 0, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
    }
    const clock = await stillRig($, on)
    const base = tally.animWrites
    // Still: three more seconds change nothing.
    await clock.advance(3_000)
    expect(tally.animWrites).toBe(base)

    await trigger($)
    await clock.settle()
    expect(tally.animWrites - base).toBeLessThanOrEqual(1)
    // And the scene moves again.
    const woke = tally.animWrites
    await clock.advance(6_000)
    expect(tally.animWrites).toBeGreaterThan(woke)
  })
}

test('S3 a session that is busy never goes still', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  await $.prompt.submit({ text: 'work on it' })
  await $.turn.start({ text: 'work on it', turnId: 't1' })
  await elapse(clock, 5 * MINUTE)
  const before = tally.animWrites
  await clock.advance(MINUTE)
  // One a slow tick (3 s) at least most of the time.
  expect(tally.animWrites - before).toBeGreaterThanOrEqual(10)
})

test('S3 hired hands working never let the scene go still', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  // A workflow hand is never in the engine's list: it stays for half an hour without a step.
  await spawn($, { workflow: { runId: 'wf', agentIndex: 1 } })
  await elapse(clock, 5 * MINUTE)
  const before = tally.animWrites
  await clock.advance(MINUTE)
  expect(tally.animWrites - before).toBeGreaterThanOrEqual(10)
})

test('S3 a truck out keeps the scene awake, and the scene still follows it home', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  // 1:58 of calm, then a push sends the truck out as the two minutes would end.
  await elapse(clock, 118_000)
  await $.tool.call({ tool: 'Bash', command: 'git push' })
  const before = tally.animWrites
  await clock.advance(10_000)
  // The truck runs a frame a tick (two a second).
  expect(tally.animWrites - before).toBeGreaterThanOrEqual(10)
})

test('S4 the idle-act rotation and the idle line resume after a wake', { timeoutMs: 120_000 }, async ($, on) => {
  const clock = await stillRig($, on)
  const frozenAct = idleAct()
  const says = tally.sayWrites
  await clock.advance(5 * MINUTE)
  expect(idleAct()).toBe(frozenAct)
  expect(tally.sayWrites).toBe(says)

  await $.prompt.submit({ text: '', isMeta: true })
  await clock.settle()
  // The rotation changes the act every 12 s, the idle line comes every minute.
  const acts = new Set<string>()
  const afterWake = tally.sayWrites
  for (let i = 0; i < 70; i += 1) {
    await clock.advance(1_000)
    acts.add(idleAct())
  }
  expect(acts.size).toBeGreaterThan(1)
  expect(tally.sayWrites).toBeGreaterThan(afterWake)
})

test('E17 an idle hour of ambient life: 6 to 15 visits, frames only while something moves or on the 3 s cadence while it stands, and nothing once still', { timeoutMs: 600_000 }, async ($, on) => {
  // Visitors on, drawn by the real dice (JEB_VISITS set but not a number).
  visits.on = true
  visits.draw = ''
  const base = freshFarm()
  const farm = {
    ...base,
    shelf: { lightning: 30, appleCinnamon: 40 },
    barn: { bales: 8, corn: 20, apples: 90, sticks: 0 },
    upgrades: ['mailbox'],
    // The day's little things are already unlocked: one turning up wakes the scene, and this test counts ambient life only.
    unlockDay: { d: '2026-06-10', n: 3, done: 3, next: START + 8 * HOUR, since: '2026-01-01', coffee: '' },
  }
  const clock = rig(on, { farm })
  try {
    await start($)
    const before = tally.animWrites
    await elapse(clock, HOUR)
    const writes = tally.animWrites - before

    let visitsSeen = 0
    let errands = 0
    let events = 0
    let moving = 0
    let standing = 0
    let lastActive = START
    let stray = 0
    let prev: any = null
    for (const { at, anim } of tally.frames) {
      const hasVisit = anim.visit !== null && anim.visit !== undefined
      if (hasVisit && !prev?.visit) {
        visitsSeen += 1
      }
      if (anim.dogRun > 0 && !(prev?.dogRun > 0)) {
        errands += 1
      }
      if (anim.event && !prev?.event) {
        events += 1
      }
      const isOtherActive = anim.dogRun > 0 || anim.event || anim.truck || anim.wag || anim.puff || anim.wink || anim.sip
      // Jeb's own change (a new idle act, the bubble opening or dimming) draws a frame of its own.
      const isJebChange =
        prev !== null && (anim.idleAct !== prev.idleAct || anim.isTalking !== prev.isTalking || anim.isDim !== prev.isDim)
      if (hasVisit) {
        // A frame something else asked for while the visitor stood is that thing's, not the stand's cadence;
        // every frame still counts toward the hour's total below.
        if (anim.visit.phase !== 'deal') {
          moving += 1
        } else if (!isOtherActive && !isJebChange) {
          standing += 1
        }
      }
      const isActive = hasVisit || isOtherActive
      if (isActive) {
        lastActive = at
      } else if (at - lastActive > 130_000) {
        // Still-life: no frame at all this long after the last of the activity.
        stray += 1
      }
      prev = anim
    }
    console.log(
      `E17: ${visitsSeen} visits, ${errands} errands, ${events} happenings in an idle hour: ${writes} anim writes ` +
        `(${moving} while a visitor moved, ${standing} while one stood, ${writes - moving - standing} others)`,
    )
    expect(visitsSeen).toBeGreaterThanOrEqual(6)
    expect(visitsSeen).toBeLessThanOrEqual(15)
    // A visitor moving writes two frames a second at most (the tractor one), standing one every 3 s.
    expect(writes).toBeLessThanOrEqual(visitsSeen * 70 + errands * 30 + events * 125 + 60)
    expect(standing).toBeLessThanOrEqual(visitsSeen * 22)
    expect(stray).toBe(0)
  } finally {
    visits.on = false
  }
})

test('E18 the live record through three working hours: written only when it changed, once a tick at most, one record kept, never over 400 bytes', { timeoutMs: 600_000 }, async ($, on) => {
  const clock = rig(on)
  await start($)
  const perHour: number[] = []
  const stored: number[] = []
  for (let hour = 1; hour <= 3; hour += 1) {
    const from = tally.liveSets
    await busy($, clock, 12, hour)
    await elapseWithCamp(clock, 48 * MINUTE)
    perHour.push(tally.liveSets - from)
    stored.push(sizes().live)
  }
  const perSecond = new Map<number, number>()
  for (const at of tally.liveAt) {
    perSecond.set(Math.floor(at / 1_000), (perSecond.get(Math.floor(at / 1_000)) ?? 0) + 1)
  }
  const peak = Math.max(...perSecond.values())
  console.log(
    `live record: ${tally.liveSets} writes in three hours (${perHour.join(', ')} an hour), peak ${peak} a second, ` +
      `largest ${tally.liveMax} bytes, ${stored.join('/')} bytes stored at each hour; ${tally.animWrites} frames, ${tally.sayWrites} lines`,
  )
  // One write a 500 ms tick at most: two in a second, under the four allowed.
  expect(peak).toBeLessThanOrEqual(2)
  // Written only when something in it changed, so never more often than the band redraws or Jeb speaks.
  expect(tally.liveSets).toBeLessThanOrEqual(tally.animWrites + tally.sayWrites)
  // One record, this session's own, small and flat.
  expect([...tally.db.keys()].filter(isLive).length).toBe(1)
  expect(tally.liveMax).toBeLessThanOrEqual(400)
  for (const bytes of stored) {
    expect(bytes).toBeLessThanOrEqual(400)
  }
  // (A still tick writes nothing at all: E5, E6 and S1 count the store among the host calls.)
})
