import type { Farm, KeptSession, SessionRec, SquareCode } from '../types'
import { MAX_LINE } from './camps'
import { cleanText, dateKeyOf, plural, recordOf } from './util'

// The session quilt and the journal: what a session did, as one colored square and
// one line. Pure; the store calls and the clock live in register.tsx.

export const QUILT_MAX = 200
export const JOURNAL_MAX = 60
export const STITCHED_MAX = 64
export const MAX_CAMP = 24
const COUNTER_CAP = 99_999
const SALES_CAP = 1_000_000_000
const MAX_BUILT = 3
const MAX_ID = 64

export const CODES: readonly SquareCode[] = ['B', 'R', 'G', 'P', 'Y', 'N']

// Every glyph here is default emoji presentation with no variation selector, and
// is listed in WIDE (canvas.ts). `reason` ends "Granny stitched a <color> square.
// <reason>!" and is short enough for the bubble's two lines of 22.
export const SQUARES: Record<SquareCode, { glyph: string; color: string; label: string; reason: string }> = {
  B: { glyph: '🟦', color: 'blue', label: 'shipping', reason: 'Shipped' },
  R: { glyph: '🟥', color: 'red', label: 'rough days', reason: 'Rough day' },
  G: { glyph: '🟩', color: 'green', label: 'tests', reason: 'Tested' },
  P: { glyph: '🟪', color: 'purple', label: 'agents', reason: 'Hired' },
  Y: { glyph: '🟨', color: 'yellow', label: 'weeding', reason: 'Weeded' },
  N: { glyph: '🟫', color: 'brown', label: 'field work', reason: 'Worked' },
}

export const isCode = (value: unknown): value is SquareCode =>
  typeof value === 'string' && CODES.includes(value as SquareCode)

export const stitchLine = (code: SquareCode) =>
  `Granny stitched a ${SQUARES[code].color} square. ${SQUARES[code].reason}!`

export type { SessionRec }

export type Counter = Exclude<keyof SessionRec, 'built' | 'camp' | 'startedAt'>

export const freshSession = (startedAt = 0, camp = ''): SessionRec => ({
  ships: 0,
  testsPassed: 0,
  testsFailed: 0,
  lintRuns: 0,
  lintFailed: 0,
  edits: 0,
  agents: 0,
  sales: 0,
  harvests: 0,
  jars: 0,
  sours: 0,
  rough: 0,
  calls: 0,
  turns: 0,
  built: [],
  camp,
  startedAt,
})

export const bump = (session: SessionRec, key: Counter, by = 1) => {
  const add = Math.max(0, Math.floor(Number(by)) || 0)
  session[key] = Math.min(key === 'sales' ? SALES_CAP : COUNTER_CAP, session[key] + add)
}

export const noteBuilt = (session: SessionRec, phrase: string) => {
  const text = cleanText(phrase, 40)
  if (text !== '' && !session.built.includes(text) && session.built.length < MAX_BUILT) {
    session.built.push(text)
  }
}

// The counters of a session record, in the order the `kept` atom holds them.
export const COUNTER_KEYS: readonly Counter[] = [
  'ships',
  'testsPassed',
  'testsFailed',
  'lintRuns',
  'lintFailed',
  'edits',
  'agents',
  'sales',
  'harvests',
  'jars',
  'sours',
  'rough',
  'calls',
  'turns',
]

// A session's id and record as the `kept` atom holds them.
export const keepOf = (id: string, rec: SessionRec): KeptSession => ({
  id,
  counts: COUNTER_KEYS.map(key => rec[key]),
  built: [...rec.built],
  startedAt: rec.startedAt,
})

// A session record read back from the `kept` atom, field by field: every counter
// a whole number within its cap, at most three short phrases built. The camp is
// left for the caller. An id that is not a sane string reads as nothing.
export const keptOf = (saved: unknown): { id: string; rec: SessionRec } | undefined => {
  const item = recordOf(saved)
  if (typeof item.id !== 'string' || item.id === '' || item.id.length > MAX_ID) {
    return undefined
  }
  const counts = Array.isArray(item.counts) ? item.counts : []
  const rec = freshSession()
  COUNTER_KEYS.forEach((key, i) => {
    const n = Math.floor(Number(counts[i]))
    rec[key] = Number.isFinite(n) && n > 0 ? Math.min(key === 'sales' ? SALES_CAP : COUNTER_CAP, n) : 0
  })
  const started = Number(item.startedAt)
  rec.startedAt = Number.isFinite(started) && started > 0 ? started : 0
  for (const phrase of Array.isArray(item.built) ? item.built : []) {
    noteBuilt(rec, String(phrase))
  }

  return { id: item.id, rec }
}

// The square a session earns, or null for one with no tool calls and no turns.
// Blue always wins when anything shipped; then red; then the top count of tests
// passed, agents, lint runs and edits, ties going to the earlier of those (edits
// on top, or nothing at all, is brown).
export const squareFor = (s: SessionRec): SquareCode | null => {
  if (s.calls === 0 && s.turns === 0) {
    return null
  }
  if (s.ships >= 1) {
    return 'B'
  }
  if (s.rough >= 5 && s.rough > s.testsPassed + s.ships) {
    return 'R'
  }
  const top = Math.max(s.testsPassed, s.agents, s.lintRuns, s.edits)
  if (top > 0) {
    if (s.testsPassed === top) {
      return 'G'
    }
    if (s.agents === top) {
      return 'P'
    }
    if (s.lintRuns === top) {
      return 'Y'
    }
  }

  return 'N'
}

// How busy a session was, to find the busiest.
export const scoreOf = (s: SessionRec) =>
  s.ships * 5 +
  s.testsPassed +
  s.testsFailed +
  s.lintRuns +
  s.edits +
  s.agents * 2 +
  s.harvests * 3 +
  s.jars * 2

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

// The local date as 'YYYY-MM-DD'.
export const dateKey = dateKeyOf

// Whether a string is a real calendar date written 'YYYY-MM-DD'.
export const isDateKey = (value: unknown): value is string => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false
  }
  const [y, m, d] = value.split('-').map(Number) as [number, number, number]
  const at = new Date(Date.UTC(y, m - 1, d))

  return at.getUTCFullYear() === y && at.getUTCMonth() === m - 1 && at.getUTCDate() === d
}

// 'Oct 22'.
export const dayLabel = (key: string) => {
  const [, m = '1', d = '1'] = key.split('-')

  return `${MONTHS[Number(m) - 1] ?? 'Jan'} ${Number(d)}`
}

// "api camp"; a name that does not start like a word (.claude) stands as it is.
export const campLabel = (camp: string) => (/^[A-Za-z0-9]/.test(camp) ? `${camp} camp` : camp)

const MAX_PARTS = 4

// One line for a session, in Jeb's voice, from counts, the camp's name and the
// names of what he built, joining only what is not zero: "Oct 22 · api camp · 3
// loads out, rain twice, 1 sour batch". `isToday` swaps the date for "today" (the
// line in progress). Never any ticket text, command or path.
export const journalLine = (s: SessionRec, date: Date, isToday = false) => {
  const parts: string[] = [...s.built]
  if (s.ships > 0) {
    parts.push(`${plural(s.ships, 'load')} out`)
  }
  if (s.testsPassed > 0) {
    parts.push(`rain ${s.testsPassed === 1 ? 'once' : s.testsPassed === 2 ? 'twice' : `${s.testsPassed} times`}`)
  }
  if (s.testsFailed > 0) {
    parts.push(plural(s.testsFailed, 'dry spell'))
  }
  if (s.lintRuns > 0) {
    parts.push(s.lintRuns >= 6 ? 'weeded all day' : `${plural(s.lintRuns, 'row')} hoed`)
  }
  if (s.lintFailed > 0) {
    parts.push('found blight')
  }
  if (s.sours > 0) {
    parts.push(`${s.sours} sour ${s.sours === 1 ? 'batch' : 'batches'}`)
  }
  if (s.harvests > 0) {
    parts.push(`${plural(s.harvests, 'harvest')} in`)
  }
  if (s.jars > 0) {
    parts.push(`${plural(s.jars, 'jar')} put up`)
  }
  if (s.agents > 0) {
    parts.push(`${plural(s.agents, 'hand')} hired`)
  }
  if (s.sales > 0) {
    parts.push(`$${s.sales} in sales`)
  }
  const body = parts.length > 0 ? parts.slice(0, MAX_PARTS).join(', ') : 'quiet day, mended a fence'
  const when = isToday ? 'today' : dayLabel(dateKey(date))
  const camp = cleanText(s.camp, MAX_CAMP) || 'camp'

  return cleanText(`${when} · ${campLabel(camp)} · ${body}`, MAX_LINE)
}

// What a heartbeat carries for this session: the square's letter and score, and
// the line so far. Nothing for a session with no square.
export const markFor = (s: SessionRec, date: Date) => {
  const code = squareFor(s)

  return code ? { sq: `${code}${scoreOf(s)}`, ln: journalLine(s, date) } : undefined
}

export type Stitch = { id: string; c: SquareCode; d: string; camp: string; line: string; score: number }

// The square and line a finished session leaves, or nothing for an idle one.
export const stitchOf = (s: SessionRec, date: Date, id: string): Stitch | undefined => {
  const c = squareFor(s)

  return c
    ? {
        id,
        c,
        d: dateKey(date),
        camp: cleanText(s.camp, MAX_CAMP) || 'camp',
        line: journalLine(s, date),
        score: scoreOf(s),
      }
    : undefined
}

// A square from a dead session's heartbeat: its last known letter, score and
// line, dated by when it last beat.
export const stitchFromBeat = (
  stale: { id: string; name: string; lastSeen: number; sq: string; ln: string },
): Stitch => ({
  id: stale.id,
  c: stale.sq.charAt(0) as SquareCode,
  d: dateKey(new Date(stale.lastSeen)),
  camp: cleanText(stale.name, MAX_CAMP) || 'camp',
  line: cleanText(stale.ln, MAX_LINE),
  score: Number(stale.sq.slice(1)) || 0,
})

// Stitches onto the farm as stored: a session already stitched (by id) is left
// out, so a square goes up once however many sessions try. Which ones went up is
// in `added`.
export const stitchFarm = (old: Farm, stitches: readonly Stitch[]): { next: Farm; added: Stitch[] } => {
  const added: Stitch[] = []
  let next = old
  for (const st of stitches) {
    if (next.stitched.includes(st.id) || !isCode(st.c) || !isDateKey(st.d)) {
      continue
    }
    added.push(st)
    next = {
      ...next,
      quilt: [...next.quilt, { c: st.c, d: st.d, camp: st.camp }].slice(-QUILT_MAX),
      journal: [...next.journal, { d: st.d, camp: st.camp, line: st.line }].slice(-JOURNAL_MAX),
      sessionsWorked: Math.min(1_000_000_000, next.sessionsWorked + 1),
      sessionsShipped: Math.min(1_000_000_000, next.sessionsShipped + (st.c === 'B' ? 1 : 0)),
      busiest:
        st.score > (next.busiest?.score ?? 0) ? { d: st.d, camp: st.camp, score: st.score } : next.busiest,
      stitched: [...next.stitched, st.id].slice(-STITCHED_MAX),
    }
  }

  return { next, added }
}






