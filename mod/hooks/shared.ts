// Pure helpers more than one hooks module needs.

import type { Farm, FarmView } from '../types'
import { STACK_COLUMNS, stackColumns } from './crafting'
import { viewOfDrops } from './drops'
import { pileOf } from './unlocks'

// The truck's trip is sixteen ticks: out to the left edge in the first half,
// then back home.
export const TRUCK_TICKS = 16

// A hired hand's look: one of six farmhands, kept for as long as the agent is out
// (a stable hash of its id).
export const HAND_LOOKS = 6
export const hashOf = (id: string) => {
  let h = 0
  for (let i = 0; i < id.length; i += 1) {
    h = (h * 31 + id.charCodeAt(i)) >>> 0
  }

  return h
}

// A count short enough for its cell: whole up to 999, then 1.2k, 12k, 123k,
// 1.2M. `room` is the columns it may take; past it the decimal goes, so a
// count is shortened and never cut off.
export const abbrevCount = (n: number, room = 5) => {
  const value = Math.max(0, Math.floor(n))
  if (value < 1000) {
    return String(value)
  }
  const unit = value >= 1_000_000 ? 1_000_000 : 1000
  const suffix = unit === 1000 ? 'k' : 'M'
  const tenths = Math.floor(value / (unit / 10))
  if (tenths < 100) {
    const text = `${Math.floor(tenths / 10)}${tenths % 10 === 0 ? '' : `.${tenths % 10}`}${suffix}`
    if (text.length <= room) {
      return text
    }
  }

  return `${Math.floor(tenths / 10)}${suffix}`
}

// How many of the newest quilt squares the view keeps.
const QUILT_SHOWN = 10

// A stack count draws as 99+ from 100 up, so stock past 100 is held at 100 and
// its changes redraw nothing; unless more columns than the stack has room for are
// that big, when which of them make it depends on the true counts.
const STOCK_CAP = 100
// Only the stock that can stand in the stack is kept: aging jars only add to the
// whiskey column as the clock moves, so a column out of the top without them is
// out for good, and its count (zeroed here) never draws.
const stackStock = (farm: Farm) => {
  const { goods, materials } = farm
  const counts = [...Object.values(materials), goods.appleButter, goods.twists, goods.whiskey + goods.aged.length]
  const isCrowded = counts.filter(n => n >= STOCK_CAP).length > STACK_COLUMNS
  const shown = new Set(stackColumns(farm, new Date(0)).map(column => column.id))
  const keep = (id: string, n: number) => (shown.has(id) ? (isCrowded ? n : Math.min(n, STOCK_CAP)) : 0)

  return {
    materials: Object.fromEntries(Object.entries(materials).map(([id, n]) => [id, keep(id, n)])) as Farm['materials'],
    goods: {
      appleButter: keep('appleButter', goods.appleButter),
      twists: keep('twists', goods.twists),
      whiskey: isCrowded ? goods.whiskey : Math.min(goods.whiskey, STOCK_CAP),
    },
  }
}

// What of the farm shows in the scene: a farm write that changes none of it leaves
// the scene as it was (see wakeOnView in register.tsx).
export const viewOf = (farm: Farm): FarmView => ({
  crops: farm.crops,
  lifetime: { bales: farm.lifetime.bales },
  barn: { corn: farm.barn.corn, apples: farm.barn.apples },
  still: farm.still,
  shelf: { appleCinnamon: farm.shelf.appleCinnamon },
  ledger: { cash: farm.ledger.cash },
  upgrades: farm.upgrades,
  built: farm.built,
  materials: stackStock(farm).materials,
  goods: { ...stackStock(farm).goods, aged: farm.goods.aged.map(jar => jar.readyAt) },
  quilt: farm.quilt.slice(-QUILT_SHOWN).map(square => ({ c: square.c })),
  unlocks: farm.unlocks ?? [],
  pile: pileOf(farm.materials.lumber),
  coffee: farm.unlockDay?.coffee ?? '',
  since: farm.unlockDay?.since ?? '',
  drops: viewOfDrops(farm),
})
