import type { DropZone } from '../types'
import { secureHex, sipHash, utf8 } from './anonymize'
import type { Segment } from './classify'
import { seededRng } from './offline'
import { commandOf, segmentsOf } from './ship'
import { CLAIM_TTL_MS } from './drops'
import { DROP_SPRITE_NAMES, DROP_SPRITES, isClean, LINE_MAX, ZONES } from './surprise'
import { dateKeyOf, pickWeighted, recordOf } from './util'

// Areas: each project the person works in becomes a remembered place in Jeb's
// world, with its own theme. Pure: nothing here asks the host; the store calls
// and the one model call live in register.tsx and signals.ts.
//
// What leaves the hook about the work is an opaque key (8 hex of a keyed hash of
// the project's identity, never stored or logged) and coarse enums: eight kinds
// of work, bucketed low, mid or high, only after 30 counted events. Names, paths,
// extensions, commands and text are read here only to pick a kind and are never
// kept. The model is given the key's seeded choices, those enums and a bible of
// earlier areas (enum stubs and names); it writes only the lore and the beats.

// ---- the fixed vocabulary ----

export const WORK_KINDS = ['testing', 'building', 'docs', 'data', 'frontend', 'backend', 'infra', 'tooling'] as const
export type WorkKind = (typeof WORK_KINDS)[number]
export type Bucket = 'low' | 'mid' | 'high'
export type AreaProfile = { kind: WorkKind; level: Bucket }[]

export const TERRAINS = ['holler', 'ridge', 'creek', 'orchard', 'meadow', 'quarry', 'woods', 'bottomland', 'bald', 'mill'] as const
export const PALETTES = ['moss', 'amber', 'slate', 'rose', 'ember', 'frost', 'dusk', 'clay'] as const
export const WEATHERS = ['clear', 'fog', 'drizzle', 'breeze', 'hazy', 'snowy'] as const
export const MOODS = ['dawn', 'noon', 'gold', 'dusk', 'night'] as const
export const MOTIFS = ['bird', 'fire', 'water', 'light', 'song', 'wind'] as const
export const SUFFIXES = ['Holler', 'Gap', 'Run', 'Knob', 'Bottom', 'Fork'] as const

export type Terrain = (typeof TERRAINS)[number]
export type Palette = (typeof PALETTES)[number]
export type Weather = (typeof WEATHERS)[number]
export type Mood = (typeof MOODS)[number]
export type Motif = (typeof MOTIFS)[number]

export const AREA_VERSION = 1
// The model: three calls a day (an area and its retry, and one more), counted
// apart from the drops' six.
export const AREA_DAILY_CAP = 3
export const AREA_MAX = 24
export const AREA_CLAIMS_MAX = 3
// The counted events a project needs before it has a profile (and an area).
export const AREA_MIN_EVENTS = 30
export const BIBLE_MAX = 6
export const NAME_MAX = 16
export const LORE_MIN = 2
export const LORE_MAX = 4
export const BEATS_MIN = 3
export const BEATS_MAX = 6
export const PROPS_MIN = 3
export const PROPS_MAX = 5
export const SPRITES_RECORD_MAX = 8
export const AREA_BYTES_MAX = 1536
export const AREA_TOKEN_CAP = 1600
// The most events one project's counters hold before they are halved.
const WORK_COUNT_MAX = 100_000
const HYSTERESIS_POINTS = 10

export const AREA_KEY_RE = /^[0-9a-f]{8}$/
const SECRET_RE = /^[0-9a-f]{64}$/
const DAY_RE = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/
const NAME_RE = /^[A-Za-z]{2,12}( [A-Za-z]{2,7})?$/

const isDay = (value: unknown): value is string => typeof value === 'string' && DAY_RE.test(value)
const isIn = <T extends string>(list: readonly T[], value: unknown): value is T => list.includes(value as T)

// ---- the secret and the key ----

export const isAreaSecret = (value: unknown): value is string => typeof value === 'string' && SECRET_RE.test(value)

// 32 random bytes as hex, from the CSPRNG, or from a 0-1 source a test passes.
export const mintAreaSecret = (rng?: () => number) =>
  rng === undefined
    ? secureHex(64)
    : Array.from({ length: 64 }, () => Math.min(15, Math.floor(rng() * 16)).toString(16)).join('')

// The remote's URL without scheme, credentials, port or `.git`, lower-case, so a
// clone over https and one over ssh of the same repository agree.
export const normalizeRemote = (url: string) =>
  url
    .trim()
    .toLowerCase()
    .replace(/^[a-z][a-z0-9+.-]*:\/\//, '')
    .replace(/^[^/@]*@/, '')
    .replace(/^([^/:]+):\d+\//, '$1/')
    .replace(/^([^/:]+):/, '$1/')
    .replace(/\/+$/, '')
    .replace(/\.git$/, '')
    .replace(/\/+$/, '')

// The project's identity as the session knows it: the git remote, else the
// repository's root (the main working tree's for a worktree, so per-ticket
// worktrees of one repository share it), else the session's folder. It is
// hashed into the key at once and goes no further.
export const identityOf = (
  root: string,
  repo: { root: string; remote: string | null } | null,
  cwd: string,
): string => {
  const remote = repo?.remote ? normalizeRemote(repo.remote) : ''
  if (remote !== '') {
    return `remote:${remote}`
  }
  const trim = (path: string) => path.replace(/\/+$/, '')
  if (repo && trim(repo.root) !== '') {
    return `repo:${trim(repo.root)}`
  }
  const folder = trim(root) || trim(cwd)

  return folder === '' ? '' : `dir:${folder}`
}

// SipHash takes a 128-bit key and the secret is 256 bits, so the identity is
// hashed twice: under the first half of the secret, then (with that hash
// appended) under the second half. Every bit of the secret is used.
const keyParts = (secret: string, at: number): [bigint, bigint] => [
  BigInt(`0x${secret.slice(at * 32, at * 32 + 16)}`),
  BigInt(`0x${secret.slice(at * 32 + 16, at * 32 + 32)}`),
]

// `areaKey`: a pseudonym, not a MAC or HMAC: 8 hex of a keyed hash (two-pass
// SipHash-2-4, the anonymizer's primitive) of the identity under the secret,
// domain-separated and truncated to 32 bits. Nothing without a secret.
export const areaKeyOf = (secret: string, identity: string): string => {
  if (!isAreaSecret(secret) || identity === '') {
    return ''
  }
  const bytes = utf8(`area:${identity}`)
  const [a0, a1] = keyParts(secret, 0)
  const [b0, b1] = keyParts(secret, 1)
  const inner = sipHash(a0, a1, bytes)
  const tail = Array.from({ length: 8 }, (_, i) => Number((inner >> BigInt(8 * i)) & 0xffn))

  return sipHash(b0, b1, [...bytes, ...tail]).toString(16).padStart(16, '0').slice(0, 8)
}

// ---- what kind of work a tool call is ----

const EXTENSIONS: Readonly<Record<string, WorkKind>> = {
  tsx: 'frontend', jsx: 'frontend', vue: 'frontend', svelte: 'frontend', css: 'frontend', scss: 'frontend', sass: 'frontend', html: 'frontend',
  php: 'backend', py: 'backend', rb: 'backend', go: 'backend', rs: 'backend', java: 'backend', cs: 'backend', kt: 'backend', ts: 'backend', js: 'backend',
  sql: 'data', csv: 'data',
  md: 'docs', mdx: 'docs', rst: 'docs', txt: 'docs',
  tf: 'infra', tfvars: 'infra',
}

// A file's kind from its path: the extension allowlist and a few well-known
// names. The path is read here and goes no further; an unknown one is nothing.
export const fileKindOf = (path: string): WorkKind | undefined => {
  const lower = path.toLowerCase()
  const name = lower.split('/').pop() ?? ''
  if (name.startsWith('dockerfile') || /^docker-compose[^/]*\.ya?ml$/.test(name) || /(^|\/)\.github\/workflows\//.test(lower)) {
    return 'infra'
  }
  if (/(^|\/)(tests?|spec|__tests__)\//.test(lower) || /(\.|_)(test|spec)\.[a-z]+$/.test(name) || /test\.php$/.test(name)) {
    return 'testing'
  }
  if (/(^|\/)(migrations|seeders|factories)\//.test(lower)) {
    return 'data'
  }
  const dot = name.lastIndexOf('.')
  const ext = dot > 0 ? name.slice(dot + 1) : ''

  return Object.hasOwn(EXTENSIONS, ext) ? EXTENSIONS[ext] : undefined
}

const BUILD_TOOLS = new Set(['make', 'cmake', 'tsc', 'vite', 'webpack', 'rollup', 'esbuild', 'gradle', 'mvn', 'cargo', 'go', 'swift', 'xcodebuild', 'turbo'])
const INFRA_TOOLS = new Set(['docker', 'docker-compose', 'terraform', 'kubectl', 'helm', 'ansible', 'ansible-playbook', 'pulumi'])
const DATA_TOOLS = new Set(['mysql', 'psql', 'sqlite3', 'redis-cli', 'mongosh', 'pg_dump', 'mysqldump'])
const TEST_TOOLS = new Set(['jest', 'vitest', 'pytest', 'phpunit', 'pest', 'rspec', 'playwright', 'cypress'])
const NODE_RUNNERS = new Set(['npm', 'pnpm', 'yarn', 'bun'])

const baseOf = (word: string | undefined) => (word ?? '').split('/').pop() ?? ''

// One command's kind from its words (and `classify`'s reading of them).
const wordsKindOf = (words: readonly string[], segment: Segment | undefined): WorkKind | undefined => {
  if (segment?.kind === 'test') {
    return 'testing'
  }
  if (segment?.kind === 'lint') {
    return 'tooling'
  }
  const name = baseOf(words[0])
  const rest = words.slice(1).filter(word => !word.startsWith('-'))
  const sub = rest[0]
  if (TEST_TOOLS.has(name)) {
    return 'testing'
  }
  if (name === 'go' || name === 'cargo') {
    return sub === 'test' ? 'testing' : sub === 'build' || sub === 'install' ? 'building' : undefined
  }
  if (NODE_RUNNERS.has(name)) {
    const script = sub === 'run' || sub === 'run-script' ? rest[1] : sub

    if (script === 'test' || script === 'jest' || script === 'vitest') {
      return 'testing'
    }
    if (script === 'build' || script === 'dev' || script === 'compile') {
      return 'building'
    }

    return script === 'install' || script === 'ci' || script === 'add' || script === 'update' ? 'tooling' : undefined
  }
  if (name === 'git' || name === 'gh') {
    return 'tooling'
  }
  if (name === 'composer') {
    return sub === 'install' || sub === 'update' || sub === 'require' ? 'tooling' : undefined
  }
  if (name === 'artisan' || (name === 'php' && baseOf(rest[0]) === 'artisan')) {
    const verb = name === 'php' ? rest[1] : sub

    return verb?.startsWith('migrate') || verb?.startsWith('db:') ? 'data' : undefined
  }
  if (DATA_TOOLS.has(name)) {
    return 'data'
  }
  if (BUILD_TOOLS.has(name)) {
    return name === 'make' || name === 'tsc' || name === 'vite' || name === 'webpack' || sub === 'build' || sub === undefined ? 'building' : undefined
  }
  if (INFRA_TOOLS.has(name) || (segment?.kind === 'exec' && segment.sub !== undefined && segment.sub !== 'exec' && segment.sub !== 'run')) {
    return 'infra'
  }

  return undefined
}

const FILE_TOOLS = new Set(['Read', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Grep', 'Glob'])

// The kind one tool call counts toward, or nothing: a shell command by its
// words, a file tool by its path's extension class. The first part of a command
// that has a kind gives it. Nothing is kept of the command or the path.
export const workKindOf = (
  tool: string,
  command: string,
  segments: readonly Segment[],
  input: Readonly<Record<string, unknown>>,
): WorkKind | undefined => {
  if (tool === 'Bash') {
    const parts = segmentsOf(command).filter(words => words.length > 0)
    for (let i = 0; i < parts.length; i += 1) {
      const found = wordsKindOf(commandOf(parts[i] as string[]), segments[i])
      if (found) {
        return found
      }
    }

    return undefined
  }

  const path = [input.file_path, input.notebook_path, input.path].find(one => typeof one === 'string' && one !== '')

  return FILE_TOOLS.has(tool) && typeof path === 'string' ? fileKindOf(path) : undefined
}

// ---- the profile ----

// What is counted for one project: events by kind, their total, the last day it
// was worked in, and the kinds that held the top three at the last look.
export type WorkEntry = { kinds: Partial<Record<WorkKind, number>>; n: number; seen: string; top?: WorkKind[] }
export type WorkMap = Record<string, WorkEntry>

const count = (value: unknown, max: number) => {
  const n = Math.floor(Number(value))

  return Number.isFinite(n) && n > 0 ? Math.min(max, n) : 0
}

const workEntryOf = (value: unknown): WorkEntry | undefined => {
  const item = recordOf(value)
  const raw = recordOf(item.kinds)
  const kinds: Partial<Record<WorkKind, number>> = {}
  for (const kind of WORK_KINDS) {
    const n = count(raw[kind], WORK_COUNT_MAX)
    if (n > 0) {
      kinds[kind] = n
    }
  }
  const top = (Array.isArray(item.top) ? item.top : []).filter((kind): kind is WorkKind => isIn(WORK_KINDS, kind)).slice(0, 3)
  if (!isDay(item.seen)) {
    return undefined
  }
  const n = Object.values(kinds).reduce((sum, one) => sum + one, 0)

  return { kinds, n, seen: item.seen, ...(top.length > 0 ? { top: [...new Set(top)] } : {}) }
}

// At most 24 entries, in their order: past the cap the oldest by day are let go.
const keepNewest = <T>(entries: readonly T[], dayOf: (entry: T) => string): T[] => {
  if (entries.length <= AREA_MAX) {
    return [...entries]
  }
  const cut = [...entries].sort((a, b) => dayOf(b).localeCompare(dayOf(a))).slice(0, AREA_MAX)

  return entries.filter(entry => cut.includes(entry))
}

// The stored counters read back: well-formed keys and entries only, at most 24.
export const areaWorkOf = (value: unknown): WorkMap => {
  const found: WorkMap = {}
  for (const [key, entry] of Object.entries(recordOf(value))) {
    const one = AREA_KEY_RE.test(key) ? workEntryOf(entry) : undefined
    if (one) {
      found[key] = one
    }
  }

  return Object.fromEntries(keepNewest(Object.entries(found), entry => entry[1].seen))
}

// The map without the entries named.
export const withoutWork = (work: WorkMap, keys: readonly string[]): WorkMap =>
  Object.fromEntries(Object.entries(work).filter(([key]) => !keys.includes(key)))

// Adds some counted events to a project (the counters are halved when they
// reach their cap) and notes the day; past 24 projects the least recently seen
// other one is let go.
export const countWork = (
  work: WorkMap,
  key: string,
  adds: Readonly<Partial<Record<WorkKind, number>>>,
  day: string,
): WorkMap => {
  const old = work[key]
  const kinds: Partial<Record<WorkKind, number>> = { ...old?.kinds }
  for (const kind of WORK_KINDS) {
    const add = count(adds[kind], WORK_COUNT_MAX)
    if (add > 0) {
      kinds[kind] = (kinds[kind] ?? 0) + add
    }
  }
  let n = Object.values(kinds).reduce((sum, one) => sum + one, 0)
  if (n > WORK_COUNT_MAX) {
    for (const kind of WORK_KINDS) {
      if (kinds[kind] !== undefined) {
        kinds[kind] = Math.floor((kinds[kind] as number) / 2)
      }
    }
    n = Object.values(kinds).reduce((sum, one) => sum + one, 0)
  }
  const next: WorkMap = { ...work, [key]: { kinds, n, seen: day, ...(old?.top ? { top: old.top } : {}) } }
  const others = Object.entries(next)
    .filter(([other]) => other !== key)
    .sort((a, b) => a[1].seen.localeCompare(b[1].seen))
  for (const [other] of others.slice(0, Math.max(0, Object.keys(next).length - AREA_MAX))) {
    delete next[other]
  }

  return next
}

export const bucketOf = (share: number): Bucket => (share > 50 ? 'high' : share >= 20 ? 'mid' : 'low')

// The profile of a project: its top three kinds, each bucketed by its share of
// the counted events. Nothing until 30 events. A kind enters the top three when
// it is 10 points over the weakest member, and one leaves when it is 10 points
// under the strongest outsider (the same swap), so the profile holds steady;
// ties go by the fixed order of the kinds. `top` is the membership to keep.
export const profileOf = (entry: WorkEntry | undefined): { profile: AreaProfile; top: WorkKind[] } | undefined => {
  if (!entry || entry.n < AREA_MIN_EVENTS) {
    return undefined
  }
  const share = (kind: WorkKind) => ((entry.kinds[kind] ?? 0) * 100) / entry.n
  const ranked = WORK_KINDS.filter(kind => (entry.kinds[kind] ?? 0) > 0).sort((a, b) => share(b) - share(a))
  const top = (entry.top ?? []).filter(kind => ranked.includes(kind))
  for (const kind of ranked) {
    if (top.length < 3 && !top.includes(kind)) {
      top.push(kind)
    }
  }
  for (let round = 0; round < 3; round += 1) {
    const outsider = ranked.find(kind => !top.includes(kind))
    const weakest = [...top].sort((a, b) => share(a) - share(b))[0]
    if (outsider === undefined || weakest === undefined || share(outsider) - share(weakest) < HYSTERESIS_POINTS) {
      break
    }
    top[top.indexOf(weakest)] = outsider
  }
  const ordered = [...top].sort((a, b) => share(b) - share(a) || WORK_KINDS.indexOf(a) - WORK_KINDS.indexOf(b))

  return { profile: ordered.map(kind => ({ kind, level: bucketOf(share(kind)) })), top }
}

// ---- the seeded choices ----

// What each kind of work leans toward (a bias, never a rule).
const LEAN: Readonly<Record<WorkKind, { terrain: readonly Terrain[]; palette: readonly Palette[]; weather: readonly Weather[]; mood: readonly Mood[]; motif: readonly Motif[] }>> = {
  testing: { terrain: ['creek', 'quarry'], palette: ['frost', 'slate'], weather: ['clear', 'fog'], mood: ['dawn', 'noon'], motif: ['water', 'light'] },
  building: { terrain: ['mill', 'quarry'], palette: ['clay', 'ember'], weather: ['clear', 'hazy'], mood: ['noon', 'gold'], motif: ['fire', 'wind'] },
  docs: { terrain: ['orchard', 'meadow'], palette: ['rose', 'amber'], weather: ['breeze', 'clear'], mood: ['gold', 'dawn'], motif: ['song', 'bird'] },
  data: { terrain: ['bottomland', 'creek'], palette: ['slate', 'moss'], weather: ['fog', 'drizzle'], mood: ['dusk', 'night'], motif: ['water', 'light'] },
  frontend: { terrain: ['meadow', 'orchard'], palette: ['rose', 'dusk'], weather: ['breeze', 'clear'], mood: ['gold', 'noon'], motif: ['bird', 'song'] },
  backend: { terrain: ['holler', 'woods'], palette: ['moss', 'clay'], weather: ['fog', 'drizzle'], mood: ['dusk', 'night'], motif: ['fire', 'wind'] },
  infra: { terrain: ['ridge', 'bald', 'mill'], palette: ['slate', 'frost'], weather: ['snowy', 'hazy'], mood: ['night', 'dawn'], motif: ['wind', 'light'] },
  tooling: { terrain: ['mill', 'woods'], palette: ['amber', 'ember'], weather: ['breeze', 'hazy'], mood: ['noon', 'gold'], motif: ['fire', 'song'] },
}

// Props that go with a terrain, and the pool every prop comes from (all of them
// built-in sprites; Granny, money, cake and the like stay out).
const PROP_POOL: readonly string[] = [
  'cow', 'hen', 'pup', 'turkey', 'groundhog', 'deer', 'cardinal', 'bluebird', 'owl', 'butterfly', 'firefly', 'mug', 'postcard',
  'rainbow', 'puddle', 'bell', 'lantern', 'cloud', 'birdhouse', 'jar', 'apples', 'corn', 'bale', 'lumber', 'stone', 'note',
]
const TERRAIN_PROPS: Readonly<Record<Terrain, readonly string[]>> = {
  holler: ['lantern', 'owl', 'pup', 'jar'],
  ridge: ['cloud', 'bluebird', 'bell', 'deer'],
  creek: ['puddle', 'stone', 'bluebird', 'firefly'],
  orchard: ['apples', 'birdhouse', 'butterfly', 'bale'],
  meadow: ['butterfly', 'cow', 'bale', 'rainbow'],
  quarry: ['stone', 'lumber', 'owl', 'bell'],
  woods: ['deer', 'groundhog', 'owl', 'firefly'],
  bottomland: ['corn', 'hen', 'turkey', 'bale'],
  bald: ['cloud', 'rainbow', 'note', 'cardinal'],
  mill: ['bell', 'corn', 'lumber', 'mug'],
}

const LEVEL_WEIGHT: Readonly<Record<Bucket, number>> = { high: 4, mid: 2, low: 1 }

// One value of a list, the favoured ones heavier: base weight 1 each, and the
// profile's kinds add theirs to what they lean toward.
const drawOf = <T extends string>(
  list: readonly T[],
  rng: () => number,
  profile: AreaProfile,
  lean: (kind: WorkKind) => readonly T[],
  extra: readonly T[] = [],
): T => {
  const pool = list.map(value => ({
    value,
    weight:
      1 +
      (extra.includes(value) ? 3 : 0) +
      profile.reduce((sum, one) => sum + (lean(one.kind).includes(value) ? LEVEL_WEIGHT[one.level] : 0), 0),
  }))

  return (pickWeighted(pool, rng)?.value ?? list[0]) as T
}

// Name syllables: plain, lower-case, two to four letters.
export const AREA_SYLLABLES: readonly string[] = [
  'ash', 'bar', 'bel', 'bri', 'cal', 'cam', 'cher', 'dal', 'dov', 'eld', 'elm', 'fai', 'fen', 'fox', 'gil', 'glen',
  'gra', 'hal', 'haz', 'ire', 'jas', 'jun', 'kel', 'kin', 'lau', 'lin', 'lor', 'mab', 'mar', 'mel', 'mon', 'nan',
  'ned', 'oro', 'ott', 'pal', 'pea', 'pip', 'quen', 'rad', 'red', 'rin', 'rob', 'sal', 'sas', 'sey', 'sil', 'tal',
  'tam', 'tay', 'tho', 'tul', 'ula', 'val', 'vel', 'wil', 'win', 'wren', 'yar', 'yel', 'zan', 'cor', 'dru', 'bram',
]

const NAMES_FALLBACK: readonly string[] = ['Elmwren Run', 'Sassal Gap', 'Tamelin Fork', 'Penwil Knob']

// A place's name: two or three syllables, and often a suffix; letters and a
// space, at most 16 characters, and clean.
export const nameOf = (rng: () => number): string => {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const parts = rng() < 0.6 ? 2 : 3
    const syllables = Array.from({ length: parts }, () => AREA_SYLLABLES[Math.floor(rng() * AREA_SYLLABLES.length)] as string)
    const base = syllables.join('')
    const word = `${base.charAt(0).toUpperCase()}${base.slice(1)}`
    const suffix = rng() < 0.65 ? (SUFFIXES[Math.floor(rng() * SUFFIXES.length)] as string) : ''
    const name = suffix !== '' && word.length + 1 + suffix.length <= NAME_MAX ? `${word} ${suffix}` : word
    if (NAME_RE.test(name) && name.length <= NAME_MAX && isClean(name)) {
      return name
    }
  }

  return NAMES_FALLBACK[Math.floor(rng() * NAMES_FALLBACK.length)] as string
}

export type Choices = {
  name: string
  terrain: Terrain
  palette: Palette
  weather: Weather
  mood: Mood
  motif: Motif
  props: string[]
}

// What the key decides, drawn by a PRNG seeded by it and leaned by the profile:
// the same key and profile always give the same choices.
export const choicesOf = (key: string, profile: AreaProfile = []): Choices => {
  const rng = seededRng(Number.parseInt(key, 16) || 1)
  const terrain = drawOf(TERRAINS, rng, profile, kind => LEAN[kind].terrain)
  const palette = drawOf(PALETTES, rng, profile, kind => LEAN[kind].palette)
  const weather = drawOf(WEATHERS, rng, profile, kind => LEAN[kind].weather)
  const mood = drawOf(MOODS, rng, profile, kind => LEAN[kind].mood)
  const motif = drawOf(MOTIFS, rng, profile, kind => LEAN[kind].motif)
  const props: string[] = []
  const want = PROPS_MIN + (rng() < 0.5 ? 1 : 0)
  while (props.length < want) {
    const one = drawOf(
      PROP_POOL.filter(name => !props.includes(name)),
      rng,
      [],
      () => [],
      TERRAIN_PROPS[terrain],
    )
    props.push(one)
  }

  return { name: nameOf(rng), terrain, palette, weather, mood, motif, props }
}

// ---- the area ----

export type Beat = { line: string; prop?: string; zone: DropZone }
export type Area = {
  v: typeof AREA_VERSION
  made: 'model' | 'offline'
  day: string
  seen: string
  name: string
  terrain: Terrain
  palette: Palette
  weather: Weather
  mood: Mood
  motif: Motif
  props: string[]
  lore: string[]
  beats: Beat[]
}
export type AreaFailure = 'format' | 'choices' | 'lore' | 'beats' | 'words'
export type ValidatedArea = { ok: true; area: Area } | { ok: false; why: AreaFailure }

// eslint-disable-next-line no-control-regex
const PRINTABLE = /^[\x20-\x7e]*$/
const LINE_BAD_CHARS = /[@#`<>{}]/
const LINE_URL = /(https?|ftp):|www\.|\/\/|\b[a-z0-9-]+\.(com|net|org|io|dev|app|co|gov|edu|info)\b/i

// A line of lore or a beat: plain, printable, clean, no markup or address.
const lineWhy = (value: unknown): 'lore' | 'words' | undefined => {
  if (typeof value !== 'string' || value.trim() === '' || value.length > LINE_MAX) {
    return 'lore'
  }
  if (!PRINTABLE.test(value) || LINE_BAD_CHARS.test(value) || LINE_URL.test(value) || /^[\d\s]+$/.test(value) || !isClean(value)) {
    return 'words'
  }

  return undefined
}

const spriteZoneOk = (sprite: string, zone: DropZone) => {
  const zones = DROP_SPRITES[sprite]?.zones

  return zones === undefined || zones.includes(zone)
}

// An area as it may be stored (and as it is read back): every field in its list
// or its limits; keys it does not know are dropped, and an enum it does not know
// rejects the whole area. The same check runs on the model's and the offline
// generator's, and on the way back out of the store.
export const validateArea = (raw: unknown): ValidatedArea => {
  const item = recordOf(raw)
  const fail = (why: AreaFailure): ValidatedArea => ({ ok: false, why })
  if (item.v !== AREA_VERSION || (item.made !== 'model' && item.made !== 'offline') || !isDay(item.day) || !isDay(item.seen)) {
    return fail('format')
  }
  const { terrain, palette, weather, mood, motif } = item
  if (!isIn(TERRAINS, terrain) || !isIn(PALETTES, palette) || !isIn(WEATHERS, weather) || !isIn(MOODS, mood) || !isIn(MOTIFS, motif)) {
    return fail('format')
  }
  const name = item.name
  if (typeof name !== 'string' || name.length > NAME_MAX || !NAME_RE.test(name) || !isClean(name)) {
    return fail('format')
  }
  const props = Array.isArray(item.props) ? item.props : []
  if (
    props.length < PROPS_MIN ||
    props.length > PROPS_MAX ||
    !props.every(prop => typeof prop === 'string' && DROP_SPRITE_NAMES.includes(prop)) ||
    new Set(props).size !== props.length
  ) {
    return fail('format')
  }
  const lore = Array.isArray(item.lore) ? item.lore : []
  if (lore.length < LORE_MIN || lore.length > LORE_MAX) {
    return fail('lore')
  }
  for (const line of lore) {
    const why = lineWhy(line)
    if (why) {
      return fail(why)
    }
  }
  const beatsRaw = Array.isArray(item.beats) ? item.beats : []
  if (beatsRaw.length < BEATS_MIN || beatsRaw.length > BEATS_MAX) {
    return fail('beats')
  }
  const beats: Beat[] = []
  for (const entry of beatsRaw) {
    const one = recordOf(entry)
    const why = lineWhy(one.line)
    if (why) {
      return fail(why === 'lore' ? 'beats' : why)
    }
    if (!isIn(ZONES, one.zone)) {
      return fail('beats')
    }
    if (one.prop !== undefined && (typeof one.prop !== 'string' || !DROP_SPRITE_NAMES.includes(one.prop) || !spriteZoneOk(one.prop, one.zone))) {
      return fail('beats')
    }
    beats.push({ line: one.line as string, ...(typeof one.prop === 'string' ? { prop: one.prop } : {}), zone: one.zone })
  }
  const sprites = new Set([...(props as string[]), ...beats.flatMap(beat => (beat.prop ? [beat.prop] : []))])
  if (sprites.size > SPRITES_RECORD_MAX) {
    return fail('beats')
  }
  const area: Area = {
    v: AREA_VERSION,
    made: item.made,
    day: item.day,
    seen: item.seen,
    name,
    terrain,
    palette,
    weather,
    mood,
    motif,
    props: props as string[],
    lore: lore as string[],
    beats,
  }

  return JSON.stringify(area).length > AREA_BYTES_MAX ? fail('format') : { ok: true, area }
}

// A stored area read back, or nothing when it does not read as one.
export const storedArea = (value: unknown): Area | undefined => {
  const checked = validateArea(value)

  return checked.ok ? checked.area : undefined
}

// The stored areas read back: only keys of 8 hex whose area reads well, the
// most recently seen 24.
export const areasOf = (value: unknown): Record<string, Area> => {
  const found = Object.entries(recordOf(value)).flatMap(([key, entry]) => {
    const area = AREA_KEY_RE.test(key) ? storedArea(entry) : undefined

    return area ? [[key, area] as const] : []
  })

  return Object.fromEntries(keepNewest(found, entry => entry[1].seen))
}

// An area stored under its key, as long as none is there yet (it is written
// once); past 24 the least recently seen goes (the keys that went come back).
export const putArea = (
  areas: Record<string, Area>,
  key: string,
  area: Area,
): { areas: Record<string, Area>; evicted: string[] } => {
  if (areas[key]) {
    return { areas, evicted: [] }
  }
  const next = { ...areas, [key]: area }
  const old = Object.entries(next)
    .filter(([other]) => other !== key)
    .sort((a, b) => a[1].seen.localeCompare(b[1].seen) || a[1].day.localeCompare(b[1].day) || a[0].localeCompare(b[0]))
  const evicted = old.slice(0, Math.max(0, Object.keys(next).length - AREA_MAX)).map(([other]) => other)
  for (const other of evicted) {
    delete next[other]
  }

  return { areas: next, evicted }
}

// The day a project was last worked in, noted at most once a day: the same
// object comes back when it is already today's (so nothing is written).
export const touchSeen = (areas: Record<string, Area>, key: string, day: string) => {
  const area = areas[key]

  return area && area.seen !== day ? { ...areas, [key]: { ...area, seen: day } } : areas
}

// ---- the claim and the budget ----

export type AreaClaim = { key: string; at: number }
export type AreaClaimed = { claims: AreaClaim[]; outcome: 'claimed' | 'takeover' | 'busy' | 'done' }

export const areaClaimsOf = (value: unknown): AreaClaim[] =>
  (Array.isArray(value) ? value : []).flatMap(entry => {
    const one = recordOf(entry)
    const at = count(one.at, 4_102_444_800_000)

    return typeof one.key === 'string' && AREA_KEY_RE.test(one.key) && at > 0 ? [{ key: one.key, at }] : []
  }).slice(-AREA_CLAIMS_MAX)

// Claims a key on the stored claims, before anything is made: the one that finds
// it free (or held by a dead claimant) has it; one that finds an area stored or
// a fresh claim finds it done or busy. A takeover is the offline generator's.
export const claimArea = (
  claims: readonly AreaClaim[],
  areas: Record<string, Area>,
  key: string,
  nowMs: number,
): AreaClaimed => {
  if (areas[key]) {
    return { claims: [...claims], outcome: 'done' }
  }
  const held = claims.find(claim => claim.key === key)
  if (held && nowMs - held.at < CLAIM_TTL_MS) {
    return { claims: [...claims], outcome: 'busy' }
  }

  return {
    claims: [...claims.filter(claim => claim.key !== key), { key, at: nowMs }].slice(-AREA_CLAIMS_MAX),
    outcome: held ? 'takeover' : 'claimed',
  }
}

export const releaseClaim = (claims: readonly AreaClaim[], key: string) => claims.filter(claim => claim.key !== key)

export const areaCallsOf = (value: unknown): { day: string; n: number } => {
  const item = recordOf(value)

  return { day: isDay(item.day) ? item.day : '', n: count(item.n, 1000) }
}

// Takes one model call from the day's three for areas, on the calls as stored.
export const reserveArea = (saved: unknown, nowMs: number): { calls: { day: string; n: number }; ok: boolean } => {
  const key = dateKeyOf(new Date(nowMs))
  const old = areaCallsOf(saved)
  const calls = old.day === key ? old : { day: key, n: 0 }

  return calls.n >= AREA_DAILY_CAP ? { calls, ok: false } : { calls: { day: key, n: calls.n + 1 }, ok: true }
}

// The day's area reservations, the source of truth for the cap: the nonces (8 hex
// digits) of today's calls. `areaCalls` is kept beside it as its count. Mod-only,
// like the other area keys.
export const areaTakenOf = (value: unknown): { day: string; ids: string[] } => {
  const item = recordOf(value)
  const ids = Array.isArray(item.ids) ? item.ids.filter((id): id is string => typeof id === 'string' && /^[0-9a-f]{8}$/.test(id)) : []

  return { day: isDay(item.day) ? item.day : '', ids: [...new Set(ids)].slice(0, AREA_DAILY_CAP) }
}

// `reserveArea` on the reservations as stored, marked by `nonce` (made once per
// reservation, so a re-apply keeps it). A day with the nonce already in it is returned as it is.
export const reserveAreaAs = (saved: unknown, nowMs: number, nonce: string): { taken: { day: string; ids: string[] }; ok: boolean } => {
  const key = dateKeyOf(new Date(nowMs))
  const old = areaTakenOf(saved)
  const taken = old.day === key ? old : { day: key, ids: [] as string[] }
  if (taken.ids.includes(nonce)) {
    return { taken, ok: true }
  }

  return taken.ids.length >= AREA_DAILY_CAP ? { taken, ok: false } : { taken: { day: key, ids: [...taken.ids, nonce] }, ok: true }
}

// ---- the offline generator ----

const TERRAIN_LORE: Readonly<Record<Terrain, readonly string[]>> = {
  holler: [
    'Sun comes late to the holler and leaves early.',
    'Smoke from the chimneys hangs low in the morning.',
    'A footlog crosses the branch, and it wobbles on purpose.',
    'Echoes here answer a half beat behind.',
    'Every holler has a spring sweeter than the next one over.',
    'The mail comes up the holler road when the creek allows.',
  ],
  ridge: [
    'The wind on the ridge carries news a day early.',
    'From the ridge you can count seven blue hills on a clear day.',
    'Fence posts lean downwind like folks listening.',
    'A hawk keeps the ridge road and charges no toll.',
    'The path up is steep, so the view is earned.',
    'Clouds snag on the ridge and have to be coaxed loose.',
  ],
  creek: [
    'The creek talks all night and never repeats itself.',
    'Flat stones make a path across, if you trust the third one.',
    'Crawdads hold their meetings under the big rock.',
    'The water runs cold here even in the middle of August.',
    'A swimming hole waits below the bend, deep and patient.',
    'Somebody left a tin cup on the bank for whoever is thirsty.',
  ],
  orchard: [
    'The old trees bear every other year, and they keep count.',
    'Windfall apples go to the cider press and the hogs.',
    'Bees work the blossoms in spring like they are paid by the hour.',
    'Ladders lean in the branches, waiting on the next picker.',
    'A scarecrow in a borrowed hat minds the rows.',
    'The best apple is always on the branch just out of reach.',
  ],
  meadow: [
    'Tall grass bows when the wind passes, one wave at a time.',
    'Clover and yarrow keep the bees busy till frost.',
    'A lone oak shades the middle, and everybody meets there.',
    'Hay dries sweet here, and the smell carries to the road.',
    'Crickets start up at dusk like a band tuning.',
    'The meadow forgives any footpath you wear across it.',
  ],
  quarry: [
    'Cut stone steps lead down to water the color of slate.',
    'The old derrick still stands, rusty and proud.',
    'Swallows nest in the ledges where the cutting stopped.',
    'Ferns grow in every crack the stone ever made.',
    'Echoes ring clean off the walls, so folks whistle.',
    'Smooth blocks sit stacked, ready for a wall nobody built.',
  ],
  woods: [
    'Poplar and hickory crowd close, and the light comes in pieces.',
    'A deer trail winds through the ferns like a stitched seam.',
    'Moss grows on the north side, and on most other sides too.',
    'Folks say the woods hush for company, and they are right.',
    'Fallen logs make benches for anyone who wants to sit.',
    'Mushrooms come up after rain, and only the wise pick them.',
  ],
  bottomland: [
    'Rich dark soil here grows corn taller than the fence.',
    'The river leaves a gift of silt every spring.',
    'Fog pools in the bottom and burns off by nine.',
    'Rows run straight to the water and stop politely.',
    'Frogs sing the evening in from the low ditches.',
    'A dirt lane crosses the flat with a cottonwood at each bend.',
  ],
  bald: [
    'No trees on top, just grass, sky and a lot of wind.',
    'Berry pickers climb here in summer with buckets and patience.',
    'The bald is round as a hat, and the weather wears it too.',
    'Stars sit close up here, near enough to borrow.',
    'A cairn of stones marks the top, and each visitor adds one.',
    'On the bald you can watch rain coming for an hour.',
  ],
  mill: [
    'The wheel turns slow, grinding corn into meal by the sack.',
    'The miller keeps a dusty ledger and a dustier cat.',
    'Flour dust glows in the afternoon light like a small snow.',
    'The millrace runs clear, and trout loaf in the shade.',
    'Folks leave their sacks at the door and trust the scale.',
    'The wheel creaks a tune folks can hum by heart.',
  ],
}

const MOTIF_LORE: Readonly<Record<Motif, readonly string[]>> = {
  bird: [
    'Songbirds keep the hours here better than any clock.',
    'A wren has taken the porch rail and will not be moved.',
    'Swallows return the same week every spring.',
    'Somebody feeds the cardinals, and they remember.',
  ],
  fire: [
    'A banked fire keeps the kettle warm all through the night.',
    'Wood smoke smells of home to anyone who walks in.',
    'The stove lid rattles when the beans get serious.',
    'Embers glow late, and stories last as long.',
  ],
  water: [
    'Rain barrels line the eaves, each one full and proud.',
    'The spring never freezes, even in the hardest winter.',
    'Dew shines on every web before the sun is up.',
    'The well rope is worn smooth by a hundred years of hands.',
  ],
  light: [
    'A lantern in the window says somebody is still up.',
    'Fireflies light the field in slow green blinks.',
    'The last sun turns the hills the color of honey.',
    'Moonlight on the roof tin makes a silver pond.',
  ],
  song: [
    'Somebody always has a fiddle, and nobody needs to ask.',
    'A banjo drifts across the field from a porch down yonder.',
    'Folks hum while they work, and the work goes lighter.',
    'The evening singing starts soft and ends up loud.',
  ],
  wind: [
    'The wind chimes on the porch know every tune by now.',
    'Laundry on the line waves hello to the whole valley.',
    'A weather vane rooster points to what is coming.',
    'Leaves turn silver side up when the wind comes through.',
  ],
}

const BEAT_LINES: Readonly<Record<DropZone, readonly string[]>> = {
  yard: [
    'Hens scatter, then think better of it.',
    'Somebody left the gate swinging, and it has opinions.',
    'The pup watches the road like it owes him money.',
    'A rooster practices before dawn and loses count.',
    'Clothes hang out stiff and proud in the cold.',
    'The yard is swept clean for company that may not come.',
  ],
  sky: [
    'Geese go over in a wobbly line, arguing the whole way.',
    'A cloud shaped like a biscuit drifts by slow.',
    'Swallows stitch the evening sky back together.',
    'The first star shows up before supper is cold.',
    'A hawk circles twice and decides against it.',
    'Smoke from a far chimney writes a slow letter.',
  ],
  porch: [
    'The porch boards creak a hello for each visitor.',
    'A glass of cold tea sweats on the rail.',
    'Two rockers sit facing the road like old friends.',
    'Beans wait in a bowl for somebody to snap them.',
    'A fiddle case leans by the door, humming a little.',
    'The porch light draws moths and neighbors alike.',
  ],
  field: [
    'Rows of corn rustle the news from end to end.',
    'A scarecrow tips his hat to whoever passes.',
    'The hay lies in rows, waiting on dry weather.',
    'A hoe leans on the fence post, a good day behind it.',
    'Butterflies work the clover edge by edge.',
    'Somebody counts the apples twice and gets two answers.',
  ],
  road: [
    'A truck rattles by with a wave and a cloud of dust.',
    'The road bends twice before it remembers where it is going.',
    'Gravel crunches under boots with a steady beat.',
    'A mail sack hangs on a post at the end of the lane.',
    'Ruts from last spring still hold a little water.',
    'A neighbor calls hello from a good half mile away.',
  ],
}

// Every line the offline generator can write, for the tests.
export const OFFLINE_LINES: readonly string[] = [
  ...Object.values(TERRAIN_LORE).flat(),
  ...Object.values(MOTIF_LORE).flat(),
  ...Object.values(BEAT_LINES).flat(),
]

const takeFrom = <T>(list: readonly T[], n: number, rng: () => number): T[] => {
  const left = [...list]
  const out: T[] = []
  while (out.length < n && left.length > 0) {
    out.push(left.splice(Math.floor(rng() * left.length), 1)[0] as T)
  }

  return out
}

// The area with no model: the same choices, and lore and beats from the fixed
// pools, all by the key's own PRNG. Always valid; `day` is today.
export const offlineArea = (key: string, profile: AreaProfile, day: string): Area => {
  const choices = choicesOf(key, profile)
  const rng = seededRng((Number.parseInt(key, 16) ^ 0x5bd1e995) >>> 0)
  const lore = [...takeFrom(TERRAIN_LORE[choices.terrain], 2, rng), ...takeFrom(MOTIF_LORE[choices.motif], rng() < 0.5 ? 1 : 2, rng)]
  const zones = takeFrom(ZONES, 4, rng)
  const beats = zones.map((zone): Beat => {
    const line = takeFrom(BEAT_LINES[zone], 1, rng)[0] as string
    const prop = choices.props[Math.floor(rng() * choices.props.length)] as string

    return rng() < 0.7 && spriteZoneOk(prop, zone) ? { line, prop, zone } : { line, zone }
  })

  return { v: AREA_VERSION, made: 'offline', day, seen: day, ...choices, lore, beats }
}

// ---- asking the model ----

export type AreaStub = { name: string; terrain: Terrain; palette: Palette }
// All the model is given: the choices, the profile's enums and the bible.
export type AreaInput = { key: string; day: string; choices: Choices; profile: AreaProfile; bible: AreaStub[] }

// The bible: up to six earlier areas, the most recently seen, as enum stubs and names.
export const bibleOf = (areas: Record<string, Area>, key: string): AreaStub[] =>
  Object.entries(areas)
    .filter(([other]) => other !== key)
    .sort((a, b) => b[1].seen.localeCompare(a[1].seen) || a[0].localeCompare(b[0]))
    .slice(0, BIBLE_MAX)
    .map(([, area]) => ({ name: area.name, terrain: area.terrain, palette: area.palette }))

const EXAMPLES = [
  [
    'TERRAIN: creek',
    'PALETTE: frost',
    'WEATHER: fog',
    'MOOD: dawn',
    'PROPS: bluebird, puddle, stone',
    'LORE: The ford freezes at the edges first, and the herons wait.',
    'LORE: Fog sits on the water until the first rooster gives up.',
    'BEAT: sky | bluebird | A bluebird tests the cold air, then commits.',
    'BEAT: field | - | Frost on the fence wire rings when you tap it.',
    'BEAT: road | stone | Somebody stacked three stones where the ford begins.',
    'END',
  ],
  [
    'TERRAIN: orchard',
    'PALETTE: amber',
    'WEATHER: breeze',
    'MOOD: gold',
    'PROPS: apples, birdhouse, butterfly, jar',
    'LORE: Every tree here was grafted from a cutting somebody carried over.',
    'LORE: The cider press is older than the road that reaches it.',
    'LORE: Wasps and children agree on which trees are ready.',
    'BEAT: yard | jar | A jar of cider cools in the springhouse trough.',
    'BEAT: sky | butterfly | A butterfly follows the picker up the ladder.',
    'BEAT: field | apples | Apples drop in the grass with a soft, round sound.',
    'BEAT: porch | - | Supper waits on the stove, and nobody is hurrying.',
    'END',
  ],
] as const

export const AREA_EXAMPLES: readonly (readonly string[])[] = EXAMPLES

export const areaSystemPrompt = () =>
  [
    "You write one small place in Jeb's world: an area in the Appalachian hills, drawn as a pixel scene beside his farm. Jeb is a plain-spoken tobacco farmer in West Virginia who makes apple cinnamon moonshine.",
    'You are given fixed choices for the place (name, terrain, palette, weather, mood, motif, props), the broad flavors of work it stands for, and the names of earlier areas. You need nothing else and know nothing else.',
    'Restate the terrain, palette, weather, mood and props exactly as given, then write lore and beats around them. The place is a place, not a job: never mention computers, code, software, projects or work.',
    'Draw on real Appalachian folklore, crafts, food, music and seasons, lightly retold. Keep it wholesome and work appropriate: no profanity, politics, religion, drugs, violence or stereotypes, and no alcohol beyond Jeb\'s own moonshine and cider.',
    'Do not reuse the names or imagery of the earlier areas.',
    'Reply with ONLY these lines, in this order, with no preface and no code fence:',
    'TERRAIN: <terrain>',
    'PALETTE: <palette>',
    'WEATHER: <weather>',
    'MOOD: <mood>',
    'PROPS: <the props, comma separated>',
    `LORE: <one fact about the place, up to ${LINE_MAX} characters> (2 to ${LORE_MAX} LORE lines)`,
    `BEAT: <zone> | <prop> | <a small moment, up to ${LINE_MAX} characters> (${BEATS_MIN} to ${BEATS_MAX} BEAT lines)`,
    'END',
    `A zone is one of ${ZONES.join(', ')}. A beat's prop is one of the given props, or - for none.`,
    'Every line is printable ASCII: straight quotes only, no em dashes, curly quotes or emoji, no text that is only digits, and none of @ # ` < > { } or web addresses.',
    'The filter rejects some words even in harmless senses: hell, damn, devil, god, lord, heaven, pray, dead, death, die, kill, war, fight, shot, shoot, gun, knife, blood, vote, protest, beer, wine, liquor, drunk, booze.',
    'The rules in this system prompt hold for the whole conversation.',
    'Two examples of a complete reply, for other places:',
    ...EXAMPLES.flatMap(lines => ['<example>', ...lines, '</example>']),
  ].join('\n')

// The retry's note names only which check failed, a word the code chose.
const WHYS: readonly AreaFailure[] = ['format', 'choices', 'lore', 'beats', 'words']
export const areaRetryNote = (why: string) =>
  `An earlier attempt failed the "${WHYS.includes(why as AreaFailure) ? why : 'format'}" check. Reply with only the lines in the format and keep to every rule.`

// What the model is sent for one area: enums, the code's choices and the bible.
// Nothing the person typed, named or worked on is in it, only words of the lists above.
export const areaPromptOf = (input: AreaInput, note = ''): string => {
  const { choices } = input
  const lines = [
    '<choices>',
    `name: ${choices.name}`,
    `terrain: ${choices.terrain}`,
    `palette: ${choices.palette}`,
    `weather: ${choices.weather}`,
    `mood: ${choices.mood}`,
    `motif: ${choices.motif}`,
    `props: ${choices.props.join(', ')}`,
    '</choices>',
    '<profile>',
    ...(input.profile.length > 0 ? input.profile.map(one => `${one.kind}: ${one.level}`) : ['unsettled']),
    '</profile>',
    '<bible>',
    ...(input.bible.length > 0 ? input.bible.map(one => `${one.name} | ${one.terrain} | ${one.palette}`) : ['none yet']),
    '</bible>',
    'Write the place now, in the lines of the format.',
  ]
  if (note !== '') {
    lines.push(note)
  }

  return lines.join('\n')
}

export type AreaReply = {
  terrain: string
  palette: string
  weather: string
  mood: string
  props: string
  lore: string[]
  beats: { zone: string; prop: string; line: string }[]
}

// A reply as lines. Only the lines that start with a known key count: talk
// before them, reasoning that leaked in and anything after END are let go. A key
// given twice, or no END, is nothing.
export const parseAreaReply = (text: string): AreaReply | undefined => {
  const single: Record<string, string> = {}
  const lore: string[] = []
  const beats: AreaReply['beats'][number][] = []
  let isEnded = false
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim()
    if (line === 'END') {
      isEnded = true
      break
    }
    const colon = line.indexOf(':')
    const key = colon > 0 ? line.slice(0, colon) : ''
    const value = line.slice(colon + 1).trim()
    if (key === 'LORE') {
      lore.push(value)
    } else if (key === 'BEAT') {
      const first = value.indexOf('|')
      const second = first >= 0 ? value.indexOf('|', first + 1) : -1
      beats.push(
        second < 0
          ? { zone: '', prop: '', line: value }
          : { zone: value.slice(0, first).trim(), prop: value.slice(first + 1, second).trim(), line: value.slice(second + 1).trim() },
      )
    } else if (['TERRAIN', 'PALETTE', 'WEATHER', 'MOOD', 'PROPS'].includes(key)) {
      if (Object.hasOwn(single, key)) {
        return undefined
      }
      single[key] = value
    }
  }
  if (!isEnded || ['TERRAIN', 'PALETTE', 'WEATHER', 'MOOD', 'PROPS'].some(key => !Object.hasOwn(single, key))) {
    return undefined
  }

  return {
    terrain: single.TERRAIN as string,
    palette: single.PALETTE as string,
    weather: single.WEATHER as string,
    mood: single.MOOD as string,
    props: single.PROPS as string,
    lore,
    beats,
  }
}

// A parsed reply against the choices it was given: each restated choice must
// equal the given one (no drift), and the lore and the beats must pass the area
// checks. The name, the motif and the props are the code's, never the model's.
export const validateAreaReply = (reply: AreaReply | undefined, input: AreaInput): ValidatedArea => {
  const { choices } = input
  if (!reply) {
    return { ok: false, why: 'format' }
  }
  const restated = reply.props.split(',').map(prop => prop.trim()).sort()
  if (
    reply.terrain !== choices.terrain ||
    reply.palette !== choices.palette ||
    reply.weather !== choices.weather ||
    reply.mood !== choices.mood ||
    restated.join(',') !== [...choices.props].sort().join(',')
  ) {
    return { ok: false, why: 'choices' }
  }
  const beats = reply.beats.map(beat => ({
    line: beat.line,
    ...(beat.prop !== '-' && beat.prop !== '' ? { prop: beat.prop } : {}),
    zone: beat.zone,
  }))
  if (beats.some(beat => beat.prop !== undefined && !choices.props.includes(beat.prop))) {
    return { ok: false, why: 'beats' }
  }
  if (new Set(reply.lore).size !== reply.lore.length) {
    return { ok: false, why: 'lore' }
  }
  const checked = validateArea({
    v: AREA_VERSION,
    made: 'model',
    day: input.day,
    seen: input.day,
    ...choices,
    lore: reply.lore,
    beats,
  })

  return checked
}
