// How much Jeb talks: `chatty` is every line he has, `ambient` (the default)
// spends one on a busy stretch every ten minutes and keeps the milestones,
// `silent` leaves the bubble on the last line.
export type Talk = 'chatty' | 'ambient' | 'silent'

export const TALK_LEVELS: readonly Talk[] = ['chatty', 'ambient', 'silent']

// The userConfig fields, read with their defaults: the creative drops are on
// until switched off, and Jeb talks ambient. The hook reactions a security plugin
// may skip are off until switched on.
export type JebOptions = {
  creativity: boolean
  talk: Talk
  hookReactions: boolean
}

export const readOptions = (raw: Readonly<Record<string, unknown>> | undefined): JebOptions => ({
  creativity: raw?.creativity !== false,
  talk: TALK_LEVELS.find(level => level === raw?.talk) ?? 'ambient',
  hookReactions: raw?.hookReactions === true,
})
