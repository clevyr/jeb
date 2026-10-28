// A small library of Appalachian and West Virginia lore for the storyteller to
// draw on: folk tradition, tall tales, history, crafts, food and the seasons.
// A few entries ride along with each drop's prompt as inspiration, never as a
// list to stay inside. The daily builder may add entries it researches.
// Rules for entries: short (at most 200 characters), printable ASCII, work
// appropriate, told as tradition or retelling rather than claims of fact, and
// no song lyrics or long quotations. The library holds at most LORE_MAX (120)
// entries, each one unique, and every entry must pass the drop word filter
// (isClean in surprise.ts), which rejects some words even in harmless senses.

export const LORE_MAX = 120
export const LORE_ENTRY_MAX = 200

export const LORE: readonly string[] = [
  'Folk say Mothman was seen near Point Pleasant in the 1960s; these days the town throws him a festival every September.',
  'The Flatwoods Monster tale comes from Braxton County in 1952, a story still told around porches with a grin.',
  'John Henry, the steel-driving man, raced a steam drill through a mountain tunnel; the legend ties him to the Big Bend Tunnel.',
  'The Golden Delicious apple traces back to a single tree found on a hillside farm in Clay County, West Virginia.',
  'An apple butter stir-off is a fall gathering: a big copper kettle, a long wooden paddle, and neighbours taking turns stirring for hours.',
  'Ramps are wild leeks dug in spring; ramp feeds bring whole communities together, and the smell lingers for days.',
  'The pepperoni roll started as a coal miner\'s lunch that needed no refrigeration and fit in a lunch pail.',
  'Woolly worm lore: count the brown and black bands on the caterpillar to guess how hard the coming winter will be.',
  'Split a persimmon seed in fall: a spoon shape means heavy snow, a fork a mild winter, a sharp blade a cold cutting wind.',
  'Blackberry winter is the cold snap that comes in May when the blackberries bloom; dogwood and redbud winters come before it.',
  'Old timers say count the fogs in August and you will know how many snows are coming that winter.',
  'Planting by the signs: crops that bear above ground go in while the moon is waxing, root crops while it wanes.',
  'Burley tobacco is cut in late summer, speared on sticks and hung to cure in tall, slatted barns until the damp weather of winter.',
  'Stripping tobacco happens by the woodstove in winter, sorting leaves by where they grew on the stalk.',
  'Clawhammer banjo is played by striking down on the strings with a fingernail and catching the short fifth string with the thumb.',
  'Old-time fiddle and banjo tunes are passed ear to ear at summer string-band gatherings, often jamming late into the night.',
  'Coonhounds like the bluetick bay with a long bawl on a fresh track and change their voice to a steady chop once the critter is treed.',
  'Quilts with names like Log Cabin and Double Wedding Ring were pieced from feed sacks and worn-out work shirts.',
  'Sorghum making in fall: cane crushed in a mill, often turned by a mule, and the juice boiled down in a long shallow pan.',
  'Bridge Day each October draws folks to the New River Gorge Bridge to watch parachutists float down into the gorge.',
  'West Virginia\'s state motto, Montani Semper Liberi, means mountaineers are always free.',
  'Soup beans and cornbread, cooked slow in cast iron, are a supper that has carried families through many a hard winter.',
  'Leather britches are green beans strung on thread and dried by the stove, then simmered all day come winter.',
  'Granny women were the healers and midwives of the hollers, trusted for their remedies and their good sense.',
  'A church homecoming means dinner on the grounds: long tables of casseroles, pies, and singing that lasts all afternoon.',
  'Whip-poor-wills call at dusk from late spring into summer, and old folks set their planting by when they first hear one.',
  'Spring peepers are tiny frogs whose chorus from the ponds is the first sure sign that spring is coming to the hills.',
  'Black bears raid apple trees in the fall, fattening up before they den for winter.',
  'The cardinal is West Virginia\'s state bird, a spot of red against the snow on a winter fence rail.',
  'A buckwheat festival in fall celebrates the golden buckwheat cakes that hill families have made for generations.',
  'County fairs bring 4-H livestock, blue-ribbon canning jars, quilt judging, and a tractor pull at the end of summer.',
  'Tall tale tradition: the storyteller swears every word is true, and the bigger the fish, the straighter the face.',
  'Jack tales are old Appalachian stories where clever young Jack outwits giants and kings with quick thinking.',
  'Folks say if a rooster crows at night, company is coming, and a dropped dishrag means someone hungry will visit.',
  'Mountain dulcimers, long and slender, are laid across the lap and strummed with a quill or a feather.',
  'A barn raising brought the whole community out for a day of work, with dinner and music when the frame went up.',
  'Old timers warn young folks to watch for copperheads on warm rocks by the woodpile in summer.',
  'Hollers are the narrow valleys between ridges, each with its own families, gossip and name.',
  'Jarflies is the old mountain word for cicadas, the summer singers that buzz through the hottest afternoons.',
  'A whistle pig is a groundhog, and a groundhog in the garden is a summer-long feud.',
  'Telling the bees is an old custom: when news comes to a house, folks go tell the hives, or the bees may up and leave.',
  'Ramps, the wild mountain leeks, come up in April. Towns hold ramp feeds, and folks call a mess of them a spring tonic.',
  'Skimming sorghum: the green foam that rises as the juice boils is ladled off, and the syrup is done when it drips off the paddle in a slow ribbon.',
  'Sang is ginseng. Diggers hunt it in the fall by its red berries, and plant the seeds back so the patch comes again.',
  'Feed sack quilts: flour and feed sacks came in printed cloth, and thrifty women saved them to piece into quilts for the cold months.',
  'Leather britches are green beans strung on thread and hung to dry in summer, then soaked and simmered with a bit of fatback in winter.',
]
