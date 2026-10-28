// Small helpers the other modules share. Pure.

// Text with control characters turned to spaces, trimmed and cut to `max`.
export const cleanText = (value: unknown, max: number) =>
  String(value ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .trim()
    .slice(0, max)

// The local day as 'YYYY-MM-DD', the one key every module dates things with.
export const dateKeyOf = (now: Date) =>
  `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`

// "1 jar", "2 jars"; `many` for the plurals that are not just an s.
export const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`

// A plain object read as a record of unknowns; anything else (an array, null, a
// primitive) reads as an empty one.
export const recordOf = (value: unknown) =>
  (typeof value === 'object' && value !== null && !Array.isArray(value) ? value : {}) as Record<
    string,
    unknown
  >

// A weighted draw: `rng` is a 0-1 source. Nothing when no entry has any weight.
export const pickWeighted = <T extends { weight: number }>(
  pool: readonly T[],
  rng: () => number,
): T | undefined => {
  const total = pool.reduce((sum, entry) => sum + entry.weight, 0)
  if (total <= 0) {
    return undefined
  }
  let roll = rng() * total
  for (const entry of pool) {
    roll -= entry.weight
    if (roll < 0) {
      return entry
    }
  }

  return pool[pool.length - 1]
}
