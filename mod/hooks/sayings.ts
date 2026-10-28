// Jeb's lines, grouped by what is going on. `bagPick` deals each group like a
// shuffled deck, so a line does not come back until the whole group has run.

export const SAYINGS = {
  morning: [
    "Mornin'. Still's warm if you need it.",
    "Rooster's been hollerin' since four. Let's get after it.",
    "Mornin'. Dew's still on the tobacco.",
    "Coffee's black and the day's young. Lord willin' and the creek don't rise.",
  ],
  afternoon: [
    "Afternoon. Sun's high and the corn's thirsty.",
    "Well, I'll be. Thought you'd forgot about the farm.",
    "Back again? Crop ain't gonna tend itself.",
    "Pull up a stump. Plenty of daylight left.",
  ],
  evening: [
    "Evenin'. Fireflies are out and the still's hummin'.",
    "Sun's gettin' low. Pour you a jar?",
    "Evenin'. Finest time of day on the porch.",
    "Howdy. Pull up a stump and rest your bones.",
  ],
  night: [
    "Moon's up. Even the hound's gone to sleep.",
    "Fire's banked low. Keep it quiet, now.",
    "Night shift, huh? Owls and us, then.",
    "Stars are thick as fleas on a hound tonight.",
    "Lamp's lit. I'm up if you are.",
    "Crickets are doin' the talkin' tonight.",
    "Slow and easy after dark. Mash don't care what time it is.",
    "Late hour for honest work, but I'll keep the porch light on.",
  ],
  working: [
    "Fixin' to get after it.",
    "Rollin' up my sleeves.",
    "Busier'n a one-legged man at a barn raisin'.",
    "That dog'll hunt. Let's go.",
    "Sleeves up. Here we go.",
    "Hotter'n a two-dollar pistol in here.",
    "Nose to the grindstone.",
    "Work's work. Let's get it done.",
  ],
  thinking: [
    "Studyin' on it...",
    "Chewin' on that a spell...",
    "Hm. Let me think on it...",
    "Scratchin' my chin over this...",
    "Figurin' it out...",
  ],
  writing: [
    "Puttin' it down on paper...",
    "Spinnin' a yarn...",
    "Writin' it out plain...",
    "Jottin' it down...",
    "Settin' it down proper...",
  ],
  read: [
    "Lookin' over the almanac...",
    "Readin' the signs...",
    "Lookin' over the crop...",
    "Thumbin' through the old almanac...",
    "Countin' rows and readin' tea leaves...",
  ],
  edit: [
    "Fixin' the porch rail...",
    "Hammerin' a loose board...",
    "Patchin' the barn roof...",
    "Hoein' a row...",
    "Drivin' nails, one at a time...",
  ],
  write: [
    "Plantin' a fresh row...",
    "Sowin' a new seed...",
    "Breakin' new ground...",
    "Turnin' over the back forty...",
    "Seed's in the dirt. Now we wait.",
  ],
  bash: [
    "Firin' up the still...",
    "Stokin' the fire...",
    "Watchin' the still...",
    "Mash is bubblin'. Don't rush it.",
    "Fire's roarin'. Mind the steam.",
  ],
  agent: [
    "Sendin' a hired hand out...",
    "Blue, go fetch the hands!",
    "Rounded up the whole holler...",
    "Hollerin' for help from the back forty...",
    "Sent Blue out to the fields. He'll be back.",
  ],
  web: [
    "Ridin' into town...",
    "Askin' around at the feed store...",
    "Tunin' the radio for news...",
    "Lettin' the radio crackle a bit...",
    "Listenin' for word from down the road...",
  ],
  idle: [
    "Lord willin' and the creek don't rise.",
    "Slicker'n snot on a doorknob out there today.",
    "Finer than frog hair, this weather.",
    "Well, I'll be. Quiet as a church mouse.",
    "Hotter'n a two-dollar pistol on the porch.",
    "Mash don't stir itself, but it'll wait.",
    "Never trust a man who don't like a good tomato.",
    "Tobacco likes a slow summer.",
    "A good hound and a good porch. What more do you need?",
    "Grandpappy said patience makes the best jar.",
    "That dog'll hunt, but only when he's a mind to.",
    "Smoke's curlin' straight up. Fair weather comin'.",
    "Heard a whippoorwill. Good sign.",
    "Apples smell like autumn in a jar.",
    "Cinnamon and apples. Heaven in a glass.",
    "If you're quiet, you can hear the corn grow.",
    "Rain's a-comin' by the ache in my knee.",
    "Never saw a crop that grew faster for bein' watched.",
    "Reckon the hogs got more sense than the whole county.",
    "Sit a spell. Work'll keep.",
    "Blue's got more energy than the whole holler.",
    "Moss don't grow on a rollin' stone, but neither does tobacco.",
    "Nothin' beats a porch and a banjo.",
    "Fixin' to whittle somethin'. Don't know what yet.",
    "Seems the creek's runnin' low. Keep the still shaded.",
    "Fences make good neighbors, and good moonshine makes better ones.",
    "Sweet and slow, that's the way I run the still.",
    "A man's only as good as his word and his jar.",
  ],
  done: [
    "That'll do. Pour you a jar?",
    "Done and dusted.",
    "Finer than frog hair.",
    "Back to the porch.",
    "Well, I'll be. That went smooth.",
    "Slicker'n snot on a doorknob.",
    "That dog'll hunt.",
    "All done. Time to rest my bones.",
    "Another row hoed.",
    "Lord willin', that'll hold.",
    "Job's done. Fire's still warm if you need it.",
    "Done and done. Sit a spell.",
    "That's a wrap. Pass the jar.",
    "Plumb done. Time for a sit.",
    "Done, and I swan it went right smart.",
    "Right tolerable work, that.",
  ],
  error: [
    "Well, that went sideways.",
    "Well, I'll be. That ain't right.",
    "Somethin's chewin' on the wires.",
    "Hornworms got into that one.",
    "That one bucked like a mule.",
    "Busted. Back to the drawin' board.",
    "Ain't that a kick in the britches.",
    "Hotter'n a two-dollar pistol, and not in a good way.",
    "Somethin' soured. Let's see what.",
    "That's a snag. We'll work it loose.",
    "Dagnabbit. Try it again, slower.",
    "That dog won't hunt. Try another way.",
    "Fit to be tied over that one.",
    "That went cattywampus.",
  ],
  denied: [
    "Got run off that one.",
    "Gate's locked. Can't go in there.",
    "Somebody said no. Reckon I'll mind.",
    "Fence says keep out. I'll keep out.",
    "Not my property. Turnin' around.",
  ],
  dry: [
    "Still's dry, need corn.",
    "No corn in the crib. Come back when she's ripe.",
    "Cold still. Needs a bushel of corn first.",
  ],
  sour: [
    "Batch went sour. Dumpin' the mash.",
    "Mash spoiled on us. Startin' over.",
    "Sour as a green persimmon. Dumpin' it.",
  ],
  lightning: [
    "White lightning, clear as creek water.",
    "Clear as glass and hotter'n a two-dollar pistol.",
    "Fresh white lightning. Don't light a match.",
  ],
  harvestTobacco: [
    "Harvest's in! Tobacco's hangin' in the barn.",
    "Tobacco's cut and hangin'. Smells like money.",
    "Well, I'll be. Fine leaf this year.",
    "Cured and hangin'. That's a good bale.",
  ],
  harvestCorn: [
    "Corn's in! Crib's fillin' up.",
    "Corn's cut. Still'll be happy.",
    "Golden ears all the way down the row.",
    "That corn's finer than frog hair.",
  ],
  harvestApples: [
    "Apples are picked! Cellar's fillin' up.",
    "Orchard's givin' this year. Basket's full.",
    "Red apples and a cool cellar. Fine combination.",
    "Picked every last one. Lord willin', they'll keep.",
  ],
  jar: [
    "Apple cinnamon bottled.",
    "Another jar for the shelf. Smells like Christmas.",
    "Apple cinnamon, bottled up and pretty as a picture.",
    "Jar's sealed. That dog'll hunt.",
  ],
  deliveryOut: [
    "Loadin' the truck. Be back directly.",
    "Takin' the F-150 to town. Hold down the fort.",
    "Got a delivery. Blue, mind the place!",
    "Truck's loaded. Off to town I go.",
    "Haulin' a load. Don't wait up.",
    "Gotta make a run to town. Back before supper.",
    "Cranked the old Ford. She's still got it.",
  ],
  deliveryBack: [
    "Back from town. Sold what I could.",
    "Truck's home. Money's in the jar.",
    "Delivered and back. Slicker'n snot.",
    "Town folks sure do like apple cinnamon.",
    "That's another load off. Cash in hand.",
    "Back in one piece. Truck ran fine.",
    "Back from town. Dog didn't burn the place down.",
  ],
  long: [
    "Longer'n a Sunday sermon, this one.",
    "Still at it. Busier'n a one-legged man in a kickin' contest.",
    "Takin' a while. Good things come to those who wait.",
    "Long haul. Sweat's pourin' off me.",
    "Slow and steady, like a mule up a hill.",
    "Hold on, partner, this one's a doozy.",
  ],
  blue: [
    "Blue, quit chasin' that rooster!",
    "Good dog, Blue.",
    "Blue's the best hand I ever hired.",
    "That dog'll hunt, and he'll nap while he's at it.",
    "Blue's dreamin' of squirrels again.",
    "Easy, Blue. That rooster's got spurs.",
    "Blue's keepin' watch. Mostly with his eyes closed.",
    "Never met a dog with more heart than Blue.",
  ],
  // Seasonal, one bag a month.
  jan: [
    "Slow as molasses in January out there.",
    "Colder than a well digger's shovel this mornin'.",
    "Stripping tobacco by the stove. Stories come easy by the fire.",
    "Airish today. Wear your coat to the barn.",
    "Seed catalogs are in the mailbox. Dreamin' season.",
  ],
  feb: [
    "Colder than a well digger's shovel, and not done yet.",
    "Whistle pig'll poke his head out soon enough.",
    "Last of the strippin'. Case weather's a fickle thing.",
    "Cabin fever's got me talkin' to the hound.",
    "Pert near time to think about the float beds.",
  ],
  mar: [
    "Sap's runnin'. Maple syrup time.",
    "Seedin' the float beds. Little green fuzz by and by.",
    "Mud up to the hubcaps. Spring's tryin' to make up its mind.",
    "Spring peepers are startin' up down at the branch.",
    "Right smart of rain this week. The ground's drinkin' it.",
  ],
  apr: [
    "Ramps are up. Smell'll clear a church.",
    "Redd up the yard. Company's comin' with the warm weather.",
    "Dogwood's blooming. Mind the dogwood winter.",
    "Clippin' seedlings. Tedious, but tolerable.",
    "A far piece to go before the corn's knee high.",
  ],
  may: [
    "Settin' plants. Back's sore but the field looks fine.",
    "Strawberry time. I'll be sticky till June.",
    "Blackberry winter's come and gone. Plantin' in earnest now.",
    "Jarflies are comin' up. Summer's on the way.",
    "Mornin' dew on the setters. Fine sight.",
  ],
  jun: [
    "Hoein' and watchin' for blue mold.",
    "Happy birthday, West Virginia, come the twentieth.",
    "Lightnin' bugs are out. Porch weather.",
    "Tolerable hot. Sweatin' like a jug of sweet tea.",
    "Corn's knee high, or near enough. Don't tell anybody I said so.",
  ],
  jul: [
    "Toppin' and suckerin'. Sticky work.",
    "Hotter'n the hinges of Hades, as Grandpappy put it.",
    "Cricket count says it's about seventy-five. Feels hotter.",
    "Sangin' season's still a ways off. Keep your eyes on the ridge.",
    "Katydids startin' up. Frost in six weeks, they say.",
  ],
  aug: [
    "Hornworms on the tobacco again. Pick 'em off.",
    "Countin' fogs. One for every snow come winter.",
    "Tobacco's gettin' tall. Barn needs to be ready.",
    "String bands at the fair. Hope I can find a seat.",
    "Dog days. Even Blue's moved to the shade.",
  ],
  sep: [
    "Cuttin' tobacco. Spear 'em on the sticks, hang 'em in the barn.",
    "Barn's fillin' up. Smells like money and sweet leaf.",
    "Apples are comin' on. Time to get the jars out.",
    "First chill in the mornin'. Sigogglin' cold, almost.",
    "Katydids say frost is a-comin'. I swan, they ain't wrong.",
  ],
  oct: [
    "Apple butter stir-off time. Stir it or it'll scorch.",
    "Leaves are turnin'. Whole holler's gone orange.",
    "Woolly worm's got a wide brown band this year. Mild winter, maybe.",
    "Tastes like October, this apple cinnamon.",
    "Curin' season. Barn doors open a crack, just so.",
  ],
  nov: [
    "Buck season. Wear your orange.",
    "Waitin' on case weather to take the tobacco down.",
    "Frost on the pumpkin and the fodder in the shock.",
    "Light bread and soup beans. That's a fine supper.",
    "Wood's stacked and the stove's hungry.",
  ],
  dec: [
    "Takin' it down and strippin'. Christmas money.",
    "Smoke from every chimney in the holler.",
    "Colder than a well digger's shovel, and Christmas comin'.",
    "Fixin' to make a jar for the neighbors. Tied a red ribbon on it.",
    "Snow'd be nice. Not too much, mind you.",
  ],
  idleMore: [
    "Madder than a wet hen about that mule, but he's yonder.",
    "Piddlin' around the yard. Nothin' wrong with that.",
    "A far piece to town, but a good day for it.",
    "Pass the light bread and a bottle of dope, and I'm happy.",
    "Everything's kindly crooked and cattywampus today.",
    "I'm on a jag of whittlin'. Don't ask what for.",
    "Fixin' to sang up the ridge soon. Sang's worth a pretty penny.",
    "Whistle pig's been at the garden again.",
    "That'll put hair on your chest, or a little off the top.",
    "Slow and easy. The mash don't care about your schedule.",
    "Pert near time for a nap. Blue agrees.",
    "Trying to catch up like a man tryin' to nail jelly to a tree.",
  ],
  // What Jeb says when a truck run sells: `{what}` is the goods, `{money}` the pay.
  saleOpal: [
    "Miss Opal flagged the truck for {what}. {money}.",
    "Miss Opal paid {money} for {what}.",
    "Sold Miss Opal {what}. {money}.",
  ],
  saleStore: [
    "Tolliver took {what}. {money}.",
    "{money} from Tolliver for {what}.",
    "Tolliver's counter paid {money} for {what}.",
    "Sold {what} at Tolliver's. {money}.",
  ],
  saleTripper: [
    "Tripper took {what}. {money}, no questions.",
    "{money} from a tripper for {what}.",
    "Tripper bought {what} off the tailgate. {money}.",
  ],
  saleWarehouse: [
    "Burley warehouse took {what}. {money}.",
    "{money} from the warehouse for {what}.",
    "Warehouse graded {what} fair. {money}.",
  ],
  saleMarket: [
    "Farmers market moved {what}. {money}.",
    "{money} at the market for {what}.",
    "Sold {what} off the tailgate. {money}.",
  ],
  saleMill: [
    "Feed mill took {what}. {money}.",
    "{money} from the mill for {what}.",
    "Mill weighed in {what}. {money}.",
  ],
  saleFair: [
    "Blue ribbon at the fair! 🎀 {money}.",
    "Best jar at the county fair. 🎀 {money}.",
    "The judges loved it. 🎀 {money}.",
  ],
} as const

export type SayingCategory = keyof typeof SAYINGS

const bags = new Map<string, string[]>()
const lastPick = new Map<string, string>()

const shuffled = (lines: readonly string[]) => {
  const deck = [...lines]
  for (let i = deck.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1))
    const a = deck[i] as string
    deck[i] = deck[j] as string
    deck[j] = a
  }

  return deck
}

// The next line of a category; the bag refills (shuffled, never opening with
// the line just said) only once every line has been dealt.
export const bagPick = (category: SayingCategory): string => {
  const lines: readonly string[] = SAYINGS[category]
  let bag = bags.get(category) ?? []

  if (bag.length === 0) {
    bag = shuffled(lines)
    const last = lastPick.get(category)
    if (bag.length > 1 && bag[bag.length - 1] === last) {
      const swap = bag[0] as string
      bag[0] = bag[bag.length - 1] as string
      bag[bag.length - 1] = swap
    }
  }

  const line = bag.pop() as string
  bags.set(category, bag)
  lastPick.set(category, line)

  return line
}

export const TOOL_SAYINGS: Record<string, SayingCategory> = {
  Bash: 'bash',
  Monitor: 'bash',
  Edit: 'edit',
  NotebookEdit: 'edit',
  Write: 'write',
  Read: 'read',
  Grep: 'read',
  Glob: 'read',
  LSP: 'read',
  WebFetch: 'web',
  WebSearch: 'web',
  Agent: 'agent',
  Workflow: 'agent',
}

export const MONTH_CATEGORIES: SayingCategory[] = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
]
