export type Mood = 'idle' | 'working' | 'pleased' | 'spooked'

export type Say = { line: string; mood: Mood }

// The random happenings on the homestead.
export type EventId =
  | 'revenuer'
  | 'neighbor'
  | 'bear'
  | 'whistlepig'
  | 'mothman'
  | 'bugs'
  | 'bells'
  | 'storm'
  | 'fog'
  | 'turkeys'
  | 'parachute'
  | 'track'
  | 'hornworm'
  | 'applebutter'
  | 'bees'
  | 'sorghum'
  | 'ramps'
  | 'sang'
  | 'quilting'
  | 'britches'
  // A creative drop's happening (see drops.ts); never drawn from the random pool.
  | 'drop'

// One running happening: `t` counts 500 ms ticks of its `dur`; `v` is a small
// variant picked when it starts (the neighbor's sale, a lightning-bug seed).
// A creative drop's happening carries its own art: up to three sprites and the
// custom pictures (at most two) they may name.
export type ActiveEvent = {
  id: EventId
  t: number
  dur: number
  v: number
  art?: { sprites: DropSprite[]; custom: DropArt[] }
}

// ---- creative drops (see drops.ts and surprise.ts) ----

// Where on the band a sprite stands, what kinds of surprise there are, and a
// sprite placed there: `sprite` is a built-in name from the allowlist or the id
// of a custom picture.
export type DropZone = 'yard' | 'sky' | 'porch' | 'field' | 'road'
export type DropKind = 'happening' | 'saying' | 'decor' | 'almanac'
export type DropSprite = { sprite: string; zone: DropZone; frames: 1 | 2 }
export type DropWindow = { from: number; to: number }
export type DropLasts = 'today' | 'week'
// A picture the model drew: `rows` holds `h * frames` strings of `w` palette keys.
export type DropArt = { id: string; w: number; h: number; frames: 1 | 2; rows: string[] }
// One step of a multi-day storyline.
export type ArcStep = {
  day: number
  kind: DropKind
  lines: string[]
  sprites: DropSprite[]
  window: DropWindow | null
  lasts: DropLasts
  keep: boolean
  festival: string
}
export type ArcState = {
  name: string
  made: 'haiku' | 'local'
  start: string
  last: string
  // Index of the next step to deliver.
  at: number
  steps: ArcStep[]
}
export type Surprise = {
  day: string
  slot: number
  kind: DropKind
  name: string
  lines: string[]
  sprites: DropSprite[]
  window: DropWindow | null
  lasts: DropLasts
  made: 'haiku' | 'local'
  // The arc this is a step of ('' none) and which step (0 none).
  arc: string
  step: number
  festival: string
}
export type CreativeLogEntry = { day: string; name: string; kind: DropKind; summary: string; arc?: string }
export type Structure = { name: string; day: string; arc: string; sprites: DropSprite[] }
export type Creative = {
  total: number
  arc: ArcState | null
  structures: Structure[]
  art: DropArt[]
  festival: { d: string; tint: string }
}
export type Drops = { day: string; done: number[]; claims: { slot: number; at: number }[] }

export type Crop = 'tobacco' | 'corn' | 'apples'

// What Jeb is doing with his hands while a tool runs, or while Claude streams:
// `think` (the model is thinking) and `draft` (it is writing its answer).
export type Pose =
  | 'none'
  | 'read'
  | 'edit'
  | 'write'
  | 'still'
  | 'web'
  | 'agent'
  | 'sweep'
  | 'mcp'
  | 'think'
  | 'draft'
  | 'hoe'

// What he does when no turn is running, rotating every dozen seconds.
export type IdleAct = 'banjo' | 'sip' | 'nap' | 'chase' | 'smoke'

// A delivery run in the F-150: `t` counts 500 ms ticks of the 16 the trip
// takes (8 out to the left edge, 8 back).
// `sputter` is the ticks the engine coughs before it goes (cold winter
// mornings); `dog` is Blue riding along in the bed.
// `load` is what rides in the bed on the way out: a box when there is nothing to
// sell, else the glyph of the main product (jars, bales, apples, corn).
export type Truck = {
  t: number
  load: 'box' | 'jar' | 'bale' | 'apple' | 'corn' | 'butter' | 'twist' | 'whiskey'
  sputter: number
  dog: boolean
}

// An ambient visit on the road: who comes by (a rig by its sprite, or Miss Opal
// on foot), `x` how far along its way it is (0 at the left edge, the kind's
// reach at the stop; the band maps that onto its own width), which way it faces
// and what it is doing.
export type VisitKind = 'store' | 'mill' | 'tripper' | 'opal' | 'mail' | 'tractor'
export type Visit = {
  kind: VisitKind
  x: number
  facing: 'in' | 'out'
  phase: 'arrive' | 'deal' | 'leave'
}

// A foreground hired hand standing in a plot, holding that crop; `id` is the
// agent it stands for (the transcript in view gets the marker).
export type Hand = { plot: Crop; id: string }

// Everything the canvas animates; written only when something visible changes.
export type Anim = {
  frame: number
  idleAct: IdleAct
  pose: Pose
  truck: Truck | null
  // A visitor on the road ('null' when none).
  visit: Visit | null
  // How many cells Blue has run left of home (0 when he is at Jeb's feet).
  dogRun: number
  isNight: boolean
  isDim: boolean
  // A line was said in the last few seconds: the pixel band shows his bubble.
  isTalking: boolean
  event: ActiveEvent | null
  // Short cosmetic effects: Blue wagging, Jeb's wink, the truck warming up,
  // the jar in his hand.
  wag: boolean
  wink: boolean
  puff: boolean
  sip: boolean
  // Agents: the hands in the plots (every running subagent, at most 2 drawn,
  // all three for a workflow), the `+N` that did not fit on a plot's label, and
  // how many teammates (0-2) stand at the sign.
  hands: Hand[]
  more: Partial<Record<Crop, number>>
  mates: number
  // Other live sessions: one lantern each over the sign.
  lanterns: number
  // A settings hook put up a gate (the 🚧 in Jeb's hands).
  isGated: boolean
  // The glyph in Jeb's hands while an MCP tool runs ('' when none).
  prop: string
  // The test run's weather over the plots, for a few seconds: rain falls on one
  // plot (or all), a dry spell tints its soil.
  weather: { kind: 'none' | 'rain' | 'dry'; plot: Crop | 'all' }
  // The building of the Compose service a command ran in, by the house ('' when none).
  building: string
  // The loose cows from triage: each a neighbor's number as its label ("#42"),
  // never a ticket key; at most three drawn, and how many more there are.
  cows: string[]
  moreCows: number
  // The quilt's clothesline: the newest stitched square flashes for a few seconds
  // after a stitch, and `live` is the color of this session's square so far.
  stitch: boolean
  live: SquareCode
  // Short bursts of the little things: a rainbow after a storm, puddles for a
  // while after rain, and how many ticks of a shooting star are left (0: none).
  rainbow: boolean
  wet: boolean
  star: number
}

// The session quilt: one square per session, by its dominant activity. B shipping
// (blue), R a rough day (red), G tests (green), P agents (purple), Y weeding
// (yellow), N field work (brown).
export type SquareCode = 'B' | 'R' | 'G' | 'P' | 'Y' | 'N'

// A stitched square and a journal line; dates are local 'YYYY-MM-DD'. At most 200
// squares and 60 lines are kept, a camp name at most 24 characters, a line 120.
export type Square = { c: SquareCode; d: string; camp: string }
export type JournalEntry = { d: string; camp: string; line: string }

// Who buys from Jeb. `town` is a legacy bucket: the dollars of a v4 farm that
// could not be told apart by buyer. Nothing new is ever sold to it.
export type CustomerId =
  | 'opal'
  | 'store'
  | 'tripper'
  | 'warehouse'
  | 'market'
  | 'mill'
  | 'fair'
  | 'town'

export type Product =
  | 'appleCinnamon'
  | 'whiteLightning'
  | 'tobacco'
  | 'apples'
  | 'corn'
  | 'appleButter'
  | 'twists'
  | 'agedWhiskey'

// What a returning truck can buy: bought, never found.
export type Purchase = 'sugar' | 'copper'

// Raw stock, found or bought; what is made from it (barrels, fence posts, copper
// coils); and what stands in the stack for sale.
export type Material = 'lumber' | 'stone' | 'straw' | 'iron' | 'sugar' | 'copper'
export type Component = 'barrel' | 'post' | 'coil'
// `aged` are the jars still in their barrels, each with the time (ms since the
// epoch) it is ready, at most 50; `whiskey` are the jars already collected.
export type Goods = {
  appleButter: number
  twists: number
  aged: { readyAt: number }[]
  whiskey: number
}

// The books, bounded: fixed key sets only. `month.key` is the local 'YYYY-MM'
// the amount was earned in ('' before the first sale); `fairYear` is the last
// year the county fair paid (0: never), which is what keeps it to once a year.
export type Ledger = {
  deliveries: number
  jarsSold: number
  total: number
  month: { key: string; amount: number }
  best: { amount: number; customer: CustomerId; product: Product } | null
  byCustomer: Record<CustomerId, number>
  byProduct: Record<Product, number>
  ribbons: number
  fairYear: number
  // `total` is lifetime earnings and only grows (the milestone upgrades read it);
  // `cash` is what is left of it after buying, `spent` and `byPurchase` what went.
  cash: number
  spent: number
  byPurchase: Record<Purchase, number>
}

// Kept across sessions in $.store. `crops` hold each plant's growth stage;
// `progress` is the part of the next stage already earned (milliseconds of
// work for tobacco, tokens for corn and apples).
export type Farm = {
  version: 10
  // Counts the writes of the farm to the store (the store has no compare-and-set,
  // so a save writes `rev + 1` and reads it back to see whether another session
  // wrote at the same moment).
  rev: number
  crops: Record<Crop, number[]>
  progress: Record<Crop, number>
  barn: { bales: number; corn: number; apples: number; sticks: number }
  still: { steps: number; hasBatch: boolean }
  shelf: { lightning: number; appleCinnamon: number }
  lifetime: {
    outputTokens: number
    inputTokens: number
    workMs: number
    // Bales ever harvested, and how many of them were traded for cinnamon sticks.
    bales: number
    balesTraded: number
  }
  ledger: Ledger
  // Homestead upgrades unlocked by lifetime dollars (ids, see UPGRADES).
  upgrades: string[]
  // Bead test of the last and best white lightning, 90-130 proof (0: none yet).
  lastProof: number
  bestProof: number
  // One-time toasts already shown.
  milestones: string[]
  // Materials, what is made from them, what stands for sale, the upgrades built
  // from them (ids, see BUILDS) and the keepsakes made (ids, see KEEPSAKES).
  materials: Record<Material, number>
  components: Record<Component, number>
  goods: Goods
  built: string[]
  keepsakes: string[]
  // Successful edits ever (every third one yields lumber) and Mothman sightings.
  counters: { edits: number; mothmanSeen: number }
  // The quilt and the journal, the sessions ever stitched (and how many shipped),
  // the busiest one and the ids of the last 64 stitched sessions, which keep a
  // session from being stitched twice.
  quilt: Square[]
  journal: JournalEntry[]
  sessionsWorked: number
  sessionsShipped: number
  busiest: { d: string; camp: string; score: number } | null
  stitched: string[]
  // The little things that have turned up (fixed ids, at most 64, in the order
  // they came) and the scheduling of the day they come on: see unlocks.ts.
  unlocks: string[]
  unlockDay: { d: string; n: number; done: number; next: number; since: string; coffee: string }
  // The last local day the mail was delivered ('' before the first): the mail comes once a day.
  mailDay: string
  // Creative drops: the slots done today and those claimed, the model calls made
  // today, the surprises kept (at most 30), the log of what the drops made (the
  // last 40), the arc, structures and custom art, and the news ids announced
  // (at most 20).
  drops: Drops
  modelCalls: { day: string; n: number }
  // The nonces (8 hex digits) of today's model calls, one per call, at most the daily cap:
  // each session reads its own back to know its write was not replaced by another's.
  modelTaken: string[]
  surprises: Surprise[]
  creativeLog: CreativeLogEntry[]
  creative: Creative
  newsSeen: string[]
  // The anonymizer's (see anonymize.ts): the farm's random salt (16 hex digits, ''
  // until the first save makes one) and the keyed tags of the camps given a place,
  // in the order they came (at most 64), which keep two camps from sharing one.
  anonSalt: string
  anonPlaces: string[]
  // Set only while a farm from before the anonymizer waits for its salt to settle
  // between sessions: its camps are still the real names (see anonymize.ts).
  anonPending?: true
}

// What the band draws of the creative drops: the decor on show (by day and
// hour, worked out at draw time), the permanent structures, the pictures they
// name and the day's festival tint.
export type FarmViewDrops = {
  decor: { day: string; sprites: DropSprite[]; window: DropWindow | null; lasts: DropLasts }[]
  structures: DropSprite[][]
  art: DropArt[]
  festival: { d: string; tint: string }
}

// The part of the farm the band draws, and nothing else: what the `view` atom
// holds, so a farm write that changes nothing on screen redraws nothing. The
// stock columns are worked out at draw time (aging jars come ready with the
// clock), so the raw stock stays (`aged` holds each jar's ready time). `quilt` is the last squares' letters.
export type FarmView = {
  crops: Farm['crops']
  lifetime: { bales: number }
  barn: { corn: number; apples: number }
  still: Farm['still']
  shelf: { appleCinnamon: number }
  ledger: { cash: number }
  upgrades: string[]
  built: string[]
  materials: Farm['materials']
  goods: Pick<Goods, 'appleButter' | 'twists' | 'whiskey'> & { aged: number[] }
  quilt: { c: SquareCode }[]
  // The little things: what has turned up, the woodpile's height (1 to 4), the
  // day the late-night coffee came and the day the farm began.
  unlocks: string[]
  pile: number
  coffee: string
  since: string
  drops: FarmViewDrops
}

// What one session has done so far, for its square and its journal line:
// bounded counters, reset at session start and on /clear. Numbers and the camp's
// place only (see anonymize.ts), never any content.
export type SessionRec = {
  ships: number
  testsPassed: number
  testsFailed: number
  lintRuns: number
  lintFailed: number
  edits: number
  agents: number
  sales: number
  harvests: number
  jars: number
  sours: number
  // Errors plus sours plus denies.
  rough: number
  calls: number
  turns: number
  // What Jeb built or made, "built the smokehouse", at most three.
  built: string[]
  camp: string
  startedAt: number
}

// What the `kept` atom holds so a plugin reload does not lose the session: its
// id and its record so far, in a compact form (`counts` are the SessionRec
// counters in a fixed order, see COUNTER_KEYS; the camp is not kept, it is read
// again). Restored at `session.start` only when the id matches.
export type KeptSession = { id: string; counts: number[]; built: string[]; startedAt: number }

// What each running session leaves in $.store under `sessions`, keyed by a keyed
// hash of the session's id (see anonymize.ts): its camp's place and when it last
// said so (ms since the epoch).
// Bounded to 8 entries, each no older than 3 minutes. `sq` (a square's letter and
// the session's score) and `ln` (its journal line, 120 characters at most) are
// what another session stitches if this one dies without saying goodbye.
export type Camp = { name: string; lastSeen: number; sq?: string; ln?: string }
export type Camps = Record<string, Camp>

declare module 'claude-code' {
  interface PluginState {
    jeb: {
      say: Say
      anim: Anim
      farm: Farm
      kept: KeptSession | null
    }
  }
}
