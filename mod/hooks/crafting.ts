import type { Component, Farm, Goods, Material, Purchase } from '../types'
import { collectAged, reserveBales, surplusOf } from './market'
import { plural } from './util'

// Materials, crafting and the growing stack. Pure: the clock is handed in, and
// every craft, purchase and count is worked out from the farm it is given (the
// one just read from the store), so two sessions rarely build the same thing
// twice or spend the same dollar twice. That is best effort: the store has no
// compare-and-set, so a save re-reads the farm after writing it and, if another
// session wrote at the same moment, applies its change again onto theirs (at
// most twice, see `saveNow` in register.tsx).

export const MATERIALS: readonly Material[] = ['lumber', 'stone', 'straw', 'iron', 'sugar', 'copper']
export const COMPONENTS: readonly Component[] = ['barrel', 'post', 'coil']

// The glyphs of the stack: each is a default-emoji (no VS16) and is listed in
// WIDE. Components are two-cell ASCII chips.
export const MATERIAL_GLYPHS: Record<Material, string> = {
  lumber: '🪵',
  stone: '🪨',
  straw: '🌾',
  iron: '🔩',
  sugar: '🍬',
  copper: '🪙',
}
export const GOODS_GLYPHS = { appleButter: '🥫', twists: '🪢', whiskey: '🥃' } as const

// What the sources give, and the rules.
export const EDITS_PER_LUMBER = 3
export const STRAW_PER_TOBACCO = 2
export const STRAW_PER_CORN = 1
export const SUGAR_PRICE = 8
export const COPPER_PRICE = 30
export const MAX_SUGAR_BUY = 3
export const MAX_COPPER_BUY = 3
export const MAX_CRAFTS = 3
// A sellable never takes a material below this (sugar, which only the apple
// butter uses, has none).
export const RESERVE = 2
export const TWISTS_PER_BALE = 4
export const SMOKEHOUSE_TWISTS = 6
export const AGE_MS = 3 * 86_400_000
export const MAX_AGED = 50
// The stocks stop being made past these (a sale or a delivery drains them).
const MAX_BUTTER = 100
const MAX_TWISTS = 200
// What the sums can hold at most, so no stock can run away.
export const MAX_STOCK = 99_999

export const MASH_BASE = 6
export const MASH_KEG = 4

// Every number a recipe can take or a farm can hold: the materials, the
// components and five things from the barn and the shelf.
type Key = Material | Component | 'apples' | 'sticks' | 'bales' | 'corn' | 'lightning'
type Cost = Partial<Record<Key, number>>

export type Kind = 'component' | 'sellable' | 'build' | 'keepsake'
export type Item = {
  id: string
  kind: Kind
  name: string
  cost: Cost
  // Jeb's line when it is made (plain ASCII, short enough for the bubble).
  line: string
  // The keepsake of a sighting is made only after one.
  needsMothman?: boolean
}

export const ITEMS: readonly Item[] = [
  { id: 'barrel', kind: 'component', name: 'barrel', cost: { lumber: 3, iron: 1 }, line: 'Coopered up a barrel.' },
  { id: 'post', kind: 'component', name: 'fence post', cost: { lumber: 2, stone: 1 }, line: 'Split a fence post.' },
  { id: 'coil', kind: 'component', name: 'copper coil', cost: { copper: 1, iron: 1 }, line: 'Bent a copper coil.' },
  {
    id: 'appleButter',
    kind: 'sellable',
    name: 'apple butter',
    cost: { apples: 5, sugar: 1, sticks: 1 },
    line: 'Crafted a crock of apple butter.',
  },
  {
    id: 'twists',
    kind: 'sellable',
    name: 'tobacco twist',
    cost: { bales: 1 },
    line: 'Twisted a bale into tobacco twists.',
  },
  {
    id: 'whiskey',
    kind: 'sellable',
    name: 'aged whiskey',
    cost: { lightning: 1, barrel: 1 },
    line: 'Laid a jar of shine down to age.',
  },
  {
    id: 'thumpKeg',
    kind: 'build',
    name: 'thump keg',
    cost: { barrel: 2, coil: 1 },
    line: 'Built a thump keg. Shine comes quicker.',
  },
  {
    id: 'smokehouse',
    kind: 'build',
    name: 'smokehouse',
    cost: { lumber: 6, stone: 4, iron: 1 },
    line: 'Smokehouse is up. Six twists a bale.',
  },
  {
    id: 'fencedFields',
    kind: 'build',
    name: 'fenced fields',
    cost: { post: 8 },
    line: 'Fenced the fields. No more whistle pigs.',
  },
  {
    id: 'copperWorm',
    kind: 'build',
    name: 'copper worm',
    cost: { coil: 2 },
    line: "Copper worm's coiled. Two jars a run.",
  },
  {
    id: 'quilt',
    kind: 'keepsake',
    name: 'Log Cabin quilt',
    cost: { straw: 10, lumber: 2 },
    line: 'Stitched a Log Cabin quilt.',
  },
  {
    id: 'doll',
    kind: 'keepsake',
    name: 'corn-shuck doll',
    cost: { straw: 5, corn: 2 },
    line: 'Made a corn-shuck doll.',
  },
  {
    id: 'weathervane',
    kind: 'keepsake',
    name: 'iron rooster weathervane',
    cost: { iron: 3, copper: 1 },
    line: 'Hung an iron rooster weathervane.',
  },
  {
    id: 'banjo',
    kind: 'keepsake',
    name: 'porch banjo',
    cost: { lumber: 3, iron: 1, copper: 1 },
    line: "Built a porch banjo. Pickin' time.",
  },
  {
    id: 'mothman',
    kind: 'keepsake',
    name: 'Mothman carving',
    cost: { lumber: 2 },
    line: 'Carved the Mothman. Keep it quiet.',
    needsMothman: true,
  },
]

const ofKind = (kind: Kind) => ITEMS.filter(item => item.kind === kind)
export const BUILDS = ofKind('build')
export const KEEPSAKES = ofKind('keepsake')
export const BUILD_IDS = BUILDS.map(item => item.id)
export const KEEPSAKE_IDS = KEEPSAKES.map(item => item.id)

const itemOf = (id: string) => ITEMS.find(item => item.id === id) as Item




export const freshMaterials = (): Record<Material, number> => ({
  lumber: 0,
  stone: 0,
  straw: 0,
  iron: 0,
  sugar: 0,
  copper: 0,
})
export const freshComponents = (): Record<Component, number> => ({ barrel: 0, post: 0, coil: 0 })
export const freshGoods = (): Goods => ({ appleButter: 0, twists: 0, aged: [], whiskey: 0 })

export const isBuilt = (farm: Pick<Farm, 'built'>, id: string) => farm.built.includes(id)

// How many good runs a batch takes, and how many twists a bale makes.
export const mashFull = (farm: Farm) => (isBuilt(farm, 'thumpKeg') ? MASH_KEG : MASH_BASE)
export const twistsPerBale = (farm: Farm) =>
  isBuilt(farm, 'smokehouse') ? SMOKEHOUSE_TWISTS : TWISTS_PER_BALE

const isMaterial = (key: string): key is Material => MATERIALS.some(id => id === key)
const isComponent = (key: string): key is Component => COMPONENTS.some(id => id === key)

const have = (farm: Farm, key: Key) => {
  if (isMaterial(key)) {
    return farm.materials[key]
  }
  if (isComponent(key)) {
    return farm.components[key]
  }
  switch (key) {
    case 'apples':
      return farm.barn.apples
    case 'sticks':
      return farm.barn.sticks
    case 'bales':
      return farm.barn.bales
    case 'corn':
      return farm.barn.corn
    case 'lightning':
      return farm.shelf.lightning
  }
}

const entries = (cost: Cost) => Object.entries(cost) as [Key, number][]

// The farm after paying a cost (no stock goes below zero).
const pay = (farm: Farm, cost: Cost): Farm => {
  const materials = { ...farm.materials }
  const components = { ...farm.components }
  const barn = { ...farm.barn }
  const shelf = { ...farm.shelf }
  for (const [key, n] of entries(cost)) {
    if (isMaterial(key)) {
      materials[key] = Math.max(0, materials[key] - n)
    } else if (isComponent(key)) {
      components[key] = Math.max(0, components[key] - n)
    } else if (key === 'lightning') {
      shelf.lightning = Math.max(0, shelf.lightning - n)
    } else {
      barn[key] = Math.max(0, barn[key] - n)
    }
  }

  return { ...farm, materials, components, barn, shelf }
}


// Whether a cost can be paid; `isSpare` keeps the reserve of each material back
// (for what is made to sell).
const canPay = (farm: Farm, cost: Cost, isSpare = false) =>
  entries(cost).every(
    ([key, n]) =>
      have(farm, key) - n >= (isSpare && isMaterial(key) && key !== 'sugar' ? RESERVE : 0),
  )

// Whether one more of an item may be made at all (never past its caps, a
// keepsake or an upgrade only once, the Mothman's carving only after a sighting).
const isOpen = (farm: Farm, item: Item) => {
  switch (item.kind) {
    case 'build':
      return !isBuilt(farm, item.id)
    case 'keepsake':
      return (
        !farm.keepsakes.includes(item.id) && (item.needsMothman !== true || farm.counters.mothmanSeen > 0)
      )
    case 'component':
      return true
    case 'sellable':
      return item.id === 'whiskey' ? farm.goods.aged.length < MAX_AGED : true
  }
}

// The upgrade next in line: the first not yet built.
export const queuedBuild = (farm: Farm): Item | undefined => BUILDS.find(item => !isBuilt(farm, item.id))

export type Made = { kind: Kind; id: string; name: string; line: string }

const clampGoods = (n: number) => Math.min(MAX_STOCK, n)

// The farm after making one of an item. The cost is paid first, so a stock that
// is not there is never made from.
const make = (farm: Farm, item: Item, now: Date): Farm => {
  const paid = pay(farm, item.cost)

  switch (item.kind) {
    case 'component': {
      const id = item.id as Component

      return { ...paid, components: { ...paid.components, [id]: paid.components[id] + 1 } }
    }
    case 'build':
      return { ...paid, built: [...paid.built, item.id] }
    case 'keepsake':
      return { ...paid, keepsakes: [...paid.keepsakes, item.id] }
    case 'sellable':
      if (item.id === 'appleButter') {
        return {
          ...paid,
          goods: { ...paid.goods, appleButter: clampGoods(paid.goods.appleButter + 1) },
        }
      }
      if (item.id === 'twists') {
        return {
          ...paid,
          goods: { ...paid.goods, twists: clampGoods(paid.goods.twists + twistsPerBale(paid)) },
        }
      }

      return {
        ...paid,
        goods: {
          ...paid.goods,
          aged: [...paid.goods.aged, { readyAt: now.getTime() + AGE_MS }].slice(0, MAX_AGED),
        },
      }
  }
}

// The bales that may be smoked into twists: those above the cinnamon reserve,
// and, while the barn has no sticks, one more kept back so the next jar of
// lightning can still be turned into apple cinnamon.
export const spareBales = (farm: Farm) =>
  Math.max(0, farm.barn.bales - reserveBales(farm) - (farm.barn.sticks < 1 ? 1 : 0))

// The next thing worth making on its own: the queued upgrade's components, then
// the upgrade; then the keepsakes; then what is for sale, which leaves the
// reserve of each material alone.
const nextCraft = (farm: Farm): Item | undefined => {
  const queued = queuedBuild(farm)
  if (queued) {
    for (const [key, n] of entries(queued.cost)) {
      if (isComponent(key) && have(farm, key) < n) {
        const part = itemOf(key)
        if (canPay(farm, part.cost)) {
          return part
        }
      }
    }
    if (canPay(farm, queued.cost)) {
      return queued
    }
  }
  for (const keepsake of KEEPSAKES) {
    if (isOpen(farm, keepsake) && canPay(farm, keepsake.cost)) {
      return keepsake
    }
  }
  const spare = surplusOf(farm)
  const butter = itemOf('appleButter')
  if (
    farm.goods.appleButter < MAX_BUTTER &&
    spare.apples >= (butter.cost.apples ?? 0) &&
    canPay(farm, butter.cost, true)
  ) {
    return butter
  }
  if (farm.goods.twists < MAX_TWISTS && spareBales(farm) >= 1) {
    return itemOf('twists')
  }
  // Whiskey ages in a barrel the queued upgrade does not need; with none to
  // spare it coopers one (leaving the reserves) once the upgrade has its own.
  const whiskey = itemOf('whiskey')
  if (isOpen(farm, whiskey) && farm.shelf.lightning >= 1) {
    const spareBarrels = farm.components.barrel - (queued?.cost.barrel ?? 0)
    if (spareBarrels >= 1) {
      return whiskey
    }
    const barrel = itemOf('barrel')
    if (spareBarrels === 0 && canPay(farm, barrel.cost, true)) {
      return barrel
    }
  }

  return undefined
}

// Everything the farm can make by itself right now, at most MAX_CRAFTS things.
export const craftAll = (farm: Farm, now: Date): { next: Farm; made: Made[] } => {
  let next = farm
  const made: Made[] = []
  while (made.length < MAX_CRAFTS) {
    const item = nextCraft(next)
    if (!item) {
      break
    }
    next = make(next, item, now)
    made.push({ kind: item.kind, id: item.id, name: item.name, line: item.line })
  }

  return { next, made }
}




export type Crafted = { next: Farm; made?: Made; text: string }


// What a returning truck buys: sugar when the apple butter lacks only that,
// copper when the queued upgrade (or, once all four are built, the next
// keepsake that wants copper) is short of it. Never more than the cash.
export const copperShortfall = (farm: Farm) => {
  const queued = queuedBuild(farm)
  if (queued) {
    const coils = Math.max(0, (queued.cost.coil ?? 0) - farm.components.coil)

    return Math.max(0, coils + (queued.cost.copper ?? 0) - farm.materials.copper)
  }
  const keepsake = KEEPSAKES.find(
    item => isOpen(farm, item) && (item.cost.copper ?? 0) > 0,
  )

  return keepsake ? Math.max(0, (keepsake.cost.copper ?? 0) - farm.materials.copper) : 0
}

export const sugarWanted = (farm: Farm) => {
  const butter = itemOf('appleButter')

  return farm.materials.sugar < 1 &&
    farm.goods.appleButter < MAX_BUTTER &&
    surplusOf(farm).apples >= (butter.cost.apples ?? 0) &&
    farm.barn.sticks >= (butter.cost.sticks ?? 0)
    ? MAX_SUGAR_BUY
    : 0
}

export type Bought = { next: Farm; sugar: number; copper: number }

export const buySupplies = (farm: Farm): Bought => {
  const sugar = Math.min(sugarWanted(farm), Math.floor(farm.ledger.cash / SUGAR_PRICE))
  const cashLeft = farm.ledger.cash - sugar * SUGAR_PRICE
  const copper = Math.min(
    copperShortfall(farm),
    MAX_COPPER_BUY,
    Math.floor(cashLeft / COPPER_PRICE),
  )
  if (sugar === 0 && copper === 0) {
    return { next: farm, sugar: 0, copper: 0 }
  }
  const cost: Record<Purchase, number> = { sugar: sugar * SUGAR_PRICE, copper: copper * COPPER_PRICE }
  const spent = cost.sugar + cost.copper

  return {
    sugar,
    copper,
    next: {
      ...farm,
      materials: {
        ...farm.materials,
        sugar: farm.materials.sugar + sugar,
        copper: farm.materials.copper + copper,
      },
      ledger: {
        ...farm.ledger,
        cash: Math.max(0, farm.ledger.cash - spent),
        spent: farm.ledger.spent + spent,
        byPurchase: {
          sugar: farm.ledger.byPurchase.sugar + cost.sugar,
          copper: farm.ledger.byPurchase.copper + cost.copper,
        },
      },
    },
  }
}

// Materials from a source, with the clamp.
export const gain = (farm: Farm, got: Partial<Record<Material, number>>): Farm => {
  const materials = { ...farm.materials }
  for (const id of MATERIALS) {
    materials[id] = Math.min(MAX_STOCK, materials[id] + (got[id] ?? 0))
  }

  return { ...farm, materials }
}

// A successful edit: every third one yields a piece of lumber.
export const noteEdit = (farm: Farm): Farm => {
  const edits = Math.min(1_000_000_000, farm.counters.edits + 1)
  const next = { ...farm, counters: { ...farm.counters, edits } }

  return edits % EDITS_PER_LUMBER === 0 ? gain(next, { lumber: 1 }) : next
}

// A sighting of the Mothman.
export const noteMothman = (farm: Farm): Farm => ({
  ...farm,
  counters: { ...farm.counters, mothmanSeen: Math.min(1_000_000, farm.counters.mothmanSeen + 1) },
})

// The columns of the stack on the canvas: the five largest stocks of the
// materials and what is for sale (ties keep the order below), drawn in that
// order so a column does not hop from place to place.
export type Column = { id: string; glyph: string; count: number }
export const STACK_COLUMNS = 5

export const stockOf = (farm: Pick<Farm, 'materials' | 'goods'>, now: Date): Column[] => [
  ...MATERIALS.map(id => ({ id, glyph: MATERIAL_GLYPHS[id], count: farm.materials[id] })),
  { id: 'appleButter', glyph: GOODS_GLYPHS.appleButter, count: farm.goods.appleButter },
  { id: 'twists', glyph: GOODS_GLYPHS.twists, count: farm.goods.twists },
  {
    id: 'whiskey',
    glyph: GOODS_GLYPHS.whiskey,
    count: collectAged(farm.goods, now.getTime()).whiskey,
  },
]

export const stackColumns = (farm: Pick<Farm, 'materials' | 'goods'>, now: Date): Column[] => {
  const stock = stockOf(farm, now).filter(column => column.count > 0)
  const top = new Set(
    stock
      .map((column, i) => ({ column, i }))
      .sort((a, b) => b.column.count - a.column.count || a.i - b.i)
      .slice(0, STACK_COLUMNS)
      .map(entry => entry.column.id),
  )

  return stock.filter(column => top.has(column.id))
}







