import type { EngineInterface } from 'claude-code'

import type { Farm } from '../types'
import type { Area, AreaInput } from './areas'
import { AREA_TOKEN_CAP, areaPromptOf, areaRetryNote, areaSystemPrompt, parseAreaReply, validateAreaReply } from './areas'
import { RIPE } from './crops'
import { seasonOfMonth } from './offline'
import type { Drop, DropCtx, PromptInput } from './surprise'
import { parseReply, promptOf, retryNote, systemPrompt, tokenCap, validateDrop } from './surprise'

// What the creative drops ask of the host, and nothing else: one Haiku
// completion, built from Jeb's own farm and his past summaries. Nothing from the
// user's setup (servers, tools, commands) is read. The call is wrapped (try/catch,
// a timeout, a result check) and a failure sends the drop to the offline generator.
// `askHaiku` is the only function that touches `$` for the drops, and `askHaikuArea`
// (below) the only one for the areas, so the two are the whole surface the
// guardrails apply to.

export const MODEL_TIMEOUT_MS = 20_000

// ---- the model ----

// What the model is sent, from the farm: numbers, the model's own past
// summaries, and the level. Never session content.
export const promptInputOf = (
  farm: Pick<Farm, 'crops' | 'shelf' | 'upgrades' | 'unlocks' | 'creative'>,
  now: Date,
  slot: number,
  level: number,
  recent: readonly string[],
  isArcOpen: boolean,
): PromptInput => {
  const arc = farm.creative.arc
  const ripe: Record<string, number> = {}
  for (const crop of ['tobacco', 'corn', 'apples'] as const) {
    ripe[crop] = farm.crops[crop].filter(stage => stage >= RIPE).length
  }

  return {
    now,
    slot,
    level,
    season: seasonOfMonth(now.getMonth()),
    farm: { jars: farm.shelf.appleCinnamon, ripe, upgrades: farm.upgrades.length, unlocks: farm.unlocks.length },
    recent,
    arc: arc && !isArcOpen ? { name: arc.name, step: arc.at, of: arc.steps.length } : null,
    isArcOpen,
    artIds: farm.creative.art.map(art => art.id),
    total: farm.creative.total,
  }
}

// Asks Haiku for a surprise: one call, and one retry if the reply is not valid
// (the retry says so but never repeats the rejected text). `reserve` takes a call
// from the day's budget and says whether there was one; a refusal, an error, a
// denial or no budget ends it with nothing, and the caller falls back to the
// offline generator.
export async function askHaiku(
  $: EngineInterface,
  input: PromptInput,
  ctx: DropCtx,
  reserve: () => Promise<boolean>,
): Promise<Drop | undefined> {
  let note = ''
  for (let attempt = 0; attempt < 2; attempt += 1) {
    let isReserved = false
    try {
      isReserved = await reserve()
    } catch {
      isReserved = false
    }
    if (!isReserved) {
      return undefined
    }
    try {
      const reply = await $.model.complete({
        model: 'haiku',
        system: systemPrompt(input.level),
        prompt: promptOf(input, note),
        maxTokens: tokenCap(input.level),
        timeoutMs: MODEL_TIMEOUT_MS,
      })
      if (!reply || reply.isAnswered !== true) {
        return undefined
      }
      const checked = validateDrop(parseReply(String(reply.text ?? '')), ctx)
      if (checked.ok) {
        return checked.drop
      }
      // The failed check's name (a fixed word, never the reply) goes to the retry.
      note = retryNote(checked.why)
    } catch {
      return undefined
    }
  }

  return undefined
}

// Asks Haiku to write an area (its lore and beats) around the choices the code
// made, and nothing else: the prompt is the choices, the profile's enums and the
// bible (see `areaPromptOf`). The same shape as `askHaiku`: one retry when the
// reply is not valid (it says which check failed, a fixed word, never the reply),
// each attempt reserved from the areas' own budget, and a refusal, an error, a
// denial or no budget ends it with nothing, so the caller writes the offline area.
export async function askHaikuArea(
  $: EngineInterface,
  input: AreaInput,
  reserve: () => Promise<boolean>,
): Promise<Area | undefined> {
  let note = ''
  for (let attempt = 0; attempt < 2; attempt += 1) {
    let isReserved = false
    try {
      isReserved = await reserve()
    } catch {
      isReserved = false
    }
    if (!isReserved) {
      return undefined
    }
    try {
      const reply = await $.model.complete({
        model: 'haiku',
        system: areaSystemPrompt(),
        prompt: areaPromptOf(input, note),
        maxTokens: AREA_TOKEN_CAP,
        timeoutMs: MODEL_TIMEOUT_MS,
      })
      if (!reply || reply.isAnswered !== true) {
        return undefined
      }
      const checked = validateAreaReply(parseAreaReply(String(reply.text ?? '')), input)
      if (checked.ok) {
        return checked.area
      }
      note = areaRetryNote(checked.why)
    } catch {
      return undefined
    }
  }

  return undefined
}
