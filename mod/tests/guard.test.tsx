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

// ---- the world beneath ----

// A probe above Jeb: after every event it watches, it reports the links that
// ran beneath it, Jeb's among them, with what each received and returned.
const probe = {
  name: 'probe',
  tier: 'prepend' as const,
  register(on: any) {
    // Each hook written out in full, as the kit wants a hooks module's: the call
    // goes on, then what settled beneath it is reported, whether it settled or threw.
    on('prompt.submit', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('tool.call', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('turn.start', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('turn.complete', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('agent.spawn', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('config.set', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('session.start', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('session.end', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('session.measure', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('command.run', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('prompt.compose', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('prompt.section', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('prompt.context', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('prompt.attachment', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('attribution.text', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('tool.check', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('settings.read', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('session.send', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('session.append', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('session.receive', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('model.complete', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('tool.describe', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('skill.prompt', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('ui.render', async ($: any, e: any, next: any) => {
      try {
        return await next(e)
      } finally {
        await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })
      }
    })
    on('turn.step', async function* ($: any, e: any, next: any) {
      const stream = next(e)
      for await (const chunk of stream) {
        yield chunk
      }
      const result = await stream.result
      await $.store.set('guard-probe', { event: next.event, component: e?.component, links: next.trace })

      return result
    })
  },
}

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

// ---- GD1: what Jeb registers ----

// Every event no hook of Jeb's may stand on, whatever matcher it carries.
const FORBIDDEN = [
  'prompt.compose',
  'prompt.section',
  'prompt.context',
  'prompt.attachment',
  'attribution.text',
  'tool.check',
  'settings.read',
  'session.send',
  'session.append',
  'session.receive',
  'model.complete',
  'tool.describe',
  'skill.prompt',
]

// The components that draw the transcript: no ui.render hook of Jeb's may
// stand on them (CommandOutput only for /jeb's own output).
const TRANSCRIPT = ['UserMessage', 'AssistantMessage', 'ToolUse', 'ToolResult', 'ToolGroup', 'CommandOutput', 'AskUserQuestion', 'ToolProgress', 'InfoNotice']

// Whether a pattern of `on` selects an event: a name, `*`, `noun.*`, or `!` either.
const selects = (pattern: string, event: string): boolean => {
  if (pattern.startsWith('!')) {
    return !selects(pattern.slice(1), event)
  }
  if (pattern === '*') {
    return true
  }
  if (pattern.endsWith('.*')) {
    return event.startsWith(pattern.slice(0, -1))
  }

  return pattern === event
}

// Whether a matcher's value admits a value (no value admits all).
const admits = (rule: unknown, value: string): boolean => {
  if (rule === undefined) {
    return true
  }
  if (Array.isArray(rule)) {
    return rule.some(one => admits(one, value))
  }
  if (rule instanceof RegExp) {
    return rule.test(value)
  }

  return rule === value
}

type Registered = { pattern: string; matcher: Record<string, any> | undefined }

const registrations = (options: Record<string, unknown>): Registered[] => {
  const found: Registered[] = []
  const fake: any = (pattern: string, matcherOrHook: unknown, hook?: unknown) => {
    found.push({ pattern, matcher: hook === undefined ? undefined : (matcherOrHook as Record<string, any>) })

    return { catch: () => undefined }
  }
  register(fake, options as any)

  return found
}

test('GD1 Jeb registers no hook on the prompt, the model, the settings, the transcript or any outbound event', { timeoutMs: 120_000 }, () => {
  // Every option on, then the defaults (the last call leaves the module as a load would).
  for (const options of [{ flavor: true, hookReactions: true, creativity: true, talk: 'chatty' }, {}]) {
    const found = registrations(options)
    // The registrar was really used: the session hooks are there.
    expect(found.some(one => one.pattern === 'prompt.submit')).toBe(true)
    expect(found.some(one => one.pattern === 'tool.call')).toBe(true)
    for (const { pattern } of found) {
      for (const event of FORBIDDEN) {
        expect(selects(pattern, event), `${pattern} selects ${event}`).toBe(false)
      }
    }
    for (const { pattern, matcher } of found.filter(one => selects(one.pattern, 'ui.render'))) {
      expect(matcher?.component, `${pattern} must name its components`).toBeDefined()
      for (const component of TRANSCRIPT) {
        const isJebsOwn = component === 'CommandOutput' || component === 'InfoNotice' ? matcher?.props?.command === 'jeb' : false
        if (!isJebsOwn) {
          expect(admits(matcher?.component, component), `a ui.render hook on ${component}`).toBe(false)
        }
      }
    }
  }
})

test('GD1 Jeb registers no ui.render hook and answers no command', () => {
  const found = registrations({})
  expect(found.filter(one => selects(one.pattern, 'ui.render'))).toEqual([])
  expect(found.filter(one => selects(one.pattern, 'command.run'))).toEqual([])
})

test('GD1 through a stretch of work Jeb reads no file, registers no command, and shows, plays or says nothing', { timeoutMs: 120_000 }, async ($, on) => {
  // The rig's own answers, counted as Jeb asks for them.
  const asked: string[] = []
  const watched = ['fs.read', 'command.register', 'ui.toast', 'ui.open', 'audio.play', 'audio.speak']
  const counted = ((event: string, ...rest: any[]) => {
    if (watched.includes(event)) {
      const hook = rest[rest.length - 1]
      rest[rest.length - 1] = (...args: any[]) => {
        asked.push(event)

        return hook(...args)
      }
    }

    return on(event, ...rest)
  }) as typeof on
  rig(counted)
  await start($)
  await work($)
  await clk.advance(HOUR)
  await work($)
  expect(asked).toEqual([])
})

// The forbidden events, raised as the engine raises them.
const RAISED: [string, unknown][] = [
  ['prompt.compose', { model: 'm', promptModel: 'm', surfaces: ['terminal'], tools: ['Bash', 'Read'], outputStyle: null, traits: [] }],
  ['prompt.section', { name: 'env', text: 'Working directory: /home/zxquser/work/glimmerhaust' }],
  ['prompt.context', { blocks: [{ name: 'claudeMd', text: 'fizzlewick context' }] }],
  ['prompt.attachment', { type: 'zxq_note', text: 'quandrix in blorptastic', origin: { kind: 'engine' } }],
  ['attribution.text', { kind: 'commit', text: 'Generated for zxqdeploy' }],
  ['tool.check', { tool: 'Bash', input: { command: 'git push origin feature/wobblequist' }, tool_use_id: 'tu-zxq-30' }],
  ['session.send', { to: 'tealwhistle', text: 'fizzlewick', origin: { kind: 'model' } }],
  ['session.append', { message: { type: 'user', role: 'user', content: [{ type: 'text', text: 'quandrix' }] }, door: 'prompt', origin: { kind: 'tool', tool: 'Bash' }, uuid: 'u-zxq-1' }],
  ['session.receive', { origin: { kind: 'bridge' }, text: 'brambletoe' }],
  ['tool.describe', { tool: 'Bash', description: 'Runs a command', provider: { plugin: 'engine', tier: 'core' } }],
  ['skill.prompt', { skill: 'triage', text: 'Triage ZXQ-4242', frontmatter: {}, source: 'userSettings' }],
]

// The model and the settings are read by a plugin's call, not raised by the
// engine: another plugin makes those calls, and every plugin but the caller
// has its hooks run on them.
const caller = {
  name: 'caller',
  tier: 'append' as const,
  register(on: any) {
    on('command.run', { command: 'guardcall' }, async ($: any) => {
      try {
        await $.model.complete({ model: 'haiku', system: 'fizzlewick system', prompt: 'quandrix prompt', maxTokens: 10 })
      } catch {
        // the call's answer does not matter, only who saw it
      }
      try {
        await $.settings.read({})
      } catch {
        // the same
      }

      return { text: 'called' }
    })
  },
}

// What the engine beneath answers each of them with (the kit answers session.append, the rig the model).
const RAISED_ANSWERS: Record<string, (e: any) => unknown> = {
  'prompt.compose': () => ({ sections: [] }),
  'prompt.section': e => ({ text: e.text }),
  'prompt.context': e => ({ blocks: e.blocks }),
  'prompt.attachment': e => ({ text: e.text }),
  'attribution.text': e => ({ text: e.text }),
  'tool.check': () => ({ decision: 'allow' }),
  'settings.read': () => ({ value: {} }),
  'session.send': () => ({ isDelivered: true }),
  'session.receive': e => ({ text: e.text }),
  'tool.describe': e => ({ description: e.description }),
  'skill.prompt': e => ({ text: e.text }),
}

test('GD1 the probe sees Jeb where he has a hook: prompt.submit runs through him', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  const { probe: probed } = await raise($, 'prompt.submit', PROMPTS.first)
  expect(probed?.links.map(link => link.plugin)).toContain('jeb')
})

test('GD1 raised through the engine, no prompt, model, settings or outbound event reaches a hook of Jeb\'s', { plugins: [probe, caller], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  for (const [event, answer] of Object.entries(RAISED_ANSWERS)) {
    on(event, (_: any, e: any) => answer(e))
  }
  await start($)
  let reached = 0
  for (const [event, input] of RAISED) {
    const seen = world.probes.length
    try {
      await callOf($, event)(copy(input))
    } catch {
      // an answer the kit refuses: only the chain above it matters here
    }
    await clk.settle()
    const probed = world.probes.slice(seen).filter(item => item.event === event)
    for (const one of probed) {
      reached += 1
      expect(one.links.map(link => link.plugin), event).not.toContain('jeb')
    }
  }
  // The model and the settings, as another plugin asks for them.
  const seen = world.probes.length
  await callOf($, 'command.run')({ command: 'guardcall', args: '', origin: { kind: 'user' }, presentation: { isFullscreen: false } })
  await clk.settle()
  for (const event of ['model.complete', 'settings.read']) {
    const probed = world.probes.slice(seen).filter(item => item.event === event)
    expect(probed.length, event).toBeGreaterThan(0)
    for (const one of probed) {
      reached += 1
      expect(one.links.map(link => link.plugin), event).not.toContain('jeb')
    }
  }
  // The probe reported every one of them.
  expect(reached).toBeGreaterThanOrEqual(RAISED.length + 2)
})

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

// Jeb's hooks module is a link of every ui.render dispatch (its matchers are
// its own to apply), so for a transcript row the check is that the link is a
// pure pass-through: what came in went on, what came up went back, and the row
// drawn is the engine's. The registration test above shows no hook there.
test('GD1 a transcript row goes through Jeb untouched: the props as given, the engine\'s row as drawn', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  const drawn = world.drawn
  await start($)
  await expectPassed($, 'prompt.submit', PROMPTS.first, 'a prompt first')
  for (const mount of MOUNTS) {
    const before = drawn.length
    const seen = world.probes.length
    const ui = await $.ui.mount({ plugin: 'jeb', surface: 'terminal', ...mount } as any)
    const tree = await ui.drawn()
    await ui.unmount()
    await clk.settle()
    expect(drawn.slice(before), `${mount.component} reached the engine as given`).toEqual([mount.props])
    expect(JSON.stringify(tree), mount.component).toContain(`engine ${mount.component}`)
    expect(JSON.stringify(tree), mount.component).not.toContain('Jeb')
    const probed = world.probes.slice(seen).filter(item => item.event === 'ui.render' && item.component === mount.component).pop()
    expect(probed, mount.component).toBeDefined()
    const { jeb, beneath } = jebLink(probed)
    if (jeb) {
      expect(['returned', 'passed'], mount.component).toContain(jeb.outcome)
      expect(beneath?.received, mount.component).toEqual(jeb.received)
      expect(jeb.returned, mount.component).toEqual(beneath?.returned)
    }
  }
})

// ---- GD1: every session event passes through ----

test('GD1 prompt.submit: every kind of prompt reaches the engine unchanged and its answer comes back unchanged', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  for (const [name, input] of Object.entries(PROMPTS)) {
    await expectPassed($, 'prompt.submit', input, `prompt ${name}`)
  }
  // An engine that drops the prompt is answered as it said.
  world.answers['prompt.submit'] = () => ({ drop: 'dropped zxqdeploy' })
  await expectPassed($, 'prompt.submit', PROMPTS.first, 'a dropped prompt')
  await expectPassed($, 'prompt.submit', PROMPTS.triage, 'a dropped triage')
})

test('GD1 prompt.submit: before the session starts, too', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await expectPassed($, 'prompt.submit', PROMPTS.first, 'prompt before start')
})

test('GD1 tool.call: every tool, result, error and denial passes unchanged, main loop and subagent', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  await expectPassed($, 'turn.start', { text: PROMPTS.first.text, turnId: 't-zxq-1' }, 'turn start')
  for (const input of TOOL_CALLS) {
    await expectPassed($, 'tool.call', input, `${input.tool} ${input.tool_use_id}`)
  }
  // Errors and denials of the engine, and the same calls in a subagent's loop.
  world.answers['tool.call'] = e => toolResult(e, true)
  for (const input of TOOL_CALLS.slice(0, 3)) {
    await expectPassed($, 'tool.call', input, `failed ${input.tool_use_id}`)
  }
  world.answers['tool.call'] = () => ({ deny: 'denied by policy for zxqdeploy' })
  for (const input of TOOL_CALLS.slice(0, 3)) {
    await expectPassed($, 'tool.call', input, `denied ${input.tool_use_id}`)
  }
  world.answers['tool.call'] = e => toolResult(e)
  for (const input of TOOL_CALLS) {
    await expectPassed($, 'tool.call', { ...input, agentId: 'a-zxq-1' }, `subagent ${input.tool_use_id}`)
  }
  // Three errors in a row bring the storm: the calls still pass unchanged.
  world.answers['tool.call'] = e => toolResult(e, true)
  for (let i = 0; i < 4; i += 1) {
    await expectPassed($, 'tool.call', { ...TOOL_CALLS[0], tool_use_id: `tu-zxq-s${i}` }, `storm ${i}`)
  }
})

test('GD1 turn.start and turn.complete pass unchanged, the main loop\'s and an agent\'s', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  await expectPassed($, 'agent.spawn', spawnInput(), 'spawn')
  for (const agentId of [undefined, 'a-zxq-1']) {
    const loop = agentId ?? 'main'
    const extra = agentId ? { agentId } : {}
    await expectPassed($, 'turn.start', { text: 'fizzlewick turn', turnId: 't-zxq-1', ...extra }, `${loop} start`)
    await expectPassed($, 'turn.complete', completeInput(extra), `${loop} complete`)
    await expectPassed($, 'turn.complete', completeInput({ ...extra, reason: 'aborted', isAborted: true }), `${loop} aborted`)
    await expectPassed($, 'turn.complete', completeInput({ ...extra, reason: 'error' }), `${loop} error`)
  }
})

test('GD1 turn.step: every chunk goes up unchanged and in order, and the result unchanged, main loop and agent', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  await expectPassed($, 'turn.start', { text: 'fizzlewick', turnId: 't-zxq-1' }, 'turn start')
  for (const agentId of [undefined, 'a-zxq-1']) {
    const input = stepInput(agentId)
    const seen = world.probes.length
    const from = world.got.length
    const got = await drain($, input)
    expect(got.out).toEqual(CHUNKS)
    for (let i = 0; i < CHUNKS.length; i += 1) {
      expect(got.out[i], `chunk ${i}`).toEqual(CHUNKS[i])
    }
    expect(got.result).toEqual(stepResult())
    const reached = world.got.slice(from).filter(item => item.event === 'turn.step')
    expect(reached.length).toBe(1)
    expect(reached[0]?.e).toEqual(input)
    const { jeb, beneath } = jebLink(world.probes.slice(seen).filter(item => item.event === 'turn.step').pop())
    expect(jeb).toBeDefined()
    expect(beneath?.received).toEqual(jeb?.received)
    expect(jeb?.returned).toEqual(beneath?.returned)
  }
})

test('GD1 agent.spawn passes unchanged, answered or denied', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  await expectPassed($, 'agent.spawn', spawnInput(), 'spawn')
  await expectPassed($, 'agent.spawn', spawnInput({ background: true, name: 'tealwhistle', tool_use_id: 'tu-zxq-11' }), 'background spawn')
  world.answers['agent.spawn'] = () => ({ deny: 'no agents for zxqdeploy' })
  await expectPassed($, 'agent.spawn', spawnInput({ tool_use_id: 'tu-zxq-12' }), 'denied spawn')
})

test('GD1 config.set: a key that is not Jeb\'s passes unchanged, answered or denied', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  const sets = [
    { key: 'theme', value: 'zxqtheme', previous: 'dark' },
    { key: 'verbose', value: true, previous: false },
    { key: 'model', value: 'opus', previous: 'sonnet' },
    { key: 'plugins.zxqdeploy.flavor', value: false, previous: true },
    { key: 'jebby.flavor', value: false, previous: true },
  ]
  for (const input of sets) {
    await expectPassed($, 'config.set', { ...input, provider: { plugin: 'engine', tier: 'core' }, origin: { kind: 'menu' } }, `set ${input.key}`)
  }
  world.answers['config.set'] = () => ({ deny: 'locked by policy zxq' })
  for (const input of sets) {
    await expectPassed($, 'config.set', { ...input, provider: { plugin: 'engine', tier: 'core' }, origin: { kind: 'menu' } }, `denied ${input.key}`)
  }
})

test('GD1 session.start and session.measure pass unchanged', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await expectPassed($, 'session.start', { cwd: CWD, surface: 'terminal', isInteractive: true }, 'interactive start')
  await expectPassed($, 'session.measure', { context: { window: 200_000, tokens: 12_000 }, rateLimits: [{ kind: 'five_hour', percentUsed: 85 }], changed: ['rateLimits'] }, 'measure 85')
  await expectPassed($, 'session.measure', { context: { window: 200_000 }, rateLimits: [{ kind: 'five_hour', percentUsed: 97 }, { kind: 'seven_day', percentUsed: 99 }], changed: ['rateLimits', 'context'] }, 'measure 97')
  await expectPassed($, 'session.start', { cwd: '/home/zxquser/fizzlewick', surface: null, isInteractive: false }, 'headless start')
})

test('GD1 session.end passes unchanged for every reason', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  for (const reason of ['clear', 'resume', 'logout', 'other', 'prompt_input_exit']) {
    await expectPassed($, 'prompt.submit', PROMPTS.first, `prompt before ${reason}`)
    await expectPassed($, 'session.end', { reason, sessionId: SESSION_ID, resume: { id: SESSION_ID } }, `end ${reason}`)
  }
})

test('GD1 command.run for any command but /jeb passes unchanged', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  for (const [command, args] of [['zxqdeploy', 'snorkelvane --force'], ['triage', 'ZXQ-4242'], ['commit', ''], ['jebby', 'tally']]) {
    await expectPassed($, 'command.run', { command, args, origin: { kind: 'user' }, presentation: { isFullscreen: false } }, `/${command}`, false)
  }
})

// The decorative rows are the engine's own: Jeb has no hook on them.
const DECOR = [
  { component: 'Spinner', props: { word: 'Zxqing', message: null, suffix: '…', mode: 'thinking' } },
  { component: 'Spinner', props: { word: 'Zxqing', message: 'fizzlewick', suffix: '…', mode: 'tool-use' } },
  { component: 'TurnDuration', props: { word: 'Baked', durationMs: 61_000 } },
  { component: 'PromptHint', props: { isDraft: false, isWorking: false, hint: '? for shortcuts', tail: 'zxq tail' } },
  { component: 'PromptHint', props: { isDraft: false, isWorking: false, hint: '? for shortcuts' } },
  { component: 'SessionMode', props: { modes: ['plan', 'zxq'] } },
]

test('GD1 the spinner, turn line, hint and mode rows are passed through unchanged, with no hook of Jeb on them', { plugins: [probe], timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  const drawn = world.drawn
  // An ordinary evening, the first dark-of-the-moon and full-moon nights after
  // it, then the same with the session started: the flourish would land on all.
  const nights = [10]
  for (const kind of ['dark', 'full']) {
    const day = Array.from({ length: 19 }, (_, i) => 11 + i).find(d => moonNight(new Date(at(d, 21))) === kind)
    if (day !== undefined) {
      nights.push(day)
    }
  }
  expect(nights.length).toBe(3)
  const mountAll = async () => {
    for (const mount of DECOR) {
      const before = drawn.length
      const seen = world.probes.length
      const ui = await $.ui.mount({ plugin: 'jeb', surface: 'terminal', ...mount } as any)
      const tree = await ui.drawn()
      await ui.unmount()
      await clk.settle()
      expect(drawn.slice(before), `${mount.component} reached the engine as given`).toEqual([mount.props])
      expect(JSON.stringify(tree), mount.component).toContain(`engine ${mount.component}`)
      const { jeb } = jebLink(world.probes.slice(seen).filter(item => item.event === 'ui.render' && item.component === mount.component).pop())
      expect(jeb, `${mount.component}: Jeb has no hook`).toBeUndefined()
    }
  }
  // No session yet, so no ticker: the clock can jump from night to night.
  for (const day of nights) {
    await clk.set(at(day, 21))
    await mountAll()
  }
  await start($)
  await mountAll()
  await clk.advance(HOUR)
  await mountAll()
})

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

test('GD2 a weekday of work, then the 9:00, 12:00 and 15:00 drops: Haiku is asked and sees no marker', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  await work($)
  await elapse(at(10, 9, 15) - clk.now())
  const morning = world.model.length
  expect(morning).toBeGreaterThan(0)
  await work($)
  await elapse(at(10, 12, 15) - clk.now())
  await work($)
  await elapse(at(10, 15, 15) - clk.now())
  await work($)
  await elapse(HOUR)
  expect(world.model.length).toBeGreaterThanOrEqual(3)
  expectClean()
  expectHaikuBudget()
  // The prompts did carry the farm and the past drops: the check above read real prompts.
  expect(world.model[world.model.length - 1]?.prompt).toContain('porch-1')
})

test('GD2 a reply that fails its check is retried, the retry sees no marker either, and the day keeps to six calls', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  // Every first try is not a drop at all; every second is.
  world.reply = n => (n % 2 === 1 ? answered('no json here') : answered(drop(n)))
  await start($)
  await work($)
  await elapse(at(10, 9, 15) - clk.now())
  await work($)
  await elapse(at(10, 12, 15) - clk.now())
  await work($)
  await elapse(at(10, 15, 15) - clk.now())
  expect(world.model.length).toBeGreaterThanOrEqual(2)
  expect(world.model.some(call => call.prompt.includes('An earlier attempt failed'))).toBe(true)
  expectClean()
  expectHaikuBudget()
})

test('GD2 a model that never answers well still gets at most six calls a day, all Haiku, none with a marker', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  world.reply = () => answered('{"kind":"nonsense"}')
  await start($)
  await work($)
  await elapse(at(10, 12, 15) - clk.now())
  await work($)
  await elapse(at(10, 16) - clk.now())
  await work($)
  await elapse(HOUR)
  expect(world.model.length).toBeGreaterThan(0)
  expectClean()
  expectHaikuBudget()
})

test('GD2 what an ended session left behind (journal, quilt, camps, a /clear) never reaches a later session\'s drops', { timeoutMs: 120_000 }, async ($, on) => {
  // Another session of the same repo is running beside this one.
  const early = at(10, 7, 30)
  rig(on, { sessions: { 'sess-other-zxq': { name: 'glimmerhaust', lastSeen: early } } }, early)
  await start($)
  await work($)
  await clk.advance(20 * MINUTE)
  await work($)
  await callOf($, 'session.end')({ reason: 'clear', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  await clk.settle()
  await work($)
  await callOf($, 'session.end')({ reason: 'prompt_input_exit', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  await clk.settle()
  // Later that morning, a new session in the same repo.
  await clk.advance(5 * MINUTE)
  await start($)
  await work($)
  await elapse(at(10, 9, 15) - clk.now())
  await work($)
  await elapse(at(10, 15, 15) - clk.now())
  expect(world.model.length).toBeGreaterThan(0)
  expectClean()
  expectHaikuBudget()
})

test('GD2 at the top creative level, with arcs and pictures allowed, the prompt still holds no marker', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on, { farm: { ...freshFarm(), creative: { ...freshCreative(), total: 200 } } })
  await start($)
  await work($)
  await elapse(at(10, 9, 15) - clk.now())
  await work($)
  await elapse(at(10, 12, 15) - clk.now())
  expect(world.model.length).toBeGreaterThan(0)
  expect(world.model[0]?.system).toContain('Story depth 6 of 6')
  expectClean()
  expectHaikuBudget()
})

// ---- GD3: nothing of the session is stored or shown ----

// A farm as a Jeb before the anonymizer left it: real camp names in the quilt,
// the journal and the busiest day, a raw session id among the stitched.
const LEGACY_FARM = {
  ...freshFarm(),
  version: 9,
  quilt: [
    { c: 'B', d: '2026-06-09', camp: 'glimmerhaust' },
    { c: 'G', d: '2026-06-09', camp: 'glimmerhaust-api' },
  ],
  journal: [
    { d: '2026-06-09', camp: 'glimmerhaust', line: 'Jun 9 · glimmerhaust camp · 2 loads out, fizzlewick deploy' },
    { d: '2026-06-09', camp: 'glimmerhaust-api', line: 'Jun 9 · glimmerhaust-api camp · rain twice' },
  ],
  busiest: { d: '2026-06-09', camp: 'glimmerhaust', score: 12 },
  stitched: ['sess-quillobrand-0001'],
  sessionsWorked: 2,
  sessionsShipped: 1,
}

// Heartbeats a Jeb before the anonymizer left (raw ids and camp names, one alive
// and one dead with its square and line), and one keyed the new way that still
// carries a work name (as a hostile write would).
const legacySessions = (now: number) => ({
  'sess-zxq-alive': { name: 'glimmerhaust', lastSeen: now - 30_000 },
  'sess-zxq-dead': { name: 'kelpforge', lastSeen: now - 10 * MINUTE, sq: 'B12', ln: 'Jun 10 · kelpforge camp · 2 loads out, kelpforge zxq' },
  a1a1a1a1a1a1: { name: 'plumbuster', lastSeen: now - 30_000, sq: 'G3', ln: 'Jun 10 · plumbuster camp · grommetvale' },
  b2b2b2b2b2b2: { name: 'snorkelvane', lastSeen: now - 10 * MINUTE, sq: 'P7', ln: 'Jun 10 · snorkelvane camp · 2 hands hired' },
})

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

// Chatty, so every line Jeb has for the work is said (and checked).
test('GD3 a day of marker-filled work on a farm and heartbeats from before the anonymizer: no marker in anything stored or said', { timeoutMs: 120_000, options: { talk: 'chatty' } }, async ($, on) => {
  rig(on, { farm: LEGACY_FARM, sessions: legacySessions(START) })
  await start($)
  // The farm's salt settles first (see settle.ts); then the old farm is made over, and the
  // dead heartbeats are on the quilt under places. Saves in those seconds still carry the old
  // farm's names (already in the store before the anonymizer); from here on, nothing Jeb writes,
  // keeps or says may hold a marker.
  await elapse(5_000)
  world.sets.splice(0)
  const farm = world.db.get('farm') as typeof LEGACY_FARM & { anonSalt: string }
  expect(farm.version).toBe(10)
  expect(farm.quilt.length).toBeGreaterThanOrEqual(4)
  for (const square of farm.quilt) {
    expect(isPlace(square.camp), square.camp).toBe(true)
  }
  expectNothingKept('session start')
  await work($)
  await elapse(5 * MINUTE)
  await work($)
  // A /clear: the square is stitched, and the conversation goes on.
  await callOf($, 'session.end')({ reason: 'clear', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  await clk.settle()
  await work($)
  // The 9:00 drop, and more work after it.
  await elapse(at(10, 9, 15) - clk.now())
  await work($)
  await elapse(2 * MINUTE)
  // The live record was written, the heartbeats too, and lines were said: the checks below read real values.
  expect(world.sets.some(set => set.key.startsWith('live:'))).toBe(true)
  expect(world.sets.some(set => set.key === 'sessions')).toBe(true)
  expect(world.said.length).toBeGreaterThan(10)
  expect(world.said.some(line => line.startsWith('Lanterns lit over at'))).toBe(true)
  expect(world.said.some(line => line.startsWith('Last time:'))).toBe(true)
  expectNothingKept('a day of work')
  // The session ends: its live record goes with it, and nothing it leaves holds a marker.
  await callOf($, 'session.end')({ reason: 'prompt_input_exit', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  await clk.settle()
  await elapse(MINUTE)
  expect(liveKeys()).toEqual([])
  expectNothingKept('session end')
})

// The same day, with the farm's salt given the seconds it takes to settle between sessions
// (see settle.ts): until then the old farm is as it was and nothing of the session is written.
test('GD3 the same day, once the salt has settled: the old farm is made over, and no marker in anything written since', { timeoutMs: 120_000, options: { talk: 'chatty' } }, async ($, on) => {
  rig(on, { farm: LEGACY_FARM, sessions: legacySessions(START) })
  await start($)
  const before = world.sets.length
  // The old farm is not made over at once: a salt is all the session writes, and it keys nothing yet.
  expect((world.db.get('farm') as { version: number; anonPending?: boolean }).anonPending).toBe(true)
  expect(world.sets.slice(before).filter(set => set.key === 'sessions' || set.key.startsWith('live:'))).toEqual([])
  await elapse(5_000)
  const farm = world.db.get('farm') as typeof LEGACY_FARM & { anonSalt: string; anonPending?: boolean }
  expect(farm.version).toBe(10)
  expect(farm.anonPending).toBeUndefined()
  expect(farm.quilt.length).toBeGreaterThanOrEqual(4)
  for (const square of farm.quilt) {
    expect(isPlace(square.camp), square.camp).toBe(true)
  }
  // Everything written from the moment the farm was made over on holds no marker.
  const madeAt = world.sets.findIndex(set => set.key === 'farm' && !(set.value as { anonPending?: boolean }).anonPending)
  expect(madeAt).toBeGreaterThanOrEqual(0)
  for (const { key, value } of world.sets.slice(madeAt)) {
    expect(markersIn(`${key} ${JSON.stringify(value)}`), `a marker in what Jeb wrote to ${key}`).toEqual([])
  }
  for (const [key, value] of world.db) {
    expect(markersIn(`${key} ${JSON.stringify(value)}`), `a marker in the store under ${key}`).toEqual([])
  }
  await work($)
  await elapse(5 * MINUTE)
  await work($)
  expect(world.sets.some(set => set.key.startsWith('live:'))).toBe(true)
  expect(world.said.some(line => line.startsWith('Lanterns lit over at'))).toBe(true)
  expect(world.said.some(line => line.startsWith('Last time:'))).toBe(true)
  for (const { key, value } of world.sets.slice(madeAt)) {
    expect(markersIn(`${key} ${JSON.stringify(value)}`), `a marker in what Jeb wrote to ${key}`).toEqual([])
  }
  for (const [key, value] of world.db) {
    expect(markersIn(`${key} ${JSON.stringify(value)}`), `a marker in the store under ${key}`).toEqual([])
  }
  for (const line of world.said) {
    expect(markersIn(line), `a marker in a line Jeb said: ${line}`).toEqual([])
  }
})

test('GD3 every live record holds only its own fields, under a token that is neither the session id nor its key', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  await start($)
  await work($)
  await elapse(3 * MINUTE)
  await work($)
  await elapse(MINUTE)
  const farm = world.db.get('farm') as { anonSalt: string }
  const key = sessionKeyOf(farm.anonSalt, SESSION_ID)
  const token = liveTokenOf(farm.anonSalt, '2026-06-10', key)
  const writes = world.sets.filter(set => set.key.startsWith('live:'))
  expect(writes.length).toBeGreaterThan(3)
  for (const { key: storeKey, value } of writes) {
    expect(storeKey).toBe(`live:${token}`)
    expect(storeKey).not.toContain(key)
    expect(storeKey).not.toContain(SESSION_ID)
    const record = value as Record<string, unknown>
    for (const field of Object.keys(record)) {
      expect(LIVE_FIELDS as readonly string[], `field ${field}`).toContain(field)
    }
    expect(record.v).toBe(1)
    expect(typeof record.at).toBe('number')
    expect(typeof record.frame).toBe('number')
    if ('line' in record) {
      expect(typeof record.line).toBe('string')
      expect(typeof record.saidAt).toBe('number')
    }
    for (const n of (record.cows as unknown[] | undefined) ?? []) {
      expect(Number.isInteger(n) && (n as number) >= 1 && (n as number) <= 99, `cow ${String(n)}`).toBe(true)
    }
    for (const hand of (record.hands as Record<string, unknown>[] | undefined) ?? []) {
      expect(Object.keys(hand).sort()).toEqual(['look', 'plot'])
    }
    expect(markersIn(JSON.stringify(record))).toEqual([])
  }
  // The triage ticket and the work board's ticket are cows, as numbers.
  expect(writes.some(({ value }) => ((value as { cows?: number[] }).cows ?? []).includes(neighborOf(farm.anonSalt, 'ZXQ-4242')))).toBe(true)
})

test('GD3 the anonymizer is stable and one way: no marker survives it, and without the salt a name says nothing', () => {
  const salt = '0123456789abcdef'
  const other = 'fedcba9876543210'
  for (const marker of MARKERS) {
    const placed = placeFor(salt, marker, [])
    expect(isPlace(placed.place)).toBe(true)
    expect(placeFor(salt, marker, placed.tags).place).toBe(placed.place)
    expect(placeSeen(salt, marker, placed.tags)).toBe(placed.place)
    const outputs = [
      placed.place,
      ...placed.tags,
      sessionKeyOf(salt, marker),
      liveTokenOf(salt, '2026-06-10', sessionKeyOf(salt, marker)),
      String(neighborOf(salt, marker)),
      lineFor(`Jun 9 · ${marker} camp · ${marker} deploy, 2 loads out`, '2026-06-09', placed.place),
      mcpKindOf(`claude_ai_${marker}`).line,
    ]
    for (const out of outputs) {
      expect(markersIn(out), `${marker} -> ${out}`).toEqual([])
    }
    expect(sessionKeyOf(salt, marker)).not.toBe(sessionKeyOf(other, marker))
    expect(sessionKeyOf(salt, marker)).not.toBe(sessionKeyOf('', marker))
  }
})

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
const NAME_OK = (name: string) => {
  const [base, suffix, ...rest] = name.split(' ')

  return rest.length === 0 && AREA_NAME.test((base ?? '').toLowerCase()) && /^[A-Z]/.test(base ?? '') && (suffix === undefined || (SUFFIXES as readonly string[]).includes(suffix))
}
const WORDS = new Set<string>([
  ...TERRAINS, ...PALETTES, ...WEATHERS, ...MOODS, ...MOTIFS, ...WORK_KINDS, ...DROP_SPRITE_NAMES, 'low', 'mid', 'high', 'unsettled', 'none', 'yet',
])
const FIXED_LINES = new Set(['none yet', 'Write the place now, in the lines of the format.', ...['format', 'choices', 'lore', 'beats', 'words'].map(areaRetryNote)])

// Every line of an area's user prompt is a tag, a fixed sentence, or `key: words`
// where each word is of a fixed list or a name composed of the syllables.
const expectAllowed = (prompt: string) => {
  for (const line of prompt.split('\n')) {
    if (/^<\/?(choices|profile|bible)>$/.test(line) || FIXED_LINES.has(line)) {
      continue
    }
    const [head, ...rest] = line.split(': ')
    const values = (rest.length > 0 ? rest.join(': ') : head ?? '').split(/,\s*/)
    if (rest.length > 0) {
      expect(['name', 'terrain', 'palette', 'weather', 'mood', 'motif', 'props', ...WORK_KINDS], line).toContain(head)
      for (const value of values) {
        expect(value === 'unsettled' || WORDS.has(value) || (head === 'name' && NAME_OK(value)), `"${value}" in the area prompt line "${line}"`).toBe(true)
      }
      continue
    }
    // A bible stub: name | terrain | palette; or a lone word of the lists.
    const parts = line.split(' | ')
    expect(parts.length === 3 ? NAME_OK(parts[0] as string) && WORDS.has(parts[1] as string) && WORDS.has(parts[2] as string) : WORDS.has(line), `an unlisted line in the area prompt: ${line}`).toBe(true)
  }
}

const AREA_ENUMS: Record<string, readonly string[]> = { terrain: TERRAINS, palette: PALETTES, weather: WEATHERS, mood: MOODS, motif: MOTIFS }
const AREA_FIELDS_ALLOWED = ['v', 'made', 'day', 'seen', 'name', 'terrain', 'palette', 'weather', 'mood', 'motif', 'props', 'lore', 'beats']
const PLAIN = /^[\x20-\x7e]*$/

// One stored area against the rules written here, apart from the module's own check.
const expectAreaWithinRules = (area: Record<string, any>, label: string) => {
  for (const field of Object.keys(area)) {
    expect(AREA_FIELDS_ALLOWED, `${label}: field ${field}`).toContain(field)
  }
  expect(area.v, label).toBe(1)
  expect(['model', 'offline'], label).toContain(area.made)
  expect(area.day, label).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  expect(area.seen, label).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  expect(typeof area.name === 'string' && area.name.length <= 16 && /^[A-Za-z ]+$/.test(area.name), `${label}: name ${String(area.name)}`).toBe(true)
  expect(NAME_OK(area.name), `${label}: name ${String(area.name)} is composed from the syllables`).toBe(true)
  for (const [field, list] of Object.entries(AREA_ENUMS)) {
    expect(list, `${label}: ${field}`).toContain(area[field])
  }
  expect(area.props.length >= 3 && area.props.length <= 5, `${label}: props`).toBe(true)
  for (const prop of area.props) {
    expect(DROP_SPRITE_NAMES, `${label}: prop ${String(prop)}`).toContain(prop)
  }
  expect(area.lore.length >= 2 && area.lore.length <= 4, `${label}: lore`).toBe(true)
  expect(area.beats.length >= 3 && area.beats.length <= 6, `${label}: beats`).toBe(true)
  const sprites = new Set<string>(area.props)
  const lines = [...area.lore]
  for (const beat of area.beats) {
    expect(Object.keys(beat).every(field => ['line', 'prop', 'zone'].includes(field)), `${label}: beat fields`).toBe(true)
    expect(ZONES, `${label}: zone`).toContain(beat.zone)
    if (beat.prop !== undefined) {
      expect(DROP_SPRITE_NAMES, `${label}: beat prop`).toContain(beat.prop)
      sprites.add(beat.prop)
    }
    lines.push(beat.line)
  }
  expect(sprites.size, `${label}: distinct sprites`).toBeLessThanOrEqual(8)
  for (const line of lines) {
    expect(typeof line === 'string' && line.length > 0 && line.length <= 64 && PLAIN.test(line), `${label}: line "${String(line)}"`).toBe(true)
    expect(/[@#`<>{}]|https?:|www\./.test(line), `${label}: markup or address in "${line}"`).toBe(false)
  }
  expect(markersIn(JSON.stringify(area)), `${label}: a marker`).toEqual([])
  expect(JSON.stringify(area).length, `${label}: size`).toBeLessThanOrEqual(1536)
}

test('GD2 areas: marker-filled work in a marker-named project makes an area, and Haiku sees no marker, only the key\'s choices, enums and names', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  areaWorld(areaReplyFor)
  await start($)
  await work($)
  await areaWork($)
  await elapse(5 * MINUTE)
  const calls = world.model.filter(isAreaCall)
  expect(calls.length, 'the area was asked of Haiku').toBe(1)
  for (const call of calls) {
    for (const marker of MARKERS) {
      expect(call.system.toLowerCase().includes(marker), `marker "${marker}" in the area system prompt`).toBe(false)
      expect(call.prompt.toLowerCase().includes(marker), `marker "${marker}" in the area prompt`).toBe(false)
    }
    expect(call.model).toBe('haiku')
    expectAllowed(call.prompt)
    // The prompt names the choices, the profile's enums and a bible, nothing else.
    expect(call.prompt).toContain('<profile>')
    expect(call.prompt).toContain('<bible>')
  }
  expectClean()
  expectHaikuBudget()
  // The area is stored under the key of the project's identity, made by the model.
  const secret = world.db.get('areaSecret') as string
  const key = areaKeyOf(secret, IDENTITY)
  const areas = world.db.get('areas') as Record<string, Record<string, any>>
  expect(Object.keys(areas)).toEqual([key])
  expect(areas[key]?.made).toBe('model')
  expectAreaWithinRules(areas[key] as Record<string, any>, 'the model\'s area')
})

test('GD3 areas: after a marker-filled day nothing marked is in the areas, their counters or any live record, and a live record holds only the key', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  areaWorld(areaReplyFor)
  await start($)
  await work($)
  await areaWork($)
  await elapse(3 * MINUTE)
  const key = areaKeyOf(world.db.get('areaSecret') as string, IDENTITY)
  expect(key).toMatch(/^[0-9a-f]{8}$/)
  const stored = ['areas', 'areaWork', 'areaCalls', 'areaClaims', 'areaSecret']
  for (const name of stored) {
    expect(world.sets.some(set => set.key === name), `${name} was written`).toBe(name !== 'areaClaims' || true)
  }
  expectNothingKept('a day of work with an area')
  for (const name of liveKeys()) {
    const record = world.db.get(name) as Record<string, unknown>
    expect(record.area, name).toBe(key)
    for (const field of Object.keys(record)) {
      expect(LIVE_FIELDS as readonly string[], `field ${field}`).toContain(field)
    }
    expect(markersIn(JSON.stringify(record)), name).toEqual([])
  }
  expect(liveKeys().length).toBe(1)
  // What is kept of the work is counts by kind under the key, never a word.
  const counted = world.db.get('areaWork') as Record<string, { kinds: Record<string, number>; n: number; seen: string }>
  expect(Object.keys(counted)).toEqual([key])
  for (const kind of Object.keys(counted[key]?.kinds ?? {})) {
    expect(WORK_KINDS as readonly string[]).toContain(kind)
  }
  expect(counted[key]?.n).toBeGreaterThanOrEqual(30)
  // The secret is 32 bytes of hex and is nowhere else.
  expect(world.db.get('areaSecret')).toMatch(/^[0-9a-f]{64}$/)
  for (const [name, value] of world.db) {
    if (name !== 'areaSecret') {
      expect(JSON.stringify(value).includes(world.db.get('areaSecret') as string), `the secret in ${name}`).toBe(false)
    }
  }
})

// Five projects in a morning, none of them answered well: two calls for the
// first (it and its retry), one for the second, then none; every one still has an
// area (offline, at once), and the model is not asked again for a key that day.
test('GD2 areas: a failing model is retried once with a fixed note, never more than three area calls a day, and every project still gets an area', { timeoutMs: 180_000 }, async ($, on) => {
  rig(on)
  areaWorld(() => 'nothing in the format at all')
  const repoNow = { value: { ...REPO } }
  const projects = ['grommetvale', 'kelpforge', 'plumbuster', 'oldzebrine', 'hobnailia']
  const keys: string[] = []
  for (const [i, name] of projects.entries()) {
    repoNow.value = { root: `/home/zxquser/work/${name}`, remote: `git@github.com:acmezxq/${name}.git`, internal: false, name }
    world.repo = repoNow.value
    await start($)
    await areaWork($)
    keys.push(areaKeyOf(world.db.get('areaSecret') as string, identityOf(`/home/zxquser/work/${name}`, repoNow.value, CWD)))
    expect(Object.keys(world.db.get('areas') as object), `after project ${i + 1}`).toContain(keys[i])
    await callOf($, 'session.end')({ reason: 'other', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
    await clk.settle()
  }
  const calls = world.model.filter(isAreaCall)
  expect(calls.length).toBe(AREA_DAILY_CAP)
  expect(calls[0]?.prompt).not.toContain('An earlier attempt failed')
  expect(calls[1]?.prompt).toContain('An earlier attempt failed the "format" check')
  expect(calls[1]?.prompt).toBe(`${calls[0]?.prompt}\n${areaRetryNote('format')}`)
  expect(world.db.get('areaCalls')).toEqual({ day: '2026-06-10', n: AREA_DAILY_CAP })
  const areas = world.db.get('areas') as Record<string, Record<string, any>>
  expect(Object.keys(areas).sort()).toEqual([...keys].sort())
  for (const key of keys) {
    expect(areas[key]?.made, key).toBe('offline')
    expectAreaWithinRules(areas[key] as Record<string, any>, `offline area ${key}`)
  }
  expect(world.db.get('areaClaims') ?? []).toEqual([])
  // The first project again the same day: its area is there, so the model is not asked.
  repoNow.value = { root: '/home/zxquser/work/grommetvale', remote: 'git@github.com:acmezxq/grommetvale.git', internal: false, name: 'grommetvale' }
  world.repo = repoNow.value
  await start($)
  await areaWork($)
  expect(world.model.filter(isAreaCall).length).toBe(AREA_DAILY_CAP)
  expectClean()
  expectHaikuBudget()
  // The drops' own count is untouched by the areas.
  expect((world.db.get('farm') as { modelCalls: { n: number } }).modelCalls.n).toBeLessThanOrEqual(6)
})

test('GD3 areas: the key is 8 hex, stable for an identity, different under another secret, and one way', () => {
  const secret = 'a1'.repeat(32)
  const other = 'b2'.repeat(32)
  const seen = new Set<string>()
  for (const marker of MARKERS) {
    const identity = `remote:github.com/acmezxq/${marker}`
    const key = areaKeyOf(secret, identity)
    expect(key).toMatch(/^[0-9a-f]{8}$/)
    expect(areaKeyOf(secret, identity), 'stable').toBe(key)
    expect(areaKeyOf(other, identity), 'another secret').not.toBe(key)
    expect(markersIn(key), marker).toEqual([])
    seen.add(key)
    // Not any plain hash of the identity, with the farm's salt, none or a guessed one.
    for (const salt of ['', '0123456789abcdef', secret.slice(0, 16), other.slice(0, 16)]) {
      for (const text of [identity, `area:${identity}`, marker, `area:${marker}`]) {
        expect(hashHex(salt, text, 8), `${salt} ${text}`).not.toBe(key)
      }
    }
  }
  expect(seen.size).toBeGreaterThanOrEqual(MARKERS.length - 1)
  // No secret, no key; no identity, no key.
  expect(areaKeyOf('', 'remote:x')).toBe('')
  expect(areaKeyOf(secret, '')).toBe('')
  // Worktrees of one repository share the key, clones over https and ssh agree.
  expect(areaKeyOf(secret, identityOf('/w/api-ticket-1', { root: '/w/api', remote: null }, '/w/api-ticket-1'))).toBe(
    areaKeyOf(secret, identityOf('/w/api', { root: '/w/api', remote: null }, '/w/api')),
  )
  expect(areaKeyOf(secret, identityOf('/a', { root: '/a', remote: 'https://github.com/AcmeZxq/Glimmerhaust.git' }, '/a'))).toBe(
    areaKeyOf(secret, identityOf('/b', { root: '/b', remote: 'git@github.com:acmezxq/glimmerhaust.git' }, '/b')),
  )
})

test('GD2 areas: the retry note and the system prompt hold only fixed words, whatever fails', () => {
  for (const why of ['format', 'choices', 'lore', 'beats', 'words', ...MARKERS, 'a reply that said fizzlewick']) {
    const note = areaRetryNote(why)
    expect(markersIn(note), why).toEqual([])
    expect(FIXED_LINES.has(note) || /failed the "format" check/.test(note), why).toBe(true)
  }
  expect(markersIn(areaSystemPrompt())).toEqual([])
  expect(areaSystemPrompt()).toBe(areaSystemPrompt())
})

test('GD3 areas: every offline area, over many keys and profiles, is within the field, enum, charset and length rules', { timeoutMs: 120_000 }, () => {
  const profiles = [[], [{ kind: 'testing', level: 'high' }], [{ kind: 'docs', level: 'mid' }, { kind: 'infra', level: 'low' }]] as const
  for (let i = 0; i < 400; i += 1) {
    const key = (Math.imul(i + 1, 2654435761) >>> 0).toString(16).padStart(8, '0')
    const area = offlineArea(key, profiles[i % 3] as never, '2026-06-10')
    expect(area.made).toBe('offline')
    expectAreaWithinRules(area as unknown as Record<string, any>, `offline ${key}`)
  }
})

test('GD1 areas: the model is asked only by signals.ts: every call of a day is a drop\'s or an area\'s own prompt, and no other hook module\'s code calls the model or reaches the web, a process, a file write, a notice or an MCP server', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on)
  areaWorld(areaReplyFor)
  await start($)
  await work($)
  await areaWork($)
  await elapse(at(10, 9, 15) - clk.now())
  await work($)
  await elapse(HOUR)
  expect(world.model.some(isAreaCall)).toBe(true)
  expect(world.model.some(call => !isAreaCall(call))).toBe(true)
  for (const call of world.model) {
    expect(isAreaCall(call) || call.system.startsWith('You are the storyteller of Jeb'), 'a model call that is neither').toBe(true)
  }
  // The source of every function each hook module exports (the loader gives a test
  // no file to read): only signals.ts holds `.model.`.
  const modules: Record<string, Record<string, unknown>> = { areas: areasMod, anonymize: anonymizeMod, drops: dropsMod, live: liveMod, offline: offlineMod, register: registerModule, signals: signalsMod, surprise: surpriseMod }
  for (const [name, mod] of Object.entries(modules)) {
    const text = Object.values(mod).filter(one => typeof one === 'function').map(String).join('\n')
    expect(/\.model\./.test(text), `${name} calls the model`).toBe(name === 'signals')
    for (const banned of [/\.http\./, /\.process\./, /\.fs\.write/, /ui\.notify/, /\.mcp\./, /\.tool\.list/, /\.command\.list/]) {
      expect(banned.test(text), `${name} matches ${String(banned)}`).toBe(false)
    }
  }
  expect(Object.keys(signalsMod).sort()).toEqual(['MODEL_TIMEOUT_MS', 'askHaiku', 'askHaikuArea', 'promptInputOf'])
})
