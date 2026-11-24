// What the original Python and its write_ts produced for the inputs the tests feed the Swift port: palette indices,
// run-length pairs, base64 frames, outlined pixels and a small pixel-art.ts. Captured once from the Python (Pillow
// 11.3) before it is deleted; pixels are rrggbbaa hex, row-major, and index or byte lists are plain hex.
import Foundation

let quantizeSize = (16, 20)
let quantizeIn = [
    "2b1a0effdeac4effb07d2afff0cd78ff7a3b1dfff1c27dffd69e62ffe68c6eff8b6a4aff684e34ff6e281cffffffffffc0392bff",
    "8c241cff3f6fb5ff2c4f86ff4a2e1affcde8f0ff6b8fa0ffe39b3affbe6e1effcdd2d7ff828791ff232326ff3668a8ff224678ff",
    "5faf50ff3c7832ff82be46ffc49646fff0c83cffdc3232ff961e1eff785032ff583822ffc8aa64ff6ea046ff968264ff78644bff",
    "a06e3cff734b28ff783c32ff552823ff969696ff69696effc46e3cff8c4623fffa9628ffffe15affc8c8cdffa0a0a8ff3c465aff",
    "fad76eff6e7d96ff3c465fffc48c50ff1e1e23ff5096e6ffd7dee8fffaf5c8fff5f0d2fff096aaff965abefff0d23cff5a5a5fff",
    "5f412dfff0eee6ff28282dff825aa0ffc8c8cdff1e2028fff5eedcff966432ff4a5c68ff262e3cff345236ff1c2a20ff244028ff",
    "c8702cffa03426ffd4a838ffe8eaf0ffa8b0b8ffd6a070ffa8704aff70482eff2a201aff66462affd6b668ff3e7048ff285032ff",
    "8e9298ff3c8c8cff5696cdffa0d2f0ff4278d7ffb07a4affe2c496ff78583effe1cdaaff7a6248ff644f39ff8a7053ff928c84ff",
    "52367aff342668ff7a4c90ffb276c6ff78449cff2e180fc8e1aa4fc8b37b2bc8f3cb79c87d391ec8f4c07ec8d99c63c8e98a6fc8",
    "8e684bc86b4c35c871261dc8fffdffc8c3372cc88f221dc8426db6c82f4d87c84d2c1bc8d0e6f1c86e8da1c8e6993bc8c16c1fc8",
    "d0d0d8c8858592c8262127c83966a9c8254479c862ad51c83f7633c885bc47c8c79447c8f3c63dc8df3033c8991c1fc87b4e33c8",
    "5b3623c8cba865c8719e47c8998065c87b624cc8a36c3dc8764929c87b3a33c8582624c8999497c86c676fc8c76c3dc88f4424c8",
    "fd9429c8ffdf5bc8cbc6cec8a39ea9c83f445bc8fdd56fc8717b97c83f4460c8c78a51c8211c24c85394e7c8dadce9c8fdf3c9c8",
    "f8eed3c8f394abc89958bfc8f3d03dc85d5860c8623f2ec8f3ece7c82b262ec88558a1c8cbc6cec8211e29c8f8ecddc8996233c8",
    "4d5a69c8292c3dc8375037c81f2821c8273e29c8cb6e2dc8a33227c8d7a639c8ebe8f1c8abaeb9c8d99e71c8ab6e4bc873462fc8",
    "2d1e1bc869442bc8d9b469c8416e49c82b4e33c8919099c83f8a8dc85994cec8a3d0f1c84576d8c8b3784bc8e5c297c87b563fc8",
    "e4cbabc87d6049c8674d3ac88d6e54c8958a85c855347bc8372469c87d4a91c8b574c7c87b429dc816271c00961c6201cfad777f",
    "33c4af80b2366981991bc6ffe827bc00002ed40162c0e67fde98a2807e3fab810120b3ffa7fab900b8586901f5884a7fea3f2080",
    "c8d8c4813cdf50ff70575b002eefae01c70eac7f3d714b80d4c063810253b3ff6a0fd50051110e01c597a57f5a51418032106381",
    "ca840cffa76f2700ea8b2c016605397fbd4e7a809e9eab8125650aff09a2fc00feb34c018d36b67f40052d80de5a108120b636ff",
    "190b8b002f4daa016a62987f781cab80a6b33081a5e255fff0ae79001a69e0015780677f1828c18076f15781dae1c9ff1287b500",
    "ba424301bea1967f4c871980799c5e818016efff4df05a00c3204601f052657f1d46998066d38681543082ff9dfe8f000737d401",
    "0ffdbf7fd2fbc28062b46081700cf6ff0ae46900d384b901e4481c7f4caa1180dcbaa781a990dcff874dc60051b5f901c8735e7f",
    "69a360806e192381f19144ffd4c53300e70136017fbdb77f61624480c2228781b6ad15ff5c10c600950b0e0117bf817f2b6d6f80",
    "69a55381413176ff808080ff000000ffffffffff000000000000000000000000",
].joined()
let quantizeWant = [
    "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f3031323334",
    "35363738393a3b3c3d3e3f404142434445324748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768",
    "696a6b6c6d0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f",
    "303132333435363738393a3b3c3d3e3f404142434445324748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60616263",
    "6465666768696a6b6c6d0000005e0d3f0000003e6d1a00000020321b0000005a5919000000666a1500000055335b00000057151c",
    "0000006d1d1d000000101d160000001c253f000000101b690000003d1b3f0000001c646c0000001b0b14000000666b510000004a",
    "1b6917010c000000",
].joined()
let rleCases: [(String, String)] = [
    ("", ""),
    ("05", "0105"),
    ("0*255", "ff00"),
    ("0*256", "ff000100"),
    ("7*600x1*2x2*1", "ff07ff075a0702010102"),
    ("01020102010201020102", "0101010201010102010101020101010201010102"),
    ("3*510x4*1", "ff03ff030104"),
]
let encodeFrame1 = [
    "2b1a0effdeac4effb07d2aff000000000000000000000000d69e62ffe68c6eff8b6a4aff000000000000000000000000c0392bff",
    "8c241cff3f6fb5ff0000000000000000000000006b8fa0ffe39b3affbe6e1eff000000000000000000000000",
].joined()
let encodeFrame2 = [
    "2b1a0efff1c27dff6e281cff000000000000000000000000f0c83cffc8aa64ff734b28ff000000000000000000000000f5f0d2ff",
    "5f412dff1e2028ff000000000000000000000000285032ff4278d7ff7a6248ff000000000000000000000000",
].joined()
let encodeWant = (6, 4, ["AQEBAgEDAwABBwEIAQkDAAENAQ4BDwMAARMBFAEVAwA=", "AQEBBgELAwABHwEkASkDAAE9AUIBRwMAAVsBYAFlAwA="])
let outlineIn = [
    "01020340000000000000000000000000000000000000000000000000c80a0affc80a0a8100000000000000000000000000000000",
    "00000000000000000000000000000000000000000000000000000000050505800000000000000000000000000000000000000000",
    "000000000000000000000000090909ff",
].joined()
let outlineWant = [
    "010203402b1a0eff2b1a0eff0000000000000000000000002b1a0effc80a0affc80a0a812b1a0eff000000000000000000000000",
    "2b1a0eff2b1a0eff00000000000000000000000000000000000000000505058000000000000000002b1a0eff0000000000000000",
    "00000000000000002b1a0eff090909ff",
].joined()
let outlineColour = "band"
let outlineWantColour = [
    "010203407a3b1dff7a3b1dff0000000000000000000000007a3b1dffc80a0affc80a0a817a3b1dff000000000000000000000000",
    "7a3b1dff7a3b1dff00000000000000000000000000000000000000000505058000000000000000007a3b1dff0000000000000000",
    "00000000000000007a3b1dff090909ff",
].joined()
let tsWantSize = 3719
let tsWant = [
    "// Generated by art/src/build.py: do not edit by hand.",
    "// One shared palette (index 0 is transparent) and every sprite as",
    "// run-length frames: base64 of (run, paletteIndex) byte pairs, row-major.",
    "",
    "export const PIXEL_PALETTE: readonly number[] = [0, 2824718, 14593102, 11566378, 15781240, 8010525, 15843965, 14065250, 15109230, 9136714, 6835764, 7219228, 16777215, 12597547, 9184284, 4157365, 2903942, 4861466, 13494512, 7049120, 14916410, 12480030, 13488855, 8554385, 2302758, 3565736, 2246264, 6270800, 3962930, 8568390, 12883526, 15779900, 14430770, 9838110, 7884850, 5781538, 13150820, 7249990, 9863780, 7889995, 10513980, 7555880, 7879730, 5580835, 9868950, 6908270, 12873276, 9192995, 16422440, 16769370, 13158605, 10526888, 3950170, 16439150, 7241110, 3950175, 12880976, 1973795, 5281510, 14147304, 16446920, 16117970, 15767210, 9853630, 15782460, 5921375, 6242605, 15789798, 2631725, 8542880, 13158605, 1974312, 16117468, 9856050, 4873320, 2502204, 3428918, 1845792, 2375720, 13135916, 10499110, 13936696, 15264496, 11055288, 14065776, 11038794, 7358510, 2760730, 6702634, 14071400, 4091976, 2641970, 9343640, 3968140, 5674701, 10539760, 4356311, 11565642, 14861462, 7886910, 14798250, 8020552, 6573881, 9072723, 9604228, 5387898, 3417704, 8014992, 11695814, 7881884]",
    "",
    "// Palette indices by colour name, for anything the mod draws itself.",
    "export const PIXEL_COLOUR: Readonly<Record<string, number>> = {\"clear\": 0, \"ink\": 1, \"hat\": 2, \"hat_dark\": 3, \"hat_light\": 4, \"band\": 5, \"skin\": 6, \"skin_dark\": 7, \"cheek\": 8, \"beard\": 9, \"beard_dark\": 10, \"mouth\": 11, \"white\": 12, \"shirt\": 13, \"shirt_dark\": 14, \"denim\": 15, \"denim_dark\": 16, \"boot\": 17, \"glass\": 18, \"glass_edge\": 19, \"amber\": 20, \"amber_dark\": 21, \"chrome\": 22, \"steel\": 23, \"tire\": 24, \"truck\": 25, \"truck_dark\": 26, \"green\": 27, \"green_dark\": 28, \"leaf\": 29, \"leaf_dry\": 30, \"corn\": 31, \"red\": 32, \"red_dark\": 33, \"soil\": 34, \"soil_dark\": 35, \"soil_dry\": 36, \"grass\": 37, \"road\": 38, \"road_dark\": 39, \"wood\": 40, \"wood_dark\": 41, \"roof\": 42, \"roof_dark\": 43, \"stone\": 44, \"stone_dark\": 45, \"copper\": 46, \"copper_dark\": 47, \"fire\": 48, \"fire_hot\": 49, \"smoke\": 50, \"smoke_dark\": 51, \"window\": 52, \"window_lit\": 53, \"blue_coat\": 54, \"blue_spot\": 55, \"tan\": 56, \"nose\": 57, \"drop\": 58, \"cloud\": 59, \"night_star\": 60, \"moon\": 61, \"pink\": 62, \"purple\": 63, \"yellow\": 64, \"grey\": 65, \"fur\": 66, \"cow_white\": 67, \"cow_black\": 68, \"dress\": 69, \"hair_grey\": 70, \"black_car\": 71, \"banjo_head\": 72, \"banjo_rim\": 73, \"ridge_far\": 74, \"ridge_far_night\": 75, \"ridge_mid\": 76, \"ridge_mid_night\": 77, \"pine\": 78, \"foliage_orange\": 79, \"foliage_red\": 80, \"foliage_gold\": 81, \"snowcap\": 82, \"fog\": 83, \"skin_tan\": 84, \"skin_brown\": 85, \"skin_deep\": 86, \"hair_dark\": 87, \"hair_brown\": 88, \"hair_blond\": 89, \"flannel_green\": 90, \"flannel_green_dark\": 91, \"tee_grey\": 92, \"tee_teal\": 93, \"water\": 94, \"water_light\": 95, \"bluebird\": 96, \"deer_tan\": 97, \"deer_light\": 98, \"owl_brown\": 99, \"owl_cream\": 100, \"dirt\": 101, \"dirt_dark\": 102, \"dirt_light\": 103, \"pebble\": 104, \"witch_robe\": 105, \"witch_robe_dark\": 106, \"witch_robe_light\": 107, \"witch_sleeve\": 108, \"witch_sleeve_dark\": 109}",
    "",
    "// 3x5 font: 15 bits per glyph, row-major, \"1\" = ink.",
    "export const PIXEL_FONT: Readonly<Record<string, string>> = {\"A\": \"010101111101101\", \"\\u00e9\": \"101\", \"\\\"\": \"000\"}",
    "",
    "export type PixelSprite = { w: number; h: number; frames: readonly string[] }",
    "",
    "export const PIXEL_SPRITES: Readonly<Record<string, PixelSprite>> = {",
    "  'walk': { w: 6, h: 4, frames: ['AQEBBgELAwABHwEkASkDAAE9AUIBRwMAAVsBYAFlAwA=', 'AQEBAgEDAwABBwEIAQkDAAENAQ4BDwMAARMBFAEVAwA=', 'AQEBAgEDAwABBwEIAQkDAAENAQ4BDwMAARMBFAEVAwA='] },",
    "  'idle': { w: 6, h: 4, frames: ['AQEBBgELAwABHwEkASkDAAE9AUIBRwMAAVsBYAFlAwA='] },",
    "}",
    "",
]
