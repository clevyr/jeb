import type { Farm } from '../types'
import { anonymizeFarm, isSalt, mintSalt } from './anonymize'

// Settling the anonymizer's salt between sessions that share one store. The store
// has no compare-and-set, so a farm from before the anonymizer (real camp names in
// it, `anonPending`) is not made over the moment a session loads it: two sessions
// that did would each make a salt, the last write would win and the other session
// would key its square under a salt the farm no longer has. Each session takes one
// step at a time, at most SETTLE_MS apart:
//
// - no salt on the stored farm: this session's own is written (a farm that got
//   another session's first stands: the save leaves it);
// - a salt read that is not the one read last time: it is adopted, whoever's it is;
// - the same salt read twice in a row: the farm is made over under that stored salt
//   and nothing else. The same farm under the same salt is the same farm, so every
//   session that gets this far writes the same thing.
//
// Pure of the host: the store and the clock are handed in.

export const SETTLE_MS = 1_000

export type Settle = {
  // The salt read last time ('' before the first read, or after a write).
  seen: string
  // When the last step ran (0: none yet).
  at: number
  // This session's own salt, made when first needed.
  own: string
}

export const freshSettle = (): Settle => ({ seen: '', at: 0, own: '' })

export type SettleIo = {
  now: number
  // The stored farm as it is, camps unconverted (undefined: none, or not a farm).
  read: () => Promise<Farm | undefined>
  // A change to the stored farm, read-modify-written in line with the other saves.
  save: (change: (old: Farm) => Farm) => Promise<void>
  // The salt the session holds as the farm's now ('' while the farm is waiting).
  salt: () => string
  rng?: () => number
}

// 'wait': not over, another step is due; 'over': the farm has its salt and its
// names are places (the session holds the salt); 'gone': there is no farm to settle.
export type SettleResult = 'wait' | 'over' | 'gone'

export const settleStep = async (state: Settle, io: SettleIo): Promise<SettleResult> => {
  if (state.at > 0 && io.now - state.at < SETTLE_MS) {
    return 'wait'
  }
  state.at = io.now
  const stored = await io.read()
  if (!stored) {
    return 'gone'
  }
  if (!stored.anonPending) {
    // Made over by another session (or never waiting): its salt is the farm's.
    await io.save(old => old)
  } else if (!isSalt(stored.anonSalt)) {
    state.own = isSalt(state.own) ? state.own : mintSalt(io.rng)
    const own = state.own
    await io.save(old => (old.anonPending && !isSalt(old.anonSalt) ? { ...old, anonSalt: own } : old))
    state.seen = ''
  } else if (stored.anonSalt !== state.seen) {
    state.seen = stored.anonSalt
  } else {
    const salt = stored.anonSalt
    await io.save(old => (old.anonPending && old.anonSalt === salt ? anonymizeFarm(old) : old))
    state.seen = ''
  }

  return isSalt(io.salt()) ? 'over' : 'wait'
}
