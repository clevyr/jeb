import { expect, mock, test } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'

import { areaSystemPrompt } from '../hooks/areas'

// Hardening: what Jeb notes of a call that has run never fails it, and an area
// that cannot be made or stored never keeps its claim.

const MINUTE = 60_000
const at = (d: number, h: number, m = 0, s = 0) => new Date(2026, 5, d, h, m, s).getTime()
const copy = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))
const SATURDAY = at(13, 10)

const db = new Map<string, unknown>()
const modelCalls: { system: string; prompt: string }[] = []
let clk: MockClock
let areaReply: ((prompt: string) => string) | undefined
let failSet: ((key: string) => boolean) | undefined
let sets: string[] = []
let toolAnswer: (() => unknown) | undefined
let spawnAnswer: (() => unknown) | undefined

const answered = (reply: string) => ({
  isAnswered: true,
  text: reply,
  usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
})

const GENERIC = JSON.stringify({ kind: 'saying', name: 'generic-1', lines: ['Nothin much, say.'], summary: 'A quiet saying' })

const rig = (on: any, entries: Record<string, unknown>, now: number): MockClock => {
  db.clear()
  for (const [key, value] of Object.entries(entries)) {
    db.set(key, copy(value))
  }
  modelCalls.length = 0
  sets = []
  areaReply = undefined
  failSet = undefined
  toolAnswer = undefined
  spawnAnswer = undefined
  const clock = mock.clock(on, { now })
  clk = clock
  mock.env(on, { HOME: '/home/jeb', JEB_VISITS: 'off', JEB_UNLOCKS: 'off', JEB_NEWS: 'null' })
  on('fs.read', (_: any, e: any) => {
    throw new Error(`ENOENT ${(e as { path: string }).path}`)
  })
  on('store.get', (_: any, e: any) => ({ value: copy(db.get(e.key)) }))
  on('store.set', (_: any, e: any) => {
    sets.push(e.key)
    if (failSet?.(e.key)) {
      throw new Error('store down')
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

    return { value: answered(isArea ? (areaReply?.(String(e.prompt)) ?? 'END') : GENERIC) }
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
  on('tool.call', () => (toolAnswer ? toolAnswer() : { result: {} }))
  on('agent.spawn', () => (spawnAnswer ? spawnAnswer() : { model: 'm', agentId: 'a1' }))
  on('prompt.submit', (_: any, e: any) => e)
  on('turn.start', (_: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.end', (_: any, e: any) => ({ sessionId: e.sessionId }))

  return clock
}

const start = ($: any) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

// ---- 1. nothing after next(e) throws out of a hook ----

test('H1 tool.call: the happy path still counts the call', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on, {}, SATURDAY)
  await start($)
  const ran = await $.tool.call({ tool: 'Read', tool_use_id: 'h-3', file_path: '/w/api/src/a.ts' })
  expect(ran).toEqual({ result: {} })
})

test('H1 agent.spawn: the happy path still hires and returns the spawn as it was', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on, {}, SATURDAY)
  await start($)
  const ran = await $.agent.spawn({ prompt: 'go', description: 'look', subagentType: 'Explore' })
  expect(ran).toEqual({ model: 'm', agentId: 'a1' })
})

// ---- 2. an area keeps no claim it cannot use ----

const AREA_CALLS = [
  { tool: 'Edit', tool_use_id: 'tu-a1', file_path: '/w/api/src/widget.ts', old_string: 'a', new_string: 'b' },
  { tool: 'Write', tool_use_id: 'tu-a2', file_path: '/w/api/Dockerfile', content: 'FROM x' },
  { tool: 'Read', tool_use_id: 'tu-a3', file_path: '/w/api/resources/js/Thing.tsx' },
  { tool: 'Read', tool_use_id: 'tu-a4', file_path: '/w/api/tests/Unit/ThingTest.php' },
  { tool: 'Bash', tool_use_id: 'tu-a5', command: 'git checkout -b feature/x' },
  { tool: 'Bash', tool_use_id: 'tu-a6', command: 'npm run build' },
  { tool: 'Bash', tool_use_id: 'tu-a7', command: 'psql -d x -c "select 1"' },
]

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

test('H2 an area the model got wrong is made offline, stored, and its claim let go', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on, {}, SATURDAY)
  areaReply = () => 'END'
  await start($)
  await areaWork($)
  expect(modelCalls.some(call => call.system === areaSystemPrompt())).toBe(true)
  const areas = db.get('areas') as Record<string, any>
  const made = Object.values(areas ?? {})
  expect(made.length).toBe(1)
  expect(made[0].made).toBe('offline')
  expect(db.get('areaClaims') ?? []).toEqual([])
})

test('H2 a store that fails after the claim is taken still lets the claim go', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on, {}, SATURDAY)
  failSet = key => key === 'areas'
  await start($)
  await areaWork($)
  expect(sets.includes('areas')).toBe(true)
  expect(db.get('areas')).toBeUndefined()
  expect(db.get('areaClaims') ?? []).toEqual([])
  // The claim was taken before it was let go.
  expect(sets.filter(key => key === 'areaClaims').length).toBeGreaterThanOrEqual(2)
})

test('H2 a claim that cannot be let go does not throw out of the tend', { timeoutMs: 120_000 }, async ($, on) => {
  rig(on, {}, SATURDAY)
  let claims = 0
  failSet = key => key === 'areaClaims' && (claims += 1) > 1
  await start($)
  await areaWork($)
  expect(Object.keys((db.get('areas') as object) ?? {}).length).toBe(1)
})
