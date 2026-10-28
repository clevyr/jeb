import type { Crop, Hand } from '../types'
import { cleanText } from './util'

// Hired hands: the agents the session runs, kept as a short list the canvas
// reads. Pure; the ticker, the hooks and the clock live in register.tsx.

export const MAX_AGENTS = 8
export const MAX_HANDS = 2
export const MAX_MATES = 2

// A hand that no list names any more is dropped after this long.
export const LIST_GRACE_MS = 60_000

// A workflow hand never appears in the engine's list, so it is let go instead
// after this long without a step or a tool call of its own.
export const WORKFLOW_IDLE_MS = 1_800_000

export type AgentKind = 'foreground' | 'workflow' | 'teammate'

export type Hired = {
  id: string
  type: string
  background: boolean
  isTeammate: boolean
  isWorkflow: boolean
  description: string
  name: string
  startedAt: number
  // When the engine last showed this hand doing something (a step or a tool
  // call); a workflow hand that goes quiet for WORKFLOW_IDLE_MS is let go.
  activeAt: number
  // 'working' until it finishes.
  state: 'working' | 'done' | 'failed'
  // A teammate stands at the sign while awake.
  isAwake: boolean
}

export const kindOf = (agent: Hired): AgentKind =>
  agent.isWorkflow
    ? 'workflow'
    : agent.isTeammate
      ? 'teammate'
      : 'foreground'

// Explore works the tobacco, Plan the orchard, anything else the corn.
export const plotOf = (type: string): Crop =>
  type === 'Explore' ? 'tobacco' : type === 'Plan' ? 'apples' : 'corn'

export const PLOT_NAMES: Record<Crop, string> = {
  tobacco: 'tobacco',
  corn: 'corn',
  apples: 'orchard',
}

type Spawned = {
  agentId: string
  subagentType?: string
  background?: boolean
  isTeammate?: boolean
  workflow?: unknown
  description?: string
  name?: string
}

export const hireOf = (spawn: Spawned, nowMs: number): Hired => ({
  id: cleanText(spawn.agentId, 64),
  type: cleanText(spawn.subagentType ?? 'general-purpose', 32),
  background: spawn.background === true,
  isTeammate: spawn.isTeammate === true,
  isWorkflow: spawn.workflow !== undefined && spawn.workflow !== null,
  description: cleanText(spawn.description, 32),
  name: cleanText(spawn.name, 32),
  startedAt: nowMs,
  activeAt: nowMs,
  state: 'working',
  isAwake: true,
})

// Adds a hand to the list, replacing one with the same id and dropping the
// oldest past MAX_AGENTS.
export const addHired = (list: readonly Hired[], hired: Hired): Hired[] =>
  [...list.filter(agent => agent.id !== hired.id), hired].slice(-MAX_AGENTS)

export const withoutHired = (list: readonly Hired[], id: string): Hired[] =>
  list.filter(agent => agent.id !== id)

export const findHired = (list: readonly Hired[], id: string | undefined) =>
  id === undefined ? undefined : list.find(agent => agent.id === id)

const PLOT_ORDER: Crop[] = ['tobacco', 'corn', 'apples']

// Who stands where: at most two hands (every running subagent, background or
// not, tends a plot), one to a plot (a workflow
// puts one in every plot), and the `+N` of those that did not fit.
export const fieldsOf = (list: readonly Hired[]) => {
  const hands: Hand[] = []
  const more: Partial<Record<Crop, number>> = {}
  const workflow = list.filter(agent => agent.isWorkflow && agent.state === 'working')
  if (workflow.length > 0) {
    for (const plot of PLOT_ORDER) {
      hands.push({ plot, id: workflow[hands.length % workflow.length]?.id ?? '' })
    }
    more.tobacco = workflow.length

    return { hands, more }
  }
  for (const agent of list) {
    if (kindOf(agent) !== 'foreground' || agent.state !== 'working') {
      continue
    }
    const plot = plotOf(agent.type)
    if (hands.length < MAX_HANDS && !hands.some(hand => hand.plot === plot)) {
      hands.push({ plot, id: agent.id })
    } else {
      more[plot] = (more[plot] ?? 0) + 1
    }
  }

  return { hands, more }
}

// How many teammates are awake at the sign (at most two).
export const matesOf = (list: readonly Hired[]) =>
  Math.min(
    MAX_MATES,
    list.filter(agent => kindOf(agent) === 'teammate' && agent.isAwake).length,
  )

// The line when a hand is taken on.
export const hireLine = (agent: Hired, handCount: number) => {
  switch (kindOf(agent)) {
    case 'workflow':
      return "Got the whole holler workin'."
    case 'teammate':
      return "Neighbor's come by to help out."
    default:
      return handCount <= 1
        ? `Got a hired hand in the ${PLOT_NAMES[plotOf(agent.type)]}.`
        : handCount === 2
          ? 'Got two hired hands in the fields.'
          : `Got ${handCount} hired hands. Fields are full up.`
  }
}

export const HAND_HOME_LINE = "Hired hand's back from town."
export const HAND_FAILED_LINE = 'Hand come back empty-handed.'

