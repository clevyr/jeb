import type { CustomerId, Farm, Visit, VisitKind } from '../types'
import { applySale, eligibleCustomers, planSale } from './market'
import type { Sale } from './market'
import { dateKeyOf, pickWeighted } from './util'

// Ambient farm life: now and then somebody comes up the road on their own (a
// buyer in a rig, Miss Opal on foot, the mail, a neighbour's tractor passing
// by), and Blue now and then runs the fields. Pure; the clock and the dice are
// handed in, and a sale is decided on the farm it is handed.

const SECOND = 1000
const MINUTE = 60 * SECOND

// Wall-clock gaps on the session clock: the first visit comes two to four
// minutes in, then four to nine minutes after the last one ended; a visit that
// cannot start (the truck is out, a happening is on) tries again 30 s later.
export const FIRST_VISIT_MS: readonly [number, number] = [2 * MINUTE, 4 * MINUTE]
export const NEXT_VISIT_MS: readonly [number, number] = [4 * MINUTE, 9 * MINUTE]
export const VISIT_RETRY_MS = 30 * SECOND
// Blue's own errand to the fields and back, when nothing else is going on.
export const ERRAND_MS: readonly [number, number] = [5 * MINUTE, 8 * MINUTE]
// A time that never comes: the schedule while a visit is under way.
export const NEVER = Number.MAX_SAFE_INTEGER

// A whole number of ms between `range[0]` and `range[1]`, from a 0-1 source.
export const spanOf = (range: readonly [number, number], rng: () => number) =>
  range[0] + Math.floor(rng() * (range[1] - range[0] + 1))

// How a visit moves, in 500 ms ticks: it advances `step` along `reach` every
// `every` ticks (a rig 2 over 32, 16 ticks; Miss Opal 1 over 20; the tractor a
// crawl of half a unit a tick over 60, a minute), then stands and deals for
// 80 to 120 ticks (40 to 60 s) and goes back at the same pace.
export const VISIT_SPECS: Record<VisitKind, { step: number; reach: number; every: number }> = {
  store: { step: 2, reach: 32, every: 1 },
  mill: { step: 2, reach: 32, every: 1 },
  tripper: { step: 2, reach: 32, every: 1 },
  mail: { step: 2, reach: 32, every: 1 },
  opal: { step: 1, reach: 20, every: 1 },
  tractor: { step: 1, reach: 60, every: 2 },
}
export const DEAL_TICKS: readonly [number, number] = [80, 120]

// The tractor never stops: it crosses once and is gone.
export const isPassing = (kind: VisitKind) => kind === 'tractor'



// The rig each buyer comes in; the fair stays a truck-run thing and the legacy
// bucket never comes.
const RIGS: Partial<Record<CustomerId, VisitKind>> = {
  opal: 'opal',
  store: 'store',
  market: 'store',
  mill: 'mill',
  warehouse: 'mill',
  tripper: 'tripper',
}

// Who would come to buy now: every open buyer with stock to take but the fair.
export const visitorsFor = (now: Date, farm: Farm) =>
  eligibleCustomers(now, farm).filter(entry => RIGS[entry.id] !== undefined)

export const MAIL_FROM = 10
export const MAIL_TO = 14

// The local day as a key, for the mail's once a day.
export const dayKeyOf = dateKeyOf

// Whether the mail may come: the mailbox is up, between 10:00 and 14:00 local,
// and not yet today.
export const isMailDue = (now: Date, farm: Pick<Farm, 'upgrades'>, lastMailDay: string) =>
  farm.upgrades.includes('mailbox') &&
  now.getHours() >= MAIL_FROM &&
  now.getHours() < MAIL_TO &&
  lastMailDay !== dayKeyOf(now)

export const WEIGHT_BUYER = 6
export const WEIGHT_MAIL = 2
export const WEIGHT_TRACTOR = 2

export type VisitPick = { kind: VisitKind; customer?: CustomerId }

// What comes by: a buyer most of the time (one with stock, drawn as the truck
// run draws, by what each could pay), else the mail when it is due, else the
// tractor. Nobody eligible to buy makes it a non-buyer visit.
export const pickVisit = (
  now: Date,
  farm: Farm,
  lastMailDay: string,
  rng: () => number,
): VisitPick => {
  const buyers = visitorsFor(now, farm)
  const pool: { weight: number; pick: 'buyer' | 'mail' | 'tractor' }[] = [
    { weight: buyers.length > 0 ? WEIGHT_BUYER : 0, pick: 'buyer' },
    { weight: isMailDue(now, farm, lastMailDay) ? WEIGHT_MAIL : 0, pick: 'mail' },
    { weight: WEIGHT_TRACTOR, pick: 'tractor' },
  ]
  const drawn = pickWeighted(pool, rng)?.pick ?? 'tractor'
  if (drawn === 'buyer') {
    const buyer = pickWeighted(buyers, rng)
    const kind = buyer ? RIGS[buyer.id] : undefined
    if (buyer && kind) {
      return { kind, customer: buyer.id }
    }
  }

  return { kind: drawn === 'mail' ? 'mail' : 'tractor' }
}

export type VisitSale = { next: Farm; sale?: Sale; isNew: boolean }

// The sale a visiting buyer makes on the farm as stored: to that buyer and no
// other (a buyer with nothing to take any more buys nothing). Miss Opal's is
// her usual jar.
export const sellVisit = (old: Farm, id: CustomerId, now: Date, rng: () => number): VisitSale => {
  const sale = planSale(id, now, old, id === 'opal' ? () => 0 : rng)
  if (!sale) {
    return { next: old, isNew: false }
  }

  return { next: applySale(old, sale, now), sale, isNew: old.ledger.byCustomer[id] === 0 }
}
