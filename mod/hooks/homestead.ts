import type { Component, Crop, CustomerId, Farm, JournalEntry, Ledger, Material, Product, Square } from '../types'
import { MAX_LINE } from './camps'
import {
  BUILD_IDS,
  COMPONENTS,
  freshComponents,
  freshGoods,
  freshMaterials,
  isBuilt,
  KEEPSAKE_IDS,
  MATERIALS,
  MAX_AGED,
  MAX_STOCK,
} from './crafting'
import { RIPE } from './crops'
import { anonymizeFarm, hasCamps, isSalt, tagsOf } from './anonymize'
import { MODEL_DAILY_CAP, creativeOf, dropsOf, freshCreative, freshDrops, logOf, modelCallsOf, modelTakenOf, newsSeenOf, surprisesOf } from './drops'
import { cleanText, recordOf } from './util'
import { freshUnlockDay, UNLOCK_IDS, UNLOCKS_MAX } from './unlocks'
import type { UnlockDay } from './unlocks'
import { isCode, isDateKey, JOURNAL_MAX, MAX_CAMP, QUILT_MAX, STITCHED_MAX } from './quilt'
import {
  CUSTOMER_IDS,
  freshLedger,
  JAR_PRICE,
  PRODUCTS,
  sellOpal,
} from './market'

export { JAR_PRICE }

// The farm's bookkeeping that needs no engine: a fresh one, reading a saved
// one back, the upgrades that dollars unlock and the sales and raids.

export const PLANTS = 8
export const FARM_VERSION = 10

export const freshPlants = () => Array.from({ length: PLANTS }, () => 0)

export const freshFarm = (): Farm => ({
  version: 10,
  rev: 0,
  crops: { tobacco: freshPlants(), corn: freshPlants(), apples: freshPlants() },
  progress: { tobacco: 0, corn: 0, apples: 0 },
  barn: { bales: 0, corn: 0, apples: 0, sticks: 0 },
  still: { steps: 0, hasBatch: false },
  shelf: { lightning: 0, appleCinnamon: 0 },
  lifetime: { outputTokens: 0, inputTokens: 0, workMs: 0, bales: 0, balesTraded: 0 },
  ledger: freshLedger(),
  upgrades: [],
  lastProof: 0,
  bestProof: 0,
  milestones: [],
  materials: freshMaterials(),
  components: freshComponents(),
  goods: freshGoods(),
  built: [],
  keepsakes: [],
  counters: { edits: 0, mothmanSeen: 0 },
  quilt: [],
  journal: [],
  sessionsWorked: 0,
  sessionsShipped: 0,
  busiest: null,
  stitched: [],
  unlocks: [],
  unlockDay: freshUnlockDay(),
  mailDay: '',
  drops: freshDrops(),
  modelCalls: { day: '', n: 0 },
  modelTaken: [],
  surprises: [],
  creativeLog: [],
  creative: freshCreative(),
  newsSeen: [],
  anonSalt: '',
  anonPlaces: [],
})

const count = (value: unknown) => {
  const n = Math.floor(Number(value))

  return Number.isFinite(n) && n > 0 ? n : 0
}

const amount = (value: unknown) => {
  const n = Number(value)

  return Number.isFinite(n) && n > 0 ? n : 0
}

// A saved crop's stages: exactly PLANTS whole numbers from 0 to ripe.
const stagesOf = (value: unknown) =>
  Array.from({ length: PLANTS }, (_, i) =>
    Math.min(RIPE, count(Array.isArray(value) ? value[i] : 0)),
  )

const idsOf = (value: unknown, known: readonly string[]) =>
  Array.isArray(value) ? known.filter(id => value.map(String).includes(id)) : []

const listOf = (value: unknown) => (Array.isArray(value) ? value : [])

// The quilt read back: only squares with one of the six letters and a real date,
// the camp cut to length, the last QUILT_MAX kept.
const quiltOf = (value: unknown): Square[] =>
  listOf(value)
    .slice(-QUILT_MAX * 2)
    .map(recordOf)
    .filter(item => isCode(item.c) && isDateKey(item.d))
    .map(item => ({
      c: item.c as Square['c'],
      d: item.d as string,
      camp: cleanText(item.camp, MAX_CAMP) || 'camp',
    }))
    .slice(-QUILT_MAX)

// The journal read back the same way: a real date and a line, cut to 120.
const journalOf = (value: unknown): JournalEntry[] =>
  listOf(value)
    .slice(-JOURNAL_MAX * 2)
    .map(recordOf)
    .filter(item => isDateKey(item.d) && cleanText(item.line, MAX_LINE) !== '')
    .map(item => ({
      d: item.d as string,
      camp: cleanText(item.camp, MAX_CAMP) || 'camp',
      line: cleanText(item.line, MAX_LINE),
    }))
    .slice(-JOURNAL_MAX)

const busiestOf = (value: unknown): Farm['busiest'] => {
  const item = recordOf(value)

  return isDateKey(item.d) && count(item.score) > 0
    ? { d: item.d, camp: cleanText(item.camp, MAX_CAMP) || 'camp', score: Math.min(1_000_000_000, count(item.score)) }
    : null
}

// The ids of stitched sessions: strings of at most 64 characters, once each, the
// last STITCHED_MAX kept.
const stitchedOf = (value: unknown) =>
  [...new Set(listOf(value).filter(id => typeof id === 'string' && id.length > 0 && id.length <= 64))].slice(
    -STITCHED_MAX,
  ) as string[]

// The little things read back: known ids only, once each, in the order they came,
// the last UNLOCKS_MAX kept. Older farms start with none.
const unlocksOf = (value: unknown) =>
  [...new Set(listOf(value).filter((id): id is string => typeof id === 'string' && (UNLOCK_IDS as readonly string[]).includes(id)))].slice(
    -UNLOCKS_MAX,
  )

const MAX_MS = 4_102_444_800_000

// The day's scheduling read back: real dates, the count 3 to 5 (0 before the
// first scheduling), whole numbers. An older farm starts empty, its first day
// being the first date it has on record.
const unlockDayOf = (value: unknown, fallbackSince: string): UnlockDay => {
  const item = recordOf(value)
  const d = isDateKey(item.d) ? item.d : ''
  const n = d === '' ? 0 : Math.min(5, Math.max(3, count(item.n)))

  return {
    d,
    n,
    done: Math.min(n, count(item.done)),
    next: Math.min(MAX_MS, count(item.next)),
    since: isDateKey(item.since) ? item.since : fallbackSince,
    coffee: isDateKey(item.coffee) ? item.coffee : '',
  }
}

// Whether a stored farm was written by a newer version of this mod; such a
// value is never read as a farm and never overwritten.
export const isFutureFarm = (saved: unknown) => {
  const raw = saved as Record<string, unknown> | undefined

  return Boolean(raw) && typeof raw === 'object' && Number(raw?.version) > FARM_VERSION
}

// A truck run sold at most this many jars before the market (v4 and older).
const LEGACY_RUN_JARS = 2

// A v4 `delivery { deliveries, jarsSold, dollars }` as books. Every old dollar
// was a jar of apple cinnamon at $25. Truck runs sold at most two jars each, so
// every jar beyond that was Miss Opal's: she is credited with those, at $25, and
// the rest (which cannot be told apart) goes to the legacy `town` bucket.
const ledgerFromDelivery = (delivery: Record<string, any> | undefined): Ledger => {
  const deliveries = count(delivery?.deliveries)
  const jarsSold = count(delivery?.jarsSold)
  const dollars = count(delivery?.dollars)
  const opal = Math.min(dollars, Math.max(0, jarsSold - LEGACY_RUN_JARS * deliveries) * JAR_PRICE)
  const fresh = freshLedger()

  return {
    ...fresh,
    deliveries,
    jarsSold,
    total: dollars,
    byCustomer: { ...fresh.byCustomer, opal, town: dollars - opal },
    byProduct: { ...fresh.byProduct, appleCinnamon: dollars },
    cash: dollars,
  }
}

// A saved v5 or v6 ledger, field by field: whole numbers, fixed key sets, a month
// key that looks like one and a best sale that names a known buyer and product.
// A v5 book had no cash: all it ever earned is still in hand.
const ledgerOf = (saved: Record<string, any> | undefined, hasCash: boolean): Ledger => {
  const key = String(saved?.month?.key)
  const hasMonth = /^\d{4}-(0[1-9]|1[0-2])$/.test(key)
  const best = saved?.best
  const hasBest =
    typeof best === 'object' &&
    best !== null &&
    CUSTOMER_IDS.includes(best.customer) &&
    PRODUCTS.includes(best.product) &&
    count(best.amount) > 0

  const total = count(saved?.total)

  return {
    deliveries: count(saved?.deliveries),
    jarsSold: count(saved?.jarsSold),
    total,
    month: { key: hasMonth ? key : '', amount: hasMonth ? count(saved?.month?.amount) : 0 },
    best: hasBest
      ? {
          amount: count(best.amount),
          customer: best.customer as CustomerId,
          product: best.product as Product,
        }
      : null,
    byCustomer: Object.fromEntries(
      CUSTOMER_IDS.map(id => [id, count(saved?.byCustomer?.[id])]),
    ) as Record<CustomerId, number>,
    byProduct: Object.fromEntries(
      PRODUCTS.map(id => [id, count(saved?.byProduct?.[id])]),
    ) as Record<Product, number>,
    ribbons: count(saved?.ribbons),
    fairYear: count(saved?.fairYear),
    cash: hasCash ? Math.min(total, count(saved?.cash)) : total,
    spent: count(saved?.spent),
    byPurchase: {
      sugar: count(saved?.byPurchase?.sugar),
      copper: count(saved?.byPurchase?.copper),
    },
  }
}

// A stock held in the stack: a whole number from 0 to the most it may hold.
const stock = (value: unknown) => Math.min(MAX_STOCK, count(value))

// The jars in their barrels: at most MAX_AGED, each a time that is a number.
const agedOf = (value: unknown) =>
  (Array.isArray(value) ? value : [])
    .map(jar => count((jar as Record<string, unknown> | null)?.readyAt))
    .filter(readyAt => readyAt > 0)
    .slice(0, MAX_AGED)
    .map(readyAt => ({ readyAt }))

// Reads a saved farm back, field by field: v10, v9, v8, v7, v6, v5 and v4, v3 and v2 as they are (a
// v4 delivery book becomes the ledger, a v2 had none and gets an empty one), a
// v1 `{ plants, bales, mash, jars }` keeps its bales and moves its jars to the
// shelf. Every number is a whole count of at
// least 0 (no NaN survives), every crop has exactly PLANTS plants and every
// missing object is filled. A farm from the future reads as nothing. A farm from
// before v10 had real camp names in its quilt and journal: they are made over into
// places, one way (see anonymize.ts), with a salt made from `rng` if it needs one.
// `readFarm` reads the same but leaves such a farm as it is, marked `anonPending`
// (its camps are still real names): a session that shares the store with others
// makes it over only once the salt has settled (see register.tsx).
export const loadFarm = (saved: unknown, rng: () => number = Math.random): Farm | undefined => {
  const farm = readFarm(saved)

  return farm?.anonPending ? anonymizeFarm(farm, rng) : farm
}

export const readFarm = (saved: unknown): Farm | undefined => {
  const raw = saved as Record<string, any> | undefined
  if (!raw || typeof raw !== 'object' || isFutureFarm(raw)) {
    return undefined
  }
  if (raw.version === 2 || raw.version === 3 || raw.version === 4 || raw.version === 5 || raw.version === 6 || raw.version === 7 || raw.version === 8 || raw.version === 9 || raw.version === 10) {
    const cut = count(raw.lifetime?.bales ?? raw.barn?.bales)
    const inBarn = count(raw.barn?.bales)
    // A farm saved before trades were counted: whatever is not in the barn
    // was traded. Never more than were cut.
    const traded = Math.min(
      cut,
      raw.lifetime?.balesTraded === undefined
        ? Math.max(0, cut - inBarn)
        : count(raw.lifetime.balesTraded),
    )

    const quilt = quiltOf(raw.quilt)
    const worked = Math.min(1_000_000_000, count(raw.sessionsWorked))

    const isLatest = raw.version === 8 || raw.version === 9 || raw.version === 10
    // The creative drops arrived with v9: older farms start with none.
    const isCreative = raw.version === 9 || raw.version === 10
    // The anonymizer arrived with v10: its camps are places already.
    const isAnon = raw.version === 10
    const firstDay = [...quilt.map(square => square.d), ...journalOf(raw.journal).map(entry => entry.d)].sort()[0] ?? ''

    const farm: Farm = {
      version: 10,
      rev: Math.min(1_000_000_000, count(raw.rev)),
      crops: {
        tobacco: stagesOf(raw.crops?.tobacco),
        corn: stagesOf(raw.crops?.corn),
        apples: stagesOf(raw.crops?.apples),
      },
      progress: {
        tobacco: amount(raw.progress?.tobacco),
        corn: amount(raw.progress?.corn),
        apples: amount(raw.progress?.apples),
      },
      barn: {
        bales: count(raw.barn?.bales),
        corn: count(raw.barn?.corn),
        apples: count(raw.barn?.apples),
        sticks: count(raw.barn?.sticks),
      },
      still: { steps: count(raw.still?.steps), hasBatch: raw.still?.hasBatch === true },
      shelf: {
        lightning: count(raw.shelf?.lightning),
        appleCinnamon: count(raw.shelf?.appleCinnamon),
      },
      lifetime: {
        outputTokens: count(raw.lifetime?.outputTokens),
        inputTokens: count(raw.lifetime?.inputTokens),
        workMs: amount(raw.lifetime?.workMs),
        bales: cut,
        balesTraded: traded,
      },
      ledger:
        raw.version >= 5 ? ledgerOf(raw.ledger, raw.version >= 6) : ledgerFromDelivery(raw.delivery),
      upgrades: idsOf(
        raw.upgrades,
        UPGRADES.map(upgrade => upgrade.id),
      ),
      lastProof: count(raw.lastProof),
      bestProof: count(raw.bestProof),
      milestones: idsOf(
        raw.milestones,
        MILESTONES.map(milestone => milestone.id),
      ),
      materials: Object.fromEntries(MATERIALS.map(id => [id, stock(raw.materials?.[id])])) as Record<
        Material,
        number
      >,
      components: Object.fromEntries(
        COMPONENTS.map(id => [id, stock(raw.components?.[id])]),
      ) as Record<Component, number>,
      goods: {
        appleButter: stock(raw.goods?.appleButter),
        twists: stock(raw.goods?.twists),
        aged: agedOf(raw.goods?.aged),
        whiskey: stock(raw.goods?.whiskey),
      },
      built: idsOf(raw.built, BUILD_IDS),
      keepsakes: idsOf(raw.keepsakes, KEEPSAKE_IDS),
      counters: {
        edits: Math.min(1_000_000_000, count(raw.counters?.edits)),
        mothmanSeen: Math.min(1_000_000, count(raw.counters?.mothmanSeen)),
      },
      quilt,
      journal: journalOf(raw.journal),
      sessionsWorked: Math.max(worked, quilt.length),
      sessionsShipped: Math.min(Math.max(worked, quilt.length), Math.min(1_000_000_000, count(raw.sessionsShipped))),
      busiest: busiestOf(raw.busiest),
      stitched: stitchedOf(raw.stitched),
      unlocks: isLatest ? unlocksOf(raw.unlocks) : [],
      unlockDay: isLatest ? unlockDayOf(raw.unlockDay, firstDay) : unlockDayOf(undefined, firstDay),
      mailDay: isDateKey(raw.mailDay) ? raw.mailDay : '',
      drops: isCreative ? dropsOf(raw.drops) : freshDrops(),
      modelCalls: isCreative ? modelCallsOf(raw.modelCalls) : { day: '', n: 0 },
      modelTaken: isCreative ? modelTakenOf(raw.modelTaken, MODEL_DAILY_CAP) : [],
      surprises: isCreative ? surprisesOf(raw.surprises) : [],
      creativeLog: isCreative ? logOf(raw.creativeLog) : [],
      creative: isCreative ? creativeOf(raw.creative) : freshCreative(),
      newsSeen: isCreative ? newsSeenOf(raw.newsSeen) : [],
      anonSalt: isSalt(raw.anonSalt) ? raw.anonSalt : '',
      anonPlaces: isAnon ? tagsOf(raw.anonPlaces) : [],
    }

    // Real names still in it: from before v10, marked as waiting, or without a salt.
    const isPending = hasCamps(farm) && (!isAnon || raw.anonPending === true || farm.anonSalt === '')

    return isPending ? { ...farm, anonPending: true } : farm
  }
  if (Array.isArray(raw.plants)) {
    const fresh = freshFarm()
    const bales = count(raw.bales)

    return {
      ...fresh,
      barn: { ...fresh.barn, bales },
      lifetime: { ...fresh.lifetime, bales },
      shelf: { lightning: 0, appleCinnamon: count(raw.jars) },
    }
  }

  return undefined
}

export type Upgrade = { id: string; at: number; what: string; line: string }

// Unlocked, never spent, as lifetime dollars cross each mark.
export const UPGRADES: Upgrade[] = [
  { id: 'mailbox', at: 50, what: 'a mailbox', line: 'Got me a mailbox by the house. Official now.' },
  { id: 'chair', at: 150, what: 'a rocking chair', line: "Rockin' chair on the porch. Earned it." },
  { id: 'hen', at: 300, what: 'a hen', line: "Picked up a hen. She'll earn her keep." },
  { id: 'pup', at: 500, what: 'a pup for Blue', line: 'Blue has a pup now. Lord help us.' },
  { id: 'coat', at: 1000, what: 'a fresh coat of paint', line: 'Fresh coat of paint on the house.' },
  { id: 'still2', at: 2000, what: 'a second still', line: "Second still's up. Don't tell the revenuer." },
]

export type Milestone = { id: string; text: string; isDone: (farm: Farm) => boolean }

export const MILESTONES: Milestone[] = [
  { id: 'jar10', text: 'Jeb sold his 10th jar.', isDone: farm => farm.ledger.jarsSold >= 10 },
  { id: 'jar50', text: 'Jeb sold his 50th jar.', isDone: farm => farm.ledger.jarsSold >= 50 },
  { id: 'bale10', text: 'Jeb hung his 10th bale.', isDone: farm => farm.lifetime.bales >= 10 },
]

// What the farm has newly earned: upgrades by dollars, one-time milestones.
export const newUnlocks = (farm: Farm) => ({
  upgrades: UPGRADES.filter(
    upgrade => farm.ledger.total >= upgrade.at && !farm.upgrades.includes(upgrade.id),
  ),
  milestones: MILESTONES.filter(
    milestone => milestone.isDone(farm) && !farm.milestones.includes(milestone.id),
  ),
})


// A neighbor buys one jar, if there is one: Miss Opal, through the market.
export const sellOne = (old: Farm, now: Date): Farm => sellOpal(old, now)

// A whistle pig takes a stage off one random corn plant (never below 0); with
// the fields fenced it takes nothing.
export const raidCorn = (old: Farm, rng: () => number): Farm => {
  if (isBuilt(old, 'fencedFields')) {
    return old
  }
  const at = Math.floor(rng() * PLANTS)
  const corn = old.crops.corn.map((stage, i) => (i === at ? Math.max(0, stage - 1) : stage))

  return { ...old, crops: { ...old.crops, corn } as Record<Crop, number[]> }
}

// A fresh batch of white lightning proofs between 90 and 130.
export const proofOf = (rng: () => number) => 90 + Math.floor(rng() * 41)
