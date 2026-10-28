import type { Camps } from '../types'
import { cleanText, recordOf } from './util'

// Parallel sessions: each one leaves a heartbeat in the store and reads the
// others' to hang a lantern for each. Pure; the store calls live in register.tsx.

export const MAX_CAMPS = 8
export const CAMP_TTL_MS = 180_000
export const BEAT_MS = 60_000
const MAX_NAME = 24
const MAX_ID = 64
export const MAX_LINE = 120
const MARK = /^[BRGPYN]\d{1,9}$/

const cleanName = (value: unknown) => cleanText(value, MAX_NAME)

// A heartbeat's square and journal line: both well-formed, or neither.
const markOf = (item: Record<string, unknown>) => {
  const sq = typeof item.sq === 'string' && MARK.test(item.sq) ? item.sq : undefined
  const ln = cleanText(typeof item.ln === 'string' ? item.ln : '', MAX_LINE)

  return sq && ln !== '' ? { sq, ln } : {}
}

// One stored heartbeat read back: a sane id, a name and a time, and the square
// and line it carries (both well-formed, or neither). Nothing when it is not one.
const readCamp = (id: string, entry: unknown) => {
  const item = recordOf(entry)
  const lastSeen = Number(item.lastSeen)
  const name = cleanName(item.name)

  return id.length > 0 && id.length <= MAX_ID && name !== '' && Number.isFinite(lastSeen)
    ? { id, name, lastSeen, mark: markOf(item) }
    : undefined
}

// The stored heartbeats that read back well, at most 64 looked at.
const campsIn = (saved: unknown) =>
  Object.entries(recordOf(saved))
    .slice(0, 64)
    .flatMap(([id, entry]) => {
      const camp = readCamp(id, entry)

      return camp ? [camp] : []
    })

// Reads the stored heartbeats back: only well-formed entries, none older than
// the TTL (or from the future), at most MAX_CAMPS, the newest kept.
export const loadCamps = (saved: unknown, nowMs: number): Camps => {
  const found = campsIn(saved)
    .filter(camp => camp.lastSeen > nowMs - CAMP_TTL_MS && camp.lastSeen <= nowMs + CAMP_TTL_MS)
    .sort((a, b) => b.lastSeen - a.lastSeen)

  return Object.fromEntries(
    found.slice(0, MAX_CAMPS).map(camp => [camp.id, { name: camp.name, lastSeen: camp.lastSeen, ...camp.mark }]),
  )
}

// This session's heartbeat merged into what is stored; it always survives.
export const beat = (
  saved: unknown,
  id: string,
  name: string,
  nowMs: number,
  mark?: { sq: string; ln: string },
): Camps => {
  const others = loadCamps(saved, nowMs)
  delete others[id]
  const kept = Object.entries(others).slice(0, MAX_CAMPS - 1)

  return {
    [id]: { name: cleanName(name) || 'camp', lastSeen: nowMs, ...(mark ? markOf(mark) : {}) },
    ...Object.fromEntries(kept),
  }
}

// A session that died without saying goodbye: its heartbeat is older than the
// TTL and still carries a square and a line. Never `selfId`, at most 8, once each.
export type Stale = { id: string; name: string; lastSeen: number; sq: string; ln: string }

export const staleOf = (saved: unknown, selfId: string, nowMs: number): Stale[] =>
  campsIn(saved)
    .flatMap(({ id, name, lastSeen, mark }) =>
      id !== selfId && 'sq' in mark && lastSeen > 0 && lastSeen <= nowMs - CAMP_TTL_MS
        ? [{ id, name, lastSeen, sq: mark.sq as string, ln: mark.ln as string }]
        : [],
    )
    .slice(0, MAX_CAMPS)

// The stored heartbeats split by who wrote them: the entries whose key `isOurs`
// says this Jeb writes (a hashed key), which are kept, and the rest (a Jeb from
// before the anonymizer, keyed by a raw session id), which are never written back:
// only the camp names of the ones still alive come back, for the lanterns.
export const splitCamps = (saved: unknown, isOurs: (id: string) => boolean, nowMs: number) => {
  const ours: Record<string, unknown> = {}
  for (const [id, entry] of Object.entries(recordOf(saved)).slice(0, 64)) {
    if (isOurs(id)) {
      ours[id] = entry
    }
  }
  const legacy = Object.entries(loadCamps(saved, nowMs))
    .filter(([id]) => !isOurs(id))
    .map(([, camp]) => camp.name)

  return { ours, legacy }
}

// This session's heartbeat taken out.
export const without = (saved: unknown, id: string, nowMs: number): Camps => {
  const others = loadCamps(saved, nowMs)
  delete others[id]

  return others
}

// The other live sessions' camp names, oldest-named first, one per session.
export const othersOf = (camps: Camps, id: string): string[] =>
  Object.entries(camps)
    .filter(([key]) => key !== id)
    .map(([, camp]) => camp.name)
    .sort()

// "the api camp", "the api and web camps", "the api, web and docs camps".
export const campList = (names: readonly string[]) => {
  const list =
    names.length <= 1
      ? (names[0] ?? '')
      : `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`

  return `the ${list} camp${names.length === 1 ? '' : 's'}`
}

export const lanternLine = (names: readonly string[]) => `Lanterns lit over at ${campList(names)}.`

// A session's camp: the worktree folder's name, else the repository's. This is
// the raw name: it is never stored or shown as it is, only the place the
// anonymizer makes of it (see anonymize.ts).
export const campName = (root: string, repo: { root: string; name: string | null } | null, cwd: string) => {
  const base = (path: string) => path.replace(/\/+$/, '').split('/').pop() ?? ''
  const isWorktree = repo !== null && root !== '' && repo.root !== root

  return cleanName(
    (isWorktree ? base(root) : repo ? (repo.name?.split('/').pop() ?? base(repo.root)) : base(root || cwd)) ||
      'camp',
  )
}
