import type { Farm, JournalEntry, Square } from '../types'
import { MAX_LINE } from './camps'
import { ITEMS } from './crafting'
import { campLabel, dateKey, dayLabel } from './quilt'
import { cleanText } from './util'

// The anonymizer: everything from the person's work that Jeb stores or shows is
// turned into something of his own before it goes anywhere. One way, and stable:
// the same name always becomes the same made-up place, but nothing turns a place
// back into a name. Pure; the salt is handed in (the farm keeps it, see
// `anonSalt`), and so are the dice that make a new one.
//
// - A camp, repo, folder, worktree or branch name becomes a place name from
//   PLACES, picked by a keyed hash of the name. The salt is random and kept on the
//   farm, so a guessed repo name hashed without it says nothing about the place.
//   The farm's `anonPlaces` holds a short keyed tag of each name in the order they
//   came: replaying it gives every name its own place (the first free one from its
//   hash), so two camps never share one while the list has room.
// - A ticket key becomes a neighbor's number (1 to 99); no key text is kept.
// - A tool or MCP server Jeb does not know gets a plain line, never its name.
// - A session id becomes a keyed hash (the heartbeat's key, a stitched id), and
//   the live record's token is a keyed hash of that, new each day.
// Nothing else of the work (commands, paths, prompts, tool input or output, agent
// descriptions or names) is passed on by any of these.

// The salt: 16 hex digits (64 bits), made once per farm.
export const SALT_DIGITS = 16
const SALT = /^[0-9a-f]{16}$/

export const isSalt = (value: unknown): value is string => typeof value === 'string' && SALT.test(value)

// `count` random hex digits from the platform's CSPRNG (crypto.getRandomValues).
export const secureHex = (count: number): string =>
  Array.from(globalThis.crypto.getRandomValues(new Uint8Array(count)), byte => (byte & 15).toString(16)).join('')

// A new salt: from the CSPRNG, or from a 0-1 source a test passes.
export const mintSalt = (rng?: () => number) =>
  rng === undefined
    ? secureHex(SALT_DIGITS)
    : Array.from({ length: SALT_DIGITS }, () => Math.min(15, Math.floor(rng() * 16)).toString(16)).join('')

// ---- the keyed hash: SipHash-2-4, keyed by the salt ----

const MASK = (1n << 64n) - 1n
// The second half of the key: the salt folded with a fixed odd constant.
const K1_MIX = 0x9e3779b97f4a7c15n
// A salt that is not one (a farm not salted yet) still hashes, with an all-zero key.
const keyOf = (salt: string): [bigint, bigint] => {
  const k0 = isSalt(salt) ? BigInt(`0x${salt}`) : 0n

  return [k0, k0 ^ K1_MIX]
}

const rotl = (x: bigint, b: bigint) => ((x << b) | (x >> (64n - b))) & MASK

// The UTF-8 bytes of a string.
export const utf8 = (text: string): number[] => {
  const out: number[] = []
  for (const ch of text) {
    const c = ch.codePointAt(0) ?? 0
    if (c < 0x80) {
      out.push(c)
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 63))
    } else if (c < 0x10000) {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
    } else {
      out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
    }
  }

  return out
}

// SipHash-2-4 of some bytes under a 128-bit key, as a 64-bit number.
export const sipHash = (k0: bigint, k1: bigint, bytes: readonly number[]): bigint => {
  let v0 = k0 ^ 0x736f6d6570736575n
  let v1 = k1 ^ 0x646f72616e646f6dn
  let v2 = k0 ^ 0x6c7967656e657261n
  let v3 = k1 ^ 0x7465646279746573n
  const round = () => {
    v0 = (v0 + v1) & MASK
    v1 = rotl(v1, 13n) ^ v0
    v0 = rotl(v0, 32n)
    v2 = (v2 + v3) & MASK
    v3 = rotl(v3, 16n) ^ v2
    v0 = (v0 + v3) & MASK
    v3 = rotl(v3, 21n) ^ v0
    v2 = (v2 + v1) & MASK
    v1 = rotl(v1, 17n) ^ v2
    v2 = rotl(v2, 32n)
  }
  const n = bytes.length
  const end = n - (n % 8)
  for (let i = 0; i < end; i += 8) {
    let m = 0n
    for (let j = 7; j >= 0; j -= 1) {
      m = (m << 8n) | BigInt(bytes[i + j] ?? 0)
    }
    v3 ^= m
    round()
    round()
    v0 ^= m
  }
  let last = BigInt(n & 0xff) << 56n
  for (let j = (n % 8) - 1; j >= 0; j -= 1) {
    last |= BigInt(bytes[end + j] ?? 0) << BigInt(8 * j)
  }
  v3 ^= last
  round()
  round()
  v0 ^= last
  v2 ^= 0xffn
  round()
  round()
  round()
  round()

  return (v0 ^ v1 ^ v2 ^ v3) & MASK
}

// The keyed hash of a text under the salt.
export const keyedHash = (salt: string, text: string): bigint => {
  const [k0, k1] = keyOf(salt)

  return sipHash(k0, k1, utf8(text))
}

// The same as lower-case hex, cut to `digits` (at most 16).
export const hashHex = (salt: string, text: string, digits: number) =>
  keyedHash(salt, text).toString(16).padStart(16, '0').slice(0, Math.max(1, Math.min(16, digits)))

// ---- places ----

// Made-up places in the hills, each a plain name of letters and spaces, at most
// 14 characters (it is shown as "<place> camp").
export const PLACES: readonly string[] = [
  'Hickory Holler',
  'Laurel Fork',
  'Sugar Run',
  'Cane Creek',
  'Pine Knob',
  'Bear Wallow',
  'Possum Trot',
  'Shady Grove',
  'Copper Ridge',
  'Elk Lick',
  'Panther Gap',
  'Turkey Knob',
  'Dry Fork',
  'Buck Creek',
  'Fox Hollow',
  'Bluebell Flat',
  'Chestnut Gap',
  'Briar Patch',
  'Sassafras Run',
  'Ginseng Hill',
  'Snake Den Gap',
  'Mossy Bottom',
  'Locust Grove',
  'Spruce Knob',
  'Coon Hollow',
  'Cedar Bend',
  'Owl Creek',
  'Hemlock Ridge',
  'Paw Paw Flats',
  'Sweetwater',
  'Stony Lonesome',
  'Big Lick',
  'Plum Orchard',
  'Ramp Hollow',
  'Mill Creek',
  'Raven Rock',
  'Persimmon Gap',
  'Berry Knob',
  'Walnut Bottom',
  'Poplar Flat',
  'Catawba Bend',
  'Dogwood Run',
  'Redbud Holler',
  'Wolf Pen',
  'Salt Lick',
  'Honey Run',
  'Kettle Creek',
  'Lonesome Pine',
  'Thistle Ridge',
  'Beech Bottom',
  'Hog Back',
  'Pigeon Roost',
  'Muddy Branch',
  'Crooked Run',
  'Painter Fork',
  'Whippoorwill',
  'Frog Level',
  'Sinking Creek',
  'Buzzard Rock',
  'Lick Skillet',
  'Johnnycake Run',
  'Tater Knob',
  'Corncrib Gap',
  'Black Bear Run',
  'Willow Bend',
  'Rocky Branch',
  'Sycamore Flat',
  'Bee Tree Gap',
  'Chinquapin',
  'Fiddler Ridge',
  'Banjo Branch',
  'Cold Spring',
  'Gum Spring',
  'Shoal Creek',
  'Long Hollow',
  'Puncheon Run',
  'Clover Lick',
  'Mudlick',
  'Grassy Knob',
  'Flint Ridge',
]

// The registry: the last names a farm has placed, as 6-hex keyed tags, in the
// order they came. At most this many; past it a new name takes its hash's own
// place (and may share it).
export const TAG_DIGITS = 6
export const MAX_PLACE_TAGS = 64
const TAG = /^[0-9a-f]{6}$/

// A stored registry read back: well-formed tags, once each, at most MAX_PLACE_TAGS.
export const tagsOf = (value: unknown): string[] =>
  [...new Set(Array.isArray(value) ? value.filter((tag): tag is string => typeof tag === 'string' && TAG.test(tag)) : [])].slice(
    0,
    MAX_PLACE_TAGS,
  )

// A camp name's tag: a short keyed hash, all the registry ever holds of it.
export const campTagOf = (salt: string, name: string) => hashHex(salt, `camp:${cleanText(name, 64)}`, TAG_DIGITS)

const homeOf = (tag: string) => Number.parseInt(tag, 16) % PLACES.length

// Every registered tag's place: in order, each takes its home or the next one free.
const slotsOf = (tags: readonly string[]) => {
  const taken = new Set<number>()
  const slots = new Map<string, number>()
  for (const tag of tags) {
    let slot = homeOf(tag)
    while (taken.has(slot) && taken.size < PLACES.length) {
      slot = (slot + 1) % PLACES.length
    }
    taken.add(slot)
    slots.set(tag, slot)
  }

  return slots
}

// A tag's place, and the registry with the tag in it (the same array when it was
// there already or there is no room).
export const placeOfTag = (tag: string, tags: readonly string[]): { place: string; tags: string[] } => {
  const isNew = !tags.includes(tag) && tags.length < MAX_PLACE_TAGS
  const next = isNew ? [...tags, tag] : (tags as string[])
  const slot = slotsOf(next).get(tag) ?? homeOf(tag)

  return { place: PLACES[slot] as string, tags: next }
}

// A name's place, and the registry with the name in it.
export const placeFor = (salt: string, name: string, tags: readonly string[]) => placeOfTag(campTagOf(salt, name), tags)

// A name's place as it would be registered now, without registering it (a camp
// shown before it is stitched, a name another session brought).
export const placeSeen = (salt: string, name: string, tags: readonly string[]) => placeFor(salt, name, tags).place

export const isPlace = (value: unknown): value is string => typeof value === 'string' && PLACES.includes(value)

// ---- tickets, sessions, tools ----

// A ticket key's neighbor: a number from 1 to 99, the same for the same key.
export const neighborOf = (salt: string, key: string) => 1 + Number(keyedHash(salt, `cow:${key}`) % 99n)

// A session id's key in the heartbeats and among the stitched sessions.
export const ID_DIGITS = 12
const TOKEN = /^[0-9a-f]{12}$/

export const isToken = (value: unknown): value is string => typeof value === 'string' && TOKEN.test(value)

export const sessionKeyOf = (salt: string, id: string) => hashHex(salt, `sid:${id}`, ID_DIGITS)

// The live record's token: a keyed hash of the session's key and the local day.
export const liveTokenOf = (salt: string, day: string, sessionKey: string) =>
  hashHex(salt, `live:${day}:${sessionKey}`, ID_DIGITS)

// What Jeb says for a tool he does not know, and for an MCP server he does not:
// never the name.
export const TOOL_LINE = "Wranglin' a new contraption..."
export const RADIO_LINE = "Talkin' to town on the CB"

// ---- the journal ----

const WHEN = /^(today|[A-Z][a-z]{2} \d{1,2})$/
const MADE_NAMES = ITEMS.filter(item => item.kind === 'build' || item.kind === 'keepsake').map(item => item.name)
const PARTS: readonly RegExp[] = [
  /^\d{1,9} loads? out$/,
  /^rain (once|twice|\d{1,9} times)$/,
  /^\d{1,9} dry spells?$/,
  /^weeded all day$/,
  /^\d{1,9} rows? hoed$/,
  /^found blight$/,
  /^\d{1,9} sour batch(es)?$/,
  /^\d{1,9} harvests? in$/,
  /^\d{1,9} jars? put up$/,
  /^\d{1,9} hands? hired$/,
  /^\$\d{1,12} in sales$/,
  /^quiet day$/,
  /^mended a fence$/,
]

// One part of a journal line's body that is Jeb's own words.
const isOwnPart = (part: string) =>
  PARTS.some(pattern => pattern.test(part)) ||
  MADE_NAMES.some(name => part === `built the ${name}` || part === `made the ${name}`)

// A journal line made over for a place: the date (its own, else the entry's), the
// place's camp and only the parts of the body that are Jeb's own words; with none
// left, a quiet day.
export const lineFor = (line: string, d: string, place: string) => {
  const parts = cleanText(line, 400).split(' · ')
  const first = parts[0] ?? ''
  const when = parts.length >= 3 && WHEN.test(first) ? first : dayLabel(d)
  const body = parts.length >= 2 ? (parts[parts.length - 1] ?? '') : ''
  const kept = body.split(', ').filter(isOwnPart).slice(0, 5)

  return cleanText(`${when} · ${campLabel(place)} · ${kept.length > 0 ? kept.join(', ') : 'quiet day, mended a fence'}`, MAX_LINE)
}

// ---- the farm ----

// Whether a farm holds anything of the work: a camp name, a stitched id.
export const hasCamps = (farm: Pick<Farm, 'quilt' | 'journal' | 'busiest' | 'stitched'>) =>
  farm.quilt.length > 0 || farm.journal.length > 0 || farm.busiest !== null || farm.stitched.length > 0

// What stands for a camp while the farm's salt settles (see `anonPending`).
export const SETTLING_CAMP = 'Back Forty'

// A farm that is waiting for its salt, as it may be shown: every camp the one
// plain place, the journal lines rebuilt around it, no ids and no salt. Any other
// farm stands as it is.
export const shieldFarm = (farm: Farm): Farm => {
  if (farm.anonPending !== true) {
    return farm
  }

  return {
    ...farm,
    anonSalt: '',
    anonPlaces: [],
    quilt: farm.quilt.map(square => ({ ...square, camp: SETTLING_CAMP })),
    journal: farm.journal.map(entry => ({ d: entry.d, camp: SETTLING_CAMP, line: lineFor(entry.line, entry.d, SETTLING_CAMP) })),
    busiest: farm.busiest ? { ...farm.busiest, camp: SETTLING_CAMP } : null,
    stitched: [],
  }
}

// A farm written before the anonymizer, made over one way: a salt if it had none,
// each camp's place (registered in the order the camps came), the journal lines
// rebuilt around them, and the stitched session ids hashed. A farm with nothing to
// make over is left as it is. With a salt on the farm the result depends on nothing
// else, so sessions that make over the same farm under the same salt agree.
export const anonymizeFarm = (farm: Farm, rng: () => number = Math.random): Farm => {
  if (!hasCamps(farm)) {
    return farm
  }
  const salt = isSalt(farm.anonSalt) ? farm.anonSalt : mintSalt(rng)
  let tags = tagsOf(farm.anonPlaces)
  const placed = new Map<string, string>()
  const placeOf = (camp: string) => {
    const known = placed.get(camp)
    if (known !== undefined) {
      return known
    }
    const done = placeFor(salt, camp, tags)
    tags = done.tags
    placed.set(camp, done.place)

    return done.place
  }
  const quilt: Square[] = farm.quilt.map(square => ({ ...square, camp: placeOf(square.camp) }))
  const journal: JournalEntry[] = farm.journal.map(entry => {
    const place = placeOf(entry.camp)

    return { d: entry.d, camp: place, line: lineFor(entry.line, entry.d, place) }
  })
  const busiest = farm.busiest ? { ...farm.busiest, camp: placeOf(farm.busiest.camp) } : null

  const { anonPending: _pending, ...rest } = farm

  return {
    ...rest,
    anonSalt: salt,
    anonPlaces: tags,
    quilt,
    journal,
    busiest,
    stitched: [...new Set(farm.stitched.map(id => (isToken(id) ? id : sessionKeyOf(salt, id))))],
  }
}

// A dead session's heartbeat from a Jeb before the anonymizer: its id hashed, its
// camp a place (looked up, not registered) and its line rebuilt around it.
export const beatFor = (
  salt: string,
  tags: readonly string[],
  stale: { id: string; name: string; lastSeen: number; sq: string; ln: string },
) => {
  const place = placeSeen(salt, stale.name, tags)

  return {
    ...stale,
    id: sessionKeyOf(salt, stale.id),
    name: place,
    ln: lineFor(stale.ln, dateKey(new Date(stale.lastSeen)), place),
  }
}
