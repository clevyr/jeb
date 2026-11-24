import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import * as areasMod from '../hooks/areas'
import {
  AREA_DAILY_CAP,
  AREA_SYLLABLES,
  areaKeyOf,
  areaRetryNote,
  areaSystemPrompt,
  identityOf,
  MOODS,
  MOTIFS,
  offlineArea,
  PALETTES,
  SUFFIXES,
  TERRAINS,
  WEATHERS,
  WORK_KINDS,
} from '../hooks/areas'
import * as dropsMod from '../hooks/drops'
import { freshCreative } from '../hooks/drops'
import * as offlineMod from '../hooks/offline'
import { freshFarm } from '../hooks/homestead'
import { moonNight } from '../hooks/almanac'
import * as anonymizeMod from '../hooks/anonymize'
import { hashHex, isPlace, lineFor, liveTokenOf, neighborOf, placeFor, placeSeen, sessionKeyOf } from '../hooks/anonymize'
import * as liveMod from '../hooks/live'
import { LIVE_FIELDS } from '../hooks/live'
import { mcpKindOf } from '../hooks/mcp'
import * as registerModule from '../hooks/register'
import { register } from '../hooks/register'
import * as signalsMod from '../hooks/signals'

// Guard, part two: encoded markers, the overrides and heartbeats, and the shape of every string Jeb stores.
// The harness below is guard.test.tsx's own (test files cannot import each other), without its probe.

import * as surpriseMod from '../hooks/surprise'
import { DROP_SPRITE_NAMES, ZONES } from '../hooks/surprise'

// The guard: the two promises Jeb makes about the person's session, pinned.
//
// GD1, observe-only: every hook Jeb has on an event that carries the session
// hands the event on exactly as it came and gives back exactly what came up
// from beneath; Jeb has no hook at all where the prompt, the model's context,
// the settings or the transcript are made.
//
// GD2, nothing of the session reaches Haiku: a day of work full of marker
// words, then the day's creative drops, and not one marker in anything the
// model is sent.
//
// GD3, nothing of the session is stored or shown: the same work, on a farm and
// heartbeats a Jeb before the anonymizer left full of markers, and not one marker
// in anything Jeb stores (the farm, the heartbeats, every live record) or says;
// the live records hold only their own fields, and the anonymizer is one way.
//
// The areas (a project's remembered place in Jeb's world) are held to the same two
// promises: only an opaque key and words of fixed lists reach Haiku for them, only
// `signals.ts` calls the model, and nothing of the work is stored under `areas`.
//
// Everything beneath Jeb is the test's: the clock, the store, the model, the
// session's id, root and repo. A probe plugin sits above Jeb and reports the
// chain beneath it (`next.trace`) for every event it watches.

const MINUTE = 60_000
const HOUR = 60 * MINUTE
// June 2026: the 10th is a Wednesday.
const at = (d: number, h: number, m = 0) => new Date(2026, 5, d, h, m, 0).getTime()
const START = at(10, 8, 50)

const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

// ---- the markers: words only the session holds ----

const MARKERS = [
  'fizzlewick',
  'quandrix',
  'brambletoe',
  'metazxq',
  'zxqdeploy',
  'snorkelvane',
  'zxq-4242',
  'zxq-9191',
  'plumbuster',
  'grommetvale',
  'grommetsvc',
  'wobblequist',
  'blorptastic',
  'frobnicator',
  'kelpforge',
  'oldzebrine',
  'newzebrine',
  'snickerdoodlex',
  'marmaladix',
  'vorpalwhisk',
  'thinkozoid',
  'glimmerhaust',
  'acmezxq',
  'zxquser',
  'quillobrand',
  'zorbleflux',
  'pemberwick',
  'drizzlecrank',
  'tealwhistle',
  'ombrevale',
  'hobnailia',
  'zxqwidget',
  'zxqtheme',
  'zxq',
]

const CWD = '/home/zxquser/work/glimmerhaust/api'
const ROOT = '/home/zxquser/work/glimmerhaust'
const REPO = { root: ROOT, remote: 'git@github.com:acmezxq/glimmerhaust.git', internal: false, name: 'glimmerhaust-api' }
const SESSION_ID = 'sess-quillobrand-7f3a'

const usage = (output: number, input: number) => ({
  model: 'm',
  input_tokens: input,
  output_tokens: output,
  cache_read_input_tokens: 0,
  cache_creation_input_tokens: 0,
})

// ---- the session's events, each full of markers ----

const PROMPTS = {
  first: { text: 'Please refactor the fizzlewick billing module in blorptastic/app/Models/Frobnicator.php' },
  attached: {
    text: 'Why does quandrix fail on staging? See the log',
    attachments: [{ kind: 'file', path: '/home/zxquser/work/glimmerhaust/storage/logs/kelpforge.log' }],
  },
  midTurn: { text: 'Also check brambletoe while you are at it', turnId: 't-zxq-1' },
  triage: { text: '/triage ZXQ-4242 plumbuster checkout', command: { name: 'triage', args: 'ZXQ-4242 plumbuster checkout' } },
  command: { text: '/zxqdeploy snorkelvane --force', command: { name: 'zxqdeploy', args: 'snorkelvane --force' } },
  meta: { text: 'Caveat: metazxq hook output for quandrix', isMeta: true },
  thanks: { text: 'thanks, that fixed fizzlewick for good' },
} as const

const TOOL_CALLS = [
  { tool: 'Bash', tool_use_id: 'tu-zxq-1', command: 'docker compose exec grommetsvc php artisan test --filter=GrommetvaleTest' },
  { tool: 'Bash', tool_use_id: 'tu-zxq-2', command: 'git push origin feature/wobblequist' },
  { tool: 'Bash', tool_use_id: 'tu-zxq-3', command: 'vendor/bin/phpstan analyse blorptastic/app', run_in_background: false },
  { tool: 'Bash', tool_use_id: 'tu-zxq-4', command: 'npm run lint -- kelpforge/src', run_in_background: true },
  { tool: 'Read', tool_use_id: 'tu-zxq-5', file_path: '/home/zxquser/work/glimmerhaust/app/Models/Frobnicator.php' },
  {
    tool: 'Edit',
    tool_use_id: 'tu-zxq-6',
    file_path: '/srv/kelpforge/config/secrets.yml',
    old_string: 'token: oldzebrine',
    new_string: 'token: newzebrine',
  },
  { tool: 'Write', tool_use_id: 'tu-zxq-7', file_path: '/home/zxquser/blorptastic/notes.md', content: 'fizzlewick notes' },
  { tool: 'Grep', tool_use_id: 'tu-zxq-8', pattern: 'quandrix', path: '/home/zxquser/work/glimmerhaust' },
  { tool: 'mcp__claude_ai_Zorbleflux__getJiraIssue', tool_use_id: 'tu-zxq-9', issueIdOrKey: 'ZXQ-9191', cloudId: 'acmezxq' },
  { tool: 'Agent', tool_use_id: 'tu-zxq-10', description: 'Audit the pemberwick ledger', prompt: 'Look at ombrevale', subagent_type: 'drizzlecrank-reviewer' },
]

// What each call came back with: text that names the session's things.
const toolResult = (e: any, isError = false) => ({
  result: {
    stdout: `PASS snickerdoodlex ${String(e.tool)} ${String(e.command ?? e.file_path ?? '')}`,
    stderr: isError ? 'FAIL marmaladix' : '',
    file: { content: 'secret content marmaladix' },
  },
  // The kit leaves a false isError out of a result: only a true one is given.
  ...(isError ? { isError: true } : {}),
  context: ['vorpalwhisk context'],
})

const CHUNKS = [
  { kind: 'thinking', index: 0, text: 'thinkozoid: the fizzlewick module' },
  { kind: 'text', index: 1, text: 'Here is the plan for vorpalwhisk in ' },
  { kind: 'text', index: 1, text: '/home/zxquser/work/glimmerhaust/app' },
  { kind: 'tool', index: 2, id: 'tu-zxq-20', name: 'mcp__claude_ai_Zorbleflux__getJiraIssue' },
  { kind: 'input', index: 2, json: '{"issueIdOrKey":"ZXQ-9191",' },
  { kind: 'input', index: 2, json: '"cloudId":"acmezxq"}' },
  { kind: 'tool', index: 3, id: 'tu-zxq-21', name: 'Bash' },
  { kind: 'input', index: 3, json: '{"command":"git push origin feature/wobblequist"}' },
  { kind: 'stop', stopReason: 'tool_use', usage: null },
]

const stepInput = (agentId?: string) => ({ turnId: 't-zxq-1', index: 0, model: 'm', messageCount: 3, ...(agentId ? { agentId } : {}) })

const stepResult = () => ({
  turnId: 't-zxq-1',
  index: 0,
  answer: 'Here is the plan for vorpalwhisk',
  toolUses: [{ name: 'Bash', input: { command: 'git push origin feature/wobblequist' } }],
  stopReason: 'tool_use',
  usage: usage(320, 4100),
})

const spawnInput = (over: object = {}) => ({
  tool_use_id: 'tu-zxq-10',
  prompt: 'Look at ombrevale and the pemberwick ledger',
  description: 'Audit the pemberwick ledger',
  subagentType: 'drizzlecrank-reviewer',
  provider: { plugin: 'engine', tier: 'core' },
  parentModel: 'm',
  background: false,
  fork: false,
  name: 'pemberwick-auditor',
  ...over,
})

const completeInput = (over: object = {}) => ({
  answer: 'All done with hobnailia and fizzlewick',
  durationMs: 61_000,
  isAborted: false,
  turnId: 't-zxq-1',
  reason: 'answer',
  usage: usage(2400, 52_000),
  ...over,
})

const AGENTS = [
  { id: 'a-zxq-1', description: 'Sweep the ombrevale caches', type: 'drizzlecrank-reviewer', status: 'running', name: 'tealwhistle' },
]

type Link = { plugin: string; tier: string; outcome: string; received: unknown; returned: unknown }
type Probe = { event: string; component?: string; links: Link[] }

let clk: MockClock

const world = {
  db: new Map<string, unknown>(),
  probes: [] as Probe[],
  // What each event's bottom hook received, oldest first.
  got: [] as { event: string; e: any }[],
  // What each event's bottom hook answers, by event.
  answers: {} as Record<string, (e: any) => unknown>,
  model: [] as { model: string; system: string; prompt: string; at: number }[],
  // The props of every row the engine beneath drew, oldest first.
  drawn: [] as unknown[],
  reply: (n: number): unknown => answered(drop(n)),
  // Every store write Jeb made, and every line he said, oldest first.
  sets: [] as { key: string; value: unknown }[],
  said: [] as string[],
  // The repo the session answers with (a test of its own sets it; the default is REPO).
  repo: undefined as unknown,
}

const drop = (n: number) => ({
  kind: n % 2 === 0 ? 'saying' : 'happening',
  name: `porch-${n}`,
  lines: [`Mornin on the porch, number ${n}.`],
  summary: `Jeb sat on the porch, number ${n}`,
  sprites: n % 2 === 0 ? undefined : [{ sprite: 'hen', zone: 'yard', frames: 2 }],
})

const answered = (reply: unknown) => ({
  isAnswered: true,
  text: typeof reply === 'string' ? reply : JSON.stringify(reply),
  usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
})

// The engine's answer for each session event, unless a test sets its own: a
// value of its own, marked, so nothing of Jeb's could be mistaken for it.
const ANSWERS: Record<string, (e: any) => unknown> = {
  'prompt.submit': e => ({ text: `${String(e.text)} [engine]`, context: ['engine context quandrix'] }),
  'tool.call': e => toolResult(e, e.tool === 'Bash' && String(e.command).includes('artisan test')),
  'turn.start': e => ({ turnId: e.turnId }),
  'turn.complete': () => ({ text: 'engine text hobnailia', usage: usage(1, 2) }),
  'agent.spawn': () => ({ model: 'm', agentId: 'a-zxq-1' }),
  'config.set': e => ({ value: e.value }),
  'session.start': e => ({ cwd: e.cwd }),
  'session.end': e => ({ sessionId: e.sessionId }),
  'session.measure': e => ({ changed: e.changed }),
  'command.run': e => ({ text: `ran ${String(e.command)} ${String(e.args)}` }),
}

const rig = (on: any, entries: Record<string, unknown> = {}, now = START): MockClock => {
  world.db = new Map(Object.entries(entries).map(([key, value]) => [key, copy(value)]))
  world.probes = []
  world.got = []
  world.answers = { ...ANSWERS }
  world.model = []
  world.drawn = []
  world.reply = n => answered(drop(n))
  world.sets = []
  world.said = []
  world.repo = undefined
  const clock = mock.clock(on, { now })
  clk = clock
  mock.env(on, { HOME: '/home/zxquser', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_NEWS: 'null' })
  on('fs.read', (_: any, e: any) => {
    throw new Error(`ENOENT ${String(e.path)}`)
  })
  on('store.get', (_: any, e: any) => ({ value: copy(world.db.get(e.key)) }))
  on('store.set', (_: any, e: any) => {
    if (e.key === 'guard-probe') {
      world.probes.push(copy(e.value))
    } else {
      world.db.set(e.key, copy(e.value))
      world.sets.push({ key: String(e.key), value: copy(e.value) })
    }

    return { value: undefined }
  })
  // The bubble's every line, as Jeb writes it; the write goes on as it came.
  on('state.set', (_: any, e: any, next: any) => {
    if (e.key === 'say') {
      world.said.push(String((e.value as { line?: unknown } | undefined)?.line ?? ''))
    }

    return next(e)
  })
  on('store.delete', (_: any, e: any) => {
    world.db.delete(e.key)

    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...world.db.keys()] }))
  on('model.complete', (_: any, e: any) => {
    world.model.push({ model: String(e.model), system: String(e.system ?? ''), prompt: String(e.prompt ?? ''), at: clock.now() })

    return { value: world.reply(world.model.length) }
  })
  // Were Jeb ever to ask the host what it has, the answers are marked too.
  on('tool.list', () => ({ value: [{ name: 'mcp__claude_ai_Zorbleflux__getJiraIssue', description: 'zxq', mcp: true }] }))
  on('command.list', () => ({ value: [{ name: 'zxqdeploy', description: 'snorkelvane', source: 'user' }] }))
  on('mcp.call', () => ({ value: { content: [{ type: 'text', text: 'ZXQ-4242 plumbuster in acmezxq' }], isError: false } }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('audio.play', () => ({ value: undefined }))
  on('audio.speak', () => ({ value: { synthesizer: 'test' } }))
  on('command.register', () => ({ value: { command: 'jeb' } }))
  on('session.id', () => ({ value: SESSION_ID }))
  on('session.root', () => ({ value: ROOT }))
  on('session.repo', () => ({ value: world.repo ?? REPO }))
  on('agent.list', () => ({ value: AGENTS }))
  on('classic.PreToolUse', () => ({}))
  for (const event of Object.keys(ANSWERS)) {
    on(event, (_: any, e: any) => {
      world.got.push({ event, e: copy(e) })

      return copy((world.answers[event] as (e: any) => unknown)(e))
    })
  }
  on('ui.render', ($$: any, e: any) => {
    world.drawn.push(copy(e.props))
    const { Text } = $$.ui.resolve(e)

    return <Text>{`engine ${String(e.component)}`}</Text>
  })
  on('turn.step', async function* (_: any, e: any) {
    world.got.push({ event: 'turn.step', e: copy(e) })
    for (const chunk of CHUNKS) {
      yield copy(chunk)
    }

    return stepResult()
  })

  return clock
}

const start = async ($: any, isInteractive = true) => {
  const result = await $.session.start({ cwd: CWD, surface: 'terminal', isInteractive })
  await clk.settle()

  return result
}

const elapse = async (ms: number) => {
  for (let left = ms; left > 0; left -= 20 * MINUTE) {
    await clk.advance(Math.min(left, 20 * MINUTE))
  }
}

const callOf = ($: any, event: string) => {
  const [noun, verb] = event.split('.') as [string, string]

  return $[noun][verb] as (input: unknown) => Promise<unknown>
}

// Raises one event as the engine does and reads what happened beneath Jeb.
const raise = async ($: any, event: string, input: unknown) => {
  const from = world.got.length
  const seen = world.probes.length
  const result = await callOf($, event)(copy(input))
  await clk.settle()
  const got = world.got.slice(from).filter(item => item.event === event)
  const probed = world.probes.slice(seen).filter(item => item.event === event)

  return { result, got, probe: probed[probed.length - 1] }
}

// Jeb's link and the one beneath it, as the probe saw them.
const jebLink = (probed: Probe | undefined) => {
  const links = probed?.links ?? []
  const i = links.findIndex(link => link.plugin === 'jeb')

  return { jeb: links[i], beneath: i >= 0 ? links[i + 1] : undefined }
}

// The observe-only check for one event: the engine beneath got the input as
// it was raised, the caller got the engine's answer as it was given, and Jeb's
// own link handed on what it received and gave back what came up.
const expectPassed = async ($: any, event: string, input: unknown, label: string, isJebs = true) => {
  const answer = world.answers[event] as (e: any) => unknown
  const { result, got, probe: probed } = await raise($, event, input)
  expect(got.length, `${label}: the engine beneath was reached once`).toBe(1)
  expect(got[0]?.e, `${label}: the event reached the engine as it was raised`).toEqual(input)
  expect(result, `${label}: the caller got the engine's answer`).toEqual(answer(copy(input)))
  const { jeb, beneath } = jebLink(probed)
  if (isJebs) {
    expect(jeb, `${label}: Jeb's hook ran`).toBeDefined()
    expect(['returned', 'passed'], `${label}: Jeb's hook settled (${String(jeb?.outcome)})`).toContain(jeb?.outcome)
    expect(beneath, `${label}: a link ran beneath Jeb`).toBeDefined()
    expect(beneath?.received, `${label}: Jeb handed the event on unchanged`).toEqual(jeb?.received)
    expect(jeb?.returned, `${label}: Jeb returned what came up from beneath`).toEqual(beneath?.returned)
    expect(jeb?.received, `${label}: Jeb received the event as raised`).toEqual(input)
  } else if (jeb) {
    expect(beneath?.received, `${label}: Jeb handed the event on unchanged`).toEqual(jeb.received)
    expect(jeb.returned, `${label}: Jeb returned what came up from beneath`).toEqual(beneath?.returned)
  }

  return result
}

// The whole stream of one step, chunk by chunk, and its result.
const drain = async ($: any, input: object) => {
  const stream = $.turn.step(copy(input))
  const out: unknown[] = []
  let step = await stream.next()
  while (!step.done) {
    out.push(step.value)
    step = await stream.next()
  }
  await clk.settle()

  return { out, result: step.value }
}

const MOUNTS = [
  { component: 'UserMessage', props: { text: 'Please refactor fizzlewick', origin: { kind: 'user' }, isExpanded: false } },
  { component: 'AssistantMessage', props: { text: 'Here is the plan for vorpalwhisk', isFirstOfReply: true } },
  {
    component: 'ToolUse',
    props: {
      tool_use_id: 'tu-zxq-1',
      tool: 'Bash',
      input: { command: 'git push origin feature/wobblequist' },
      isRunning: false,
      isErrored: false,
      isInterrupted: false,
      output: 'snickerdoodlex',
    },
  },
  { component: 'ToolResult', props: { tool_use_id: 'tu-zxq-5', tool: 'Read', output: 'marmaladix', isErrored: false } },
  {
    component: 'ToolGroup',
    props: { calls: [{ tool_use_id: 'tu-zxq-5', tool: 'Read', input: { file_path: '/home/zxquser/blorptastic/a.php' } }], isActive: false, isExpanded: false },
  },
  { component: 'CommandOutput', props: { command: 'zxqdeploy', args: 'snorkelvane', text: 'deployed glimmerhaust', isErrored: false } },
]
const DECOR = [
  { component: 'Spinner', props: { word: 'Zxqing', message: null, suffix: '…', mode: 'thinking' } },
  { component: 'Spinner', props: { word: 'Zxqing', message: 'fizzlewick', suffix: '…', mode: 'tool-use' } },
  { component: 'TurnDuration', props: { word: 'Baked', durationMs: 61_000 } },
  { component: 'PromptHint', props: { isDraft: false, isWorking: false, hint: '? for shortcuts', tail: 'zxq tail' } },
  { component: 'PromptHint', props: { isDraft: false, isWorking: false, hint: '? for shortcuts' } },
  { component: 'SessionMode', props: { modes: ['plan', 'zxq'] } },
]
// ---- GD2: nothing of the session reaches Haiku ----

const BAND = { hasSurvey: false, isWorking: true, maxRows: 20, bodyColumns: 160, scroll: { offset: 0, bodyRows: 19 }, view: {} }

// A stretch of real work: prompts, commands, tools, a stream, an agent, a turn's end.
const work = async ($: any) => {
  const raiseAll = async (event: string, input: unknown) => {
    await callOf($, event)(copy(input))
    await clk.settle()
  }
  await raiseAll('prompt.submit', PROMPTS.first)
  await raiseAll('turn.start', { text: PROMPTS.first.text, turnId: 't-zxq-1' })
  await drain($, stepInput())
  for (const input of TOOL_CALLS) {
    await raiseAll('tool.call', input)
  }
  await raiseAll('agent.spawn', spawnInput())
  await raiseAll('turn.start', { text: 'Look at ombrevale', turnId: 't-zxq-a', agentId: 'a-zxq-1' })
  await drain($, stepInput('a-zxq-1'))
  await raiseAll('tool.call', { ...TOOL_CALLS[4], agentId: 'a-zxq-1' })
  await raiseAll('turn.complete', completeInput({ agentId: 'a-zxq-1', turnId: 't-zxq-a' }))
  await raiseAll('prompt.submit', PROMPTS.midTurn)
  await raiseAll('prompt.submit', PROMPTS.attached)
  // Three failed test runs in a row: a storm, and a bad batch.
  for (let i = 0; i < 3; i += 1) {
    await raiseAll('tool.call', { ...TOOL_CALLS[0], tool_use_id: `tu-zxq-f${i}` })
  }
  await raiseAll('turn.complete', completeInput())
  await raiseAll('prompt.submit', PROMPTS.triage)
  await raiseAll('prompt.submit', PROMPTS.command)
  await raiseAll('prompt.submit', PROMPTS.meta)
  await raiseAll('prompt.submit', PROMPTS.thanks)
  await raiseAll('command.run', { command: 'zxqdeploy', args: 'snorkelvane --force' })
  await raiseAll('command.run', { command: 'jeb', args: 'craft zxqwidget' })
  await raiseAll('command.run', { command: 'jeb', args: 'journal fizzlewick' })
  await raiseAll('config.set', { key: 'theme', value: 'zxqtheme', previous: 'dark', provider: { plugin: 'engine', tier: 'core' }, origin: { kind: 'menu' } })
  await raiseAll('session.measure', { context: { window: 200_000 }, rateLimits: [{ kind: 'five_hour', percentUsed: 90 }], changed: ['rateLimits'] })
  // The transcript rows are drawn, and the decorative ones beside them.
  for (const mount of [...MOUNTS, ...DECOR]) {
    try {
      const ui = await $.ui.mount({ plugin: 'jeb', surface: 'terminal', ...mount } as any)
      await ui.unmount()
    } catch {
      // a row the surface refuses is not drawn
    }
    await clk.settle()
  }
  await $.ui.mount({ plugin: 'jeb', surface: 'terminal', component: 'AbovePrompt', props: BAND }).then((ui: any) => ui.unmount())
}

// Every marker the model could have been sent, case-insensitively.
const expectClean = () => {
  for (const call of world.model) {
    const system = call.system.toLowerCase()
    const prompt = call.prompt.toLowerCase()
    for (const marker of MARKERS) {
      expect(system.includes(marker), `marker "${marker}" in the system prompt`).toBe(false)
      expect(prompt.includes(marker), `marker "${marker}" in the prompt`).toBe(false)
    }
  }
}

const dayOf = (ms: number) => {
  const d = new Date(ms)

  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
}

// The drops' calls keep to six a day; the areas' (their own prompt) to three, counted apart.
const expectHaikuBudget = () => {
  const perDay = new Map<string, number>()
  const areasPerDay = new Map<string, number>()
  for (const call of world.model) {
    expect(call.model).toBe('haiku')
    const days = call.system === areaSystemPrompt() ? areasPerDay : perDay
    days.set(dayOf(call.at), (days.get(dayOf(call.at)) ?? 0) + 1)
  }
  for (const [day, n] of perDay) {
    expect(n, `model calls on ${day}`).toBeLessThanOrEqual(6)
  }
  for (const [day, n] of areasPerDay) {
    expect(n, `area calls on ${day}`).toBeLessThanOrEqual(3)
  }
}

const markersIn = (text: string) => {
  const lower = text.toLowerCase()

  return MARKERS.filter(marker => lower.includes(marker))
}

// Every value Jeb wrote, the store as it stands (keys too) and every line he said: no marker anywhere.
const expectNothingKept = (label: string) => {
  for (const { key, value } of world.sets) {
    expect(markersIn(`${key} ${JSON.stringify(value)}`), `${label}: a marker in what Jeb wrote to ${key}`).toEqual([])
  }
  for (const [key, value] of world.db) {
    expect(markersIn(`${key} ${JSON.stringify(value)}`), `${label}: a marker in the store under ${key}`).toEqual([])
  }
  for (const line of world.said) {
    expect(markersIn(line), `${label}: a marker in a line Jeb said: ${line}`).toEqual([])
  }
}

const liveKeys = () => [...world.db.keys()].filter(key => key.startsWith('live:'))
// ---- areas: nothing of the work reaches Haiku or the store, only a key and fixed words ----

// More work in the marker-filled project: files whose names and extensions are
// the session's own, a branch, a build and a query. Each is read for its kind and kept nowhere.
const AREA_CALLS = [
  { tool: 'Edit', tool_use_id: 'tu-zxq-a1', file_path: '/home/zxquser/work/glimmerhaust/src/widget.fizzlewick', old_string: 'a', new_string: 'b' },
  { tool: 'Write', tool_use_id: 'tu-zxq-a2', file_path: '/srv/kelpforge/Dockerfile.quandrix', content: 'FROM zxq' },
  { tool: 'Read', tool_use_id: 'tu-zxq-a3', file_path: '/home/zxquser/work/glimmerhaust/resources/js/Brambletoe.tsx' },
  { tool: 'Read', tool_use_id: 'tu-zxq-a4', file_path: '/home/zxquser/work/glimmerhaust/tests/Unit/GrommetvaleTest.php' },
  { tool: 'Bash', tool_use_id: 'tu-zxq-a5', command: 'git checkout -b feature/wobblequist' },
  { tool: 'Bash', tool_use_id: 'tu-zxq-a6', command: 'npm run build -- --outDir zxq-dist' },
  { tool: 'Bash', tool_use_id: 'tu-zxq-a7', command: 'psql -d brambletoe -c "select 1"' },
]

const areaRound = async ($: any) => {
  for (const input of AREA_CALLS) {
    await callOf($, 'tool.call')(copy(input))
  }
  await clk.settle()
}

// Thirty counted events and some housekeeping on top.
const areaWork = async ($: any) => {
  for (let i = 0; i < 6; i += 1) {
    await areaRound($)
  }
  await elapse(90_000)
}

const isAreaCall = (call: { system: string }) => call.system === areaSystemPrompt()

// A valid reply to an area prompt: the choices restated, then lore and beats.
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

// The drops get a drop and the areas a good area, whatever the prompts hold.
const areaWorld = (area: (prompt: string) => string) => {
  world.reply = n => {
    const last = world.model[world.model.length - 1]

    return answered(last && isAreaCall(last) ? area(last.prompt) : drop(n))
  }
}

const IDENTITY = identityOf(ROOT, REPO, CWD)
const AREA_NAME = new RegExp(`^(?:${AREA_SYLLABLES.join('|')}){2,3}$`)
// ---- encoded markers ----

const utf8Bytes = (text: string) => Array.from(new TextEncoder().encode(text))
const hexOf = (text: string) => utf8Bytes(text).map(byte => byte.toString(16).padStart(2, '0')).join('')
const reversed = (text: string) => Array.from(text).reverse().join('')

// The base64 of a marker as it reads inside a longer text, whatever the three
// alignments of its bytes: only the characters its own bytes alone decide.
const base64Cores = (text: string): string[] => {
  const cores: string[] = []
  for (let lead = 0; lead < 3; lead += 1) {
    const encoded = btoa('x'.repeat(lead) + text)
    const total = lead + text.length
    const body = encoded.replace(/=+$/, '')
    const from = [0, 2, 3][lead] as number
    const to = total % 3 === 0 ? body.length : body.length - 1
    cores.push(body.slice(from, to))
  }

  return cores
}

// Every form of every marker a store or a prompt must not hold: hex and base64
// of the marker and of its reverse, the reverse itself, in the case they were
// given and in capitals. Markers under six letters (`zxq`) are left to the plain check:
// their hex or base64 is short enough to turn up in a random salt by chance.
const encodedForms = () => {
  const forms: { marker: string; kind: string; needle: string; isLower: boolean }[] = []
  for (const marker of MARKERS) {
    const variants = [marker, marker.toUpperCase(), marker[0]?.toUpperCase() + marker.slice(1)]
    for (const word of variants) {
      const back = reversed(word)
      forms.push({ marker, kind: 'reversed', needle: back.toLowerCase(), isLower: true })
      if (marker.length < 6) {
        continue
      }
      for (const [kind, text] of [['', word], ['reversed ', back]] as const) {
        forms.push({ marker, kind: `${kind}hex`, needle: hexOf(text), isLower: true })
        for (const core of base64Cores(text)) {
          if (core.length >= 6) {
            forms.push({ marker, kind: `${kind}base64`, needle: core, isLower: false })
          }
        }
      }
    }
  }

  return forms
}

// What of the encoded forms a text holds, as "marker (kind)".
const encodedIn = (text: string): string[] => {
  const lower = text.toLowerCase()
  const found = new Set<string>()
  for (const { marker, kind, needle, isLower } of encodedForms()) {
    if (isLower ? lower.includes(needle) : text.includes(needle)) {
      found.add(`${marker} (${kind})`)
    }
  }

  return [...found]
}

// Everything Jeb wrote and holds, and every model prompt, for any form of a marker.
const expectNoEncoded = (label: string) => {
  for (const { key, value } of world.sets) {
    expect(encodedIn(`${key} ${JSON.stringify(value)}`), `${label}: an encoded marker in what Jeb wrote to ${key}`).toEqual([])
  }
  for (const [key, value] of world.db) {
    expect(encodedIn(`${key} ${JSON.stringify(value)}`), `${label}: an encoded marker in the store under ${key}`).toEqual([])
  }
  for (const [n, call] of world.model.entries()) {
    expect(encodedIn(call.system), `${label}: an encoded marker in system prompt ${n}`).toEqual([])
    expect(encodedIn(call.prompt), `${label}: an encoded marker in prompt ${n}`).toEqual([])
  }
}

test('G2 the encoded forms of a marker are found: the check itself is live', { timeoutMs: 120_000 }, () => {
  expect(encodedIn(`x ${hexOf('fizzlewick')} y`)).toContain('fizzlewick (hex)')
  expect(encodedIn(`x ${btoa('fizzlewick')} y`)).toContain('fizzlewick (base64)')
  expect(encodedIn(`x ${btoa('a fizzlewick')} y`)).toContain('fizzlewick (base64)')
  expect(encodedIn(`x ${btoa('ab fizzlewick!')} y`)).toContain('fizzlewick (base64)')
  expect(encodedIn(`x ${hexOf(reversed('fizzlewick'))} y`)).toContain('fizzlewick (reversed hex)')
  expect(encodedIn(`x ${btoa(reversed('fizzlewick'))} y`)).toContain('fizzlewick (reversed base64)')
  expect(encodedIn(`x ${reversed('fizzlewick')} y`)).toContain('fizzlewick (reversed)')
  expect(encodedIn('a plain day on the farm, 0123456789abcdef')).toEqual([])
})

test('G2 a day of marker-filled work, drops and an area: no hex, base64 or reversed marker in the store or in any prompt', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  areaWorld(areaReplyFor)
  await start($)
  await work($)
  await areaWork($)
  await elapse(at(10, 9, 15) - clk.now())
  await work($)
  await elapse(at(10, 12, 15) - clk.now())
  await work($)
  await elapse(at(10, 15, 15) - clk.now())
  await callOf($, 'session.end')({ reason: 'clear', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  await clk.settle()
  await elapse(MINUTE)
  expect(world.model.length, 'the check read real prompts').toBeGreaterThan(3)
  expect(world.model.some(isAreaCall), 'an area prompt was read').toBe(true)
  expect(world.sets.length).toBeGreaterThan(20)
  expectNoEncoded('a day of work')
  expectClean()
})

// ---- the overrides and the heartbeats ----

const SEEDED_SESSIONS = (now: number) => ({
  'sess-zxq-alive': { name: 'glimmerhaust', lastSeen: now - 30_000 },
  'sess-zxq-dead': { name: 'kelpforge', lastSeen: now - 10 * MINUTE, sq: 'B12', ln: 'Jun 10 · kelpforge camp · 2 loads out, kelpforge zxq' },
  a1a1a1a1a1a1: { name: 'plumbuster', lastSeen: now - 30_000, sq: 'G3', ln: 'Jun 10 · plumbuster camp · grommetvale' },
})

test('G2 the overrides and sessions keys: written, and holding no marker, plain or encoded, whatever was seeded there', { timeoutMs: 120_000 }, async ($, on) => {
  // A hostile or damaged `overrides`: only a boolean creativity and a known talk level survive.
  rig(on, { overrides: { creativity: true, talk: 'fizzlewick', zxq: 'quandrix', note: hexOf('fizzlewick') }, sessions: SEEDED_SESSIONS(START) })
  await start($)
  await elapse(5_000)
  await work($)
  await raise($, 'config.set', { key: 'jeb.talk', value: 'chatty', previous: 'normal', provider: { plugin: 'engine', tier: 'core' }, origin: { kind: 'menu' } })
  await raise($, 'config.set', { key: 'jeb.creativity', value: false, previous: true, provider: { plugin: 'engine', tier: 'core' }, origin: { kind: 'menu' } })
  await elapse(3 * MINUTE)
  const watched = ['overrides', 'sessions']
  for (const key of watched) {
    expect(world.sets.some(set => set.key === key), `${key} was written`).toBe(true)
  }
  expect(world.db.get('overrides')).toEqual({ creativity: false, talk: 'chatty' })
  // The dead heartbeat's old names are gone from `sessions`; what stays is keyed, placed and bounded.
  const sessions = world.db.get('sessions') as Record<string, Record<string, unknown>>
  for (const [id, beat] of Object.entries(sessions)) {
    expect(id, 'a heartbeat key').toMatch(/^[0-9a-f]{12}$/)
    for (const field of Object.keys(beat)) {
      expect(['name', 'lastSeen', 'sq', 'ln'], `heartbeat field ${field}`).toContain(field)
    }
  }
  for (const { key, value } of world.sets.filter(set => watched.includes(set.key))) {
    const text = `${key} ${JSON.stringify(value)}`
    expect(markersIn(text), `a marker in what Jeb wrote to ${key}`).toEqual([])
    expect(encodedIn(text), `an encoded marker in what Jeb wrote to ${key}`).toEqual([])
  }
  for (const key of watched) {
    const text = `${key} ${JSON.stringify(world.db.get(key))}`
    expect(markersIn(text), `a marker in the store under ${key}`).toEqual([])
    expect(encodedIn(text), `an encoded marker in the store under ${key}`).toEqual([])
  }
  expectNoEncoded('overrides and sessions')
})

// ---- the shape of every string Jeb stores ----

const TEXT_BAD = /[@#`<>{}]|https?:|www\./
// Words Jeb or the model makes: printable ASCII, short, no markup or address.
const isText = (value: string) => value.length > 0 && value.length <= 200 && /^[\x20-\x7e]+$/.test(value) && !TEXT_BAD.test(value)
// A name of the code's own making: a lowercase token, maybe with a count.
// A journal line: "Mon D · <place> camp · <what the day held>", the only string with a middle dot.
const isJournalLine = (value: string) =>
  value.length <= 200 && /^[A-Z][a-z]{2} \d{1,2} · [\x20-\x7e]+ camp · [\x20-\x7e]+$/.test(value) && !TEXT_BAD.test(value)
const isToken = (value: string) => /^[a-z][a-z0-9_-]{0,31}$/.test(value)
const isDayOrEmpty = (value: string) => value === '' || /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/.test(value)
const isMonthOrEmpty = (value: string) => value === '' || /^\d{4}-(0[1-9]|1[0-2])$/.test(value)
const isAreaName = (value: string) => NAME_RE.test(value)
const NAME_RE = /^[A-Za-z]{2,12}( [A-Za-z]{2,7})?$/
const isSaltOrEmpty = (value: string) => value === '' || anonymizeMod.isSalt(value)
const isAreaKey = (value: string) => areasMod.AREA_KEY_RE.test(value)
const isPlaceName = (value: string) => isPlace(value)
const isSquare = (value: string) => /^[A-Z][0-9]{0,3}$/.test(value)
const isSessionKey = (value: string) => /^[0-9a-f]{12}$/.test(value)
const isEnum = (list: readonly string[]) => (value: string) => list.includes(value)
const isSprite = (value: string) => (DROP_SPRITE_NAMES as readonly string[]).includes(value)
const isZone = (value: string) => (ZONES as readonly string[]).includes(value)

// Path (arrays as []) -> what a string there must be. A path not listed fails.
const SHAPES: [RegExp, (value: string) => boolean, string][] = [
  [/^farm\.(ledger\.month\.key)$/, isMonthOrEmpty, 'month'],
  [/^farm\.(unlockDay\.(d|since)|mailDay|drops\.day|modelCalls\.day|creative\.festival\.d|surprises\[\]\.day|creativeLog\[\]\.day)$/, isDayOrEmpty, 'day'],
  [/^farm\.(unlockDay\.coffee|creative\.festival\.tint)$/, v => v === '' || isToken(v), 'token'],
  [/^farm\.anonSalt$/, isSaltOrEmpty, 'salt'],
  [/^farm\.surprises\[\]\.(name|kind|lasts|made|arc|festival)$/, v => v === '' || isToken(v), 'token'],
  [/^farm\.surprises\[\]\.lines\[\]$/, isText, 'text'],
  [/^farm\.surprises\[\]\.sprites\[\]\.sprite$/, isSprite, 'sprite'],
  [/^farm\.surprises\[\]\.sprites\[\]\.zone$/, isZone, 'zone'],
  [/^farm\.creativeLog\[\]\.(name|kind)$/, isToken, 'token'],
  [/^farm\.creativeLog\[\]\.summary$/, isText, 'text'],
  [/^farm\.(quilt\[\]\.camp|journal\[\]\.camp|busiest\.camp)$/, isPlaceName, 'place'],
  [/^farm\.quilt\[\]\.(c|k)$/, isSquare, 'square'],
  [/^farm\.quilt\[\]\.d$|^farm\.journal\[\]\.d$|^farm\.busiest\.d$/, isDayOrEmpty, 'day'],
  [/^farm\.journal\[\]\.line$/, isJournalLine, 'journal line'],
  [/^farm\.anonPlaces\[\]$/, v => /^[0-9a-f]{6}$/.test(v), 'camp tag'],
  [/^farm\.stitched\[\]$/, isSessionKey, 'session key'],
  [/^farm\.modelTaken\[\]$/, v => /^[0-9a-f]{8}$/.test(v), 'nonce'],
  [/^live\.(pose|mood|act|truck\.load|event\.id|weather\.kind|weather\.plot|hands\[\]\.plot|hands\[\]\.look)$/, isToken, 'token'],
  [/^live\.line$/, isText, 'text'],
  [/^live\.live$/, isSquare, 'square'],
  [/^live\.area$/, isAreaKey, 'area key'],
  [/^live\.event\.art\.sprites\[\]\.sprite$/, isSprite, 'sprite'],
  [/^live\.event\.art\.sprites\[\]\.zone$/, isZone, 'zone'],
  [/^areas\.[0-9a-f]{8}\.(day|seen)$/, isDayOrEmpty, 'day'],
  [/^areas\.[0-9a-f]{8}\.made$/, isEnum(['model', 'offline']), 'enum'],
  [/^areas\.[0-9a-f]{8}\.name$/, isAreaName, 'area name'],
  [/^areas\.[0-9a-f]{8}\.terrain$/, isEnum(TERRAINS), 'enum'],
  [/^areas\.[0-9a-f]{8}\.palette$/, isEnum(PALETTES), 'enum'],
  [/^areas\.[0-9a-f]{8}\.weather$/, isEnum(WEATHERS), 'enum'],
  [/^areas\.[0-9a-f]{8}\.mood$/, isEnum(MOODS), 'enum'],
  [/^areas\.[0-9a-f]{8}\.motif$/, isEnum(MOTIFS), 'enum'],
  [/^areas\.[0-9a-f]{8}\.props\[\]$/, isSprite, 'sprite'],
  [/^areas\.[0-9a-f]{8}\.lore\[\]$/, isText, 'text'],
  [/^areas\.[0-9a-f]{8}\.beats\[\]\.line$/, isText, 'text'],
  [/^areas\.[0-9a-f]{8}\.beats\[\]\.(prop)$/, isSprite, 'sprite'],
  [/^areas\.[0-9a-f]{8}\.beats\[\]\.zone$/, isZone, 'zone'],
]

// Every string leaf of a value, with its path (array positions as []).
const stringLeaves = (value: unknown, path: string, out: [string, string][] = []): [string, string][] => {
  if (typeof value === 'string') {
    out.push([path, value])
  } else if (Array.isArray(value)) {
    for (const item of value) {
      stringLeaves(item, `${path}[]`, out)
    }
  } else if (value !== null && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) {
      stringLeaves(item, `${path}.${key}`, out)
    }
  }

  return out
}

// Every write to the farm, a live record or the areas: each string in it has a shape listed above.
const expectShapes = (label: string) => {
  const roots = ['farm', 'areas']
  let checked = 0
  const unlisted = new Set<string>()
  const misfits: string[] = []
  for (const { key, value } of world.sets) {
    const root = key.startsWith('live:') ? 'live' : key
    if (root !== 'live' && !roots.includes(root)) {
      continue
    }
    for (const [path, text] of stringLeaves(value, root)) {
      const shape = SHAPES.find(([pattern]) => pattern.test(path))
      if (!shape) {
        unlisted.add(path)
      } else if (!shape[1](text)) {
        misfits.push(`${path} is not a ${shape[2]}: ${JSON.stringify(text).slice(0, 60)}`)
      }
      checked += 1
    }
  }
  expect([...unlisted], `${label}: strings at paths with no listed shape`).toEqual([])
  expect(misfits, `${label}: strings that do not fit their shape`).toEqual([])

  return checked
}

test('G2 every string written to the farm, a live record or the areas has a listed shape: token, enum, day, salt, key, place or plain words', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  areaWorld(areaReplyFor)
  await start($)
  await work($)
  await areaWork($)
  await elapse(at(10, 9, 15) - clk.now())
  await work($)
  await elapse(at(10, 12, 15) - clk.now())
  await work($)
  await callOf($, 'session.end')({ reason: 'clear', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  await clk.settle()
  await elapse(at(10, 15, 15) - clk.now())
  expect(world.sets.some(set => set.key === 'areas')).toBe(true)
  expect(world.sets.some(set => set.key.startsWith('live:'))).toBe(true)
  expect(expectShapes('a day of work')).toBeGreaterThan(40)
})

test('G2 the same shapes hold for a farm from before the anonymizer, once made over', { timeoutMs: 120_000 }, async ($, on) => {
  const old = {
    ...freshFarm(),
    version: 9,
    quilt: [{ c: 'B', d: '2026-06-09', camp: 'glimmerhaust' }],
    journal: [{ d: '2026-06-09', camp: 'glimmerhaust', line: 'Jun 9 · glimmerhaust camp · 2 loads out, fizzlewick deploy' }],
    busiest: { d: '2026-06-09', camp: 'glimmerhaust', score: 12 },
    stitched: ['sess-quillobrand-0001'],
  }
  rig(on, { farm: old, sessions: SEEDED_SESSIONS(START) })
  await start($)
  await elapse(5_000)
  world.sets.splice(0)
  await work($)
  await elapse(5 * MINUTE)
  await callOf($, 'session.end')({ reason: 'clear', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  await clk.settle()
  await elapse(MINUTE)
  expect(expectShapes('a made-over farm')).toBeGreaterThan(5)
  expectNoEncoded('a made-over farm')
})

// ---- the secret and the salt come from the CSPRNG ----

test('G2 a new salt and a new area secret are hex of the same shape and differ each time; a source a test passes is still used', () => {
  const salts = new Set(Array.from({ length: 50 }, () => anonymizeMod.mintSalt()))
  const secrets = new Set(Array.from({ length: 50 }, () => areasMod.mintAreaSecret()))
  expect(salts.size).toBe(50)
  expect(secrets.size).toBe(50)
  for (const salt of salts) {
    expect(anonymizeMod.isSalt(salt), salt).toBe(true)
  }
  for (const secret of secrets) {
    expect(areasMod.isAreaSecret(secret), secret).toBe(true)
  }
  expect(anonymizeMod.mintSalt(() => 0)).toBe('0'.repeat(16))
  expect(areasMod.mintAreaSecret(() => 0.999)).toBe('f'.repeat(64))
})
