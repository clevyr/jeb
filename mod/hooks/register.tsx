import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, TurnStepChunk, TurnStepResult } from 'claude-code'

import type { ActiveEvent, Anim, Camps, Crop, CustomerId, Drops, DropArt, EventId, Farm, IdleAct, KeptSession, Mood, Pose, Say, Surprise, Truck, Visit } from '../types'
import {
  addHired,
  fieldsOf,
  findHired,
  HAND_FAILED_LINE,
  HAND_HOME_LINE,
  hireLine,
  hireOf,
  kindOf,
  LIST_GRACE_MS,
  matesOf,
  WORKFLOW_IDLE_MS,
  withoutHired,
} from './agents'
import type { Hired } from './agents'
import {
  beatFor,
  isPlace,
  isSalt,
  isToken,
  lineFor,
  liveTokenOf,
  mintSalt,
  neighborOf,
  campTagOf,
  placeOfTag,
  placeSeen,
  secureHex,
  sessionKeyOf,
  shieldFarm,
  TOOL_LINE,
} from './anonymize'
import { freshSettle, settleStep } from './settle'
import {
  AREA_MIN_EVENTS,
  areaTakenOf,
  areaClaimsOf,
  areaKeyOf,
  areasOf,
  areaWorkOf,
  bibleOf,
  choicesOf,
  claimArea,
  countWork,
  identityOf,
  isAreaSecret,
  mintAreaSecret,
  offlineArea,
  profileOf,
  putArea,
  releaseClaim,
  reserveAreaAs,
  touchSeen,
  validateArea,
  withoutWork,
  workKindOf,
} from './areas'
import type { Area, AreaClaimed, AreaInput, AreaProfile, WorkEntry, WorkKind } from './areas'
import { beat, campName, lanternLine, othersOf, splitCamps, staleOf, without } from './camps'
import type { Stale } from './camps'
import { classify, denyRuleOf, workOf } from './classify'
import type { Segment } from './classify'
import {
  CLEAR_LINE,
  FORK_LINE,
  GATE_LINE,
  markGate,
  resumeLine,
  SWEEP_AUTO_LINE,
  SWEEP_LINE,
  sweptLine,
  takeGate,
} from './chores'
import { mcpKindOf, mcpServerOf } from './mcp'
import {
  activeArc,
  applyDelivery,
  claimSlot,
  dueSlot,
  forcedSlot,
  freshDrops,
  newsOf,
  nextArcStep,
  recentSummaries,
  reserveModelAs,
  sayingPool,
  withNewsSeen,
} from './drops'
import type { Claimed, Delivery } from './drops'
import { flagsPathOf, isDropsOffByApp } from './flags'
import { JEB_NEWS } from './news'
import { offlineDrop } from './offline'
import { askHaiku, askHaikuArea, promptInputOf } from './signals'
import { levelOf } from './surprise'
import type { Drop } from './surprise'
import {
  dateLines,
  dayFlags,
  isNightHour,
} from './almanac'
import {
  buySupplies,
  craftAll,
  gain,
  isBuilt,
  mashFull,
  noteEdit,
  noteMothman,
  STRAW_PER_CORN,
  STRAW_PER_TOBACCO,
} from './crafting'
import type { Made } from './crafting'
import { CROP_BARN, RIPE } from './crops'
import { beatsOf, durationOf, pickEvent, restOf } from './events'
import type { Beat } from './events'
import {
  freshFarm,
  freshPlants,
  isFutureFarm,
  newUnlocks,
  proofOf,
  raidCorn,
  readFarm,
  sellOne,
} from './homestead'
import type { Milestone, Upgrade } from './homestead'
import {
  bump,
  freshSession,
  keepOf,
  keptOf,
  markFor,
  noteBuilt,
  squareFor,
  stitchFarm,
  stitchFromBeat,
  stitchLine,
  stitchOf,
} from './quilt'
import type { Counter } from './quilt'
import { fillSale, loadFor, pickCustomer, saleCategory, sellTo, STICKS_PER_BALE } from './market'
import type { Sold } from './market'
import { readOptions, TALK_LEVELS } from './options'
import type { JebOptions, Talk } from './options'
import {
  LIMIT_LINE,
  limitCrossings,
  reactTo,
} from './reactions'
import { TRUCK_TICKS, viewOf } from './shared'
import { bagPick, MONTH_CATEGORIES, TOOL_SAYINGS } from './sayings'
import type { SayingCategory } from './sayings'
import { isShip } from './ship'
import {
  COFFEE_FROM,
  COFFEE_TO,
  dateKeyOf,
  firstUnlockSpan,
  RAINBOW_TICKS,
  RETRY_UNLOCK_MS,
  STAR_TICKS,
  stepUnlock,
  unlockOf,
  WET_MS,
} from './unlocks'
import type { Step } from './unlocks'
import { liveAtOf, liveBody, liveKey, livePrune, liveRecord, tokenOfKey } from './live'
import type { LiveRecord } from './live'
import { recordOf } from './util'
import {
  DEAL_TICKS,
  ERRAND_MS,
  FIRST_VISIT_MS,
  isPassing,
  NEVER,
  NEXT_VISIT_MS,
  pickVisit,
  sellVisit,
  spanOf,
  VISIT_RETRY_MS,
  VISIT_SPECS,
} from './visits'
import {
  BAD_BATCH_LINE,
  BURST_CHUNKS,
  BURST_TICKS,
  BUILDING_CAP_MS,
  buildingOf,
  BUSY_TALK_MS,
  CLEAN_LINE,
  cowLabel,
  COUNTY_RAIN_LINE,
  cowLine,
  DENY_CAP_MS,
  DENY_LINES,
  DROUGHT_LINE,
  FIRST_RAIN_LINE,
  HAND_WATER_LINE,
  HOED_LINE,
  HUSH_MS,
  IDLE_TALK_MS,
  LINT_CAP_MS,
  MAX_COWS,
  MAX_KEPT_COWS,
  MAX_SEEN_KEYS,
  PHPSTAN_LINE,
  plotFor,
  RAIN_LINE,
  RUN_LINE,
  serviceKey,
  STREAK_AT,
  STREAK_LINE,
  TEST_CAP_MS,
  TEST_RUN_LINE,
  ticketKeys,
  UP_LINE,
  WEATHER_TICKS,
  WEEDS_LINE,
} from './workday'

// Economy: how much work grows one stage of a crop, and how the still runs.
const TOBACCO_MS = 20_000
const CORN_TOKENS = 400
const APPLE_TOKENS = 25_000

// Deliveries: a trip sells to one buyer (see market.ts); this many may queue.
const MAX_QUEUE = 5

// Animation: one 500 ms ticker drives everything. Motion (happenings, the
// truck, Blue's run, fx) writes a frame per tick, 2 a second; the idle frame
// advances on a slow tick, every 3 seconds.
const TICK_MS = 500
const SLOW_TICKS = 6
const FLUSH_MS = 10_000
const FRAME_WRAP = 5040
// The 30 s housekeeping: the clock, the agent list (every other round, the
// heartbeat).
const DND_TICKS = 60
// The session clock and the machine's differ by more than this: it slept, or
// somebody set the clock.
const CLOCK_JUMP_MS = 60_000
// A save that finds another session wrote at the same moment applies its change
// again onto theirs, at most this many times.
const MAX_REAPPLY = 2
// At most this many ticket keys wait for the anonymizer's salt to settle.
const MAX_HELD_KEYS = 16
// The odds, each 30 s of a night with the scene awake, of a shooting star.
const STAR_ODDS = 0.04
const IDLE_ACT_TICKS = 24
// Still life: this long (counted in ticks) with no activity freezes the scene on
// its current frame, so the terminal has nothing to repaint until the next
// activity wakes it.
const STILL_AFTER_MS = 120_000
const STILL_TICKS = STILL_AFTER_MS / TICK_MS
const IDLE_SAY_TICKS = 120
const DIM_TICKS = 60
// How long a speech bubble stays up after a line, in ticks (8 s).
const TALK_TICKS = 16
const LONG_TURN_MS = 120_000
const DOG_STEP = 4
const DOG_REACH = 36
const EVENT_IDLE_TICKS = 360
const EVENT_BUSY_TICKS = 1440
const EVENT_COOLDOWN_TICKS = 1200
const FX_WAG = 6
const FX_WINK = 5
const FX_PUFF = 4
const FX_GATE = 8
// The newest square on the clothesline flashes for six seconds after a stitch.
const FX_STITCH = 12
// A session ending stitches its square only if this much of the exit bound is left.
const STITCH_MIN_MS = 300
const HEART_TICKS = 120
// Live streaming: a change of activity (thinking, writing, a tool) shows at
// once, at most LIVE_BUDGET of them in each second (two ticks); the rest wait
// for the next window and the latest wins.
const LIVE_WINDOW_TICKS = 2
const LIVE_BUDGET = 3
const MAX_STEP_TURNS = 32
const MAX_STREAMED = 16

// Ambient visits (see visits.ts) draw their gaps, kinds and quantities from
// `visitRng`: Math.random, unless JEB_VISITS in the environment says otherwise
// (a decimal from 0 up to 1 is a fixed draw, for a test; `off` leaves the road
// empty).
const VISITS_OFF = 'off'
let visitRng: () => number = Math.random
const MAIL_LINE = "Mail's here."

// The userConfig values, set when the module registers (and kept current when
// /config changes one).
let OPT: JebOptions = readOptions(undefined)

// The one 500 ms ticker; a new session cancels the old one.
let ticker: { cancel: () => void } | undefined

// A line said before the session started (the classic SessionStart can come first).
let pendingLine: string | undefined

// Writes to the farm run one after another, each on the stored value.
let saving: Promise<unknown> = Promise.resolve()

// Writes of this session's live record (and its removal) run one after another too.
let living: Promise<unknown> = Promise.resolve()

const FIRST_LINE = 'Howdy. Pull up a stump.'


// What the store keeps of the options: the creativity switch and the talk level.
// The hook reactions are read once, as the hooks register.
type Overrides = { creativity?: boolean; talk?: Talk }

// What a line is, for the talk gate: `first` the turn's opening remark,
// `say` the everyday chatter, `milestone` a harvest, jar, upgrade or delivery,
// `verdict` a test or lint result, `streak` a result after a run of failures,
// `deny` a refused command, `start` a greeting or a session's own line, `cont`
// the rest of a happening already begun, `reply` the answer to a person's poke.
type TalkKind = 'first' | 'say' | 'milestone' | 'verdict' | 'streak' | 'deny' | 'start' | 'cont' | 'reply'

const IDLE_ACTS: IdleAct[] = ['banjo', 'sip', 'nap', 'chase', 'smoke']

const RATES: Record<Crop, number> = {
  tobacco: TOBACCO_MS,
  corn: CORN_TOKENS,
  apples: APPLE_TOKENS,
}

type Barn = Farm['barn']

// One change of what the model is doing, as the stream showed it.
type Live = { act: string; name: string; id: string }

const freshAnim = (): Anim => ({
  frame: 0,
  idleAct: 'banjo',
  pose: 'none',
  truck: null,
  visit: null,
  dogRun: 0,
  isNight: false,
  isDim: false,
  isTalking: false,
  event: null,
  wag: false,
  wink: false,
  puff: false,
  sip: false,
  hands: [],
  more: {},
  mates: 0,
  lanterns: 0,
  isGated: false,
  prop: '',
  weather: { kind: 'none', plot: 'all' },
  building: '',
  cows: [],
  moreCows: 0,
  stitch: false,
  live: 'N',
  rainbow: false,
  wet: false,
  star: 0,
})

const say = atom({ plugin: 'jeb', key: 'say' } as const, {
  line: FIRST_LINE,
  mood: 'idle',
} as Say)
const anim = atom({ plugin: 'jeb', key: 'anim' } as const, freshAnim())
const farm = atom({ plugin: 'jeb', key: 'farm' } as const, freshFarm())
// The session's id and record so far: unlike S it survives a plugin reload (the
// one a change of /config causes), so the record is not wiped.
const kept = atom({ plugin: 'jeb', key: 'kept' } as const, null as KeptSession | null)

// What the ticker and the hooks share; reset whenever a session starts.
const fresh = () => ({
  isBusy: false,
  pose: 'none' as Pose,
  ticks: 0,
  idleTicks: 0,
  quiet: 0,
  // Ticks since Jeb last said something: the bubble shows for a few seconds after.
  sinceSaid: 0,
  // The bubble as the say atom holds it, and when it was said (ms on the session
  // clock), kept here too so the live record never has to read the atom back.
  line: FIRST_LINE,
  mood: 'idle' as Mood,
  saidAt: 0,
  // Ticks since anything happened, and whether the scene is frozen (still life).
  calm: 0,
  isStill: false,
  pendingMs: 0,
  turnMs: 0,
  isLongSaid: false,
  dogRun: 0,
  dogDir: 0,
  truck: null as Truck | null,
  // Who the truck on the road set out for (the sale itself is decided when it is home).
  truckFor: null as CustomerId | null,
  queued: 0,
  // The ambient visit: when the next one is due (ms on the session clock; 0
  // before the session is scheduled), the one under way, who it is for, the ticks
  // spent dealing, the day the mail last came and when Blue next runs the fields.
  nextVisitAt: 0,
  visit: null as Visit | null,
  visitFor: null as CustomerId | null,
  visitTicks: 0,
  visitDeal: 0,
  nextErrandAt: 0,
  lastAnim: '',
  lastView: '',
  nowMs: 0,
  errorStreak: 0,
  eventTicks: 0,
  event: null as ActiveEvent | null,
  eventUsed: {} as Partial<Record<EventId, number>>,
  beats: [] as Beat[],
  beatIdx: 0,
  fx: { wag: 0, wink: 0, puff: 0, sip: 0, gate: 0, wx: 0, stitch: 0, star: 0 },
  // The little things (see unlocks.ts): when to look at the day's unlocks next
  // (ms on the session clock; 0 before the session is scheduled), what the farm
  // has unlocked and the day the late-night coffee came as the last save left
  // them, the burst clocks (rainbow in ticks, puddles in ms) and the night a
  // shooting star last crossed.
  unlockAt: 0,
  unlocks: [] as string[],
  coffee: '',
  rainbowUntil: 0,
  wetUntil: 0,
  starNight: '',
  isUnlocking: false,
  isCoffeeing: false,
  // The creative drops (see drops.ts): the stored slots and surprises as the last
  // save left them (plain state, so a quiet beat asks the host for nothing), when
  // this session began and last ran a drop, whether one is running, a happening
  // waiting for the road, and JEB_CREATIVITY
  // ('off' leaves the drops out, 'local' leaves the model and the host out).
  drops: freshDrops() as Drops,
  surprises: [] as Surprise[],
  startedAt: 0,
  dropLast: 0,
  isDropping: false,
  dropPlay: null as { art: { sprites: Surprise['sprites']; custom: DropArt[] }; until: number } | null,
  creativity: 'on' as 'on' | 'off' | 'local',
  // The desktop app's creative-drops flag (see flags.ts), as last read at a decision
  // point, and the slot (by day) it was last read for.
  isAppDropsOff: false,
  flagSlot: '',
  flagAt: 0,
  // JEB_DROP_NOW=1: one forced surprise this session, ignoring the clock (see tendDrops).
  // 'pending' until it has run (or been skipped by a failed gate), then 'done'.
  dropNow: 'off' as 'off' | 'pending' | 'done',
  dropNowAt: 0,
  // The news item to announce: this build's (see news.ts), or what JEB_NEWS says (JSON, for a test).
  news: null as unknown,
  // What this session has done so far, for its square and its journal line.
  session: freshSession(),
  turnSeed: 0,
  limits: {} as Record<string, number>,
  isTicking: false,
  // False for a `-p` run or the SDK: no ticker, no heartbeat, no squares.
  isInteractive: true,
  isStoreLocked: false,
  overrides: {} as Overrides,
  // Agents (at most 8), the camps of the other sessions (at most 7 names), and
  // this session's own heartbeat identity.
  agents: [] as Hired[],
  isListing: false,
  sessionId: '',
  // What `kept` last held (JSON), so an unchanged record is not written again.
  lastKept: '',
  campName: '',
  cwd: '',
  camps: [] as string[],
  // Compaction's broom, an MCP tool's glyph, a settings hook's gate.
  isSweeping: false,
  sweepPose: 'none' as Pose,
  prop: '',
  // The calls a settings hook refused (by tool_use_id, at most 16).
  gates: new Map<string, true>(),
  // The last words Jeb set on the spinner and the turn line.
  // Live streaming: what the model is doing now ('thinking', 'writing' or
  // 'tool:<name>'), the one change the throttle is holding back, the window it
  // counts in, the tool ids the stream announced (at most 16) and the turns
  // whose tokens already came in step by step (at most 32).
  activity: '',
  livePending: null as Live | null,
  liveWin: -1,
  liveCount: 0,
  streamed: [] as string[],
  stepTurns: [] as string[],
  // The workday. Cooldowns (ms stamps) live under a fixed set of keys; the
  // weather and the building are for the canvas; the cows are neighbors' numbers
  // made from the ticket keys (never the keys); fails count tests failed in a row;
  // `hushUntil` is the quiet after a failed run; the burst counters watch a long
  // streamed answer.
  cool: {} as Record<string, number>,
  wx: { kind: 'none', plot: 'all' } as Anim['weather'],
  building: '',
  cows: [] as number[],
  seenKeys: [] as number[],
  testFails: 0,
  lintFails: 0,
  hushUntil: 0,
  turnSaid: false,
  burstAt: 0,
  burstN: 0,
  burstUntil: 0,
  beatSpoke: false,
  // The anonymizer (see anonymize.ts): the farm's salt and its camps' tags as the
  // last save left them ('' until the farm has a salt: one is made the first time
  // it is needed), and this session's own key and today's live token, worked out
  // once for the id, salt and day they were made for.
  salt: '',
  places: [] as string[],
  // A farm from before the anonymizer is made over only once its salt has settled
  // between sessions (see settle.ts): whether this session waits for that, the salt
  // it last read from the store, when it read it, a salt of its own to offer, and
  // the ticket keys held until there is a salt to turn them into numbers.
  isSettling: false,
  isSettleBusy: false,
  settle: freshSettle(),
  heldKeys: [] as string[],
  // The lanterns line (see lanternLine) is said once the first heartbeat has come, if it could not be at the start.
  isLanternDue: false,
  // This session's camp as a tag (a short keyed hash of its name, see
  // anonymize.ts): the place is worked out from it, and it is registered on the
  // farm when the session's square is stitched. The raw name is never kept.
  campTag: '',
  keyFor: '',
  sessionKey: '',
  tokenFor: '',
  liveToken: '',
  // The live record (see live.ts): the token it was last written under and its
  // fields then (JSON), so an unchanged record is never written again; none is
  // written while the session is ending (until a /clear or a resume goes on under
  // its new id).
  liveAt: '',
  lastLive: '',
  isEnding: false,
  // The project's area (see areas.ts): its key ('' while the session has none),
  // the counted events not yet written, whether the stored counters and area have
  // been looked at, whether the area exists, the counted events as stored, the
  // day its `seen` was last noted, the day the model was last tried for it, and
  // whether a round is under way. The project's identity is never kept.
  areaKey: '',
  areaPending: {} as Partial<Record<WorkKind, number>>,
  isAreaLooked: false,
  isAreaHeld: false,
  areaCount: 0,
  areaSeenDay: '',
  areaTriedDay: '',
  isAreaBusy: false,
})
let S = fresh()

const POSES: Record<string, Pose> = {
  Read: 'read',
  Grep: 'read',
  Glob: 'read',
  LSP: 'read',
  Edit: 'edit',
  NotebookEdit: 'edit',
  Write: 'write',
  Bash: 'still',
  Monitor: 'still',
  WebFetch: 'web',
  WebSearch: 'web',
}

const STILL_TOOLS = new Set(['Bash', 'Monitor'])
const TOWN_TOOLS = new Set(['WebFetch', 'WebSearch'])
const ERRANDS = new Set(['Agent', 'Workflow'])
// A successful edit (main or subagent) is a third of a piece of lumber.
const EDIT_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit'])

// The session's clock as of the last second; refreshed by the ticker.
const nowDate = () => new Date(S.nowMs)

const isNightNow = () => isNightHour(nowDate().getHours())

const greetingFor = (): SayingCategory => {
  const hour = nowDate().getHours()

  return isNightNow() ? 'night' : hour < 12 ? 'morning' : hour < 18 ? 'afternoon' : 'evening'
}

type Outcome = { next: Farm; harvests: Crop[]; jars: number }

// Earns `amount` toward the next stage of one crop; each whole stage grows a
// random unripe plant, and a field that is all ripe is cut into the barn.
const growCrop = (old: Farm, crop: Crop, amount: number) => {
  const rate = RATES[crop]
  const barn = CROP_BARN[crop]
  let plants = [...old.crops[crop]]
  let progress = old.progress[crop] + Math.max(0, amount || 0)
  let stock = old.barn[barn]
  let harvests = 0

  while (progress >= rate) {
    progress -= rate
    const unripe = plants.flatMap((stage, i) => (stage < RIPE ? [i] : []))
    const at = unripe[Math.floor(Math.random() * unripe.length)]

    if (at !== undefined) {
      plants[at] = (plants[at] ?? 0) + 1
    }
    if (plants.every(stage => stage >= RIPE)) {
      plants = freshPlants()
      stock += 1
      harvests += 1
    }
  }

  return {
    next: {
      ...old,
      crops: { ...old.crops, [crop]: plants },
      progress: { ...old.progress, [crop]: progress },
      barn: { ...old.barn, [barn]: stock },
    } as Farm,
    harvests,
  }
}

// White lightning + a bushel of apples + a cinnamon stick make apple
// cinnamon. With no sticks on hand Jeb trades a bale for some in town.
const infuse = (old: Farm) => {
  let next = old
  let jars = 0

  while (next.shelf.lightning >= 1 && next.barn.apples >= 1) {
    let barn: Barn = next.barn
    if (barn.sticks < 1) {
      if (barn.bales < 1) {
        break
      }
      barn = { ...barn, bales: barn.bales - 1, sticks: barn.sticks + STICKS_PER_BALE }
      next = {
        ...next,
        lifetime: { ...next.lifetime, balesTraded: next.lifetime.balesTraded + 1 },
      }
    }
    next = {
      ...next,
      barn: { ...barn, apples: barn.apples - 1, sticks: barn.sticks - 1 },
      shelf: { lightning: next.shelf.lightning - 1, appleCinnamon: next.shelf.appleCinnamon + 1 },
    }
    jars += 1
    // The copper worm draws a second jar from the same lightning, if the barn
    // has the apple and the stick for it.
    if (isBuilt(next, 'copperWorm') && next.barn.apples >= 1 && next.barn.sticks >= 1) {
      next = {
        ...next,
        barn: { ...next.barn, apples: next.barn.apples - 1, sticks: next.barn.sticks - 1 },
        shelf: { ...next.shelf, appleCinnamon: next.shelf.appleCinnamon + 1 },
      }
      jars += 1
    }
  }

  return { next, jars }
}

const applyGrowth = (old: Farm, gains: [Crop, number][]): Outcome => {
  let next = old
  const harvests: Crop[] = []

  for (const [crop, amount] of gains) {
    const grown = growCrop(next, crop, amount)
    next = grown.next
    for (let i = 0; i < grown.harvests; i += 1) {
      harvests.push(crop)
    }
  }
  const bales = harvests.filter(crop => crop === 'tobacco').length
  const ears = harvests.filter(crop => crop === 'corn').length
  // The stalks and husks of a harvest are straw.
  const infused = infuse({
    ...gain(next, { straw: bales * STRAW_PER_TOBACCO + ears * STRAW_PER_CORN }),
    lifetime: { ...next.lifetime, bales: next.lifetime.bales + bales },
  })

  return { next: infused.next, harvests, jars: infused.jars }
}

// Every turn's cost feeds the crops: output tokens grow corn, all input
// tokens (cache included) grow apples.
const applyUsage = (
  old: Farm,
  usage: {
    input_tokens: number
    output_tokens: number
    cache_read_input_tokens: number
    cache_creation_input_tokens: number
  },
): Outcome => {
  const input =
    usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens
  const done = applyGrowth(old, [
    ['corn', usage.output_tokens],
    ['apples', input],
  ])

  return {
    ...done,
    next: {
      ...done.next,
      lifetime: {
        ...done.next.lifetime,
        outputTokens: old.lifetime.outputTokens + usage.output_tokens,
        inputTokens: old.lifetime.inputTokens + input,
      },
    },
  }
}

// Claude's working time grows tobacco.
const applyWork = (old: Farm, ms: number): Outcome => {
  const done = applyGrowth(old, [['tobacco', ms]])

  return {
    ...done,
    next: {
      ...done.next,
      lifetime: { ...done.next.lifetime, workMs: old.lifetime.workMs + ms },
    },
  }
}

// A WebFetch/WebSearch trip to town brings home a cinnamon stick.
const townTrip = (old: Farm): Outcome => {
  const infused = infuse({ ...old, barn: { ...old.barn, sticks: old.barn.sticks + 1 } })

  return { next: infused.next, harvests: [], jars: infused.jars }
}

type StillRun = Outcome & { result: 'dry' | 'failed' | 'sour' | 'step' | 'lightning' }

// One Bash/Monitor run. A batch starts on a bushel of corn, takes MASH_FULL
// good runs to come off as white lightning, and a failed run sours it.
const runStill = (old: Farm, isError: boolean): StillRun => {
  const idle = { harvests: [] as Crop[], jars: 0 }

  if (isError) {
    return old.still.hasBatch
      ? { ...idle, next: { ...old, still: { steps: 0, hasBatch: false } }, result: 'sour' }
      : { ...idle, next: old, result: 'failed' }
  }

  let next = old
  if (!old.still.hasBatch) {
    if (old.barn.corn < 1) {
      return { ...idle, next: old, result: 'dry' }
    }
    next = {
      ...old,
      barn: { ...old.barn, corn: old.barn.corn - 1 },
      still: { steps: 0, hasBatch: true },
    }
  }

  const steps = next.still.steps + 1
  if (steps < mashFull(next)) {
    return { ...idle, next: { ...next, still: { steps, hasBatch: true } }, result: 'step' }
  }

  const infused = infuse({
    ...next,
    still: { steps: 0, hasBatch: false },
    shelf: { ...next.shelf, lightning: next.shelf.lightning + 1 },
  })

  const proof = proofOf(Math.random)

  return {
    harvests: [],
    jars: infused.jars,
    next: {
      ...infused.next,
      lastProof: proof,
      bestProof: Math.max(infused.next.bestProof, proof),
    },
    result: 'lightning',
  }
}

// One more of something this session did.
const note = (key: Counter, by = 1) => bump(S.session, key, by)

// Work started and not waited on: whatever goes wrong with it is dropped.
const detach = (work: Promise<unknown>) => {
  void work.catch(() => undefined)
}

// The creativity switch: what the store kept, else the /config option.
const isCreativityOn = () => S.overrides.creativity ?? OPT.creativity

// How much Jeb talks: what the store kept, else the /config option.
const talkLevel = (): Talk => S.overrides.talk ?? OPT.talk

const isCooling = (key: string, ms: number) => {
  const at = S.cool[key]

  return at !== undefined && S.nowMs - at < ms
}

// Takes the cooldown if it is free.
const spend = (key: string, ms: number) => {
  if (isCooling(key, ms)) {
    return false
  }
  S.cool[key] = S.nowMs

  return true
}

// The quiet after a failed run, or while a long answer streams.
const isLulled = () => S.nowMs < S.hushUntil || S.ticks < S.burstUntil

// The one gate every spoken line but a reply goes through. Silent says
// nothing; a hush lets only verdicts and milestones by; ambient keeps the
// everyday chatter to a line every ten minutes on a busy stretch (the turn's
// first line is free) and every five when idle.
function mayTalk(kind: TalkKind): boolean {
  if (kind === 'reply') {
    return true
  }
  const level = talkLevel()
  if (level === 'silent') {
    return false
  }
  const isNews = kind === 'milestone' || kind === 'verdict' || kind === 'streak'
  if (isLulled() && !isNews) {
    return false
  }
  if (level === 'chatty') {
    return true
  }
  if (kind === 'milestone' || kind === 'streak' || kind === 'deny' || kind === 'start' || kind === 'cont') {
    return true
  }
  if (kind === 'first') {
    S.turnSaid = true

    return true
  }
  if (S.isBusy) {
    if (!S.turnSaid) {
      S.turnSaid = true

      return true
    }

    return spend('talk:busy', BUSY_TALK_MS)
  }

  return spend('talk:idle', IDLE_TALK_MS)
}

// Puts a line in the bubble, whatever the dial says.
async function put($: EngineInterface, line: string, mood: Mood) {
  // Nobody is at the prompt in a `-p` run or the SDK.
  if (!S.isInteractive) {
    return
  }
  S.quiet = 0
  S.sinceSaid = 0
  S.line = line
  S.mood = mood
  S.saidAt = S.nowMs
  wake()
  await update($, say, () => ({ line, mood }))
}

// Says a line if the gate lets it by; whether it did.
async function speak($: EngineInterface, line: string, mood: Mood, kind: TalkKind) {
  if (!mayTalk(kind)) {
    return false
  }
  await put($, line, mood)

  return true
}

// The same, for a line that keeps its own cooldown: nothing is taken unless it is said.
async function speakCapped(
  $: EngineInterface,
  key: string,
  ms: number,
  line: string,
  mood: Mood,
  kind: TalkKind,
) {
  if (isCooling(key, ms) || !mayTalk(kind)) {
    return false
  }
  S.cool[key] = S.nowMs
  await put($, line, mood)

  return true
}

// Applies one pure change to the farm as it stands in the store (another
// session may have moved it), writes that and puts the result in the atom. A
// farm from the future is never read or written: the session plays on its own,
// whether it was there at the start or a newer Jeb wrote it since.
//
// The store has no compare-and-set, so this is best effort: the write is `rev +
// 1`, and it is read back. If what is there is not ours (another session wrote
// at the same moment: the same rev with other contents, or an older one), the
// change is applied again onto theirs, at most MAX_REAPPLY times. A higher rev
// means another session saved on top of ours after reading it, so ours stands.
async function saveNow($: EngineInterface, change: (old: Farm) => Farm) {
  if (!S.isInteractive) {
    // No ticker keeps the clock in a `-p` run: it is read where it is needed.
    S.nowMs = await $.clock.now()
  }
  let raw = S.isStoreLocked ? undefined : await $.store.get('farm')
  if (!S.isStoreLocked && isFutureFarm(raw)) {
    S.isStoreLocked = true
    raw = undefined
  }
  let next: Farm
  for (let attempt = 0; ; attempt += 1) {
    const stored = readFarm(raw)
    const base = salted(stored ?? (await read($, farm)))
    next = salted(change(base))
    // A change that changes nothing, on a farm never stored, writes nothing.
    if (!stored && (next === base || JSON.stringify(next) === JSON.stringify(base))) {
      return
    }
    if (S.isStoreLocked || JSON.stringify(next) === JSON.stringify(raw)) {
      break
    }
    next = { ...next, rev: base.rev + 1 }
    await $.store.set('farm', next)
    const again = await $.store.get('farm')
    if (isFutureFarm(again)) {
      S.isStoreLocked = true
      break
    }
    const isOurs =
      again === undefined ||
      JSON.stringify(again) === JSON.stringify(next) ||
      Number((again as { rev?: unknown }).rev) > next.rev
    if (isOurs || attempt >= MAX_REAPPLY) {
      break
    }
    raw = again
  }
  S.unlocks = next.unlocks
  S.coffee = next.unlockDay.coffee
  S.drops = next.drops
  S.surprises = next.surprises
  // A farm still waiting for its salt gives no salt and no places to the session,
  // and only its shielded form goes to the atom.
  S.salt = next.anonPending ? '' : next.anonSalt
  S.places = next.anonPending ? [] : next.anonPlaces
  const shown = shieldFarm(next)
  await update($, farm, () => shown)
  wakeOnView(shown)
}

// The farm with a salt: its own, else this session's (made the first time one is
// needed). The farm keeps it from its first save on.
// A farm waiting for its salt to settle is left alone (see settle.ts).
function salted(from: Farm): Farm {
  if (from.anonPending || isSalt(from.anonSalt)) {
    return from
  }
  if (!isSalt(S.salt)) {
    S.salt = mintSalt()
  }

  return { ...from, anonSalt: S.salt }
}

// A farm write that changed what shows in the scene wakes it.
function wakeOnView(from: Farm) {
  const key = JSON.stringify(viewOf(from))
  if (key !== S.lastView) {
    S.lastView = key
    wake()
  }
}

function saveFarm($: EngineInterface, change: (old: Farm) => Farm): Promise<void> {
  const run = saving.then(() => saveNow($, change))
  saving = run.catch(() => undefined)

  return run
}

const isFxOn = () =>
  S.fx.wag > 0 || S.fx.puff > 0 || S.fx.wink > 0 || S.fx.sip > 0 || S.fx.gate > 0 || S.fx.wx > 0 || S.fx.stitch > 0 || S.fx.star > 0

// Something is moving, said or worked on right now: the scene is never still.
const isActiveNow = () =>
  S.isBusy ||
  S.truck !== null ||
  S.visit !== null ||
  S.dogDir !== 0 ||
  S.event !== null ||
  isFxOn() ||
  S.agents.some(agent => agent.state === 'working')

// Any activity: the still scene wakes at once, and the count to the next still
// starts over. Plain arithmetic on S; it asks nothing of the host.
function wake() {
  S.calm = 0
  S.isStill = false
}

// The canvas's state as the modules hold it now.
const snapshot = (): Anim => {
  // The tractor crawls: moving alone, it draws a frame every second tick. A
  // visitor dealing, and a happening at rest, stand: the frame turns every 3 s.
  const isCrawl = S.visit !== null && isPassing(S.visit.kind)
  const rest = S.event ? restOf(S.event) : undefined
  const isMoving =
    S.truck !== null ||
    S.dogDir !== 0 ||
    (S.event !== null && rest === undefined) ||
    isFxOn() ||
    (S.visit !== null && !isCrawl && S.visit.phase !== 'deal')
  const { hands, more } = fieldsOf(S.agents)

  return {
    frame: (isMoving ? S.ticks : Math.floor(S.ticks / (isCrawl ? 2 : SLOW_TICKS))) % FRAME_WRAP,
    idleAct: IDLE_ACTS[Math.floor(S.idleTicks / IDLE_ACT_TICKS) % IDLE_ACTS.length] ?? 'banjo',
    pose: S.pose,
    truck: S.truck,
    visit: S.visit,
    dogRun: S.dogRun,
    isNight: isNightNow(),
    // Silent leaves the bubble on its last line, dimmed.
    isDim: talkLevel() === 'silent' || (!S.isBusy && S.quiet > DIM_TICKS),
    isTalking: S.sinceSaid < TALK_TICKS,
    event: S.event && rest !== undefined ? { ...S.event, t: Math.max(rest, S.event.t - (S.event.t % SLOW_TICKS)) } : S.event,
    wag: S.fx.wag > 0,
    wink: S.fx.wink > 0,
    puff: S.fx.puff > 0,
    sip: S.fx.sip > 0,
    hands,
    more,
    mates: matesOf(S.agents),
    lanterns: S.camps.length,
    isGated: S.fx.gate > 0,
    prop: S.prop,
    weather: S.fx.wx > 0 ? S.wx : { kind: 'none', plot: 'all' },
    building: S.building,
    cows: S.cows.slice(0, MAX_COWS).map(cowLabel),
    moreCows: Math.max(0, S.cows.length - MAX_COWS),
    stitch: S.fx.stitch > 0,
    live: squareFor(S.session) ?? 'N',
    rainbow: S.ticks < S.rainbowUntil,
    wet: S.nowMs < S.wetUntil,
    star: S.fx.star,
  }
}

// Writes the anim atom only if something visible changed.
async function pushAnim($: EngineInterface) {
  if (!S.isInteractive) {
    return
  }
  if (S.isStill) {
    // A frozen scene redraws only for something that is moving; anything else
    // (a lantern, the clock) waits for the next activity.
    if (!isActiveNow()) {
      return
    }
    wake()
  }
  const next = snapshot()
  const key = JSON.stringify(next)
  if (key !== S.lastAnim) {
    S.lastAnim = key
    await update($, anim, () => next)
  }
}

// ---- the live record (see live.ts) ----

// This session's key: a keyed hash of its id ('' while the id is not known).
function ownKey() {
  if (S.sessionId === '' || !isSalt(S.salt)) {
    return ''
  }
  const memo = `${S.salt}|${S.sessionId}`
  if (memo !== S.keyFor) {
    S.keyFor = memo
    S.sessionKey = sessionKeyOf(S.salt, S.sessionId)
  }

  return S.sessionKey
}

// A session id's key (a stitched id, a heartbeat's).
const keyOfId = (id: string) => (id === S.sessionId ? ownKey() : sessionKeyOf(S.salt, id))

// Today's token for this session's live record ('' while there is none to have).
function liveTokenNow() {
  const key = ownKey()
  if (key === '' || !isSalt(S.salt)) {
    return ''
  }
  const day = dateKeyOf(nowDate())
  const memo = `${key}|${day}`
  if (memo !== S.tokenFor) {
    S.tokenFor = memo
    S.liveToken = liveTokenOf(S.salt, day, key)
  }

  return S.liveToken
}

// One write of a live record (or, with no value, its removal), in order with the others.
function liveStore($: EngineInterface, token: string, value: LiveRecord | undefined) {
  const run = living.then(() => (value === undefined ? $.store.delete(liveKey(token)) : $.store.set(liveKey(token), value)))
  living = run.catch(() => undefined)

  return run
}

// Once a tick at most: this session's live record goes into the store if any of its
// fields changed (the frame and the time move with it but never cause a write).
// Plain arithmetic on S until there is something to write; the record of the day
// before goes when the token turns over.
async function pushLive($: EngineInterface) {
  if (!S.isInteractive || S.isEnding) {
    return
  }
  const token = liveTokenNow()
  if (token === '') {
    return
  }
  if (token !== S.liveAt) {
    const old = S.liveAt
    S.liveAt = token
    S.lastLive = ''
    if (old !== '') {
      detach(liveStore($, old, undefined))
    }
  }
  const now = snapshot()
  const body = liveBody({
    anim: now,
    mood: S.mood,
    line: S.line,
    saidAt: S.saidAt,
    isBusy: S.isBusy,
    isStill: S.isStill,
    talk: talkLevel(),
    isDropsOff: !isCreativityOn(),
    cows: S.cows,
    area: S.areaKey === '' || !isCreative() ? undefined : S.areaKey,
  })
  const key = JSON.stringify(body)
  if (key === S.lastLive) {
    return
  }
  S.lastLive = key
  try {
    await liveStore($, token, liveRecord(body, S.nowMs, now.frame))
  } catch {
    // a record that cannot be written is written with the next change
    S.lastLive = ''
  }
}

// The session is over: its live record goes. The next one (after a /clear or a
// resume) writes its own under its own token.
async function dropLive($: EngineInterface) {
  const token = S.liveAt
  S.liveAt = ''
  S.lastLive = ''
  if (token !== '') {
    await liveStore($, token, undefined)
  }
}

// On the heartbeat: the other sessions' live records that are gone are taken out
// (see livePrune), as are the oldest past the cap. A record a fresh heartbeat names
// (today's token of its key, or yesterday's) is alive however long it has been
// still. Asked of the host only once a minute; a store that cannot list its keys
// leaves them be.
async function pruneLive($: EngineInterface, camps: Camps) {
  if (!S.isInteractive || !isSalt(S.salt)) {
    return
  }
  try {
    const own = S.liveAt
    const tokens = (await $.store.keys()).flatMap(key => {
      const token = tokenOfKey(key)

      return token !== undefined && token !== own ? [token] : []
    })
    if (tokens.length === 0) {
      return
    }
    const days = [dateKeyOf(nowDate()), dateKeyOf(new Date(S.nowMs - 86_400_000))]
    const linked = new Set(
      Object.keys(camps)
        .filter(isToken)
        .flatMap(key => days.map(day => liveTokenOf(S.salt, day, key))),
    )
    const records: { token: string; at: number | undefined }[] = []
    for (const token of tokens.slice(0, 64)) {
      records.push({ token, at: linked.has(token) ? S.nowMs : liveAtOf(await $.store.get(liveKey(token))) })
    }
    for (const token of livePrune(records, linked, own, S.nowMs)) {
      await liveStore($, token, undefined)
    }
  } catch {
    // a prune that fails is tried again on the next beat
  }
}

// The clock as of the last tick; asked for only before the first one.
async function clockMs($: EngineInterface) {
  return S.nowMs > 0 ? S.nowMs : await $.clock.now()
}

// What Jeb says when a change brought in a harvest or a jar.
async function announce($: EngineInterface, out: Outcome) {
  const state = await read($, farm)
  note('harvests', out.harvests.length)
  note('jars', out.jars)

  if (out.jars > 0) {
    await speak(
      $,
      `${bagPick('jar')} ${state.shelf.appleCinnamon} on the shelf.`,
      'pleased',
      'milestone',
    )
  } else if (out.harvests.length > 0) {
    const crop = out.harvests[0] ?? 'tobacco'
    const category = {
      tobacco: 'harvestTobacco',
      corn: 'harvestCorn',
      apples: 'harvestApples',
    }[crop] as SayingCategory
    const line = bagPick(category)
    await speak($, line, 'pleased', 'milestone')
  }
}

type Unlocked = { upgrades: Upgrade[]; milestones: Milestone[] }

// The farm with whatever it has newly earned written in (upgrades by dollars,
// one-time milestones), and what that was. Decided on the farm it is handed.
const unlockFarm = (old: Farm): { next: Farm; found: Unlocked } => {
  const found = newUnlocks(old)
  if (found.upgrades.length === 0 && found.milestones.length === 0) {
    return { next: old, found }
  }

  return {
    next: {
      ...old,
      upgrades: [...old.upgrades, ...found.upgrades.map(upgrade => upgrade.id)],
      milestones: [...old.milestones, ...found.milestones.map(milestone => milestone.id)],
    },
    found,
  }
}

// Jeb says a word about the last upgrade, or else the first milestone.
async function sayUnlocks($: EngineInterface, found: Unlocked) {
  if (found.upgrades.length === 0 && found.milestones.length === 0) {
    return
  }
  const last = found.upgrades[found.upgrades.length - 1]
  await speak($, last ? last.line : (found.milestones[0]?.text ?? ''), 'pleased', 'milestone')
}

// New upgrades and milestones, for a change that did not look (a sale, a visit).
// What is new is decided inside the save, on the stored farm, so two overlapping
// calls (or two sessions) announce a mark only once.
async function celebrate($: EngineInterface) {
  let found: Unlocked = { upgrades: [], milestones: [] }
  await saveFarm($, old => {
    const done = unlockFarm(old)
    found = done.found

    return done.next
  })
  await sayUnlocks($, found)
}

// The session's record of an upgrade built or a keepsake made.
function noteMade(made: readonly Made[]) {
  for (const item of made) {
    if (item.kind === 'build' || item.kind === 'keepsake') {
      noteBuilt(S.session, `${item.kind === 'build' ? 'built' : 'made'} the ${item.name}`)
    }
  }
}

// What Jeb says of what he made on his own: a line each through the talk gate,
// the everyday kind for a component or a sellable, news for an upgrade built or
// a keepsake made.
async function sayMade($: EngineInterface, made: readonly Made[]) {
  noteMade(made)
  for (const item of made) {
    const isNews = item.kind === 'build' || item.kind === 'keepsake'
    await speak($, item.line, 'pleased', isNews ? 'milestone' : 'say')
  }
}

// Applies a change that may bring a harvest or a jar, crafts whatever the new
// stock allows and writes whatever it newly earned (all in the same save), saves
// it and speaks.
async function grow($: EngineInterface, change: (old: Farm) => Outcome) {
  let out: Outcome | undefined
  let made: Made[] = []
  let found: Unlocked = { upgrades: [], milestones: [] }
  await saveFarm($, old => {
    const grown = change(old)
    const done = craftAll(grown.next, nowDate())
    const unlocked = unlockFarm(done.next)
    made = done.made
    found = unlocked.found
    out = { ...grown, next: unlocked.next }

    return unlocked.next
  })
  if (out) {
    await announce($, out)
    await sayUnlocks($, found)
    await sayMade($, made)
  }
}

// A change to the farm that may bring something to make (a material, a sighting):
// the change and the crafting it allows are one save, so what is made is decided
// on the farm as stored and two sessions cannot make it twice.
async function saveCrafting($: EngineInterface, change: (old: Farm) => Farm) {
  let made: Made[] = []
  await saveFarm($, old => {
    const done = craftAll(change(old), nowDate())
    made = done.made

    return done.next
  })
  await sayMade($, made)
}

// Claude's working time grows tobacco; saved at most every ten seconds, and
// when a turn ends or the tally is read.
async function flushWork($: EngineInterface) {
  const ms = S.pendingMs
  if (ms <= 0) {
    return
  }
  S.pendingMs = 0
  await grow($, old => applyWork(old, ms))
}

async function startTruck($: EngineInterface) {
  // No ticker drives a truck in a `-p` run: it would never get home.
  if (!S.isInteractive) {
    return
  }
  const state = await read($, farm)
  if (S.truck) {
    S.queued = Math.min(MAX_QUEUE, S.queued + 1)

    return
  }
  const now = nowDate()
  const month = now.getMonth()
  const isColdMorning = (month === 11 || month <= 1) && now.getHours() < 9
  // The run sets out for one buyer, chosen by what each could take; the bed
  // carries what that buyer would pay the most for.
  const customer = pickCustomer(now, state, Math.random)
  S.truckFor = customer ?? null
  // The truck has the road: a visit under way goes home.
  if (S.visit) {
    endVisit()
  }
  wake()
  S.truck = {
    t: 0,
    load: loadFor(customer, now, state),
    sputter: isColdMorning ? 2 : 0,
    dog: Math.random() < 0.2,
  }
  await speak(
    $,
    isColdMorning ? 'Gotta mash the pedal three times.' : bagPick('deliveryOut'),
    'pleased',
    'milestone',
  )
  await pushAnim($)
}

// The truck is home: it sells to one buyer, and the next queued load goes. What
// is sold is decided inside the save, on the farm as stored, so a jar another
// session already sold is never sold again.
async function finishDelivery($: EngineInterface) {
  let sold: { sale: Sold['sale']; isNew: boolean } | undefined
  let made: Made[] = []
  const preferred = S.truckFor ?? undefined
  const now = nowDate()
  S.truckFor = null
  await saveFarm($, old => {
    // The run brings supplies home first (from the cash already in hand, while
    // the barn still has its apples), then sells, then Jeb makes what he can.
    const bought = buySupplies(old)
    const out = sellTo(bought.next, preferred, now, Math.random)
    sold = { sale: out.sale, isNew: out.isNew }
    const done = craftAll(
      {
        ...out.next,
        ledger: { ...out.next.ledger, deliveries: out.next.ledger.deliveries + 1 },
      },
      now,
    )
    made = done.made

    return done.next
  })
  const back = bagPick('deliveryBack')
  const sale = sold?.sale
  if (sale) {
    note('sales', sale.total)
    const line = fillSale(bagPick(saleCategory(sale.customer)), sale)
    // The fair and a new buyer's first sale are news; the rest is busy chatter.
    const kind = sale.isRibbon || sold?.isNew ? 'milestone' : 'say'
    await speak($, line, 'pleased', kind)
  } else {
    await speak($, back, 'pleased', 'milestone')
  }
  await celebrate($)
  await sayMade($, made)
  if (S.queued > 0) {
    S.queued -= 1
    await startTruck($)
  } else {
    await pushAnim($)
  }
}

function startErrand() {
  wake()
  if (S.dogDir === 0) {
    S.dogDir = 1
    S.dogRun = DOG_STEP
  }
}

// Ambient life: the scheduler is plain arithmetic on S and asks nothing of the
// host until something is due. A visit (or Blue's errand) that cannot start
// now tries again on the next 30 s.
const isRoadBusy = () =>
  S.truck !== null || S.event !== null || S.visit !== null || S.dogDir !== 0

// Blue runs the fields and back when it is quiet.
function dueErrand() {
  if (S.isBusy || isRoadBusy()) {
    S.nextErrandAt = S.nowMs + VISIT_RETRY_MS

    return
  }
  startErrand()
  S.nextErrandAt = S.nowMs + spanOf(ERRAND_MS, visitRng)
}

// A visit is over (or called off): the road is empty and the next is scheduled.
function endVisit() {
  S.visit = null
  S.visitFor = null
  S.visitTicks = 0
  S.nextVisitAt = S.nowMs + spanOf(NEXT_VISIT_MS, visitRng)
}

// A visit is due: somebody comes up the road, unless something else has it.
async function dueVisit($: EngineInterface) {
  // Nobody comes up the road while Jeb is at work: it tries again on the 30 s.
  if (S.isBusy || isRoadBusy()) {
    S.nextVisitAt = S.nowMs + VISIT_RETRY_MS

    return
  }
  const state = await read($, farm)
  // The truck or a happening may have set out while the farm was read.
  if (S.isBusy || isRoadBusy()) {
    S.nextVisitAt = S.nowMs + VISIT_RETRY_MS

    return
  }
  const now = nowDate()
  const pick = pickVisit(now, state, state.mailDay, visitRng)
  S.visitFor = pick.customer ?? null
  S.visitTicks = 0
  S.nextVisitAt = NEVER
  wake()
  S.visit = { kind: pick.kind, x: 0, facing: 'in', phase: 'arrive' }
  await pushAnim($)
}

// The rig has stopped: a buyer's sale is decided on the farm as stored, and
// Jeb says what came of it; the mail only gets a word.
async function dealVisit($: EngineInterface) {
  const customer = S.visitFor
  if (customer === null) {
    if (S.visit?.kind === 'mail') {
      // The mail counts as come when it is delivered, not when it sets out.
      const key = dateKeyOf(nowDate())
      await saveFarm($, old => (old.mailDay === key ? old : { ...old, mailDay: key }))
      await speak($, MAIL_LINE, 'pleased', 'say')
    }

    return
  }
  let sold: { sale: NonNullable<ReturnType<typeof sellVisit>['sale']>; isNew: boolean } | undefined
  const now = nowDate()
  await saveFarm($, old => {
    const out = sellVisit(old, customer, now, visitRng)
    sold = out.sale ? { sale: out.sale, isNew: out.isNew } : undefined

    return out.next
  })
  if (sold) {
    note('sales', sold.sale.total)
    const line = fillSale(bagPick(saleCategory(sold.sale.customer)), sold.sale)
    await speak($, line, 'pleased', sold.isNew ? 'milestone' : 'say')
    await celebrate($)
  }
}

// One tick of a visit: it drives (or walks) in, deals for a few ticks, and goes
// back the way it came; the tractor only crosses.
async function stepVisit($: EngineInterface, visit: Visit) {
  const spec = VISIT_SPECS[visit.kind]
  if (visit.phase === 'deal') {
    S.visitTicks += 1
    if (S.visitTicks >= S.visitDeal) {
      S.visit = { ...visit, phase: 'leave', facing: 'out' }
    }

    return
  }
  if (S.ticks % spec.every !== 0) {
    return
  }
  if (visit.phase === 'arrive') {
    const x = Math.min(spec.reach, visit.x + spec.step)
    if (x < spec.reach) {
      S.visit = { ...visit, x }
    } else if (isPassing(visit.kind)) {
      endVisit()
      await pushAnim($)
    } else {
      S.visit = { ...visit, x, phase: 'deal' }
      S.visitTicks = 0
      S.visitDeal = spanOf(DEAL_TICKS, visitRng)
      await dealVisit($)
    }

    return
  }
  const x = Math.max(0, visit.x - spec.step)
  if (x > 0) {
    S.visit = { ...visit, x }
  } else {
    endVisit()
    await pushAnim($)
  }
}

// A line for a quiet moment: the date's own, the month's, or the usual.
const idleLine = (act: IdleAct) => {
  if (act === 'nap' || act === 'chase') {
    return bagPick('blue')
  }
  const now = nowDate()
  // The day's sayings from the creative drops join the pool now and then.
  const pool = sayingPool(S.surprises, now)
  if (pool.length > 0 && Math.random() < 0.25) {
    return pool[Math.floor(Math.random() * pool.length)] as string
  }
  const special = dateLines(now)
  const roll = Math.random()
  if (special.length > 0 && roll < 0.3) {
    return special[Math.floor(Math.random() * special.length)] as string
  }
  if (roll < 0.55) {
    return bagPick(MONTH_CATEGORIES[now.getMonth()] as SayingCategory)
  }
  if (roll < 0.7) {
    return bagPick('idleMore')
  }

  return bagPick(isNightNow() ? 'night' : 'idle')
}

// Says whatever beats of the running happening are due, and does what they do.
async function runBeats($: EngineInterface) {
  const ev = S.event
  if (!ev) {
    return
  }
  const p = ev.t / ev.dur
  while (S.beatIdx < S.beats.length && (S.beats[S.beatIdx] as Beat).at <= p) {
    const beat = S.beats[S.beatIdx] as Beat
    S.beatIdx += 1
    const mood = ev.id === 'mothman' || ev.id === 'revenuer' ? 'spooked' : 'idle'
    // A sale is made first, and what Jeb says is what came of it.
    let line = beat.line
    if (beat.effect === 'sell') {
      let dollars = 0
      await saveFarm($, old => {
        const next = sellOne(old, nowDate())
        dollars = Math.max(0, next.ledger.total - old.ledger.total)

        return next
      })
      note('sales', dollars)
      line = (dollars > 0 ? beat.ifSold : beat.ifNot) ?? beat.line
    }
    // The rest of a happening goes on once its first beat was said.
    if (await speak($, line, mood, S.beatSpoke ? 'cont' : 'say')) {
      S.beatSpoke = true
    }
    if (beat.effect === 'sell') {
      await celebrate($)
    } else if (beat.effect === 'raid') {
      await saveFarm($, old => raidCorn(old, Math.random))
    } else if (beat.effect === 'bark' && ev.id === 'track') {
      startErrand()
    }
  }
}

async function startEvent($: EngineInterface, id: EventId) {
  const state = await read($, farm)
  if (S.visit) {
    endVisit()
  }
  wake()
  S.event = { id, t: 0, dur: durationOf(id, Math.random), v: Math.floor(Math.random() * 1000) }
  S.eventUsed[id] = S.ticks
  S.beats = beatsOf(id, state.shelf.appleCinnamon > 0)
  S.beatIdx = 0
  S.beatSpoke = false
  S.eventTicks = 0
  await runBeats($)
  if (id === 'mothman') {
    await saveCrafting($, noteMothman)
  }
  await pushAnim($)
}

// Every few minutes (rarely while busy) something may happen on the homestead.
async function rollEvent($: EngineInterface) {
  if (S.isBusy && Math.random() > 0.5) {
    return
  }
  const blocked = new Set<EventId>(
    (Object.keys(S.eventUsed) as EventId[]).filter(
      id => S.ticks - (S.eventUsed[id] ?? 0) < EVENT_COOLDOWN_TICKS,
    ),
  )
  const id = pickEvent(
    { now: nowDate(), isBusy: S.isBusy, errorStreak: S.errorStreak },
    blocked,
    Math.random,
  )
  if (id) {
    await startEvent($, id)
  }
}

// The session clock is set from the machine's, on its own cadence. Whether the
// two had drifted apart by more than a minute (the machine slept, or the clock
// was set); the session clock is re-based either way. A failed read leaves it as
// it was.
async function syncClock($: EngineInterface) {
  try {
    const wall = Number(await $.clock.now())
    if (!Number.isFinite(wall)) {
      return false
    }
    const isJump = Math.abs(wall - S.nowMs) > CLOCK_JUMP_MS
    S.nowMs = wall

    return isJump
  } catch {
    return false
  }
}

// Plain arithmetic on S, asked of the host only when something is due: the day's
// next unlock, the late-night coffee, and (never waking a still scene) a shooting
// star on a night the scene is awake anyway.
async function tendLittleThings($: EngineInterface) {
  if (!S.isInteractive || S.unlockAt === 0) {
    return
  }
  if (S.nowMs >= S.unlockAt) {
    await dueUnlock($)
  }
  const now = nowDate()
  const hour = now.getHours()
  if (
    hour >= COFFEE_FROM &&
    hour < COFFEE_TO &&
    S.unlocks.includes('midnightcoffee') &&
    S.coffee !== dateKeyOf(now) &&
    !S.isCoffeeing
  ) {
    await dueCoffee($)
  }
  if (
    !S.isStill &&
    S.fx.star === 0 &&
    S.unlocks.includes('shootingstar') &&
    isNightNow() &&
    S.starNight !== dateKeyOf(now) &&
    Math.random() < STAR_ODDS
  ) {
    S.starNight = dateKeyOf(now)
    S.fx.star = STAR_TICKS
    wake()
  }
}

// Something unlocks, if the day's plan allows it now: decided on the farm as
// stored, and Jeb says one warm line about it.
async function dueUnlock($: EngineInterface) {
  if (S.isUnlocking) {
    return
  }
  S.isUnlocking = true
  try {
    let step: Step | undefined
    await saveFarm($, old => {
      const made = stepUnlock(old, S.nowMs, Math.random)
      step = made
      if (made.found === undefined && JSON.stringify(made.unlockDay) === JSON.stringify(old.unlockDay)) {
        return old
      }

      return { ...old, unlocks: made.unlocks, unlockDay: made.unlockDay }
    })
    S.unlockAt = step?.retryAt ?? S.nowMs + RETRY_UNLOCK_MS
    const found = step?.found
    if (found) {
      await speak($, unlockOf(found)?.line ?? '', 'pleased', 'milestone')
    }
  } catch {
    S.unlockAt = S.nowMs + RETRY_UNLOCK_MS
  } finally {
    S.isUnlocking = false
  }
}

const COFFEE_LINE = 'Brought you a cup. Get some rest soon.'

// Past midnight Jeb brings a cup of coffee, once a night (the night is marked on
// the stored farm, so a second session or a restart does not bring another).
async function dueCoffee($: EngineInterface) {
  S.isCoffeeing = true
  try {
    const key = dateKeyOf(nowDate())
    let isNew = false
    await saveFarm($, old => {
      if (old.unlockDay.coffee === key) {
        return old
      }
      isNew = true

      return { ...old, unlockDay: { ...old.unlockDay, coffee: key } }
    })
    if (isNew) {
      await speak($, COFFEE_LINE, 'pleased', 'milestone')
    }
  } catch {
    // a cup that cannot be poured is poured next time
  } finally {
    S.isCoffeeing = false
  }
}

// ---- the creative drops (see drops.ts, surprise.ts, signals.ts) ----

// Whether drops may happen now: the option (the stored value first) and the dial.
const isCreative = () => isPluginCreative() && !S.isAppDropsOff

// The option and the dial alone: what the app's flag is added to.
const isPluginCreative = () => isCreativityOn() && S.creativity !== 'off'

// Reads the app's flags file into S, only at a decision point (never on a quiet
// tick). A file that cannot be read leaves the drops on.
async function readAppFlag($: EngineInterface) {
  const run = S
  let isOff = false
  try {
    const path = flagsPathOf(await $.env.get('JEB_HOME'), await $.env.get('HOME'))
    if (path !== undefined) {
      isOff = isDropsOffByApp(await $.fs.read(path))
    }
  } catch {
    isOff = false
  }
  if (S === run) {
    S.isAppDropsOff = isOff
  }
}

// A slot the app's flag holds back is looked at again this often.
const FLAG_RETRY_MS = 600_000

// A happening waits this long for the road to clear before it is let go.
const DROP_WAIT_MS = 300_000

const stepName = (arc: string, index: number) => `${arc.slice(0, 20)}-${index + 1}`

// A drop as the farm stores it: a plain surprise, or the first step of a new arc.
const deliveryOf = (drop: Drop, slot: number, made: 'haiku' | 'local', today: string): Delivery => {
  if (drop.kind !== 'arc') {
    return {
      slot,
      made,
      kind: drop.kind,
      name: drop.name,
      lines: drop.lines,
      summary: drop.summary,
      sprites: drop.sprites,
      window: drop.window,
      lasts: drop.lasts,
      festival: drop.festival,
      keep: drop.keep,
      art: drop.art,
      arc: null,
    }
  }
  const first = drop.steps[0]
  const arc = { name: drop.name, made, start: today, last: today, at: 0, steps: drop.steps }
  if (!first) {
    throw new Error('an arc with no steps')
  }

  return {
    slot,
    made,
    kind: first.kind,
    name: stepName(drop.name, 0),
    lines: first.lines,
    summary: drop.summary,
    sprites: first.sprites,
    window: first.window,
    lasts: first.lasts,
    festival: first.festival,
    keep: false,
    art: drop.art,
    arc: { name: drop.name, step: 1 },
    begin: arc,
  }
}

// The next step of the arc under way, as a delivery (no model is asked).
const stepDelivery = (arc: NonNullable<Farm['creative']['arc']>, index: number, slot: number): Delivery => {
  const step = arc.steps[index] as NonNullable<Farm['creative']['arc']>['steps'][number]

  return {
    slot,
    made: arc.made,
    kind: step.kind,
    name: stepName(arc.name, index),
    lines: step.lines,
    summary: (step.lines[0] ?? '').slice(0, 80),
    sprites: step.sprites,
    window: step.window,
    lasts: step.lasts,
    festival: step.festival,
    keep: step.keep,
    art: [],
    arc: { name: arc.name, step: index + 1 },
  }
}

// Takes one of the day's six model calls on the stored farm; whether there was one.
// The reservation carries a nonce, made once here (so a re-apply of the change onto
// another session's write keeps it). The write is read back: unless the stored farm
// is of the same day and holds the nonce (another session's write replaced ours,
// even at the same count), the call is not made.
async function reserveCall($: EngineInterface) {
  const nonce = secureHex(8)
  let isOk = false
  let claimed: { day: string; n: number } | undefined
  await saveFarm($, old => {
    const taken = reserveModelAs(old, S.nowMs, nonce)
    isOk = taken.ok
    claimed = taken.ok ? taken.farm.modelCalls : undefined

    return taken.farm
  })
  if (!isOk || !claimed) {
    return false
  }
  if (S.isStoreLocked) {
    return true
  }
  try {
    const stored = readFarm(await $.store.get('farm'))
    if (!stored || stored.modelCalls.day !== claimed.day || !stored.modelTaken.includes(nonce)) {
      return false
    }
  } catch {
    return false
  }

  return true
}

// What the drop for a slot is: Haiku's (within the budget),
// else the offline generator's. A takeover from a dead claimant is always offline.
async function makeDrop($: EngineInterface, old: Farm, slot: number, level: number, isArcOpen: boolean, isTakeover: boolean) {
  const now = nowDate()
  const ctx = { level, knownArt: old.creative.art.map(art => art.id), isArcOpen }
  const recent = recentSummaries(old.creativeLog)
  let drop: Drop | undefined
  let made: 'haiku' | 'local' = 'local'
  if (!isTakeover && S.creativity !== 'local' && !S.isAppDropsOff) {
    drop = await askHaiku($, promptInputOf(old, now, slot, level, recent, isArcOpen), ctx, () => reserveCall($))
    made = drop ? 'haiku' : 'local'
  }
  if (!drop) {
    drop = offlineDrop({
      now,
      slot,
      level,
      total: old.creative.total,
      labels: [],
      counts: {},
      recent,
      isArcOpen,
      knownArt: ctx.knownArt,
    })
  }

  return deliveryOf(drop, slot, made, dateKeyOf(now))
}

// A happening's sprites stand in the scene for 30 to 60 seconds, as any other happening.
function startDropEvent() {
  const play = S.dropPlay
  if (!play) {
    return
  }
  S.dropPlay = null
  wake()
  S.event = { id: 'drop', t: 0, dur: durationOf('drop', Math.random), v: Math.floor(Math.random() * 1000), art: play.art }
  S.beats = []
  S.beatIdx = 0
  S.beatSpoke = false
  S.eventTicks = 0
}

// The surprise arrives: a happening plays its sprites (when the road is free) and
// Jeb says its first line. Decor, sayings and almanac lines simply take their
// place (the farm view, the bubble pool, the hint crumbs) once stored.
async function playDrop($: EngineInterface, surprise: Surprise) {
  if (surprise.kind === 'happening' && surprise.sprites.length > 0) {
    const state = await read($, farm)
    const custom = state.creative.art.filter(art => surprise.sprites.some(sprite => sprite.sprite === art.id))
    S.dropPlay = { art: { sprites: surprise.sprites, custom }, until: S.nowMs + DROP_WAIT_MS }
    if (S.event === null) {
      startDropEvent()
    }
  }
  await speak($, surprise.lines[0] ?? '', 'pleased', 'milestone')
  await pushAnim($)
}

// A slot is due: claimed on the stored farm first (so two sessions never make the
// same one), then made, stored and played. A claim that dies with its session is
// taken over, offline, once it is two minutes old.
async function dueDrop($: EngineInterface, slot: number, isForced = false) {
  S.isDropping = true
  if (!isForced) {
    S.dropLast = S.nowMs
  }
  const run = S
  try {
    // A forced surprise claims nothing: it must leave the real slots as they are.
    let claim: Claimed<Farm> | undefined
    if (!isForced) {
      await saveFarm($, old => {
        claim = claimSlot(old, slot, S.nowMs)

        return claim.farm
      })
      if (!claim || claim.outcome === 'busy' || claim.outcome === 'done') {
        return
      }
    }
    const old = await read($, farm)
    const today = dateKeyOf(nowDate())
    const arc = activeArc(old, today)
    const due = nextArcStep(arc, today)
    const delivery =
      arc && due
        ? stepDelivery(arc, due.index, slot)
        : await makeDrop($, old, slot, levelOf(old.creative.total), arc === null, claim?.outcome === 'takeover')
    if (S !== run) {
      return
    }
    let surprise: Surprise | undefined
    await saveFarm($, stored => {
      const done = applyDelivery(stored, delivery, S.nowMs, isForced)
      surprise = done.surprise

      return done.farm
    })
    if (surprise && S === run) {
      await playDrop($, surprise)
    }
  } catch {
    // a drop that fails is made again, offline, once its claim is stale
  } finally {
    if (S === run) {
      S.isDropping = false
    }
  }
}

// Plain arithmetic on S until a slot is due: a happening waiting for the road
// goes out when it is clear, and the day's next slot runs if its time has come.
async function tendDrops($: EngineInterface) {
  if (!S.isInteractive || S.isDropping || !isPluginCreative()) {
    return
  }
  if (S.dropPlay) {
    if (S.nowMs > S.dropPlay.until) {
      S.dropPlay = null
    } else if (S.event === null) {
      startDropEvent()
      await pushAnim($)
    }
  }
  // JEB_DROP_NOW: one forced surprise, once per session, at the first pass the gates allow.
  // The app's flag is read when it first comes up and, while it holds the surprise back,
  // again every FLAG_RETRY_MS, as for a due slot.
  if (S.dropNow === 'pending') {
    if (S.dropNowAt === 0 || (S.isAppDropsOff && S.nowMs - S.dropNowAt >= FLAG_RETRY_MS)) {
      S.dropNowAt = S.nowMs
      await readAppFlag($)
    }
    if (!S.isAppDropsOff) {
      S.dropNow = 'done'
      await dueDrop($, forcedSlot(S.nowMs), true)

      return
    }
  }
  const slot = dueSlot({ drops: S.drops, nowMs: S.nowMs, startedAt: S.startedAt, lastAt: S.dropLast })
  if (slot !== undefined) {
    // The app's flag is read once as each slot comes due; while it holds the slot
    // back it is read again every ten minutes, so turning it on lets the slot run.
    const due = `${dateKeyOf(nowDate())}:${slot}`
    if (S.flagSlot !== due || (S.isAppDropsOff && S.nowMs - S.flagAt >= FLAG_RETRY_MS)) {
      S.flagSlot = due
      S.flagAt = S.nowMs
      await readAppFlag($)
    }
    if (S.isAppDropsOff) {
      return
    }
    await dueDrop($, slot)
  }
}

// ---- areas ----

// A key of the store, read, changed and written in line with the other writes;
// nothing is written when it comes out as it was (or as an empty value, when
// there was none). Returns what it holds.
async function saveStored<T>($: EngineInterface, key: string, change: (saved: unknown) => T) {
  const run = saving.then(async () => {
    const raw = await $.store.get(key)
    const next = change(raw)
    const isEmpty = typeof next === 'object' && next !== null && Object.keys(next).length === 0
    if (JSON.stringify(next) !== JSON.stringify(raw) && !(raw === undefined && isEmpty)) {
      await $.store.set(key, next)
    }

    return next
  })
  saving = run.catch(() => undefined)

  return run
}

// The area secret: made once, kept in the store and read by nothing else (not
// the desktop). Another session that made one first wins: the stored one is read
// back after the write.
async function areaSecret($: EngineInterface) {
  const made = await saveStored($, 'areaSecret', saved => (isAreaSecret(saved) ? saved : mintAreaSecret()))
  const again = await $.store.get('areaSecret')

  return isAreaSecret(again) ? again : made
}

// The session's project as a key, worked out once from where it is: the git
// remote, else the repository's root, else the folder (see identityOf). The
// identity goes into the keyed hash at once and is kept nowhere. Only the plugin
// option keeps the key from being made: the app's switch can come back on during
// the session, and the key is what the project's work and place wait on.
async function resolveArea($: EngineInterface) {
  S.areaKey = ''
  if (!isPluginCreative()) {
    return
  }
  try {
    let root = ''
    let repo: { root: string; remote: string | null } | null = null
    try {
      root = await $.session.root()
    } catch {
      root = ''
    }
    try {
      repo = await $.session.repo()
    } catch {
      repo = null
    }
    const identity = identityOf(root, repo, S.cwd)
    if (identity !== '') {
      S.areaKey = areaKeyOf(await areaSecret($), identity)
    }
  } catch {
    S.areaKey = ''
  }
}

// A tool call counts toward the kind of work it is, if it is one: plain
// arithmetic on S, written with the 30 s housekeeping.
function noteWork(tool: string, command: string, segments: readonly Segment[], input: Record<string, unknown>) {
  if (!S.isInteractive || S.areaKey === '' || !isCreative()) {
    return
  }
  const kind = workKindOf(tool, command, segments, input)
  if (kind) {
    S.areaPending[kind] = (S.areaPending[kind] ?? 0) + 1
  }
}

// Takes one of the day's three area calls on the stored reservations (`areaTaken`,
// the nonces of today's calls); whether there was one. The nonce is made once here.
// `areaCalls` is written as the count of them (the mirror). The write is read back:
// unless the stored reservations are of the same day and hold the nonce, another
// session's write replaced it and the call is not made.
async function reserveAreaCall($: EngineInterface) {
  const nonce = secureHex(8)
  let isOk = false
  let claimed: { day: string; ids: string[] } | undefined
  const kept = await saveStored($, 'areaTaken', saved => {
    const taken = reserveAreaAs(saved, S.nowMs, nonce)
    isOk = taken.ok
    claimed = taken.ok ? taken.taken : undefined

    return taken.taken
  })
  if (!isOk || !claimed) {
    return false
  }
  await saveStored($, 'areaCalls', () => ({ day: kept.day, n: kept.ids.length }))
  if (S.isStoreLocked) {
    return true
  }
  try {
    const stored = areaTakenOf(await $.store.get('areaTaken'))
    if (stored.day !== claimed.day || !stored.ids.includes(nonce)) {
      return false
    }
  } catch {
    return false
  }

  return true
}

// The area for a key that has none: claimed first on the stored claims (so two
// sessions never make one twice), then Haiku's (within its budget), else the
// offline generator's, which is written at once on a refusal, an error or no
// budget; the model is not asked again for the key that day. A takeover from a
// dead claimant is always offline. The area is stored once, the oldest past 24
// goes with its counters, and the claim is let go.
async function makeArea($: EngineInterface, key: string, profile: AreaProfile) {
  const day = dateKeyOf(nowDate())
  S.areaTriedDay = day
  const run = S
  let areas = areasOf(await $.store.get('areas'))
  if (areas[key]) {
    S.isAreaHeld = true

    return
  }
  let claim: AreaClaimed | undefined
  await saveStored($, 'areaClaims', saved => {
    claim = claimArea(areaClaimsOf(saved), areas, key, S.nowMs)

    return claim.claims
  })
  if (!claim || claim.outcome === 'busy' || claim.outcome === 'done') {
    return
  }
  const input: AreaInput = { key, day, choices: choicesOf(key, profile), profile, bible: bibleOf(areas, key) }
  let area: Area | undefined
  try {
    // The app's switch is read again before a place is made: turned off since it
    // was last read, it makes none, from Haiku or offline.
    await readAppFlag($)
    if (!isCreative()) {
      return
    }
    if (claim.outcome === 'claimed' && S.creativity === 'on') {
      area = await askHaikuArea($, input, () => reserveAreaCall($))
    }
    // A model area that does not hold up is replaced by the offline one.
    let checked = area ? validateArea(area) : undefined
    if (!checked?.ok) {
      checked = validateArea(offlineArea(key, profile, day))
    }
    if (!checked.ok) {
      return
    }
    const made = checked.area
    let evicted: string[] = []
    areas = await saveStored($, 'areas', saved => {
      const put = putArea(areasOf(saved), key, made)
      evicted = put.evicted

      return put.areas
    })
    if (evicted.length > 0) {
      await saveStored($, 'areaWork', saved => withoutWork(areaWorkOf(saved), evicted))
    }
    if (S === run) {
      S.isAreaHeld = true
      S.areaSeenDay = day
    }
  } finally {
    // The claim is let go whatever came of the area; a claim that cannot be let go times out.
    try {
      await saveStored($, 'areaClaims', saved => releaseClaim(areaClaimsOf(saved), key))
    } catch {
      // a claim that stays is taken over once it is stale
    }
  }
}

// Every 30 s, with the housekeeping: the counted events are written to the
// project's counters (and its top kinds kept for the hysteresis), the day it
// was worked in is noted on its area at most once a day, and a project with
// enough events and no area yet gets one. Until there is something to write or
// look at it is arithmetic on S and asks the host for nothing.
async function tendAreas($: EngineInterface) {
  if (!S.isInteractive || S.areaKey === '' || S.isAreaBusy || !isCreative()) {
    return
  }
  const key = S.areaKey
  const today = dateKeyOf(nowDate())
  const adds = S.areaPending
  const isPending = Object.keys(adds).length > 0
  const isWaiting = !S.isAreaHeld && S.areaCount >= AREA_MIN_EVENTS && S.areaTriedDay !== today
  const isSeenDue = S.isAreaHeld && S.areaSeenDay !== today
  if (S.isAreaLooked && !isPending && !isWaiting && !isSeenDue) {
    return
  }
  S.isAreaBusy = true
  const run = S
  try {
    S.areaPending = {}
    let entry: WorkEntry | undefined
    await saveStored($, 'areaWork', saved => {
      const work = isPending ? countWork(areaWorkOf(saved), key, adds, today) : areaWorkOf(saved)
      const found = work[key]
      const top = profileOf(found)?.top
      if (found && top) {
        found.top = top
      }
      entry = found

      return work
    })
    S.areaCount = entry?.n ?? 0
    const profile = profileOf(entry)?.profile ?? []
    S.isAreaLooked = true
    if (S.isAreaHeld && S.areaSeenDay === today) {
      return
    }
    if (S.isAreaHeld || S.areaCount >= AREA_MIN_EVENTS) {
      let isHeld = false
      await saveStored($, 'areas', saved => {
        const areas = areasOf(saved)
        isHeld = areas[key] !== undefined

        return touchSeen(areas, key, today)
      })
      if (isHeld) {
        S.isAreaHeld = true
        S.areaSeenDay = today
      } else if (S.areaCount >= AREA_MIN_EVENTS && S.areaTriedDay !== today) {
        await makeArea($, key, profile)
      }
    }
  } catch {
    // an area that cannot be written is tried again on a later round
  } finally {
    if (S === run) {
      S.isAreaBusy = false
    }
  }
}

// Jeb's news, once: claimed on the stored farm (so another session does not say
// it too), then said as a milestone. A malformed item says nothing.
async function announceNews($: EngineInterface) {
  const news = newsOf(S.news)
  if (!news) {
    return
  }
  let isNew = false
  await saveFarm($, old => {
    if (old.newsSeen.includes(news.id)) {
      return old
    }
    isNew = true

    return withNewsSeen(old, news.id)
  })
  if (isNew) {
    await speak($, news.line, 'pleased', 'milestone')
  }
}

// Every 30 s: the clock, then the engine's agent list, and
// on every other round the heartbeat. A round that found the clock had jumped
// skips the heartbeat: its notion of which camps are dead was made on the wrong
// time, so nothing is stitched or pruned until the next one.
async function housekeep($: EngineInterface, isBeat: boolean) {
  const isJump = await syncClock($)
  // The round that found the clock had jumped judges nothing on the wrong time.
  if (!isJump) {
    await tendLittleThings($)
    await tendDrops($)
    await tendAreas($)
  }
  await Promise.all([
    refreshAgents($),
    isBeat && !isJump ? heartbeat($) : undefined,
  ])
}

// What Jeb looks like and says for a tool: an MCP server's glyph and line, the
// tool's own pose and saying, or a plain one for a tool he does not know.
const toolLook = (name: string) => {
  const server = mcpServerOf(name)
  const mcp = server === undefined ? undefined : mcpKindOf(server)
  // Own keys only: a tool named like an Object.prototype member gets the plain look.
  const category = Object.hasOwn(TOOL_SAYINGS, name) ? TOOL_SAYINGS[name] : undefined
  const pose = Object.hasOwn(POSES, name) ? POSES[name] : undefined

  return {
    pose: (mcp ? 'mcp' : (pose ?? 'none')) as Pose,
    prop: mcp?.glyph ?? '',
    // A tool Jeb does not know gets a plain line: its name is never said.
    line: mcp ? `${mcp.line}…` : category ? bagPick(category) : TOOL_LINE,
  }
}

// Whether this second still has room for a change of activity.
function hasLiveRoom() {
  const win = Math.floor(S.ticks / LIVE_WINDOW_TICKS)
  if (win !== S.liveWin) {
    S.liveWin = win
    S.liveCount = 0
  }

  return S.liveCount < LIVE_BUDGET
}

// Jeb's pose and bubble for a change of activity, written right away. While he
// sweeps the barn (compaction) the broom stays in his hands.
function showLive($: EngineInterface, live: Live) {
  wake()
  if (S.isSweeping) {
    return
  }
  if (live.act === 'thinking' || live.act === 'writing') {
    S.pose = live.act === 'thinking' ? 'think' : 'draft'
    S.prop = ''
    detach(speak($, bagPick(live.act), 'working', 'say'))
  } else {
    const look = toolLook(live.name)
    S.pose = look.pose
    S.prop = look.prop
    detach(speak($, look.line, 'working', 'say'))
  }
  detach(pushAnim($))
}

// Counts the text chunks of the main stream in windows of BURST_TICKS ticks:
// past BURST_CHUNKS in one, the answer is a writing burst and Jeb hushes for a
// window. Plain arithmetic on S, nothing asked of the host.
function noteBurst() {
  if (S.ticks - S.burstAt >= BURST_TICKS) {
    S.burstAt = S.ticks
    S.burstN = 0
  }
  S.burstN += 1
  if (S.burstN > BURST_CHUNKS) {
    S.burstUntil = S.ticks + BURST_TICKS
  }
}

function noteStreamed(id: string) {
  if (!S.streamed.includes(id)) {
    S.streamed.push(id)
    if (S.streamed.length > MAX_STREAMED) {
      S.streamed.shift()
    }
  }
}

// One chunk of the main loop's response going by: only a change of activity
// does anything, and that is throttled. A chunk is already on its way when this
// runs; whatever goes wrong here is dropped.
function observeChunk($: EngineInterface, chunk: TurnStepChunk) {
  try {
    let live: Live
    if (chunk.kind === 'text') {
      noteBurst()
      live = { act: 'writing', name: '', id: '' }
    } else if (chunk.kind === 'thinking') {
      live = { act: 'thinking', name: '', id: '' }
    } else if (chunk.kind === 'tool') {
      live = { act: `tool:${chunk.name}`, name: chunk.name, id: chunk.id }
      noteStreamed(chunk.id)
    } else {
      return
    }
    if (live.act === S.activity) {
      return
    }
    S.activity = live.act
    if (hasLiveRoom()) {
      S.livePending = null
      S.liveCount += 1
      showLive($, live)
    } else {
      S.livePending = live
    }
  } catch {
    // a chunk that cannot be read is let go by
  }
}

// A finished step's own cost grows the crops now, not when the turn ends. The
// turn is remembered so turn.complete does not count the same tokens again.
function observeStep($: EngineInterface, result: TurnStepResult) {
  try {
    const { usage } = result
    if (!usage) {
      return
    }
    if (!S.stepTurns.includes(result.turnId)) {
      S.stepTurns.push(result.turnId)
      if (S.stepTurns.length > MAX_STEP_TURNS) {
        S.stepTurns.shift()
      }
    }
    detach(grow($, old => applyUsage(old, usage)))
  } catch {
    // a step that cannot be read is let go by
  }
}

// One 500 ms beat: tobacco time, the truck, Blue, the happenings, then the
// idle rotation. Idle beats are plain arithmetic on S; the clock is read only
// by the 30 s housekeeping.
async function tickOnce($: EngineInterface) {
  S.ticks += 1
  S.nowMs += TICK_MS
  const isSlow = S.ticks % SLOW_TICKS === 0
  if (S.isSettling) {
    detach(settleNow($))
  }

  // Ambient life, due or not: a comparison of two numbers, even while still.
  if (S.nextVisitAt > 0 && S.nowMs >= S.nextVisitAt) {
    await dueVisit($)
  }
  if (S.nextErrandAt > 0 && S.nowMs >= S.nextErrandAt) {
    dueErrand()
  }

  if (S.isStill) {
    if (isActiveNow()) {
      wake()
    } else {
      // Still life: only the 30 s housekeeping runs; the scene, the rotation
      // and the happenings' clocks hold where they stopped.
      if (S.ticks % DND_TICKS === 0) {
        detach(housekeep($, S.ticks % HEART_TICKS === 0))
      }

      return
    }
  }

  // A change of activity the throttle held back goes out as soon as a window
  // has room; nothing is asked of the host while none is waiting.
  if (S.livePending && hasLiveRoom()) {
    const live = S.livePending
    S.livePending = null
    S.liveCount += 1
    showLive($, live)
  }

  if (S.ticks % DND_TICKS === 0) {
    detach(housekeep($, S.ticks % HEART_TICKS === 0))
  }

  if (S.isBusy) {
    S.pendingMs += TICK_MS
    S.turnMs += TICK_MS
    if (S.pendingMs >= FLUSH_MS) {
      await flushWork($)
    }
    if (S.turnMs >= LONG_TURN_MS && !S.isLongSaid) {
      S.isLongSaid = true
      await speak($, bagPick('long'), 'working', 'say')
    }
  } else {
    S.idleTicks += 1
    S.quiet += 1
  }
  if (S.sinceSaid < TALK_TICKS) {
    S.sinceSaid += 1
  }

  for (const key of ['wag', 'wink', 'puff', 'sip', 'gate', 'wx', 'stitch', 'star'] as const) {
    if (S.fx[key] > 0) {
      S.fx[key] -= 1
    }
  }

  if (S.dogDir !== 0) {
    S.dogRun += S.dogDir * DOG_STEP
    if (S.dogRun >= DOG_REACH) {
      S.dogDir = -1
    } else if (S.dogRun <= 0) {
      S.dogRun = 0
      S.dogDir = 0
    }
  }

  if (S.truck) {
    if (S.truck.sputter > 0) {
      S.truck = { ...S.truck, sputter: S.truck.sputter - 1 }
    } else {
      const t = S.truck.t + 1
      if (t >= TRUCK_TICKS) {
        S.truck = null
        await finishDelivery($)
      } else {
        S.truck = { ...S.truck, t }
      }
    }
  }

  if (S.visit) {
    await stepVisit($, S.visit)
  }

  if (S.event) {
    S.event = { ...S.event, t: S.event.t + 1 }
    await runBeats($)
    // The happening may have changed while beats were spoken.
    if (S.event && S.event.t >= S.event.dur) {
      // A storm that has blown over leaves puddles, and now and then a rainbow.
      if (S.event.id === 'storm') {
        S.rainbowUntil = S.ticks + RAINBOW_TICKS
        S.wetUntil = S.nowMs + WET_MS
      }
      S.event = null
    }
  } else if (!S.truck && !S.visit) {
    S.eventTicks += 1
    if (S.eventTicks >= (S.isBusy ? EVENT_BUSY_TICKS : EVENT_IDLE_TICKS)) {
      S.eventTicks = 0
      await rollEvent($)
    }
  }

  if (!S.isBusy && S.idleTicks > 0 && S.idleTicks % IDLE_SAY_TICKS === 0 && !S.truck && !S.event) {
    // Jeb's own idle remark is the scene's, not activity: it does not restart the count to still.
    const calm = S.calm
    await speak($, idleLine(snapshot().idleAct), 'idle', 'say')
    S.calm = calm
  }

  if (S.truck || S.visit || S.dogDir !== 0 || S.event || isFxOn() || isSlow) {
    await pushAnim($)
  }

  S.calm = isActiveNow() ? 0 : S.calm + 1
  // The scene freezes only once the bubble is gone, so no line is left up in still-life.
  if (S.calm >= STILL_TICKS && S.sinceSaid >= TALK_TICKS && !S.isStill) {
    // The last frame, with night and dim as they are now; then the freeze.
    await pushAnim($)
    S.isStill = true
  }
  // Whatever changed this tick (and since the last) goes to the live record, once.
  await pushLive($)
}

// One beat at a time: a beat that is still running when the next is due makes
// the next one wait for the one after. A beat that fails is dropped.
async function tick($: EngineInterface) {
  if (S.isTicking) {
    return
  }
  S.isTicking = true
  try {
    await tickOnce($)
  } catch {
    // a bad beat is skipped
  } finally {
    S.isTicking = false
  }
}

// The line a command that is a test run or a Compose start says on its way in
// (it takes the place of the tool's own line): its cooldown key, its length and
// the words. A test run in a subagent says something only for a full suite.
type PreLine = { key: string; ms: number; line: string }

const preLineOf = (
  segments: readonly Segment[],
  work: Segment | undefined,
  isMain: boolean,
): PreLine | undefined => {
  if (work?.kind === 'test') {
    if (isMain) {
      return { key: 'test:run', ms: TEST_CAP_MS, line: TEST_RUN_LINE }
    }

    return work.filtered ? undefined : { key: 'test:run', ms: TEST_CAP_MS, line: HAND_WATER_LINE }
  }
  const start = segments.find(
    seg => seg.kind === 'exec' && ((seg.sub === 'up' && seg.detached) || (seg.sub === 'run' && seg.rm)),
  )

  return start
    ? { key: `barn:${serviceKey(start.svc)}`, ms: BUILDING_CAP_MS, line: start.sub === 'up' ? UP_LINE : RUN_LINE }
    : undefined
}

// Rain or a dry spell over one plot (or all), for a few seconds.
function setWeather(kind: 'rain' | 'dry', plot: Anim['weather']['plot']) {
  S.wx = { kind, plot }
  S.fx.wx = WEATHER_TICKS
  if (kind === 'rain') {
    S.wetUntil = S.nowMs + WET_MS
  }
}

// A failed run quiets everything but verdicts and milestones for a while.
function startLull() {
  S.hushUntil = S.nowMs + HUSH_MS
}

// A test run's or a lint run's result, in the weather and the weeding. Called
// only for the last segment of a foreground call in the main loop. The weather
// and the lull happen whatever Jeb may say.
async function weigh($: EngineInterface, work: Segment, command: string, isError: boolean) {
  if (work.kind === 'test') {
    const plot = work.filtered ? plotFor(command) : 'all'
    note(isError ? 'testsFailed' : 'testsPassed')
    if (isError) {
      S.testFails += 1
      startLull()
      setWeather('dry', plot)
      if (S.testFails === STREAK_AT) {
        // The streak line is not held to the cap, and takes it.
        if (await speak($, STREAK_LINE, 'spooked', 'streak')) {
          S.cool.test = S.nowMs
        }

        return
      }
      await speakCapped(
        $,
        'test',
        TEST_CAP_MS,
        work.filtered ? BAD_BATCH_LINE : DROUGHT_LINE,
        'spooked',
        'verdict',
      )

      return
    }
    const hadFails = S.testFails > 0
    S.testFails = 0
    setWeather('rain', plot)
    // The field is cleared: a stone, and a piece of iron salvaged from the fix
    // when this is the first pass after a failure.
    await saveCrafting($, old => gain(old, { stone: 1, iron: hadFails ? 1 : 0 }))
    if (hadFails) {
      if (await speak($, FIRST_RAIN_LINE, 'pleased', 'streak')) {
        S.cool.test = S.nowMs
      }

      return
    }
    await speakCapped(
      $,
      'test',
      TEST_CAP_MS,
      work.filtered ? RAIN_LINE : COUNTY_RAIN_LINE,
      'pleased',
      'verdict',
    )

    return
  }

  const key = `lint:${work.tool ?? 'lint'}`
  note('lintRuns')
  if (isError) {
    note('lintFailed')
    S.lintFails += 1
    startLull()
    await speakCapped($, key, LINT_CAP_MS, work.tool === 'phpstan' ? PHPSTAN_LINE : WEEDS_LINE, 'spooked', 'verdict')
  } else {
    // A run that rewrites files exits 0 and has not passed anything: it hoed.
    // A clean pass after a failed run salvages a piece of iron.
    if (!work.fixes) {
      const hadFails = S.lintFails > 0
      S.lintFails = 0
      if (hadFails) {
        await saveCrafting($, old => gain(old, { iron: 1 }))
      }
    }
    await speakCapped($, key, LINT_CAP_MS, work.fixes ? HOED_LINE : CLEAN_LINE, 'pleased', 'verdict')
  }
}

// A refused command: the deny rule's own line if the command matches one that
// has not just spoken, else the usual line.
async function sayDeny($: EngineInterface, segments: readonly Segment[], fallback: string) {
  const rule = denyRuleOf(segments)
  if (rule && (await speakCapped($, `deny:${rule}`, DENY_CAP_MS, DENY_LINES[rule], 'spooked', 'deny'))) {
    return
  }
  await speak($, fallback, 'spooked', 'deny')
}

// Ticket keys from triage: a cow in the field for each key not already there,
// and a line for the keys not seen before this session. Each key is turned into a
// neighbor's number at once (see anonymize.ts); only the numbers are kept.
function noteCows($: EngineInterface, ticketKeys: readonly string[]) {
  if (ticketKeys.length === 0) {
    return
  }
  // Without a settled salt the keys wait, in memory only.
  if (!isSalt(S.salt)) {
    S.heldKeys = [...S.heldKeys, ...ticketKeys].slice(-MAX_HELD_KEYS)

    return
  }
  const keys = [...new Set(ticketKeys.map(key => neighborOf(S.salt, key)))]
  const fresh = keys.filter(key => !S.seenKeys.includes(key))
  for (const key of keys) {
    if (!S.cows.includes(key)) {
      S.cows.push(key)
      if (S.cows.length > MAX_KEPT_COWS) {
        S.cows.shift()
      }
    }
  }
  for (const key of fresh) {
    S.seenKeys.push(key)
    if (S.seenKeys.length > MAX_SEEN_KEYS) {
      S.seenKeys.shift()
    }
  }
  if (fresh.length > 0) {
    detach(speak($, cowLine(fresh), 'idle', 'say'))
  }
  detach(pushAnim($))
}

// What a tool call leaves to do once its result has gone back: the still, the
// town trip, the sayings, the truck. None of it holds the call up. `verdict` is
// the test or lint run whose exit code is this call's (the last segment, in the
// foreground, of the main loop); it speaks instead of the generic error lines.
async function afterCall(
  $: EngineInterface,
  call: {
    tool: string
    command: string
    isShown: boolean
    isStorm: boolean
    segments: readonly Segment[]
    verdict: Segment | undefined
    // The command already had its own line on the way in (a test run, a
    // Compose start): the generic result lines stay out of its way.
    isOwned: boolean
  },
  ran: { isError?: boolean },
  isDenied: boolean,
) {
  const { tool, command, isShown, verdict } = call
  const { isOwned } = call

  if (isDenied) {
    if (isShown) {
      await sayDeny($, call.segments, bagPick('denied'))
    }
  } else if (STILL_TOOLS.has(tool)) {
    let still: StillRun | undefined
    let made: Made[] = []
    await saveFarm($, old => {
      still = runStill(old, Boolean(ran.isError))
      // A batch that comes off may leave lightning waiting to be aged.
      if (still.result !== 'lightning') {
        return still.next
      }
      const done = craftAll(still.next, nowDate())
      made = done.made

      return done.next
    })

    if (verdict) {
      await weigh($, verdict, command, Boolean(ran.isError))
    }
    if (still?.result === 'sour') {
      note('sours')
      note('rough')
      if (!isOwned) {
        await speak($, bagPick('sour'), 'spooked', 'say')
      }
    } else if (still?.result === 'failed') {
      if (!isOwned) {
        await speak($, bagPick('error'), 'spooked', 'say')
      }
    } else if (still?.result === 'dry') {
      if (!isOwned) {
        await speak($, bagPick('dry'), 'spooked', 'say')
      }
    } else if (still?.result === 'lightning') {
      if (still.jars > 0) {
        await announce($, still)
      } else {
        await speak($, bagPick('lightning'), 'pleased', 'milestone')
      }
      await sayMade($, made)
    }
  } else if (ran.isError) {
    if (isShown) {
      await speak($, bagPick('error'), 'spooked', 'say')
    }
  } else if (TOWN_TOOLS.has(tool)) {
    await grow($, townTrip)
  }
  if (!isDenied && !ran.isError && EDIT_TOOLS.has(tool)) {
    note('edits')
    await saveCrafting($, noteEdit)
  }

  if (call.isStorm && !S.event) {
    await startEvent($, 'storm')
  }
  if (!isDenied && !ran.isError && (tool === 'PublishPlugin' || isShip(command))) {
    // The truck leads the loose cows home.
    S.cows = []
    note('ships')
    await startTruck($)
  }
  await pushAnim($)
}

// The turn is over: the last of its working time and its tokens go to the farm.
async function afterTurn(
  $: EngineInterface,
  isMain: boolean,
  usage:
    | {
        input_tokens: number
        output_tokens: number
        cache_read_input_tokens: number
        cache_creation_input_tokens: number
      }
    | undefined,
) {
  if (isMain) {
    await flushWork($)
    await speak($, bagPick('done'), 'pleased', 'say')
    await pushAnim($)
  }
  if (usage) {
    await grow($, old => applyUsage(old, usage))
  }
}

// Reads what the store keeps of the options: the creativity switch and the talk level.
const overridesFrom = (saved: unknown): Overrides => {
  const raw = (typeof saved === 'object' && saved !== null ? saved : {}) as Record<string, unknown>
  const found: Overrides = {}
  if (typeof raw.creativity === 'boolean') {
    found.creativity = raw.creativity
  }
  const talk = TALK_LEVELS.find(level => level === raw.talk)
  if (talk) {
    found.talk = talk
  }

  return found
}

// Sessions: one store key, read-merge-written one after another with the farm's
// writes. Returns what it stored.
async function saveCamps($: EngineInterface, change: (saved: unknown) => Camps) {
  const run = saving.then(async () => {
    const raw = await $.store.get('sessions')
    const next = change(raw)
    if (JSON.stringify(next) !== JSON.stringify(raw)) {
      await $.store.set('sessions', next)
    }

    return next
  })
  saving = run.catch(() => undefined)

  return run
}

// The squares of sessions that died without saying goodbye go up on the quilt,
// once each (decided on the stored farm, by session id), and Granny says so.
async function stitchStale($: EngineInterface, stale: readonly Stale[]) {
  let last: ReturnType<typeof stitchFromBeat> | undefined
  await saveFarm($, old => {
    const done = stitchFarm(old, stale.map(stitchFromBeat))
    last = done.added[done.added.length - 1]

    return done.next
  })
  if (last) {
    S.fx.stitch = FX_STITCH
    await speak($, stitchLine(last.c), 'pleased', 'milestone')
    await pushAnim($)
  }
}

// The stored heartbeats, read in line with the writes to the store.
function readCamps($: EngineInterface) {
  const run = saving.then(() => $.store.get('sessions'))
  saving = run.catch(() => undefined)

  return run
}

// A dead heartbeat as it is stitched: one this Jeb wrote stands as it is (a hashed
// key and a place); one from a Jeb before the anonymizer, or with a camp that is
// not a place, is made over first (see anonymize.ts), so nothing raw reaches the quilt.
const staleFor = (stale: Stale): Stale => {
  if (isToken(stale.id) && isPlace(stale.name)) {
    return stale
  }
  const made = beatFor(S.salt, S.places, stale)

  return isToken(stale.id) ? { ...made, id: stale.id } : made
}

// A camp's name as it is shown: a place, or the place a raw name is given.
const shownCamp = (name: string) => (isPlace(name) ? name : placeSeen(S.salt, name, S.places))

// The heartbeats this Jeb writes, with any camp that is not a place made one (and
// its line rebuilt around it) before they are written back.
const placedCamps = (ours: Record<string, unknown>) =>
  Object.fromEntries(
    Object.entries(ours).map(([id, entry]) => {
      const item = recordOf(entry)
      const name = typeof item.name === 'string' ? item.name : ''
      if (name === '' || isPlace(name)) {
        return [id, entry]
      }
      const place = shownCamp(name)
      const day = dateKeyOf(new Date(Number(item.lastSeen) || S.nowMs))

      return [id, { ...item, name: place, ...(typeof item.ln === 'string' ? { ln: lineFor(item.ln, day, place) } : {}) }]
    }),
  )

// A change to the heartbeats that also finds the dead ones (older than the TTL,
// with a square on them). Their squares go up on the quilt first; their
// heartbeats leave the store (with the change) only once that farm save is done,
// so a crash or a timeout between the two loses nothing. A save that fails
// leaves the whole change for the next beat. The change is handed only the
// heartbeats this Jeb writes (hashed keys): those of a Jeb before it are never
// written back, and only the raw camp names of the ones alive come with them.
async function sweepCamps(
  $: EngineInterface,
  selfId: string,
  change: (ours: Record<string, unknown>, legacy: string[]) => Camps,
) {
  const stale = staleOf(await readCamps($), selfId, S.nowMs).map(staleFor)
  if (stale.length > 0) {
    await stitchStale($, stale)
  }

  return saveCamps($, saved => {
    const split = splitCamps(saved, isToken, S.nowMs)

    return change(placedCamps(split.ours), split.legacy)
  })
}

// This session's own square and journal line go up, once, when it ends; whether
// that is done (so its heartbeat may go) and whether a square went up.
// The camp's place is registered on the farm as stored in the same save (so two
// camps never share one while the list has room, see anonymize.ts).
async function stitchOwn($: EngineInterface, id: string, rec: typeof S.session) {
  if (squareFor(rec) === null || !isSalt(S.salt)) {
    return false
  }
  const date = new Date(await clockMs($))
  const key = keyOfId(id)
  let isAdded = false
  let place = ''
  await saveFarm($, old => {
    const placed =
      S.campTag === '' ? { place: S.campName || rec.camp, tags: old.anonPlaces } : placeOfTag(S.campTag, old.anonPlaces)
    const stitch = stitchOf({ ...rec, camp: placed.place }, date, key)
    if (!stitch) {
      return old
    }
    const done = stitchFarm(placed.tags === old.anonPlaces ? old : { ...old, anonPlaces: placed.tags }, [stitch])
    isAdded = done.added.length > 0
    place = placed.place

    return isAdded ? done.next : old
  })
  if (place !== '' && S.campTag !== '') {
    S.campName = place
    S.session.camp = place
  }

  return isAdded
}

// This session's id and camp name, read once (and again after a /clear).
async function resolveSession($: EngineInterface) {
  try {
    S.sessionId = String(await $.session.id())
  } catch {
    S.sessionId = ''
  }
  if (S.sessionId === '') {
    S.sessionId = `s${Math.random().toString(36).slice(2, 10)}`
  }
  await resolveCamp($)
}

// This session's camp, once there is a settled salt to key it with (until then it
// has none, and its raw name is not looked at).
async function resolveCamp($: EngineInterface) {
  if (S.campName === '' && isSalt(S.salt)) {
    let root = ''
    let repo: { root: string; name: string | null } | null = null
    try {
      root = await $.session.root()
    } catch {
      root = ''
    }
    try {
      repo = await $.session.repo()
    } catch {
      repo = null
    }
    // The raw name goes no further than its tag: the camp is the place it gives.
    S.campTag = campTagOf(S.salt, campName(root, repo, S.cwd))
    S.campName = placeOfTag(S.campTag, S.places).place
  }
  S.session.camp = S.campName
}

// The salt of a farm from before the anonymizer, settled between sessions that
// share the store (it has no compare-and-set). One step on a tick, at most once a
// second (see settle.ts): a farm with no salt gets this session's (or one another wrote first, which
// stands); a salt read is adopted, and only when the same one reads the same twice
// in a row is the farm made over, under that stored salt and nothing else, so every
// session makes the same farm of it. Until then nothing is keyed, placed or stored
// of the work, and the view shows the farm shielded.
async function settleNow($: EngineInterface) {
  if (!S.isSettling || S.isSettleBusy) {
    return
  }
  if (S.isStoreLocked) {
    // A farm from the future is never touched: this session plays on with a salt of its own.
    S.isSettling = false
    S.salt = isSalt(S.salt) ? S.salt : mintSalt()
    await settled($)

    return
  }
  S.isSettleBusy = true
  try {
    const result = await settleStep(S.settle, {
      now: S.nowMs,
      read: async () => readFarm(await readStored($)),
      save: change => saveFarm($, change),
      salt: () => S.salt,
    })
    if (result === 'gone') {
      S.salt = mintSalt()
    }
    if (result !== 'wait') {
      S.isSettling = false
      await settled($)
    }
  } finally {
    S.isSettleBusy = false
  }
}

// The salt has settled: the camp, the heartbeat and the ticket keys held come next.
async function settled($: EngineInterface) {
  await resolveCamp($)
  const held = S.heldKeys
  S.heldKeys = []
  noteCows($, held)
  if (S.isInteractive && S.sessionId !== '') {
    await heartbeat($)
  }
  if (S.isLanternDue && S.camps.length > 0) {
    S.isLanternDue = false
    await speak($, lanternLine(S.camps), 'idle', 'start')
  }
  await pushAnim($)
}

// The stored farm as it is, read in line with the writes to the store.
function readStored($: EngineInterface) {
  const run = saving.then(() => $.store.get('farm'))
  saving = run.catch(() => undefined)

  return run
}

// The session's id and record go into the `kept` atom (only when they changed),
// so a plugin reload can pick them up again. Never from a render, and not for a
// run nobody is at.
async function keepSession($: EngineInterface) {
  if (S.sessionId === '' || !S.isInteractive) {
    return
  }
  const next = keepOf(S.sessionId, S.session)
  const key = JSON.stringify(next)
  if (key !== S.lastKept) {
    S.lastKept = key
    await update($, kept, () => next)
  }
}

// After /clear or a resume the process goes on under another id: the new one is
// taken from the engine (never the one that just ended), and the record goes
// with it. Until it is known the id stays empty and the next beat asks again.
async function adoptSession($: EngineInterface, endedId: string) {
  S.sessionId = ''
  S.isEnding = false
  try {
    const id = String(await $.session.id())
    if (id !== '' && id !== endedId) {
      S.sessionId = id
    }
  } catch {
    S.sessionId = ''
  }
  try {
    await keepSession($)
  } catch {
    // a record that cannot be kept is kept next time
  }
}

// Every 60 s: this session's heartbeat goes into the store and the others' come
// back as lanterns. A store that fails leaves the lanterns as they were.
async function heartbeat($: EngineInterface) {
  try {
    // Nothing of the work is keyed, placed or written until the salt has settled.
    if (!isSalt(S.salt)) {
      return
    }
    if (S.sessionId === '') {
      await resolveSession($)
    }
    const key = ownKey()
    let legacy: string[] = []
    const camps = await sweepCamps($, key, (ours, alive) => {
      legacy = alive

      return beat(ours, key, S.campName, S.nowMs, markFor(S.session, new Date(S.nowMs)))
    })
    const before = S.camps.length
    S.camps = [...othersOf(camps, key), ...legacy].map(shownCamp).sort()
    if (S.camps.length !== before) {
      await pushAnim($)
    }
    await keepSession($)
    await pruneLive($, camps)
  } catch {
    // a beat that fails changes nothing
  }
}

// A hand is finished: it is let go, and a hand tending a plot says how it went
// ("back from town", or "come back empty-handed"). A hand already gone is left be.
function finishHired($: EngineInterface, id: string, isFailed: boolean) {
  const agent = findHired(S.agents, id)
  if (!agent || agent.state !== 'working') {
    return
  }
  S.agents = withoutHired(S.agents, id)
  if (kindOf(agent) === 'foreground') {
    detach(speak($, isFailed ? HAND_FAILED_LINE : HAND_HOME_LINE, 'pleased', 'say'))
  }
}

// An agent showed a sign of life (a step or a tool call of its own).
function touchHired(id: string | undefined) {
  const agent = findHired(S.agents, id)
  if (agent) {
    agent.activeAt = S.nowMs
  }
}

// Takes a spawned agent on, and says so.
function hire($: EngineInterface, spawn: Parameters<typeof hireOf>[0]) {
  const agent = hireOf(spawn, S.nowMs)
  note('agents')
  const hadWorkflow = S.agents.some(other => other.isWorkflow)
  S.agents = addHired(S.agents, agent)
  const hands = S.agents.filter(other => kindOf(other) === 'foreground').length
  if (!(agent.isWorkflow && hadWorkflow)) {
    detach(speak($, hireLine(agent, hands), 'idle', 'say'))
  }
  detach(pushAnim($))
}

const LIVE_STATUSES = new Set(['pending', 'running', 'waiting'])

// At session start and every 30 s: the engine's own list says who has finished,
// and who is running that this module does not know (a hot reload resets the
// list): those are taken on as plain hands, without a hire line.
async function refreshAgents($: EngineInterface) {
  if (S.isListing) {
    return
  }
  S.isListing = true
  try {
    const known = new Map((await $.agent.list()).map(info => [info.id, info]))
    for (const agent of [...S.agents]) {
      const info = known.get(agent.id)
      if (info) {
        if (info.status === 'completed' || info.status === 'failed' || info.status === 'killed') {
          finishHired($, agent.id, info.status !== 'completed')
        } else if (agent.isTeammate) {
          agent.isAwake = info.status === 'running'
        }
      } else if (
        agent.isWorkflow
          ? S.nowMs - agent.activeAt > WORKFLOW_IDLE_MS
          : S.nowMs - agent.startedAt > LIST_GRACE_MS
      ) {
        // No list names a workflow hand, so one that has gone quiet for good is
        // let go without a word.
        finishHired($, agent.id, false)
      }
    }
    for (const info of known.values()) {
      if (LIVE_STATUSES.has(info.status) && !findHired(S.agents, info.id)) {
        S.agents = addHired(
          S.agents,
          hireOf(
            {
              agentId: info.id,
              subagentType: info.type,
              isTeammate: info.type === 'teammate' || info.teammateId !== undefined,
              description: info.description,
              name: info.name,
            },
            S.nowMs,
          ),
        )
      }
    }
    await pushAnim($)
  } catch {
    // a list that fails changes nothing
  } finally {
    S.isListing = false
  }
}

// /clear: the conversation is new, the farm and the other camps are not.
function clearSession($: EngineInterface) {
  detach(flushWork($))
  S.isBusy = false
  S.pose = 'none'
  S.prop = ''
  S.idleTicks = 0
  S.quiet = 0
  S.turnMs = 0
  S.isLongSaid = false
  S.dogRun = 0
  S.dogDir = 0
  S.event = null
  S.eventUsed = {}
  S.beats = []
  S.beatIdx = 0
  S.eventTicks = 0
  S.fx = { wag: 0, wink: 0, puff: 0, sip: 0, gate: 0, wx: 0, stitch: 0, star: 0 }
  S.session = freshSession(S.nowMs, S.campName)
  S.building = ''
  S.cows = []
  S.testFails = 0
  S.lintFails = 0
  S.turnSaid = false
  S.errorStreak = 0
  S.agents = []
  S.isSweeping = false
  S.gates.clear()
  S.activity = ''
  S.livePending = null
  S.sessionId = ''
  S.turnSeed = Math.floor(Math.random() * 100_000)
  detach(speak($, CLEAR_LINE, 'idle', 'start'))
  detach(pushAnim($))
}

// A test's view of how much the session holds on to.
export const stateSize = () => JSON.stringify(S).length

export const register: Register = (on, options) => {
  OPT = readOptions(options)

  on('session.start', async ($, e, next) => {
    // Jeb's start-up is only watching: whatever it throws, the session starts.
    try {
      await (async () => {
        ticker?.cancel()
        ticker = undefined
        S = fresh()
        S.isInteractive = e.isInteractive
        S.nowMs = await $.clock.now()
        S.startedAt = S.nowMs
        S.session = freshSession(S.nowMs)
        S.cwd = e.cwd
        S.turnSeed = Math.floor(Math.random() * 100_000)

        const stored = await $.store.get('farm')
        let lastTime: string | undefined
        if (isFutureFarm(stored)) {
          // A newer Jeb wrote this farm: leave it alone and play on a fresh one.
          S.isStoreLocked = true
          const first = freshFarm()
          await update($, farm, () => first)
          wakeOnView(first)
        } else {
          const saved = readFarm(stored)
          if (saved) {
            const shown = shieldFarm(saved)
            lastTime = shown.journal[shown.journal.length - 1]?.line
            await saveFarm($, () => saved)
            // A farm that still has real names waits for its salt to settle.
            S.isSettling = saved.anonPending === true
          }
        }
        // The anonymizer's salt: the stored farm's (just read), else one made now,
        // which the farm keeps from its first save. A farm waiting for its salt is
        // given one by the settling (settle.ts).
        if (S.isSettling) {
          await settleNow($)
        } else if (!isSalt(S.salt)) {
          S.salt = mintSalt()
        }
        S.saidAt = S.nowMs
        S.overrides = overridesFrom(await $.store.get('overrides'))

        // A `-p` run or the SDK: the hooks pass through and the crops grow from what
        // is used, but nothing periodic is set up (no ticker, no heartbeat) and no
        // square or journal line will be stitched.
        if (!S.isInteractive) {
          return
        }

        // The plugin may have reloaded under a running session (a change of /config
        // does it): the same session id means the record so far is still its own,
        // and Jeb does not greet again.
        await resolveSession($)
        const keptSession = keptOf(await read($, kept))
        const isReload = keptSession !== undefined && keptSession.id === S.sessionId
        if (keptSession && isReload) {
          S.session = { ...keptSession.rec, camp: S.campName || keptSession.rec.camp }
        }

        // JEB_CREATIVITY=off leaves the creative drops out and =local leaves the model
        // and the host out of them (for a test).
        try {
          const dial = await $.env.get('JEB_CREATIVITY')
          S.creativity = dial === 'off' ? 'off' : dial === 'local' ? 'local' : 'on'
        } catch {
          S.creativity = 'on'
        }

        // JEB_DROP_NOW=1 (dev/run --surprise) runs one surprise at once, whatever the hour.
        try {
          S.dropNow = (await $.env.get('JEB_DROP_NOW')) === '1' ? 'pending' : 'off'
        } catch {
          S.dropNow = 'off'
        }

        // The project's key, once the creativity dial is known (an area is creative
        // content: with creativity off there is no key, no counting and no area).
        await readAppFlag($)
        await resolveArea($)

        S.news = JEB_NEWS
        try {
          const dial = await $.env.get('JEB_NEWS')
          if (dial !== undefined && dial !== '') {
            try {
              S.news = JSON.parse(dial)
            } catch {
              S.news = null
            }
          }
        } catch {
          // an environment that cannot be read leaves the build's own news
        }

        if (!isReload) {
          const flags = dayFlags(nowDate())
          const holiday = flags.isNewYear || flags.isBirthday || flags.isGroundhog
          await speak($, holiday ? (dateLines(nowDate())[0] as string) : bagPick(greetingFor()), 'idle', 'start')
          // Once a session: the last one's journal line.
          if (lastTime) {
            await speak($, `Last time: ${lastTime}`, 'idle', 'start')
          }
        }
        // The news, once, right after the greeting.
        try {
          await announceNews($)
        } catch {
          // news that cannot be told is told next time
        }
        await heartbeat($)
        if (S.camps.length > 0 && !isReload) {
          await speak($, lanternLine(S.camps), 'idle', 'start')
        } else {
          S.isLanternDue = S.isSettling && !isReload
        }
        if (pendingLine) {
          await speak($, pendingLine, 'idle', 'start')
          pendingLine = undefined
        }
        await pushAnim($)
        await refreshAgents($)

        // The first visit comes two to four minutes in, Blue's first errand later
        // (neither, with JEB_VISITS=off).
        let isVisitsOff = false
        visitRng = Math.random
        try {
          const dial = await $.env.get('JEB_VISITS')
          const fixed = Number(dial)
          isVisitsOff = dial === VISITS_OFF
          if (dial !== undefined && dial !== '' && Number.isFinite(fixed) && fixed >= 0 && fixed < 1) {
            visitRng = () => fixed
          }
        } catch {
          // an environment that cannot be read leaves the visits on
        }
        // JEB_UNLOCKS=off leaves the day's little things unscheduled (for a test).
        let isUnlocksOff = false
        try {
          isUnlocksOff = (await $.env.get('JEB_UNLOCKS')) === 'off'
        } catch {
          // an environment that cannot be read leaves them on
        }
        S.unlockAt = isUnlocksOff ? 0 : S.nowMs + firstUnlockSpan(Math.random)
        if (!isVisitsOff) {
          S.nextVisitAt = S.nowMs + spanOf(FIRST_VISIT_MS, visitRng)
          S.nextErrandAt = S.nowMs + spanOf(ERRAND_MS, visitRng)
        }

        ticker = $.clock.every(TICK_MS, () => {
          void tick($)
        })

      })()
    } catch {
      // the session starts without him
    }

    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    try {
      const { next: levels, isCrossed } = limitCrossings(S.limits, e.rateLimits)
      S.limits = levels
      if (isCrossed) {
        await speak($, LIMIT_LINE, 'spooked', 'milestone')
      }
    } catch {
      // watching only: the hook goes on
    }

    return next(e)
  })

  // A change made in the /config menu keeps the switch and the talk level current,
  // and replaces a value that was kept in the store.
  on('config.set', async ($, e, next) => {
    // A change made in the menu may reload the plugin: the record is kept first.
    try {
      await keepSession($)
    } catch {
      // a record that cannot be kept is kept next time
    }
    const result = await next(e)
    try {
      if (e.key === 'jeb.creativity' && result.deny === undefined && typeof e.value === 'boolean') {
        OPT = { ...OPT, creativity: e.value }
        S.overrides.creativity = e.value
        detach($.store.set('overrides', S.overrides))
      }
      const talk = TALK_LEVELS.find(level => level === e.value)
      if (e.key === 'jeb.talk' && talk && result.deny === undefined) {
        OPT = { ...OPT, talk }
        S.overrides.talk = talk
        detach($.store.set('overrides', S.overrides))
        detach(pushAnim($))
      }
    } catch {
      // the call has run: what we note of it never fails it
    }

    return result
  })

  // The prompt is only read: what Jeb makes of it never changes it. Slash
  // commands and meta prompts are not the person talking, so Jeb ignores them.
  on('prompt.submit', async ($, e, next) => {
    try {
      wake()
      if (e.command === undefined && e.isMeta !== true) {
        const reaction = reactTo(e.text)
        if (e.turnId === undefined) {
          S.idleTicks = 0
          S.eventTicks = 0
        }
        if (reaction.wag) {
          S.fx.wag = FX_WAG
        }
        if (reaction.wink) {
          S.fx.wink = FX_WINK
        }
        if (reaction.puff) {
          S.fx.puff = FX_PUFF
        }
        detach(speak($, reaction.line ?? bagPick('working'), 'working', e.turnId === undefined ? 'first' : 'say'))
        detach(pushAnim($))
      } else if (e.command?.name === 'triage') {
        // Only the ticket keys of the arguments are read; the arguments are not kept.
        noteCows($, ticketKeys(e.command.args))
      }
    } catch {
      // watching only: the hook goes on
    }

    return next(e)
  })

  // Jeb is busy for as long as a main-loop turn runs.
  on('turn.start', async ($, e, next) => {
    try {
      wake()
      if (e.agentId === undefined) {
        note('turns')
        S.isBusy = true
        S.idleTicks = 0
        S.eventTicks = 0
        S.turnMs = 0
        S.isLongSaid = false
        S.turnSeed = Math.floor(Math.random() * 100_000)
        S.activity = ''
        S.livePending = null
        detach(pushAnim($))
      } else {
        const mate = findHired(S.agents, e.agentId)
        if (mate?.isTeammate) {
          mate.isAwake = true
          detach(pushAnim($))
        }
      }
    } catch {
      // watching only: the hook goes on
    }

    return next(e)
  })

  // The response as it streams. Pass-through: every chunk goes up first, as it
  // came and in order, and the result goes up as it came; what Jeb makes of a
  // chunk happens after, and can never change or hold up the stream.
  on('turn.step', async function* ($, e, next) {
    const isMain = e.agentId === undefined
    try {
      wake()
      if (isMain) {
        S.activity = ''
      } else {
        touchHired(e.agentId)
      }
    } catch {
      // watching only: the hook goes on
    }
    const stream = next(e)
    for await (const chunk of stream) {
      yield chunk
      if (isMain) {
        try {
          observeChunk($, chunk)
        } catch {
          // watching only: the stream goes on
        }
      }
    }
    const result = await stream.result
    try {
      observeStep($, result)
    } catch {
      // the call has run: what we note of it never fails it
    }

    return result
  })

  on('tool.call', async ($, e, next) => {
    const input = e as unknown as Record<string, unknown>
    let isShown = false
    let command = ''
    let segments: Segment[] = []
    let verdict: ReturnType<typeof workOf>
    let pre: ReturnType<typeof preLineOf>
    // What Jeb does with a call is only watching: whatever it throws, the call goes on.
    try {
      wake()
      const isMain = e.agentId === undefined
      touchHired(e.agentId)
      // A subagent's tool call moves Jeb only while the main turn is running.
      isShown = isMain || S.isBusy
      command = e.tool === 'Bash' && typeof input.command === 'string' ? input.command : ''
      // What the command is is read once, from its words: a test run, a lint run,
      // something in a Compose service. Only the last segment of a foreground
      // command in the main loop has a verdict.
      segments = command === '' ? [] : classify(command)
      const work = workOf(segments)
      const isForeground = input.run_in_background !== true
      verdict = isMain && isForeground && work?.isLast ? work : undefined
      const isWeeding = work?.kind === 'lint'
      pre = preLineOf(segments, work, isMain)

      if (isShown) {
        // The stream already put this call's pose and line up: nothing flickers twice.
        const isStreamed =
          e.tool_use_id !== undefined &&
          S.livePending === null &&
          S.activity === `tool:${e.tool}` &&
          S.streamed.includes(e.tool_use_id)
        if (!isStreamed) {
          const look = toolLook(e.tool)
          // The broom stays in his hands while he sweeps the barn.
          if (!S.isSweeping) {
            S.pose = look.pose
            S.prop = look.prop
          }
          S.activity = `tool:${e.tool}`
          S.livePending = null
          // A classified command's line takes the tool's place; a lint run, weeding, says none.
          if (!pre && !isWeeding) {
            detach(speak($, look.line, 'working', 'say'))
          }
        }
        if (isWeeding && !S.isSweeping) {
          S.pose = 'hoe'
          S.prop = ''
        }
        if (pre) {
          detach(speakCapped($, pre.key, pre.ms, pre.line, 'working', 'say'))
        }
        // The Compose service the command runs in is a building by the house.
        const building = buildingOf(segments.find(seg => seg.svc !== undefined)?.svc)
        const isMoved = isWeeding || building !== S.building
        S.building = building
        if (ERRANDS.has(e.tool)) {
          startErrand()
        }
        if (!isStreamed || ERRANDS.has(e.tool) || isMoved) {
          detach(pushAnim($))
        }
      }

      // A triage ticket fetched through the work board is a loose cow too; its
      // line comes after the tool's own.
      if (mcpServerOf(e.tool) !== undefined && e.tool.includes('getJiraIssue')) {
        noteCows($, ticketKeys(input.issueIdOrKey))
      }

    } catch {
      // the call goes on unwatched
    }

    const ran = await next(e)
    try {
      // A settings hook that said no to this very call was seen beneath it
      // (classic.PreToolUse). The command never ran: it is not a failure, a test
      // result or a call of the session's, so nothing of it is counted. The gate
      // has its own line and its 🚧.
      if (takeGate(S.gates, e.tool_use_id)) {
        detach(pushAnim($))

        return ran
      }
      note('calls')
      const isDenied = 'deny' in ran && ran.deny !== undefined
      if (isDenied || ran.isError) {
        note('rough')
      }
      noteWork(e.tool, command, segments, input)

      // A storm blows in when the third error in a row lands, once.
      let isStorm = false
      if (!isDenied) {
        if (ran.isError) {
          S.errorStreak += 1
          isStorm = S.errorStreak === 3 && !S.event
        } else {
          S.errorStreak = 0
        }
      }
      detach(
        afterCall(
          $,
          {
            tool: e.tool,
            command,
            isShown,
            isStorm,
            segments,
            verdict,
            isOwned: verdict !== undefined || pre !== undefined,
          },
          ran,
          isDenied,
        ),
      )
    } catch {
      // the call has run: what we note of it never fails it
    }

    return ran
  })

  on('turn.complete', async ($, e, next) => {
    try {
      // Subagent turns feed the crops but do not end Jeb's work.
      const isMain = e.agentId === undefined
      if (isMain) {
        S.isBusy = false
        S.pose = 'none'
        S.prop = ''
        S.building = ''
        S.turnSaid = false
        S.activity = ''
        S.livePending = null
        S.idleTicks = 0
        S.eventTicks = 0
      } else {
        // A hired hand's turn ends it, a teammate's only sends it to rest.
        const hand = findHired(S.agents, e.agentId)
        if (hand?.isTeammate) {
          hand.isAwake = false
        } else if (hand) {
          finishHired($, hand.id, e.reason !== 'answer')
        }
        detach(pushAnim($))
      }
      // A turn whose steps already brought their tokens in does not bring them twice.
      detach(afterTurn($, isMain, S.stepTurns.includes(e.turnId) ? undefined : e.usage))
    } catch {
      // watching only: the hook goes on
    }

    return next(e)
  })

  // Agents. Observing only: the spawn goes through unchanged, and what Jeb
  // makes of it happens once it has started.
  on('agent.spawn', async ($, e, next) => {
    wake()
    const result = await next(e)
    try {
      if (result.deny === undefined && result.agentId) {
        hire($, {
          agentId: result.agentId,
          subagentType: e.subagentType,
          background: e.background,
          isTeammate: e.isTeammate,
          workflow: e.workflow,
          description: e.description,
          name: e.name,
        })
      }
    } catch {
      // the call has run: what we note of it never fails it
    }

    return result
  })

  // Hooks a security plugin above Jeb may skip: the settings hooks (resume and
  // fork lines, a denying settings hook, subagent and teammate stops) and
  // compaction. Where one is skipped Claude Code prints a line at every load,
  // so they are only registered when the hookReactions option is on.
  if (OPT.hookReactions) {
    on('classic.SubagentStop', ($, e, next) => {
      const result = next(e)
      try {
        finishHired($, e.agent_id, false)
        detach(pushAnim($))
      } catch {
        // the call has run: what we note of it never fails it
      }

      return result
    })

    on('classic.TeammateIdle', ($, e, next) => {
      const result = next(e)
      try {
        for (const agent of S.agents) {
          if (agent.isTeammate && (agent.name === e.teammate_name || agent.id.startsWith(`${e.teammate_name}@`))) {
            agent.isAwake = false
          }
        }
        detach(pushAnim($))
      } catch {
        // the call has run: what we note of it never fails it
      }

      return result
    })

    // A settings hook that denies a call puts up a gate; the decision is theirs.
    on('classic.PreToolUse', async ($, e, next) => {
      const result = await next(e)
      try {
        if (result.deny !== undefined) {
          markGate(S.gates, e.tool_use_id)
          S.fx.gate = FX_GATE
          const given = (e as unknown as Record<string, unknown>).command
          const command = e.tool === 'Bash' && typeof given === 'string' ? given : ''
          detach(sayDeny($, command === '' ? [] : classify(command), GATE_LINE))
          detach(pushAnim($))
        }
      } catch {
        // the call has run: what we note of it never fails it
      }

      return result
    })

    // Resume and fork get a line; the others say nothing.
    on('classic.SessionStart', ($, e, next) => {
      const result = next(e)
      try {
        const line =
          e.source === 'resume'
            ? resumeLine(e.seconds_since_last_response)
            : e.source === 'fork'
              ? FORK_LINE
              : undefined
        if (line) {
          if (ticker) {
            detach(speak($, line, 'idle', 'start'))
          } else {
            pendingLine = line
          }
        }
      } catch {
        // the call has run: what we note of it never fails it
      }

      return result
    })

    // Compaction of the main conversation: Jeb sweeps out the barn while it runs.
    on('session.compact', async ($, e, next) => {
      if (e.agentId !== undefined || e.trigger === 'precompute') {
        return next(e)
      }
      try {
        S.isSweeping = true
        S.sweepPose = S.pose === 'sweep' ? S.sweepPose : S.pose
        S.pose = 'sweep'
        detach(speak($, e.trigger === 'auto' ? SWEEP_AUTO_LINE : SWEEP_LINE, 'working', 'say'))
        detach(pushAnim($))
      } catch {
        // watching only: the compaction goes on
      }
      try {
        const result = await next(e)
        try {
          if (result.skip === undefined) {
            const line = sweptLine(result.tokensBefore, result.tokensAfter)
            if (line) {
              detach(speak($, line, 'pleased', 'say'))
            }
          }
        } catch {
          // the call has run: what we note of it never fails it
        }

        return result
      } finally {
        S.isSweeping = false
        if (S.pose === 'sweep') {
          S.pose = S.sweepPose
        }
        detach(pushAnim($))
      }
    })
  }

  // The session ends: its square and line are stitched (any end but a resume; a
  // /clear counts), then its heartbeat goes, and a /clear starts the day over. A
  // square that could not be stitched in time leaves the heartbeat, so another
  // session stitches it from there. A resume goes on under a new session id: the
  // old heartbeat goes unstitched and the record carries over to the new id, so
  // nothing is counted twice. A run nobody is at stitches and beats nothing.
  on('session.end', async ($, e, next) => {
    if (!S.isInteractive) {
      return next(e)
    }
    try {
      S.isEnding = true
      // The truck's not coming: the loose cows are led home with the session.
      S.cows = []
      detach(pushAnim($))
    } catch {
      // watching only: the hook goes on
    }
    const rec = S.session
    let isDone = true
    let isStitched = false
    if (e.reason !== 'resume' && squareFor(rec) !== null) {
      isDone = false
      try {
        if (next.budget.remainingMs > STITCH_MIN_MS) {
          isStitched = await stitchOwn($, e.sessionId, rec)
          isDone = true
        }
      } catch {
        // a stitch that fails leaves the heartbeat behind
      }
    }
    if (isDone && isSalt(S.salt)) {
      const key = keyOfId(e.sessionId)
      detach(sweepCamps($, key, ours => without(ours, key, S.nowMs)))
    }
    // Its live record goes with it.
    try {
      await dropLive($)
    } catch {
      // a record that cannot be taken out is pruned by the others once it is stale
    }
    if (e.reason === 'clear') {
      clearSession($)
      // The new conversation's clothesline flashes the square just stitched.
      if (isStitched) {
        S.fx.stitch = FX_STITCH
      }
    }
    const result = await next(e)
    try {
      if (e.reason === 'clear' || e.reason === 'resume') {
        await adoptSession($, e.sessionId)
      }
    } catch {
      // the call has run: what we note of it never fails it
    }

    return result
  })
}
