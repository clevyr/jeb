import { expect, test } from 'claude-code/testing'

import { LORE, LORE_ENTRY_MAX, LORE_MAX } from '../hooks/lore'
import { isClean, LORE_PICKS, lorePicks, promptOf, systemPrompt } from '../hooks/surprise'

// Words that never belong in a work-appropriate farm story.
const OFF_LIMITS = /\b(damn|hell|kill|blood|gore|murder|drunk|whiskey shot|politic|election|church fight|gun|shoot|drug|weed|cocaine|sex)\b/i

test('LO1 the lore library stays small, short, plain ASCII and work appropriate', { timeoutMs: 120_000 }, () => {
  expect(LORE.length).toBeGreaterThan(10)
  expect(LORE.length).toBeLessThanOrEqual(LORE_MAX)
  expect(new Set(LORE).size).toBe(LORE.length)
  for (const entry of LORE) {
    expect(entry.length, entry).toBeLessThanOrEqual(LORE_ENTRY_MAX)
    expect(/^[\x20-\x7e]+$/.test(entry), entry).toBe(true)
    expect(OFF_LIMITS.test(entry), entry).toBe(false)
    expect(isClean(entry), entry).toBe(true)
  }
})

test('LO2 each drop gets three distinct lore notes, stable for a slot and rotating across slots', { timeoutMs: 120_000 }, () => {
  const day = new Date(2026, 9, 23, 9)
  const nine = lorePicks(day, 9)
  expect(nine.length).toBe(LORE_PICKS)
  expect(new Set(nine).size).toBe(LORE_PICKS)
  expect(lorePicks(day, 9)).toEqual(nine)
  const noon = lorePicks(new Date(2026, 9, 23, 12), 12)
  expect(noon).not.toEqual(nine)
  expect(lorePicks(day, 9, [])).toEqual([])
  expect(lorePicks(day, 9, ['only one'])).toEqual(['only one'])
})

test('LO3 the prompt carries the lore and the system prompt says everything is only an example', () => {
  const input = {
    now: new Date(2026, 9, 23, 9),
    slot: 9,
    level: 1,
    season: 'fall',
    farm: { jars: 0, ripe: { tobacco: 0, corn: 0, apples: 0 }, upgrades: 0, unlocks: 0 },
    recent: [],
    arc: null,
    isArcOpen: true,
    artIds: [],
    total: 0,
  } as unknown as Parameters<typeof promptOf>[0]
  const prompt = promptOf(input)
  expect(prompt).toContain('Some lore you may draw on, or not:')
  for (const entry of lorePicks(input.now, input.slot)) {
    expect(prompt).toContain(entry)
  }
  const system = systemPrompt(1)
  expect(system).toContain('is an example, not a list to stay inside')
  expect(system).toContain('work appropriate')
})
