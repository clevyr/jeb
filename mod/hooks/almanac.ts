// Jeb's almanac: the moon, the signs, the burley calendar, weather lore and
// the tunes. Pure: every function takes the date it should read (local time
// for the calendar, absolute time for the moon).

export const SYNODIC = 29.530588853
const NEW_MOON_JD = 2451550.1

export const MOON_NAMES = [
  'new',
  'waxing crescent',
  'first quarter',
  'waxing gibbous',
  'full',
  'waning gibbous',
  'last quarter',
  'waning crescent',
] as const
export const MOON_EMOJI = ['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘'] as const
const CUTOFFS = [0.03, 0.22, 0.28, 0.47, 0.53, 0.72, 0.78, 0.97]


export const julianDay = (date: Date) => date.getTime() / 86_400_000 + 2440587.5

export type Moon = { age: number; phase: number; name: string; emoji: string; isWaxing: boolean }

export const moonPhase = (date: Date): Moon => {
  const raw = (julianDay(date) - NEW_MOON_JD) % SYNODIC
  const age = (raw + SYNODIC) % SYNODIC
  const phase = age / SYNODIC
  const at = CUTOFFS.findIndex(cutoff => phase < cutoff)
  const named = at < 0 ? 0 : at

  return {
    age,
    phase,
    name: MOON_NAMES[named] as string,
    emoji: MOON_EMOJI[named] as string,
    isWaxing: phase < 0.5,
  }
}


const FRUITFUL = new Set([3, 7, 11])
const BARREN = new Set([0, 2, 4, 5, 8, 10])

export const signKind = (index: number): 'fruitful' | 'barren' | 'middling' =>
  FRUITFUL.has(index) ? 'fruitful' : BARREN.has(index) ? 'barren' : 'middling'


const short = (isWaxing: boolean, signIndex: number) => {
  const kind = signKind(signIndex)

  return kind === 'fruitful'
    ? isWaxing
      ? 'fine day to set beans'
      : 'fine day to plant taters'
    : kind === 'barren'
      ? "good for weedin' and clearin'"
      : isWaxing
        ? 'beans and corn will do'
        : 'taters and turnips will do'
}




export const dayIndex = (date: Date) =>
  Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86_400_000)











export const HAPPENINGS = [
  "Seed catalogs are showin' up in the mailbox this time of year.",
  "Folks are pourin' over seed catalogs and waitin' on spring.",
  "It's maple syrup time, this time of year, where the sap runs.",
  'Ramp feeds are about this time of year, spring in a skillet.',
  "Strawberry time. Folks are pickin' and puttin' up jam.",
  "West Virginia's birthday is June 20. Montani Semper Liberi.",
  "Porch pickin' and a Fourth of July supper this time of year.",
  "String-band gatherings and the county fair come around this time of year.",
  "Sorghum and apple time hereabouts, this time of year.",
  "Apple butter stir-offs this time of year. Somebody's always stirrin'.",
  "Buck season's comin' on, and folks are talkin' about it at the store.",
  "Stripping tobacco by the stove, tellin' stories.",
]

export const happening = (date: Date) => HAPPENINGS[date.getMonth()] as string




// Night here is 21:00 through 05:59.
export const isNightHour = (hour: number) => hour >= 21 || hour < 6

// 'dark' on new-moon nights and 'full' on full-moon nights, else undefined.
export const moonNight = (date: Date): 'dark' | 'full' | undefined => {
  if (!isNightHour(date.getHours())) {
    return undefined
  }
  const { phase } = moonPhase(date)
  if (phase < 0.03 || phase > 0.97) {
    return 'dark'
  }

  return phase >= 0.47 && phase <= 0.53 ? 'full' : undefined
}

// Nth weekday (0 Sunday) of a month, as a day of the month.
export const nthWeekday = (year: number, month: number, weekday: number, n: number) => {
  const first = new Date(year, month, 1).getDay()

  return 1 + ((weekday - first + 7) % 7) + (n - 1) * 7
}

export const isThirdSaturdayOfOctober = (date: Date) =>
  date.getMonth() === 9 && date.getDay() === 6 && date.getDate() === nthWeekday(date.getFullYear(), 9, 6, 3)

export const isThanksgiving = (date: Date) =>
  date.getMonth() === 10 && date.getDate() === nthWeekday(date.getFullYear(), 10, 4, 4)

export type Day = {
  isPumpkin: boolean
  isThanksgiving: boolean
  isChristmas: boolean
  isGroundhog: boolean
  isNewYear: boolean
  isBirthday: boolean
}

export const dayFlags = (date: Date): Day => {
  const m = date.getMonth()
  const d = date.getDate()

  return {
    isPumpkin: m === 9 && d >= 25,
    isThanksgiving: isThanksgiving(date),
    isChristmas: m === 11 && d >= 20 && d <= 26,
    isGroundhog: m === 1 && d === 2,
    isNewYear: m === 0 && d === 1,
    isBirthday: m === 5 && d === 20,
  }
}

// Groundhog Day's verdict, the same all day.
export const shadowVerdict = (date: Date) =>
  dayIndex(date) % 2 === 0
    ? 'Whistle pig saw his shadow. Six more weeks of winter.'
    : 'Whistle pig saw no shadow. Early spring, maybe.'

// A line for the date, if it has one (a holiday or a time of year).
export const dateLines = (date: Date): string[] => {
  const flags = dayFlags(date)
  const m = date.getMonth()
  const hour = date.getHours()
  const lines: string[] = []

  if (flags.isNewYear) {
    lines.push('New year. Same holler.')
  }
  if (flags.isGroundhog) {
    lines.push(shadowVerdict(date))
  }
  if (flags.isBirthday) {
    lines.push('Happy birthday, West Virginia. Montani Semper Liberi.')
  }
  if ((m === 2 || m === 3) && hour >= 17 && hour < 22) {
    lines.push("Spring peepers are singin' down at the branch.")
  }
  if (m === 3) {
    lines.push("Ramps are up. Smell'll clear a church.")
  }
  if (flags.isThanksgiving) {
    lines.push('Thanksgiving. Wild turkey in the yard, store-bought on the table.')
  }
  if (flags.isChristmas) {
    lines.push("Tree's up. Snow'd be nice.")
  }
  if (flags.isPumpkin) {
    lines.push('Pumpkins in the orchard. Mind the ghosts.')
  }

  return lines
}
