import type { CustomerId, Farm, Goods, Ledger, Product, Truck } from '../types'
import type { SayingCategory } from './sayings'
import { pickWeighted } from './util'

// The market: who buys what, at what price, and the books. Pure; the clock and
// the dice are handed in, and every sale is worked out from the farm it is
// handed (the one just read from the store), so a sale is decided where it is
// saved and two sessions rarely sell the same jar twice. That is best effort:
// the store has no compare-and-set, so a save re-reads the farm after writing
// it and, if another session wrote at the same moment, decides the sale again on
// theirs (at most twice, see `saveNow` in register.tsx).

// How many cinnamon sticks a bale trades for.
export const STICKS_PER_BALE = 8

// What the still and the mash keep back: a sale never takes the barn below
// these (apples go into cinnamon, corn into mash).
export const APPLE_KEEP = 10
export const CORN_KEEP = 3

// Prices are fixed: no dice, no decay, a single seasonal bump (bales in winter).
export const JAR_PRICE = 25
export const STORE_JAR_PRICE = 20
export const STORE_APPLE_PRICE = 5
export const TRIPPER_JAR_PRICE = 15
export const BALE_PRICE = 40
export const WINTER_BALE_PRICE = 55
export const MARKET_APPLE_PRICE = 6
export const MILL_CORN_PRICE = 4
export const FAIR_PRIZE = 50
// What Jeb makes himself (see crafting.ts): the store pays more for butter and
// twists than anyone, the tripper pays at night, the aged whiskey fetches $60.
export const STORE_BUTTER_PRICE = 30
export const MARKET_BUTTER_PRICE = 28
export const STORE_TWIST_PRICE = 16
export const TRIPPER_TWIST_PRICE = 18
export const WHISKEY_PRICE = 60

// The lots each buyer takes.
export const STORE_JARS: readonly [number, number] = [2, 4]
export const STORE_APPLES = 20
export const TRIPPER_JARS: readonly [number, number] = [4, 6]
export const MARKET_APPLES = 30
export const STORE_BUTTER: readonly [number, number] = [1, 3]
export const MARKET_BUTTER: readonly [number, number] = [1, 3]
export const STORE_TWISTS: readonly [number, number] = [2, 6]
export const TRIPPER_TWISTS: readonly [number, number] = [2, 6]
export const WHISKEY_LOT: readonly [number, number] = [1, 2]

// The fair is open once a year and always wins the draw; its weight is only how
// it is listed.
export const FAIR_WEIGHT = 1000

export const CUSTOMER_IDS: readonly CustomerId[] = [
  'opal',
  'store',
  'tripper',
  'warehouse',
  'market',
  'mill',
  'fair',
  'town',
]

// The five a farm always sold, and the three it makes: the ledger always lists
// the first five and the others once they have earned something.
export const BASE_PRODUCTS: readonly Product[] = [
  'appleCinnamon',
  'whiteLightning',
  'tobacco',
  'apples',
  'corn',
]

export const PRODUCTS: readonly Product[] = [
  ...BASE_PRODUCTS,
  'appleButter',
  'twists',
  'agedWhiskey',
]



export const freshLedger = (): Ledger => ({
  deliveries: 0,
  jarsSold: 0,
  total: 0,
  month: { key: '', amount: 0 },
  best: null,
  byCustomer: { opal: 0, store: 0, tripper: 0, warehouse: 0, market: 0, mill: 0, fair: 0, town: 0 },
  byProduct: {
    appleCinnamon: 0,
    whiteLightning: 0,
    tobacco: 0,
    apples: 0,
    corn: 0,
    appleButter: 0,
    twists: 0,
    agedWhiskey: 0,
  },
  ribbons: 0,
  fairYear: 0,
  cash: 0,
  spent: 0,
  byPurchase: { sugar: 0, copper: 0 },
})

// The local calendar month, as the ledger keys it.
export const monthKey = (now: Date) =>
  `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`

// Bales the still may still need: each batch of white lightning waiting for
// cinnamon takes a cinnamon stick, and a bale makes eight of them.
export const reserveBales = (farm: Farm) => Math.ceil(farm.shelf.lightning / STICKS_PER_BALE)

// What the barn holds above the reserves and floors, and what Jeb made that is
// for sale (all of it: nothing crafted is kept back).
export const surplusOf = (farm: Farm) => ({
  bales: Math.max(0, farm.barn.bales - reserveBales(farm)),
  apples: Math.max(0, farm.barn.apples - APPLE_KEEP),
  corn: Math.max(0, farm.barn.corn - CORN_KEEP),
  appleButter: farm.goods.appleButter,
  twists: farm.goods.twists,
})

// The aged jars whose three days are up move out of their barrels, to the
// collected whiskey. Pure; `nowMs` is the clock.
export const collectAged = (goods: Goods, nowMs: number): Goods => {
  const ready = goods.aged.filter(jar => jar.readyAt <= nowMs)
  if (ready.length === 0) {
    return goods
  }

  return {
    ...goods,
    aged: goods.aged.filter(jar => jar.readyAt > nowMs),
    whiskey: goods.whiskey + ready.length,
  }
}

// Whiskey that can be sold now: the collected jars and the aged ones that are ready.
export const readyWhiskey = (farm: Farm, now: Date) => {
  const goods = collectAged(farm.goods, now.getTime())

  return goods.whiskey
}

export type SaleLine = { product: Product; qty: number; dollars: number }
export type Sale = { customer: CustomerId; lines: SaleLine[]; total: number; isRibbon: boolean }

// One thing a buyer takes, between `min` and `max` of it (never more than stands
// in the barn or on the shelf).
type Want = { product: Product; min: number; max: number; price: number }

const isWinter = (now: Date) => [11, 0, 1].includes(now.getMonth())

// What a buyer would take from this farm at this time; nothing when it is not
// their hour or day, or there is nothing they would buy.
export const wantsOf = (id: CustomerId, now: Date, farm: Farm): Want[] => {
  const hour = now.getHours()
  const day = now.getDay()
  const month = now.getMonth()
  const { appleCinnamon, lightning } = farm.shelf
  const spare = surplusOf(farm)
  const whiskey = readyWhiskey(farm, now)

  switch (id) {
    case 'opal':
      return appleCinnamon >= 1
        ? [{ product: 'appleCinnamon', min: 1, max: 1, price: JAR_PRICE }]
        : []
    case 'store': {
      if (day < 1 || day > 5 || hour < 8 || hour >= 18) {
        return []
      }
      const wants: Want[] = []
      if (appleCinnamon >= STORE_JARS[0]) {
        wants.push({
          product: 'appleCinnamon',
          min: STORE_JARS[0],
          max: Math.min(STORE_JARS[1], appleCinnamon),
          price: STORE_JAR_PRICE,
        })
      }
      const apples = Math.min(STORE_APPLES, spare.apples)
      if (apples >= 1) {
        wants.push({ product: 'apples', min: apples, max: apples, price: STORE_APPLE_PRICE })
      }
      if (spare.appleButter >= STORE_BUTTER[0]) {
        wants.push({
          product: 'appleButter',
          min: STORE_BUTTER[0],
          max: Math.min(STORE_BUTTER[1], spare.appleButter),
          price: STORE_BUTTER_PRICE,
        })
      }
      if (spare.twists >= STORE_TWISTS[0]) {
        wants.push({
          product: 'twists',
          min: STORE_TWISTS[0],
          max: Math.min(STORE_TWISTS[1], spare.twists),
          price: STORE_TWIST_PRICE,
        })
      }
      if (whiskey >= WHISKEY_LOT[0]) {
        wants.push({
          product: 'agedWhiskey',
          min: WHISKEY_LOT[0],
          max: Math.min(WHISKEY_LOT[1], whiskey),
          price: WHISKEY_PRICE,
        })
      }

      return wants
    }
    case 'tripper': {
      if (hour < 18 && hour >= 5) {
        return []
      }
      const wants: Want[] = []
      if (lightning >= TRIPPER_JARS[0]) {
        wants.push({
          product: 'whiteLightning',
          min: TRIPPER_JARS[0],
          max: Math.min(TRIPPER_JARS[1], lightning),
          price: TRIPPER_JAR_PRICE,
        })
      }
      if (spare.twists >= TRIPPER_TWISTS[0]) {
        wants.push({
          product: 'twists',
          min: TRIPPER_TWISTS[0],
          max: Math.min(TRIPPER_TWISTS[1], spare.twists),
          price: TRIPPER_TWIST_PRICE,
        })
      }
      if (whiskey >= WHISKEY_LOT[0]) {
        wants.push({
          product: 'agedWhiskey',
          min: WHISKEY_LOT[0],
          max: Math.min(WHISKEY_LOT[1], whiskey),
          price: WHISKEY_PRICE,
        })
      }

      return wants
    }
    case 'warehouse':
      return spare.bales >= 1
        ? [
            {
              product: 'tobacco',
              min: spare.bales,
              max: spare.bales,
              price: isWinter(now) ? WINTER_BALE_PRICE : BALE_PRICE,
            },
          ]
        : []
    case 'market': {
      const apples = Math.min(MARKET_APPLES, spare.apples)
      const isOpen = day === 6 || [8, 9, 10].includes(month)
      if (!isOpen) {
        return []
      }
      const wants: Want[] = []
      if (apples >= 1) {
        wants.push({ product: 'apples', min: apples, max: apples, price: MARKET_APPLE_PRICE })
      }
      if (spare.appleButter >= MARKET_BUTTER[0]) {
        wants.push({
          product: 'appleButter',
          min: MARKET_BUTTER[0],
          max: Math.min(MARKET_BUTTER[1], spare.appleButter),
          price: MARKET_BUTTER_PRICE,
        })
      }

      return wants
    }
    case 'mill':
      return spare.corn >= 1
        ? [{ product: 'corn', min: spare.corn, max: spare.corn, price: MILL_CORN_PRICE }]
        : []
    case 'fair':
      return month === 7 && farm.ledger.fairYear !== now.getFullYear() && appleCinnamon >= 1
        ? [{ product: 'appleCinnamon', min: 1, max: 1, price: FAIR_PRIZE }]
        : []
    case 'town':
      return []
  }
}

// How much a buyer is preferred: the most they could pay right now, so whoever
// can take the most surplus is likeliest. The fair, open once a year, always wins.
export const weightOf = (id: CustomerId, now: Date, farm: Farm) => {
  const wants = wantsOf(id, now, farm)
  if (wants.length === 0) {
    return 0
  }
  if (id === 'fair') {
    return FAIR_WEIGHT
  }

  return wants.reduce((sum, want) => sum + want.max * want.price, 0)
}

export const eligibleCustomers = (now: Date, farm: Farm) =>
  CUSTOMER_IDS.flatMap(id => {
    const weight = weightOf(id, now, farm)

    return weight > 0 ? [{ id, weight }] : []
  })

// A weighted draw among the buyers who are open and have something to buy; `rng`
// is a 0-1 source. The fair, which can only be had once a year, is never passed up.
export const pickCustomer = (now: Date, farm: Farm, rng: () => number): CustomerId | undefined => {
  const pool = eligibleCustomers(now, farm)
  if (pool.some(entry => entry.id === 'fair')) {
    return 'fair'
  }

  return pickWeighted(pool, rng)?.id
}

// The sale a buyer would make now, quantities drawn from their lot.
export const planSale = (
  id: CustomerId,
  now: Date,
  farm: Farm,
  rng: () => number,
): Sale | undefined => {
  const wants = wantsOf(id, now, farm)
  if (wants.length === 0) {
    return undefined
  }
  const lines = wants.map(want => {
    const qty = want.min + Math.floor(rng() * (want.max - want.min + 1))

    return { product: want.product, qty, dollars: qty * want.price }
  })

  return {
    customer: id,
    lines,
    total: lines.reduce((sum, line) => sum + line.dollars, 0),
    isRibbon: id === 'fair',
  }
}

const isJar = (product: Product) =>
  product === 'appleCinnamon' || product === 'whiteLightning' || product === 'agedWhiskey'

// The farm after a sale: the goods leave (never below zero), the money goes in
// the books. A truck run's own count of trips is not touched here.
export const applySale = (old: Farm, sale: Sale, now: Date): Farm => {
  const take = (have: number, product: Product) =>
    Math.max(
      0,
      have - sale.lines.filter(line => line.product === product).reduce((sum, l) => sum + l.qty, 0),
    )
  const key = monthKey(now)
  const { ledger } = old
  // Aged jars whose time is up are sellable: they come out of the barrels first.
  const goods = collectAged(old.goods, now.getTime())
  const main = sale.lines.reduce((top, line) => (line.dollars > top.dollars ? line : top))
  const byProduct = { ...ledger.byProduct }
  for (const line of sale.lines) {
    byProduct[line.product] += line.dollars
  }

  return {
    ...old,
    shelf: {
      lightning: take(old.shelf.lightning, 'whiteLightning'),
      appleCinnamon: take(old.shelf.appleCinnamon, 'appleCinnamon'),
    },
    barn: {
      ...old.barn,
      bales: take(old.barn.bales, 'tobacco'),
      apples: take(old.barn.apples, 'apples'),
      corn: take(old.barn.corn, 'corn'),
    },
    goods: {
      ...goods,
      appleButter: take(goods.appleButter, 'appleButter'),
      twists: take(goods.twists, 'twists'),
      whiskey: take(goods.whiskey, 'agedWhiskey'),
    },
    ledger: {
      ...ledger,
      jarsSold:
        ledger.jarsSold +
        sale.lines.filter(line => isJar(line.product)).reduce((sum, l) => sum + l.qty, 0),
      total: ledger.total + sale.total,
      cash: ledger.cash + sale.total,
      month: {
        key,
        amount: (ledger.month.key === key ? ledger.month.amount : 0) + sale.total,
      },
      best:
        ledger.best === null || sale.total > ledger.best.amount
          ? { amount: sale.total, customer: sale.customer, product: main.product }
          : ledger.best,
      byCustomer: { ...ledger.byCustomer, [sale.customer]: ledger.byCustomer[sale.customer] + sale.total },
      byProduct,
      ribbons: ledger.ribbons + (sale.isRibbon ? 1 : 0),
      fairYear: sale.isRibbon ? now.getFullYear() : ledger.fairYear,
    },
  }
}

export type Sold = { next: Farm; sale?: Sale; isNew: boolean }

// A truck run's sale, decided on the farm as stored: the buyer the truck set out
// for if they still want what is there, else whoever does. `isNew` is a first
// sale to a buyer who never bought before.
export const sellTo = (
  old: Farm,
  preferred: CustomerId | undefined,
  now: Date,
  rng: () => number,
): Sold => {
  const id =
    preferred !== undefined && wantsOf(preferred, now, old).length > 0
      ? preferred
      : pickCustomer(now, old, rng)
  const sale = id === undefined ? undefined : planSale(id, now, old, rng)
  if (!sale) {
    return { next: old, isNew: false }
  }

  return {
    next: applySale(old, sale, now),
    sale,
    isNew: old.ledger.byCustomer[sale.customer] === 0,
  }
}

const LOADS: Record<Product, Truck['load']> = {
  appleCinnamon: 'jar',
  whiteLightning: 'jar',
  tobacco: 'bale',
  apples: 'apple',
  corn: 'corn',
  appleButter: 'butter',
  twists: 'twist',
  agedWhiskey: 'whiskey',
}

// What rides in the truck bed for a buyer: the glyph of what they would pay the
// most for, or a box when there is nobody to sell to.
export const loadFor = (
  id: CustomerId | undefined,
  now: Date,
  farm: Farm,
): Truck['load'] => {
  const wants = id === undefined ? [] : wantsOf(id, now, farm)
  const main = wants.reduce<Want | undefined>(
    (top, want) => (!top || want.max * want.price > top.max * top.price ? want : top),
    undefined,
  )

  return main ? LOADS[main.product] : 'box'
}

const WORDS = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten']
const wordOf = (n: number) => WORDS[n] ?? String(n)

const lineWhat = (line: SaleLine) => {
  const { qty } = line
  switch (line.product) {
    case 'appleCinnamon':
    case 'whiteLightning':
      return `${wordOf(qty)} ${qty === 1 ? 'jar' : 'jars'}`
    case 'tobacco':
      return `${wordOf(qty)} ${qty === 1 ? 'bale' : 'bales'}`
    case 'apples':
      return `${qty} bu apples`
    case 'corn':
      return `${qty} bu corn`
    case 'appleButter':
      return `${wordOf(qty)} ${qty === 1 ? 'crock' : 'crocks'} of apple butter`
    case 'twists':
      return `${wordOf(qty)} ${qty === 1 ? 'tobacco twist' : 'tobacco twists'}`
    case 'agedWhiskey':
      return `${wordOf(qty)} ${qty === 1 ? 'jar' : 'jars'} of aged whiskey`
  }
}

// "three jars" or "three jars, 20 bu apples".
export const whatOf = (sale: Sale) => sale.lines.map(lineWhat).join(', ')

// The saying category of each buyer's sale lines (the legacy bucket has none of
// its own).
export const saleCategory = (id: CustomerId): SayingCategory => {
  switch (id) {
    case 'opal':
      return 'saleOpal'
    case 'tripper':
      return 'saleTripper'
    case 'warehouse':
      return 'saleWarehouse'
    case 'market':
      return 'saleMarket'
    case 'mill':
      return 'saleMill'
    case 'fair':
      return 'saleFair'
    case 'store':
    case 'town':
      return 'saleStore'
  }
}

// A sale line's template, `{what}` and `{money}` filled in.
export const fillSale = (template: string, sale: Sale) =>
  template.replace('{what}', whatOf(sale)).replace('{money}', `$${sale.total}`)

// A neighbor's visit: Miss Opal takes one jar, if there is one.
export const sellOpal = (old: Farm, now: Date): Farm => {
  const sale = planSale('opal', now, old, () => 0)

  return sale ? applySale(old, sale, now) : old
}

