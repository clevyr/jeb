import { LORE } from './lore'
import type { ArcStep, DropArt, DropKind, DropLasts, DropSprite, DropWindow, DropZone } from '../types'
import { PIXEL_COLOUR } from './pixel-art'
import { recordOf } from './util'

// The creative drops' content: the schema a surprise must match, the sprites it
// may name, the pictures it may draw, the filter that keeps it wholesome and the
// level that decides how much of it is allowed. Pure: nothing here asks the host.

export const ZONES: readonly DropZone[] = ['yard', 'sky', 'porch', 'field', 'road']
export const KINDS: readonly DropKind[] = ['happening', 'saying', 'decor', 'almanac']

export const NAME_MAX = 24
export const LINE_MAX = 64
export const LINES_MAX = 3
export const SUMMARY_MAX = 80
export const SPRITES_MAX = 3
export const ARC_MIN_STEPS = 2
export const ARC_MAX_STEPS = 7
export const ART_ID_MAX = 20
export const ART_SIDE_MAX = 24
export const ART_SIDE_MIN = 3
export const ART_BYTES_MAX = 2048
export const ART_OPAQUE_MIN = 0.2
export const MAX_LEVEL = 6

// ---- the sprites a surprise may place ----

// Built-in pixel sprites (and the emoji that stands for each in the emoji band,
// '' for none) that are safe anywhere: animals, props, icons, weather and a
// visitor. Never Jeb, the house or the still. `zones` narrows where one may stand.
export type SpriteDef = { pixel: string; emoji: string; zones?: readonly DropZone[] }

export const DROP_SPRITES: Readonly<Record<string, SpriteDef>> = {
  cow: { pixel: 'cow', emoji: '🐄' },
  hen: { pixel: 'hen', emoji: '🐓' },
  pup: { pixel: 'pup', emoji: '🐶' },
  turkey: { pixel: 'turkey', emoji: '🦃' },
  groundhog: { pixel: 'groundhog', emoji: '🦫' },
  deer: { pixel: 'deer', emoji: '🦌' },
  cardinal: { pixel: 'cardinal', emoji: '🐦' },
  bluebird: { pixel: 'bluebird', emoji: '🐦' },
  owl: { pixel: 'owl', emoji: '🦉' },
  butterfly: { pixel: 'butterfly', emoji: '🦋' },
  firefly: { pixel: 'firefly', emoji: '✨' },
  mug: { pixel: 'mug', emoji: '☕' },
  lunch: { pixel: 'lunch', emoji: '🌭' },
  postcard: { pixel: 'postcard', emoji: '💌' },
  cake: { pixel: 'cake', emoji: '🎂' },
  rainbow: { pixel: 'rainbow', emoji: '🌈' },
  puddle: { pixel: 'puddle', emoji: '💧' },
  star: { pixel: 'star-streak', emoji: '🌠' },
  bell: { pixel: 'prop-bell', emoji: '🔔' },
  parachute: { pixel: 'prop-parachute', emoji: '🪂' },
  lantern: { pixel: 'lantern', emoji: '🏮' },
  cloud: { pixel: 'cloud', emoji: '' },
  birdhouse: { pixel: 'birdhouse', emoji: '🛖' },
  jar: { pixel: 'icon-jar', emoji: '🫙' },
  cash: { pixel: 'icon-cash', emoji: '💵' },
  apples: { pixel: 'icon-apples', emoji: '🍎' },
  corn: { pixel: 'icon-corn', emoji: '🌽' },
  bale: { pixel: 'icon-bale', emoji: '🌿' },
  lumber: { pixel: 'icon-lumber', emoji: '🪵' },
  stone: { pixel: 'icon-stone', emoji: '🪨' },
  sugar: { pixel: 'icon-sugar', emoji: '🍬' },
  note: { pixel: 'note', emoji: '' },
  heart: { pixel: 'heart', emoji: '' },
  opal: { pixel: 'opal', emoji: '👵' },
  tractor: { pixel: 'rig-tractor', emoji: '🚜', zones: ['road'] },
}

export const DROP_SPRITE_NAMES: readonly string[] = Object.keys(DROP_SPRITES)

// The glyph a custom picture falls back to in the emoji band, by what kind of
// surprise it is part of; sayings and almanac lines draw nothing.
export const ART_GLYPHS: Readonly<Record<DropKind, string>> = {
  happening: '✨',
  decor: '🎀',
  saying: '',
  almanac: '',
}

export const isBuiltin = (name: string) => Object.hasOwn(DROP_SPRITES, name)

// ---- the content filter ----

// Whole words (and their plurals and endings) a surprise may not contain: the
// profanity, politics, religion, drugs, violence, stereotypes, slurs, sex and
// drink that Jeb does not do. Moonshine and cider are Jeb's own and stay fine.
const BANNED = [
  'fuck', 'shit', 'damn', 'hell', 'crap', 'ass', 'asshole', 'bitch', 'bastard', 'piss', 'dick', 'cock', 'slut', 'whore',
  'politics', 'political', 'politician', 'election', 'trump', 'biden', 'obama', 'democrat', 'republican', 'liberal',
  'conservative', 'vote', 'senator', 'congress', 'maga', 'protest',
  'god', 'jesus', 'christ', 'lord', 'bible', 'pray', 'prayer', 'heaven', 'satan', 'devil', 'allah', 'muslim', 'jew',
  'jewish', 'christian', 'catholic', 'atheist', 'sermon',
  'drug', 'marijuana', 'cannabis', 'cocaine', 'meth', 'heroin', 'opium', 'overdose', 'stoned',
  'kill', 'murder', 'gun', 'shoot', 'shot', 'stab', 'blood', 'bloody', 'dead', 'death', 'die', 'dies', 'bomb', 'war', 'weapon',
  'rifle', 'shotgun', 'knife', 'suicide', 'corpse', 'violence', 'fight',
  'hillbilly', 'redneck', 'inbred', 'hick', 'yokel', 'nigger', 'faggot', 'retard', 'tranny', 'chink', 'spic',
  'sex', 'sexy', 'naked', 'nude', 'porn',
  'beer', 'wine', 'vodka', 'drunk', 'tipsy', 'wasted', 'hangover', 'booze', 'liquor', 'bourbon',
]
const BANNED_RE = new RegExp(`\\b(?:${BANNED.join('|')})(?:s|es|ed|ing|er|ers)?\\b`, 'i')

export const isClean = (text: string) => !BANNED_RE.test(text)

// Printable ASCII only (space to tilde).
// eslint-disable-next-line no-control-regex
const isPrintable = (text: string) => /^[\x20-\x7e]*$/.test(text)

const NAME_RE = /^[a-z0-9-]{1,24}$/
const ART_ID_RE = /^[a-z0-9-]{1,20}$/

// ---- the picture a model may draw ----

// The legend: one character for each of about two dozen existing palette names.
export const ART_LEGEND: Readonly<Record<string, string>> = {
  k: 'ink',
  w: 'white',
  g: 'grey',
  s: 'stone',
  r: 'red',
  d: 'red_dark',
  y: 'yellow',
  a: 'amber',
  b: 'drop',
  e: 'water',
  n: 'green',
  N: 'green_dark',
  l: 'leaf',
  p: 'pine',
  o: 'wood',
  O: 'wood_dark',
  t: 'dirt',
  i: 'pink',
  u: 'purple',
  f: 'skin',
  m: 'denim',
  c: 'corn',
  h: 'hair_dark',
  q: 'copper',
}

export const ART_CLEAR = '.'

// The legend as the system prompt prints it.
export const legendText = () => `${ART_CLEAR}=clear ${Object.entries(ART_LEGEND).map(([key, name]) => `${key}=${name}`).join(' ')}`

// A picture read strictly, or nothing: an id of a-z, 0-9 and dashes (20 at
// most) that is no built-in sprite's name; 3 to 24 pixels each way; one or two
// frames; exactly `h * frames` rows of exactly `w` legend characters or `.`;
// every frame at least a fifth opaque; at most 2 KB as stored. A fully clear
// border is fine: the outline is drawn around it at runtime.
export const validateArt = (raw: unknown): DropArt | undefined => {
  const item = recordOf(raw)
  const { id } = item
  if (typeof id !== 'string' || !ART_ID_RE.test(id) || isBuiltin(id) || !isClean(id.replace(/-/g, ' '))) {
    return undefined
  }
  const { w, h } = item
  if (!Number.isInteger(w) || !Number.isInteger(h)) {
    return undefined
  }
  const width = w as number
  const height = h as number
  if (width < ART_SIDE_MIN || width > ART_SIDE_MAX || height < ART_SIDE_MIN || height > ART_SIDE_MAX) {
    return undefined
  }
  const frames = item.frames === undefined ? 1 : item.frames
  if (frames !== 1 && frames !== 2) {
    return undefined
  }
  const { rows } = item
  if (!Array.isArray(rows) || rows.length !== height * frames) {
    return undefined
  }
  for (const row of rows) {
    if (typeof row !== 'string' || row.length !== width) {
      return undefined
    }
    for (const ch of row) {
      if (ch !== ART_CLEAR && !Object.hasOwn(ART_LEGEND, ch)) {
        return undefined
      }
    }
  }
  const need = Math.ceil(width * height * ART_OPAQUE_MIN)
  for (let f = 0; f < frames; f += 1) {
    const opaque = (rows as string[])
      .slice(f * height, (f + 1) * height)
      .join('')
      .split('')
      .filter(ch => ch !== ART_CLEAR).length
    if (opaque < need) {
      return undefined
    }
  }
  const art: DropArt = { id, w: width, h: height, frames, rows: [...(rows as string[])] }

  return JSON.stringify(art).length <= ART_BYTES_MAX ? art : undefined
}

export type ArtFrames = { w: number; h: number; frames: Uint8Array[] }

// A picture as palette indices, one array per frame, one pixel wider and taller
// on every side than it was drawn: the 1px ink outline is added here, around
// every opaque pixel's clear neighbours (never drawn into the picture itself).
export const artFrames = (art: DropArt): ArtFrames => {
  const ink = PIXEL_COLOUR.ink as number
  const w = art.w + 2
  const h = art.h + 2
  const frames: Uint8Array[] = []
  for (let f = 0; f < art.frames; f += 1) {
    const out = new Uint8Array(w * h)
    const at = (x: number, y: number) => {
      if (x < 0 || y < 0 || x >= art.w || y >= art.h) {
        return 0
      }
      const ch = (art.rows[f * art.h + y] as string)[x] as string
      const name = ART_LEGEND[ch]

      return name === undefined ? 0 : (PIXEL_COLOUR[name] as number)
    }
    for (let y = 0; y < h; y += 1) {
      for (let x = 0; x < w; x += 1) {
        const own = at(x - 1, y - 1)
        if (own !== 0) {
          out[y * w + x] = own
        } else if (at(x - 2, y - 1) !== 0 || at(x, y - 1) !== 0 || at(x - 1, y - 2) !== 0 || at(x - 1, y) !== 0) {
          out[y * w + x] = ink
        }
      }
    }
    frames.push(out)
  }

  return { w, h, frames }
}

// ---- the festival tint ----

// A festival tints the ridges and the road toward one of these, a quarter of
// the way and no more: the colours are fixed so a model can never pick a bad one.
export const FESTIVAL_TINTS: Readonly<Record<string, readonly [number, number, number]>> = {
  gold: [255, 200, 80],
  rose: [240, 130, 150],
  mint: [130, 220, 170],
  sky: [120, 180, 240],
  dusk: [170, 130, 220],
}
export const TINT_NAMES: readonly string[] = Object.keys(FESTIVAL_TINTS)

// ---- the level ----

// 1 + floor(log2(1 + drops / 6)), at most 6: the more Jeb has made, the more he
// may. 0 drops is level 1, 6 is 2, 18 is 3, 42 is 4, 90 is 5 and 186 is 6.
export const levelOf = (total: number) =>
  Math.min(MAX_LEVEL, 1 + Math.floor(Math.log2(1 + Math.max(0, Math.floor(total || 0)) / 6)))

// The level is only a soft sense of how far the story has come: every power is
// open at every level.
export const STORY_SCALE =
  'Let the scale follow the story: lean toward small moments early on and let bigger changes (arcs, pictures, permanent structures, festival days) come when the story has earned them, though any of them may come at any time.'

export const artAllowed = (_level: number) => 2
export const arcStepsAllowed = (_level: number) => ARC_MAX_STEPS

// The reply token cap: a picture and a long arc need room. Never more than 1800.
export const tokenCap = (_level: number) => 1800

// ---- the schema ----

export type Drop = {
  kind: DropKind | 'arc'
  name: string
  lines: string[]
  summary: string
  sprites: DropSprite[]
  window: DropWindow | null
  lasts: DropLasts
  art: DropArt[]
  keep: boolean
  festival: string
  steps: ArcStep[]
}

export type DropCtx = {
  level: number
  // The ids of the custom pictures already stored: a drop may name them again.
  knownArt: readonly string[]
  // No arc is under way, so a new one may begin.
  isArcOpen: boolean
}

export type Validated = { ok: true; drop: Drop } | { ok: false; why: string }

const fail = (why: string): Validated => ({ ok: false, why })

const linesOf = (value: unknown): string[] | undefined => {
  if (!Array.isArray(value) || value.length < 1 || value.length > LINES_MAX) {
    return undefined
  }
  const lines: string[] = []
  for (const line of value) {
    if (typeof line !== 'string' || line.trim() === '' || line.length > LINE_MAX || !isPrintable(line)) {
      return undefined
    }
    lines.push(line.trim())
  }

  return lines
}

export const windowOf = (value: unknown): DropWindow | null | undefined => {
  if (value === undefined || value === null) {
    return null
  }
  const item = recordOf(value)
  const { from, to } = item
  if (!Number.isInteger(from) || !Number.isInteger(to)) {
    return undefined
  }

  return (from as number) >= 0 && (from as number) <= 23 && (to as number) >= 1 && (to as number) <= 24 && (to as number) > (from as number)
    ? { from: from as number, to: to as number }
    : undefined
}

export const lastsOf = (value: unknown): DropLasts | undefined =>
  value === undefined ? 'today' : value === 'today' || value === 'week' ? value : undefined

type RawSprite = { sprite: string; zone: DropZone; frames: 1 | 2 }

// The sprite list as asked for, in shape only: at most three, each a name, a
// known zone and one or two frames. Which names exist is decided later.
const spriteShape = (value: unknown): RawSprite[] | undefined => {
  if (value === undefined) {
    return []
  }
  if (!Array.isArray(value) || value.length > SPRITES_MAX) {
    return undefined
  }
  const out: RawSprite[] = []
  for (const entry of value) {
    const item = recordOf(entry)
    const frames = item.frames === undefined ? 1 : item.frames
    if (
      typeof item.sprite !== 'string' ||
      !ZONES.includes(item.zone as DropZone) ||
      (frames !== 1 && frames !== 2)
    ) {
      return undefined
    }
    out.push({ sprite: item.sprite, zone: item.zone as DropZone, frames })
  }

  return out
}

// The sprites that exist: a built-in (in a zone it may stand in) or a picture
// named in `art`. An unknown one is dropped, not an error.
const resolveSprites = (list: readonly RawSprite[], art: ReadonlySet<string>): DropSprite[] =>
  list.filter(entry => {
    if (isBuiltin(entry.sprite)) {
      const zones = (DROP_SPRITES[entry.sprite] as SpriteDef).zones

      return zones === undefined || zones.includes(entry.zone)
    }

    return art.has(entry.sprite)
  })

type Shape = {
  kind: DropKind | 'arc'
  name: string
  lines: string[]
  summary: string
  sprites: RawSprite[]
  window: DropWindow | null
  lasts: DropLasts
  keep: boolean
  festival: string
}

const summaryOf = (given: unknown, lines: readonly string[]) => {
  if (typeof given === 'string' && given.trim() !== '' && given.length <= SUMMARY_MAX && isPrintable(given)) {
    return given.trim()
  }

  return (lines[0] ?? '').slice(0, SUMMARY_MAX)
}

// One drop's own fields, checked: whatever is wrong with them rejects it.
const shapeOf = (item: Record<string, unknown>, isStep: boolean): Shape | string => {
  const kind = item.kind
  if (!(kind === 'arc' && !isStep) && !KINDS.includes(kind as DropKind)) {
    return 'kind'
  }
  const name = item.name
  if (typeof name !== 'string' || !NAME_RE.test(name)) {
    return 'name'
  }
  const lines = linesOf(item.lines)
  // An arc's own words are its steps': it needs none.
  const arcLines = kind === 'arc' && (item.lines === undefined || (Array.isArray(item.lines) && item.lines.length === 0))
  if (!lines && !arcLines) {
    return 'lines'
  }
  const sprites = spriteShape(item.sprites)
  if (!sprites) {
    return 'sprites'
  }
  const window = windowOf(item.window)
  if (window === undefined) {
    return 'window'
  }
  const lasts = lastsOf(item.lasts)
  if (!lasts) {
    return 'lasts'
  }
  if (item.keep !== undefined && typeof item.keep !== 'boolean') {
    return 'keep'
  }
  if (item.summary !== undefined && typeof item.summary !== 'string') {
    return 'summary'
  }
  const summary = summaryOf(item.summary, lines ?? [])
  const festival = typeof item.festival === 'string' && TINT_NAMES.includes(item.festival) ? item.festival : ''
  const text = [name, summary, ...(lines ?? []), typeof item.summary === 'string' ? item.summary : ''].join(' ')
  if (!isClean(text.replace(/-/g, ' '))) {
    return 'words'
  }

  return {
    kind: kind as Shape['kind'],
    name,
    lines: lines ?? [],
    summary,
    sprites,
    window,
    lasts,
    keep: item.keep === true,
    festival,
  }
}

// The art a drop defines: an object or a list, each picture read strictly. A bad
// one is dropped (the sprites that name it go with it); past two the rest are
// stripped.
const artOf = (raw: unknown, level: number): DropArt[] => {
  const list = raw === undefined ? [] : Array.isArray(raw) ? raw : [raw]
  const out: DropArt[] = []
  for (const entry of list.slice(0, 4)) {
    const art = validateArt(entry)
    if (art && !out.some(other => other.id === art.id)) {
      out.push(art)
    }
  }

  return out.slice(0, artAllowed(level))
}

type Body = Pick<Drop, 'lines' | 'sprites' | 'window' | 'lasts' | 'keep' | 'festival'> & { kind: DropKind }

// A drop's body: the sprites that exist, a happening or decor with none turned
// into a saying, and the window only decor has.
const bodyOf = (shape: Shape, kind: DropKind, art: ReadonlySet<string>): Body => {
  const effective = kind
  const sprites = resolveSprites(shape.sprites, art)
  const drawn = effective === 'happening' || effective === 'decor'
  const final: DropKind = drawn && sprites.length === 0 ? 'saying' : effective

  return {
    kind: final,
    lines: shape.lines,
    sprites: final === 'happening' || final === 'decor' ? sprites : [],
    window: final === 'decor' ? shape.window : null,
    lasts: final === 'happening' ? 'today' : shape.lasts,
    keep: final === 'decor' && shape.keep,
    festival: shape.festival,
  }
}

const EMPTY: Omit<Drop, 'kind' | 'name' | 'lines' | 'summary'> = {
  sprites: [],
  window: null,
  lasts: 'today',
  art: [],
  keep: false,
  festival: '',
  steps: [],
}

// A raw reply, read strictly. Bad shape, an unknown kind, a long or non-ASCII
// line, a banned word, a bad window and the like reject it whole.
export const validateDrop = (raw: unknown, ctx: DropCtx): Validated => {
  const item = recordOf(raw)
  const shape = shapeOf(item, false)
  if (typeof shape === 'string') {
    return fail(shape)
  }
  const art = artOf(item.art, ctx.level)
  const known = new Set([...ctx.knownArt, ...art.map(one => one.id)])

  if (shape.kind !== 'arc') {
    const body = bodyOf(shape, shape.kind, known)

    // keep is only for an arc's final step: a drop on its own never keeps.
    return { ok: true, drop: { ...EMPTY, ...body, name: shape.name, summary: shape.summary, art: usedArt(art, body.sprites), keep: false } }
  }

  // An arc: two to seven steps, each a drop of its own on a day (1 to 7) no
  // earlier than the step before.
  const rawSteps = item.steps
  if (!Array.isArray(rawSteps) || rawSteps.length < ARC_MIN_STEPS || rawSteps.length > ARC_MAX_STEPS) {
    return fail('steps')
  }
  const shapes: { shape: Shape; day: number }[] = []
  let lastDay = 1
  for (const entry of rawSteps) {
    const step = recordOf(entry)
    const made = shapeOf(step, true)
    if (typeof made === 'string') {
      return fail(`step ${made}`)
    }
    if (!Number.isInteger(step.day) || (step.day as number) < 1 || (step.day as number) > 7 || (step.day as number) < lastDay) {
      return fail('step day')
    }
    lastDay = step.day as number
    shapes.push({ shape: made, day: step.day as number })
  }
  const cap = arcStepsAllowed(ctx.level)
  const steps = ctx.isArcOpen ? shapes.slice(0, cap) : []
  // With an arc already running, the arc is only its first step.
  if (cap === 0 || !ctx.isArcOpen || steps.length < ARC_MIN_STEPS) {
    const first = (shapes[0] as { shape: Shape }).shape
    const body = bodyOf(first, first.kind as DropKind, known)

    return { ok: true, drop: { ...EMPTY, ...body, name: first.name, summary: shape.summary, art: usedArt(art, body.sprites), keep: false } }
  }
  const made: ArcStep[] = steps.map(({ shape: one, day }, i) => {
    const body = bodyOf(one, one.kind as DropKind, known)

    return { day, ...body, keep: body.keep && i === steps.length - 1 }
  })
  const sprites = made.flatMap(step => step.sprites)

  return {
    ok: true,
    drop: {
      ...EMPTY,
      kind: 'arc',
      name: shape.name,
      lines: [],
      summary: shape.summary,
      art: usedArt(art, sprites),
      steps: made,
    },
  }
}

// The pictures a list of sprites really names (one drawn but never placed is not kept).
const usedArt = (art: readonly DropArt[], sprites: readonly DropSprite[]) =>
  art.filter(one => sprites.some(sprite => sprite.sprite === one.id))

// ---- reading a stored value back ----

export const spritesOf = (value: unknown): DropSprite[] =>
  (Array.isArray(value) ? value : [])
    .slice(0, SPRITES_MAX)
    .map(recordOf)
    .filter(
      item =>
        typeof item.sprite === 'string' &&
        (isBuiltin(item.sprite) || ART_ID_RE.test(item.sprite)) &&
        ZONES.includes(item.zone as DropZone),
    )
    .map(item => ({ sprite: item.sprite as string, zone: item.zone as DropZone, frames: item.frames === 2 ? 2 : 1 }) as DropSprite)

export const storedLines = (value: unknown) => {
  const lines = (Array.isArray(value) ? value : [])
    .filter((line): line is string => typeof line === 'string' && isPrintable(line) && line.trim() !== '')
    .slice(0, LINES_MAX)
    .map(line => line.trim().slice(0, LINE_MAX))

  return lines
}

export const storedName = (value: unknown) => (typeof value === 'string' && NAME_RE.test(value) ? value : '')

export const isKind = (value: unknown): value is DropKind => KINDS.includes(value as DropKind)

export const isTint = (value: unknown): value is string => typeof value === 'string' && TINT_NAMES.includes(value)

// ---- the prompt ----

export type PromptInput = {
  now: Date
  slot: number
  level: number
  season: string
  farm: { jars: number; ripe: Readonly<Record<string, number>>; upgrades: number; unlocks: number }
  // Only the model's own past summaries come back to it.
  recent: readonly string[]
  arc: { name: string; step: number; of: number } | null
  isArcOpen: boolean
  artIds: readonly string[]
  total: number
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

export const partOfDay = (hour: number) => (hour < 12 ? 'morning' : hour < 17 ? 'afternoon' : hour < 21 ? 'evening' : 'night')

// The sprites that may not stand in every zone, as the prompt lists them.
const zoneLimits = () =>
  Object.entries(DROP_SPRITES)
    .filter(([, def]) => def.zones !== undefined && def.zones.length < ZONES.length)
    .map(([name, def]) => `${name}: ${(def.zones as readonly DropZone[]).join('/')} only`)
    .join(', ')

export const systemPrompt = (level: number) =>
  [
    'You are the storyteller of Jeb\'s unfolding life. Jeb is an Appalachian tobacco farmer in the West Virginia hills who makes apple cinnamon moonshine, shown in a pixel-art band above a terminal prompt.',
    'Each drop is the next small moment in his life, and over weeks they add up to a story: neighbours and kin who come and go, places on and around the farm, seasons and traditions, projects, mishaps, milestones, memories.',
    'Be genuinely creative. Invent new people, critters, places, events and pictures freely; you are not limited to the context you are given. The farm counts below are optional colour you may use, nod to or ignore.',
    'Keep continuity: read your recent drops, carry threads and recurring characters forward, let things change and grow, and avoid repeating yourself.',
    'Everything named above and below is an example, not a list to stay inside. Draw on the real folklore, legends, tall tales, history, music, crafts, food and seasonal customs of Appalachia and West Virginia that you know, and retell, adapt or invent from them. The lore notes in each prompt are only a starting spark.',
    'Keep it wholesome and work appropriate: legends and spooky critters stay light and cozy, never frightening or gory; no profanity, politics, drugs, violence or stereotypes, no religion beyond what is already there, and no alcohol jokes beyond the existing moonshine.',
    'Jeb speaks plain, dry and folksy. Reply with ONLY one JSON object, no prose and no code fence.',
    'Fields: kind ("happening" | "saying" | "decor" | "almanac" | "arc"), name (a-z0-9- up to 24), lines (1 to 3 strings, each up to 64 printable ASCII characters: straight quotes only, no em dashes, curly quotes or emoji),',
    `summary (up to ${SUMMARY_MAX} characters, what happened, naming any recurring character), sprites (optional, up to 3 of { sprite, zone ("yard"|"sky"|"porch"|"field"|"road"), frames 1|2 }),`,
    'window (optional { from 0-23, to 1-24 } local hours a decor shows; to must be greater than from, and it cannot wrap past midnight), lasts ("today" | "week"), and optionally art, steps, keep and festival.',
    `sprite is one of: ${DROP_SPRITE_NAMES.join(', ')}, or the id of a picture you define in art or one already stored.`,
    `art (optional, at the top level of the reply, also for an arc; one picture or a list of pictures): { id (a-z0-9- up to 20), w and h from ${ART_SIDE_MIN} to ${ART_SIDE_MAX}, frames 1 or 2, rows: array of h*frames strings, each exactly w characters } where every character is one of this legend:`,
    legendText(),
    'A picture needs at least a fifth of its pixels drawn. Do not draw a border or outline: the ink outline is added outside the picture. Keep pictures small, about 8 to 16 pixels a side.',
    'An arc is { kind:"arc", name, summary, art (optional, top level only), steps:[ { day 1-7, kind, name, lines, sprites, window, lasts } ... ] } of 2 to 7 steps; day counts calendar days from today, the first step is shown now so it should be day 1, and days never decrease; the last step may say keep:true to leave a permanent decor structure. Drops come Monday to Friday only, so a step due on a weekend arrives the next workday.',
    `Silent rules: a happening or decor with no sprite becomes a saying; every picture you draw must be placed as a sprite or it is dropped; an art id must not be a built-in sprite name; lasts "week" only counts for decor and almanac. Some sprites are limited to certain zones (${zoneLimits()}).`,
    'The filter rejects some words even in harmless senses: hell, damn, devil, god, lord, heaven, pray, dead, death, die, kill, war, fight, shot, shoot, gun, knife, blood, vote, protest, beer, wine, liquor, drunk, booze.',
    'Recurring characters are only names in your lines and summaries; continue the threads in the log when they fit.',
    `${STORY_SCALE} Story depth ${level} of 6 (it grows as drops add up).`,
  ].join('\n')

// What the model is sent: the date and time, the slot, the season, the level and
// what it may do, the farm's counts, and the last few of its own summaries.
export const promptOf = (input: PromptInput, retryNote = ''): string => {
  const hour = input.now.getHours()
  const ripe = Object.entries(input.farm.ripe).map(([crop, n]) => `${crop} ${n}`)
  const arcLine = input.arc
    ? `An arc is under way ("${input.arc.name}", step ${input.arc.step} of ${input.arc.of}): do not start another.`
    : input.isArcOpen
      ? 'No arc is under way: you may begin one if the story calls for it.'
      : 'Do not start an arc.'
  const lines = [
    `Today is ${WEEKDAYS[input.now.getDay()]} ${input.now.getFullYear()}-${String(input.now.getMonth() + 1).padStart(2, '0')}-${String(input.now.getDate()).padStart(2, '0')}, ${partOfDay(hour)} (${hour}:00 local), ${input.season}. This is the ${input.slot}:00 drop.`,
    `Story depth ${input.level} of 6 after ${input.total} drops.`,
    `Farm: ${input.farm.jars} jars on the shelf; ripe plants ${ripe.join(', ')}; ${input.farm.upgrades} upgrades; ${input.farm.unlocks} little things.`,
    arcLine,
    `Pictures already stored you may name again: ${input.artIds.length > 0 ? input.artIds.join(', ') : 'none'}.`,
    `Recent drops of yours (newest last): ${input.recent.length > 0 ? input.recent.map(line => `- ${line}`).join(' ') : 'none yet'}`,
    `Some lore you may draw on, or not: ${lorePicks(input.now, input.slot).map(line => `- ${line}`).join(' ')}`,
    'Write the next moment in Jeb\'s life now, as the JSON object.',
  ]
  if (retryNote !== '') {
    lines.push(retryNote)
  }

  return lines.join('\n')
}

// Three lore notes for a drop, the same for one day and slot, different across
// slots so the sparks rotate through the library.
export const LORE_PICKS = 3

export const lorePicks = (now: Date, slot: number, library: readonly string[] = LORE): string[] => {
  if (library.length === 0) {
    return []
  }
  const day = Math.floor(new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 86_400_000)
  const picks: string[] = []
  let seed = (day * 31 + slot * 7) >>> 0
  while (picks.length < Math.min(LORE_PICKS, library.length)) {
    seed = (Math.imul(seed, 1103515245) + 12345) >>> 0
    const entry = library[seed % library.length] as string
    if (!picks.includes(entry)) {
      picks.push(entry)
    }
  }

  return picks
}

export const RETRY_NOTE = 'That reply was invalid. Answer again with only the JSON object and keep to every rule.'

// The retry is a fresh call that has seen nothing before: it is told only which
// check an earlier attempt failed (a token the code chose, never the reply).
export const retryNote = (why: string) =>
  `An earlier attempt failed the "${why}" check. Reply with only the JSON object and keep to every rule.`

// A model's reply as a value: fences and talk around the object are let go;
// anything that is not one JSON object is nothing.
export const parseReply = (text: string): unknown => {
  const from = text.indexOf('{')
  const to = text.lastIndexOf('}')
  if (from < 0 || to <= from) {
    return undefined
  }
  try {
    return JSON.parse(text.slice(from, to + 1))
  } catch {
    return undefined
  }
}
