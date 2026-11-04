// What Jeb's banner looks like (Banner.swift puts it on screen): pure drawing, no window. The card is 180 x 50 grid units
// (u = 2 pt = one art pixel) with a 2u hard shadow, drawn as one Pix at art resolution (frame, bevel, tab) and scaled by a whole
// number with interpolation off, so every art pixel stays a square block; the text is CoreText over it at the backing scale.
// The sprite is its own layer (Banner.swift). bannerCheck (JEB_BANNER_CHECK=1) checks all of it by numbers, never by eye.
// The look follows the day: a holiday's tab colour and badge (the moon at night when there is none), the night panel, a red ring
// round the tab when an update failed, the area camp's colours on the bevel, and a frosty rime on it in winter.
// "More Space" scaled resolutions are resampled by macOS afterwards, which is out of our control.

import AppKit
import CoreText

/// The card's geometry in grid units (1u = 2 pt = one art pixel).
struct BannerLayout {
    static let u = 2, cardW = 180, cardH = 50, shadow = 2
    static let winW = cardW + shadow, winH = cardH + shadow
    /// Outline 1 + bevel 2 + inner line 1; the inner panel is 172 x 42.
    static let frame = 4, innerW = cardW - 2 * frame, innerH = cardH - 2 * frame
    static let spriteX = 3, textX = 28, crop = 30
    /// The text column in points: it starts at the inner panel's left + textX and is 280 wide.
    static let textLeft = (frame + textX) * u, textWidth: CGFloat = 280
    /// The "JEB" tab (3x5 font, 2u padding), in units from the card's top-left.
    static let tab = (x: frame + textX, y: frame + 2, w: 15, h: 9)
    static let subtitleLeft = (tab.x + tab.w + 3) * u
    /// The subtitle's width in points: to the text column's end, or 2u short of a badge whose left edge is at `badgeX` units.
    static func subtitleWidth(badgeX: Int? = nil) -> CGFloat { CGFloat(badgeX.map { ($0 - 2) * u } ?? textLeft + Int(textWidth)) - CGFloat(subtitleLeft) }
    /// The badges' boxes: a group right-aligned on the tab row, 2u in from the inner panel's edge, each centred on the tab and 2u
    /// apart, first to last from left to right; each at most 12 x 9.
    static let badgeMax = (w: 12, h: 9), badgeGap = 2
    static func badgeBoxes(_ sizes: [(w: Int, h: Int)]) -> [(x: Int, y: Int)] {
        var right = frame + innerW - 2, out: [(x: Int, y: Int)] = []
        for s in sizes.reversed() { out.insert((right - s.w, tab.y + (tab.h - s.h) / 2), at: 0); right -= s.w + badgeGap }
        return out
    }
    static func badgeBox(w: Int, h: Int) -> (x: Int, y: Int) { badgeBoxes([(w, h)])[0] }
    static let subtitleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    static let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let maxLines = 3, lineHeight = 15
    /// Baselines in points from the card's top, whole points.
    static var subtitleBaseline: Int { Int((Double(tab.y * u + tab.h) + Double(subtitleFont.capHeight) / 2).rounded()) }
    static var bodyBaseline: Int { (tab.y + tab.h) * u + 18 }
    /// Where the sprite layer sits in the window's (y-up) points: its feet on the inner panel's bottom edge.
    static func spriteRect(width: Int, rows: Int) -> CGRect {
        CGRect(x: (frame + spriteX) * u, y: (winH - frame - innerH) * u, width: width * u, height: rows * u)
    }
    /// The card's shape in units: a rectangle with its four corner pixels notched; the shadow is the same shape moved by `shadow`.
    static func inCard(_ x: Int, _ y: Int) -> Bool {
        guard (0..<cardW).contains(x), (0..<cardH).contains(y) else { return false }
        return !((x == 0 || x == cardW - 1) && (y == 0 || y == cardH - 1))
    }
    static func inShape(_ x: Int, _ y: Int) -> Bool { inCard(x, y) || inCard(x - shadow, y - shadow) }
}

/// What an area camp lends the banner (FarmScene.areaLook): only the camp's palette, weather and mood names.
struct AreaLook: Equatable { var palette: String, weather: String, mood: String }

/// What the day and the farm lend the banner, beyond the note: farm night, winter, and the area camp on the main screen.
struct BannerLook: Equatable {
    var night = false, winter = false
    var area: AreaLook?
    /// The night panel: macOS dark, or the farm's night. Never the reverse.
    func dark(_ system: Bool) -> Bool { system || night }
    /// Farm night (Banner shows the moon), Dec-Feb, and `area` (nil away from an area camp).
    static func now(area: AreaLook? = nil) -> BannerLook {
        let month = Calendar.current.component(.month, from: nowDate())
        return BannerLook(night: isNightHour(Int(hourNow())), winter: month == 12 || month <= 2, area: area)
    }
}

/// The banner's colours for one note and look. `ring` (clear for none) is the 1u ring round the tab; `rime` (clear for none) the
/// frost speckled on the top bevel.
struct BannerPalette {
    var panel: UInt32, body: UInt32, subtitle: UInt32, accent: UInt32, tabInk: UInt32
    var outline: UInt32, bevelLight: UInt32, bevelDark: UInt32, shadow: UInt32
    var ring: UInt32 = 0, rime: UInt32 = 0
}

/// The sprite drawn at (x, y) units from the card's top-left: a holiday's badge, or the moon at night.
struct BannerBadge: Equatable { var name: String, frame: Int, x: Int, y: Int, w: Int, h: Int }

struct BannerChrome {
    var image: CGImage
    /// The body lines as drawn (the last one ends in an ellipsis if cut).
    var lines: [String]
    /// The subtitle or the body had to be cut.
    var truncated: Bool
    var widths: [CGFloat]
    var badges: [BannerBadge]
    /// Where text sits, in points from the card's top-left (the subtitle first, then each body line).
    var bands: [CGRect]
}

struct BannerSprite {
    var frames: [CGImage], seconds: [Double], rows: Int
    /// The art frame each image is, for the check.
    var indices: [Int]
}

enum BannerArt {
    private static func rgb(_ hex: Int) -> UInt32 { word(hex >> 16 & 255, hex >> 8 & 255, hex & 255) }
    /// A named art colour, or a fixed fallback (Art.colour is clear for a name the art lacks).
    private static func named(_ art: Art, _ name: String, _ fallback: Int) -> UInt32 { let c = art.colour(name); return c == 0 ? rgb(fallback) : c }

    private static func luminance(_ c: UInt32) -> Double {
        func lin(_ v: UInt32) -> Double { let s = Double(v & 255) / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c) + 0.7152 * lin(c >> 8) + 0.0722 * lin(c >> 16)
    }
    /// WCAG contrast ratio.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The tab's colour: the active holiday's own (Art.holidays, the first active one), else by how the result reads.
    static func accent(_ note: Note, art: Art) -> UInt32 {
        switch art.holidays.first {
        case "halloween": return named(art, "foliage_orange", 0xd9731f)
        case "christmas": return named(art, "pine", 0x1f5c3a)
        case "stpatricks": return named(art, "green_dark", 0x2f7a3a)
        case "valentines", "easter": return named(art, "pink", 0xd96a9a)
        case "july4": return named(art, "denim_dark", 0x2a4a7a)
        case "thanksgiving": return named(art, "foliage_red", 0xa83a22)
        case "newyear": return named(art, "yellow", 0xe8c13a)
        default: break
        }
        switch note.tone {
        case .good: return named(art, "green_dark", 0x2f7a3a)
        case .bad: return named(art, "red_dark", 0xa02e22)
        case .plain: return named(art, "wood_dark", 0x6b4423)
        }
    }

    /// The card's colours. The bevel leans toward an area camp's palette and mood, the panel a tenth toward the palette (left
    /// plain if any text would then read worse); in winter or a snowy area the bevel cools toward the frost colour and gets a
    /// light rime. Increase Contrast keeps all of that plain. The tab gets a 1u ring: red when the update failed (at least 3:1
    /// against the panel), else the body colour when the tab alone would not stand out from the panel (under 3:1).
    static func palette(_ note: Note, art: Art, dark: Bool, contrast hard: Bool, look: BannerLook = BannerLook()) -> BannerPalette {
        let ink = named(art, "ink", 0x1a1410), cream = named(art, "banjo_head", 0xf5eedc)
        var panel = dark ? named(art, "ridge_far_night", 0x262e3c) : cream
        let body = dark ? cream : ink
        let soft = dark ? named(art, "hat_light", 0xd9c9a3) : named(art, "wood_dark", 0x6b4423)
        let accent = accent(note, art: art)
        func subtitle(on panel: UInt32) -> UInt32 { hard || contrast(soft, panel) < 4.5 ? body : soft }
        var light = named(art, "wood", 0xb07a3c), shade = named(art, "wood_dark", 0x6b4423), rime: UInt32 = 0
        if hard { light = body; shade = body }     // Increase Contrast: an ink (or cream, on dark) frame and the body colour for the subtitle
        else {
            if let area = look.area, let name = AreaTheme.paletteColour[area.palette], case let p = art.colour(name), p != 0 {
                light = mix(light, p, 0.4); shade = mix(shade, p, 0.3)
                if let (mood, amount) = AreaTheme.moodMix[area.mood] { light = mix(light, art.colour(mood), amount); shade = mix(shade, art.colour(mood), amount) }
                let tinted = mix(panel, p, 0.10)
                if contrast(body, tinted) >= 7, contrast(subtitle(on: tinted), tinted) >= 4.5 { panel = tinted }
            }
            if look.winter || look.area?.weather == "snowy", let name = AreaTheme.paletteColour["frost"], case let frost = art.colour(name), frost != 0 {
                light = mix(light, frost, 0.3); shade = mix(shade, frost, 0.25); rime = frost
            }
        }
        var ring: UInt32 = 0
        if note.tone == .bad {
            let reds = [named(art, "red_dark", 0xa02e22), named(art, "red", 0xdc3232), rgb(0xff6a5c)]
            ring = reds.first { contrast($0, panel) >= 3 } ?? reds[2]
        } else if contrast(accent, panel) < 3 { ring = body }
        return BannerPalette(panel: panel, body: body, subtitle: subtitle(on: panel), accent: accent,
                             tabInk: contrast(cream, accent) >= contrast(ink, accent) ? cream : ink, outline: ink,
                             bevelLight: light, bevelDark: shade, shadow: mix(ink, panel, 0.3), ring: ring, rime: rime)
    }

    /// Whether a sprite frame reads on `panel`: at least a third of its pixels at 3:1 or better.
    static func reads(_ name: String, frame: Int, art: Art, on panel: UInt32) -> Bool {
        guard let s = art.sprite(name), s.frames.indices.contains(frame) else { return false }
        let colours = s.frames[frame].filter { $0 != 0 }.map { art.paletteWord(Int($0)) }
        return !colours.isEmpty && colours.filter { contrast($0, panel) >= 3 }.count * 3 >= colours.count
    }

    /// The badges for the tab row: the first two active holidays' own sprites, else the moon (in its phase) at night. A sprite the
    /// art lacks, over 12 x 9, or that does not read on `panel` is left out. A second badge is dropped too when `subtitle` would
    /// no longer fit beside two.
    static func badges(art: Art, look: BannerLook, panel: UInt32, subtitle: String = "") -> [BannerBadge] {
        var wanted = art.holidays.prefix(2).map { ("badge-" + $0, 0) }
        if wanted.isEmpty, look.night { wanted = [("moon", moonPhase(nowDate()))] }
        var sprites: [(name: String, frame: Int, w: Int, h: Int)] = []
        for (name, frame) in wanted {
            guard art.has(name), let s = art.sprite(name), s.w <= BannerLayout.badgeMax.w, s.h <= BannerLayout.badgeMax.h, reads(name, frame: frame, art: art, on: panel) else { continue }
            sprites.append((name, frame, s.w, s.h))
        }
        while sprites.count > 1 {
            let at = BannerLayout.badgeBoxes(sprites.map { ($0.w, $0.h) })
            if !fit(subtitle, BannerLayout.subtitleFont, BannerLayout.subtitleWidth(badgeX: at[0].x)).cut { break }
            sprites.removeLast()
        }
        let at = BannerLayout.badgeBoxes(sprites.map { ($0.w, $0.h) })
        return zip(sprites, at).map { BannerBadge(name: $0.name, frame: $0.frame, x: $1.x, y: $1.y, w: $0.w, h: $0.h) }
    }

    /// The card, shadow and text as one image of 364 x 104 points at `backing` pixels a point (the sprite is separate).
    static func chrome(_ note: Note, art: Art, backing: Int, dark: Bool, contrast hard: Bool, look: BannerLook = BannerLook()) -> BannerChrome {
        typealias L = BannerLayout
        let pal = palette(note, art: art, dark: dark, contrast: hard, look: look)
        let badges = BannerArt.badges(art: art, look: look, panel: pal.panel, subtitle: note.subtitle)
        var p = Pix(w: L.winW, h: L.winH)
        for y in 0..<L.winH { for x in 0..<L.winW where L.inShape(x, y) { p.dot(x, y, pal.shadow) } }
        for y in 0..<L.cardH { for x in 0..<L.cardW where L.inCard(x, y) { p.dot(x, y, pal.outline) } }
        p.rect(1, 1, L.cardW - 2, L.cardH - 2, pal.bevelLight)
        p.rect(1, L.cardH - 3, L.cardW - 2, 2, pal.bevelDark)
        p.rect(L.cardW - 3, 1, 2, L.cardH - 2, pal.bevelDark)
        if pal.rime != 0 { for y in 1...2 { for x in 1..<(L.cardW - 3) where speckle(x, y + 500) < 22 { p.dot(x, y, pal.rime) } } }
        p.rect(3, 3, L.cardW - 6, L.cardH - 6, pal.outline)
        p.rect(L.frame, L.frame, L.innerW, L.innerH, pal.panel)
        if pal.ring != 0 { p.rect(L.tab.x - 1, L.tab.y - 1, L.tab.w + 2, L.tab.h + 2, pal.ring) }
        p.rect(L.tab.x, L.tab.y, L.tab.w, L.tab.h, pal.accent)
        art.text("JEB", into: &p, x: L.tab.x + 2, y: L.tab.y + 2, colour: pal.tabInk)
        for b in badges { art.blit(b.name, into: &p, x: b.x, y: b.y, frame: b.frame) }

        let k = L.u * backing, w = L.winW * k, h = L.winH * k
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(p.image(), in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(backing), y: CGFloat(backing))     // from here on, points (y up)
        let winH = CGFloat(L.winH * L.u)
        func draw(_ s: String, _ font: NSFont, _ colour: UInt32, x: Int, baseline: Int) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, NSAttributedString.Key(rawValue: kCTForegroundColorFromContextAttributeName as String): true]
            ctx.setFillColor(cgColor(colour))
            ctx.textPosition = CGPoint(x: CGFloat(x), y: winH - CGFloat(baseline))
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs)), ctx)
        }
        var truncated = false
        let subWidth = L.subtitleWidth(badgeX: badges.first?.x)
        let sub = fit(note.subtitle, L.subtitleFont, subWidth)
        truncated = sub.cut
        draw(sub.text, L.subtitleFont, pal.subtitle, x: L.subtitleLeft, baseline: L.subtitleBaseline)
        var bands = [CGRect(x: CGFloat(L.subtitleLeft), y: CGFloat(L.subtitleBaseline - 10), width: subWidth, height: 14)]
        var lines = wrap(note.body, L.bodyFont, L.textWidth)
        if lines.count > L.maxLines {
            var t = lines[(L.maxLines - 1)...].joined(separator: " ")
            while !t.isEmpty, ctWidth(t + "…", L.bodyFont) > L.textWidth { t.removeLast() }
            lines = Array(lines[..<(L.maxLines - 1)]) + [t.trimmingCharacters(in: .whitespaces) + "…"]
            truncated = true
        }
        for (i, line) in lines.enumerated() {
            let base = L.bodyBaseline + i * L.lineHeight
            draw(line, L.bodyFont, pal.body, x: L.textLeft, baseline: base)
            bands.append(CGRect(x: CGFloat(L.textLeft), y: CGFloat(base - 9), width: L.textWidth, height: 12))
        }
        return BannerChrome(image: ctx.makeImage()!, lines: lines, truncated: truncated, widths: lines.map { ctWidth($0, L.bodyFont) }, badges: badges, bands: bands)
    }

    /// The sprite's frames cropped to its top 30 rows (38 in a costume: headRows keeps the hat), and how long each shows:
    /// jeb-idle's eyes open 2.7 s then a 0.2 s blink (FarmScene.homeIdle), jeb-sip 1.2 s a frame, any other animation 0.5 s,
    /// a one-frame sprite none (static). The art's jeb-idle stands in for a sprite it lacks. `still` (Reduce Motion) keeps
    /// only the first frame, with no timings.
    static func sprite(_ name: String, art: Art, still: Bool = false) -> BannerSprite {
        let n = art.has(name) ? name : "jeb-idle"
        guard let s = art.sprite(n) else { return BannerSprite(frames: [], seconds: [], rows: 0, indices: []) }
        let rows = min(art.headRows(n, BannerLayout.crop), s.h), count = s.frames.count
        let indices: [Int], seconds: [Double]
        if count <= 1 || still { indices = [0]; seconds = [] }
        else if n == "jeb-idle" { indices = [0, min(3, count - 1)]; seconds = [2.7, 0.2] }
        else { indices = Array(0..<count); seconds = Array(repeating: n == "jeb-sip" ? 1.2 : 0.5, count: count) }
        return BannerSprite(frames: indices.compactMap { art.image(n, rows: rows, scale: 1, frame: $0) }, seconds: seconds, rows: rows, indices: indices)
    }

    private static func cgColor(_ c: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat(c & 255) / 255, green: CGFloat(c >> 8 & 255) / 255, blue: CGFloat(c >> 16 & 255) / 255, alpha: 1)
    }

    static func ctWidth(_ s: String, _ font: NSFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font])), nil, nil, nil))
    }

    /// `s` as it is, or cut with an ellipsis to fit `width`.
    private static func fit(_ s: String, _ font: NSFont, _ width: CGFloat) -> (text: String, cut: Bool) {
        guard ctWidth(s, font) > width else { return (s, false) }
        var t = s
        while !t.isEmpty, ctWidth(t + "…", font) > width { t.removeLast() }
        return (t.trimmingCharacters(in: .whitespaces) + "…", true)
    }

    /// Greedy word wrap that keeps explicit newlines.
    static func wrap(_ text: String, _ font: NSFont, _ width: CGFloat) -> [String] {
        var out: [String] = []
        for para in text.components(separatedBy: "\n") {
            let ns = para as NSString
            guard ns.length > 0 else { out.append(""); continue }
            let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: para, attributes: [.font: font]))
            var i = 0
            while i < ns.length {
                let n = CTTypesetterSuggestLineBreak(typesetter, i, Double(width))
                guard n > 0 else { break }
                out.append(ns.substring(with: NSRange(location: i, length: n)).trimmingCharacters(in: .whitespaces))
                i += n
            }
        }
        return out
    }
}

// MARK: - The check (JEB_BANNER_CHECK=1)

private func pixels(_ image: CGImage) -> [UInt32] {
    var buf = [UInt32](repeating: 0, count: image.width * image.height)
    buf.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return buf
}

/// Renders every sample banner at backing 1 and 2, light and dark, with and without Increase Contrast, and checks the numbers:
/// size; the shape (notched corners and shadow, opaque exactly inside); frame, tab and shadow blocks of one colour each; text
/// fits and leaves ink; WCAG contrast; the sprite's scale, pixels and timings; every line Jeb has fits one line. Then the theming:
/// every holiday, tone, panel, contrast setting, area palette, mood, weather and winter against the contrast floors, the tab ring
/// and the rime; the badges' geometry and their readability on both panels (the moon on the night one); Reduce Motion's one
/// frame; and a grid of renders checked pixel by pixel. Logs each failure and a total; returns the exit status. No image is
/// written or shown.
func bannerCheck(art: Art) -> Int32 {
    typealias L = BannerLayout
    var checks = 0, failed = 0
    func expect(_ ok: Bool, _ what: @autoclosure () -> String) { checks += 1; if !ok { failed += 1; log("banner check FAIL: \(what())") } }
    let h = Holiday.current(), baseLook = BannerLook.now()
    let samples = JebLines.samples(seed: "check", holidays: h, on: Date(), calendar: .current)
    let dates = Holiday.check()
    checks += dates.checks; failed += dates.failures.count
    for f in dates.failures { log("banner check FAIL: \(f)") }
    log("banner check: holiday dates \(dates.checks) checks, \(dates.failures.count) failed, at most \(dates.maxActive) at once 2026-2040")
    var shapeCount = 0
    for y in 0..<L.winH { for x in 0..<L.winW where L.inShape(x, y) { shapeCount += 1 } }
    for (kind, note) in samples {
        for backing in [1, 2] { for system in [false, true] { for hard in [false, true] {
            let dark = baseLook.dark(system)
            let tag = "\(kind) b\(backing) \(dark ? "dark" : "light")\(hard ? " contrast" : "")"
            let c = BannerArt.chrome(note, art: art, backing: backing, dark: dark, contrast: hard, look: baseLook), pal = BannerArt.palette(note, art: art, dark: dark, contrast: hard, look: baseLook)
            let k = L.u * backing, w = L.winW * k
            expect(c.image.width == 364 * backing && c.image.height == 104 * backing, "\(tag): image \(c.image.width)x\(c.image.height)")
            guard c.image.width == w, c.image.height == L.winH * k else { continue }
            let px = pixels(c.image)
            var opaque = 0, badAlpha = 0, mixed = 0, wrongColour = 0
            for uy in 0..<L.winH { for ux in 0..<L.winW {
                let first = px[uy * k * w + ux * k], inside = L.inShape(ux, uy)
                let ring = L.inCard(ux, uy) && !(ux >= L.frame && ux < L.cardW - L.frame && uy >= L.frame && uy < L.cardH - L.frame)
                let tab = ux >= L.tab.x && ux < L.tab.x + L.tab.w && uy >= L.tab.y && uy < L.tab.y + L.tab.h
                let single = !inside || ring || tab || !L.inCard(ux, uy)
                if first >> 24 != (inside ? 255 : 0) { badAlpha += 1 }
                for dy in 0..<k { for dx in 0..<k {
                    let v = px[(uy * k + dy) * w + ux * k + dx]
                    if v >> 24 == 255 { opaque += 1 }
                    if single, v != first { mixed += 1 }
                } }
                if !inside, first != 0 { wrongColour += 1 }
            } }
            expect(badAlpha == 0, "\(tag): \(badAlpha) blocks with the wrong alpha (notches, shadow)")
            expect(opaque == k * k * shapeCount, "\(tag): \(opaque) opaque px, expected \(k * k * shapeCount)")
            expect(mixed == 0, "\(tag): \(mixed) px break a frame, tab or shadow block")
            expect(wrongColour == 0, "\(tag): \(wrongColour) outside blocks not clear")
            expect(px[(L.tab.y + 1) * k * w + (L.tab.x + 1) * k] == pal.accent, "\(tag): tab colour")
            expect(px[(L.cardH + 1) * k * w + (L.cardW - 20) * k] == pal.shadow, "\(tag): shadow colour")
            expect(c.widths.allSatisfy { $0 <= L.textWidth }, "\(tag): a line wider than 280 pt \(c.widths)")
            expect(!c.truncated, "\(tag): truncated \(c.lines)")
            for (i, band) in c.bands.enumerated() {
                let x0 = Int(band.minX) * backing, x1 = Int(band.maxX) * backing, y0 = Int(band.minY) * backing, y1 = Int(band.maxY) * backing
                var ink = 0
                for y in y0..<y1 { for x in x0..<x1 where px[y * w + x] != pal.panel { ink += 1 } }
                expect(ink >= 4, "\(tag): text band \(i) has \(ink) ink px")
            }
            expect(BannerArt.contrast(pal.body, pal.panel) >= 7, "\(tag): body contrast \(BannerArt.contrast(pal.body, pal.panel))")
            expect(BannerArt.contrast(pal.subtitle, pal.panel) >= 4.5, "\(tag): subtitle contrast \(BannerArt.contrast(pal.subtitle, pal.panel))")
            expect(BannerArt.contrast(pal.tabInk, pal.accent) >= 4.5, "\(tag): tab contrast \(BannerArt.contrast(pal.tabInk, pal.accent))")
        } } }
    }
    for name in ["jeb-idle", "jeb-sip", "jeb-wave", "jeb-happy", "jeb-think"] + samples.map({ $0.note.sprite }) {
        let sp = BannerArt.sprite(name, art: art)
        guard let s = art.sprite(art.has(name) ? name : "jeb-idle"), let first = sp.frames.first else { expect(false, "sprite \(name): none"); continue }
        let rect = L.spriteRect(width: first.width, rows: sp.rows)
        expect(rect.width == CGFloat(L.u * s.w), "sprite \(name): width \(rect.width), art \(s.w) px")
        expect(sp.rows == min(art.headRows(art.has(name) ? name : "jeb-idle", L.crop), s.h) && sp.rows * L.u == Int(rect.height), "sprite \(name): rows \(sp.rows)")
        for backing in [1, 2] {
            let device = rect.width * CGFloat(backing) / CGFloat(first.width)
            expect(device == CGFloat(L.u * backing) && rect.minX * CGFloat(backing) == (rect.minX * CGFloat(backing)).rounded() && rect.minY * CGFloat(backing) == (rect.minY * CGFloat(backing)).rounded(),
                   "sprite \(name) b\(backing): scale \(device), origin \(rect.origin)")
        }
        for (frame, i) in zip(sp.frames, sp.indices) {
            let want = s.frames[i][0..<(s.w * sp.rows)].filter { $0 != 0 }.count
            let got = pixels(frame).filter { $0 >> 24 == 255 }.count
            expect(frame.width == s.w && frame.height == sp.rows && got == want, "sprite \(name) frame \(i): \(got) opaque px, art has \(want)")
        }
        let want: [Double] = s.frames.count <= 1 ? [] : (name == "jeb-idle" ? [2.7, 0.2] : Array(repeating: name == "jeb-sip" ? 1.2 : 0.5, count: s.frames.count))
        expect(sp.seconds == want, "sprite \(name): timings \(sp.seconds), expected \(want)")
        log("banner check: sprite \(name) frames \(sp.frames.count) timings \(sp.seconds) rows \(sp.rows) size \(first.width)x\(sp.rows)")
    }
    for line in JebLines.allLines {
        let width = BannerArt.ctWidth(line, L.bodyFont)
        expect(BannerArt.wrap(line, L.bodyFont, L.textWidth).count == 1 && width <= L.textWidth, "line over one row (\(width) pt): \(line)")
    }

    // The theming. The holidays are forced per case (Art.holidays is what the badges and the tab colour read); the real ones come back.
    let realHolidays = art.holidayNames
    defer { art.holidayNames = realHolidays; art.refreshHoliday() }
    func setHoliday(_ h: [String]) { art.holidayNames = { h }; art.refreshHoliday() }
    // every holiday alone, then overlaps: two at once, and three at once
    let holidaySets: [[String]] = [[]] + Holiday.names.map { [$0] } + [["christmas", "newyear"], ["halloween", "thanksgiving", "christmas"]]
    func plain(_ tone: Tone, subtitle: String = "Updated to 1.2.3") -> Note { Note(title: "T", subtitle: subtitle, body: "Done.", sprite: "jeb-idle", tone: tone) }
    func label(_ hs: [String]) -> String { hs.isEmpty ? "none" : hs.joined(separator: "+") }

    // Each holiday is complete: an emoji, a greeting and its name and a tab colour.
    for name in Holiday.names {
        expect(!(JebLines.emoji[name] ?? "").isEmpty, "holiday \(name): no emoji")
        expect(JebLines.greetingName[name] != nil, "holiday \(name): no greeting name")
        let g = JebLines.greeting(name, season: 2026)
        expect(g.subtitle != "Howdy" && g.body != "Howdy, neighbor.", "holiday \(name): no greeting lines")
        setHoliday([name])
        expect(BannerArt.accent(plain(.plain), art: art) != art.colour("wood_dark"), "holiday \(name): no tab colour")
        expect(art.has("badge-" + name), "holiday \(name): no badge")
    }
    let lightPanel = art.colour("banjo_head"), nightPanel = art.colour("ridge_far_night")
    var looks = [BannerLook(), BannerLook(winter: true), BannerLook(night: true), BannerLook(night: true, winter: true)]
    for palette in Area.palettes.sorted() { for mood in Area.moods.sorted() { for weather in ["clear", "snowy"] {
        looks.append(BannerLook(area: AreaLook(palette: palette, weather: weather, mood: mood)))
    } } }
    var matrix = 0
    for holiday in holidaySets {
        setHoliday(holiday)
        for tone in [Tone.good, .bad, .plain] { for system in [false, true] { for hard in [false, true] { for look in looks {
            matrix += 1
            let dark = look.dark(system), note = plain(tone), base = dark ? nightPanel : lightPanel
            let pal = BannerArt.palette(note, art: art, dark: dark, contrast: hard, look: look)
            let tag = "palette \(label(holiday)) \(tone) \(dark ? "dark" : "light")\(hard ? " contrast" : "") \(look)"
            expect(BannerArt.contrast(pal.body, pal.panel) >= 7, "\(tag): body contrast \(BannerArt.contrast(pal.body, pal.panel))")
            expect(BannerArt.contrast(pal.subtitle, pal.panel) >= 4.5, "\(tag): subtitle contrast \(BannerArt.contrast(pal.subtitle, pal.panel))")
            expect(BannerArt.contrast(pal.tabInk, pal.accent) >= 4.5, "\(tag): tab contrast \(BannerArt.contrast(pal.tabInk, pal.accent))")
            let pull = look.area.flatMap { AreaTheme.paletteColour[$0.palette] }.map(art.colour) ?? base
            expect(pal.panel == base || (!hard && pal.panel == mix(base, pull, 0.10)), "\(tag): panel is neither plain nor a tenth toward the palette")
            if hard { expect(pal.bevelLight == pal.body && pal.bevelDark == pal.body && pal.rime == 0, "\(tag): Increase Contrast keeps the frame plain") }
            else if look.area != nil { expect(pal.bevelLight != art.colour("wood"), "\(tag): the bevel is not tinted") }
            expect(pal.accent == BannerArt.accent(note, art: art), "\(tag): accent")
            if tone == .bad { expect(pal.ring != 0 && BannerArt.contrast(pal.ring, pal.panel) >= 3, "\(tag): failure ring \(BannerArt.contrast(pal.ring, pal.panel)) vs the panel") }
            else { expect(pal.ring == (BannerArt.contrast(pal.accent, pal.panel) < 3 ? pal.body : 0), "\(tag): ring") }
            expect((pal.rime != 0) == (!hard && (look.winter || look.area?.weather == "snowy")), "\(tag): rime \(pal.rime)")
            let badges = BannerArt.badges(art: art, look: look, panel: pal.panel, subtitle: note.subtitle)
            let want = holiday.isEmpty ? (look.night ? ["moon"] : []) : holiday.prefix(2).map { "badge-" + $0 }
            expect(badges.map { $0.name } == want, "\(tag): badges \(badges.map { $0.name }), expected \(want)")
            if want == ["moon"] { expect(dark, "\(tag): the moon on a light panel") }
        } } } }
    }
    log("banner check: palette matrix \(matrix) cases")

    // The badges: geometry on the tab row, and readable on both panels (the moon only on the night one, and there only the phase badge() picks).
    for name in Holiday.names.map({ "badge-" + $0 }) + ["moon"] {
        guard let s = art.sprite(name) else { expect(false, "badge \(name): none"); continue }
        let at = L.badgeBox(w: s.w, h: s.h), plainWidth = L.subtitleWidth(), narrow = L.subtitleWidth(badgeX: at.x)
        expect(s.w <= L.badgeMax.w && s.h <= L.badgeMax.h, "badge \(name): \(s.w)x\(s.h) over \(L.badgeMax)")
        expect(at.x + s.w == L.frame + L.innerW - 2 && at.y >= L.tab.y && at.y + s.h <= L.tab.y + L.tab.h && at.y == L.tab.y + (L.tab.h - s.h) / 2, "badge \(name): box \(at) not right-aligned and centred on the tab row")
        expect(at.x > L.tab.x + L.tab.w + 1 && narrow == CGFloat((at.x - 2) * L.u - L.subtitleLeft) && narrow < plainWidth && narrow >= 150, "badge \(name): subtitle width \(narrow) (was \(plainWidth))")
        for frame in 0..<art.frameCount(name) {
            if name != "moon" { expect(BannerArt.reads(name, frame: frame, art: art, on: lightPanel), "badge \(name): unreadable on the light panel") }
            // the moon is the shared sky art: badge() already drops a phase that is unreadable (the new moon), so only the holiday badges must always read
            if name != "moon" { expect(BannerArt.reads(name, frame: frame, art: art, on: nightPanel), "badge \(name) frame \(frame): unreadable on the night panel") }
        }
    }
    // Two badges: right-aligned as a group, 2u apart, in order, each centred on the tab; every subtitle fits beside the widest pair or the
    // second badge is dropped (and then it fits beside one).
    let badgeSizes = Holiday.names.compactMap { n in art.sprite("badge-" + n).map { (w: $0.w, h: $0.h) } }
    let widest = badgeSizes.sorted { $0.w > $1.w }.prefix(2).map { $0 }
    let boxes2 = L.badgeBoxes(widest)
    expect(boxes2.count == 2 && boxes2[1].x + widest[1].w == L.frame + L.innerW - 2 && boxes2[0].x + widest[0].w + L.badgeGap == boxes2[1].x, "two badges: boxes \(boxes2) not right-aligned with a \(L.badgeGap)u gap")
    for (i, s) in widest.enumerated() where boxes2.count == 2 { expect(boxes2[i].y == L.tab.y + (L.tab.h - s.h) / 2, "two badges: badge \(i) not centred on the tab row") }
    var subtitles = Set(samples.map { $0.note.subtitle }); for g in JebLines.greetingName.values { subtitles.insert(g) }
    subtitles.insert(JebLines.updatesOff(holiday: nil).subtitle)
    var dropped = 0
    for sub in subtitles.sorted() {
        let two = L.subtitleWidth(badgeX: boxes2.first?.x), one = L.subtitleWidth(badgeX: L.badgeBox(w: widest.first?.w ?? 0, h: 9).x)
        if BannerArt.ctWidth(sub, L.subtitleFont) > two { dropped += 1 }
        expect(BannerArt.ctWidth(sub, L.subtitleFont) <= one, "subtitle \(sub) does not fit beside one badge")
    }
    log("banner check: \(subtitles.count) subtitles, \(dropped) too wide beside the two widest badges (these show one badge)")
    expect(moonPhase(Date(timeIntervalSince1970: 947_182_440)) == 0 && moonPhase(Date(timeIntervalSince1970: 948_458_136)) == 4, "moonPhase: new moon 2000-01-06, full moon 14.8 days on")
    expect((0..<60).allSatisfy { (0..<8).contains(moonPhase(Date(timeIntervalSince1970: 1.7e9 + Double($0) * 86_400 * 0.5))) }, "moonPhase: out of 0-7")

    // Reduce Motion: one still frame and no keyframes (Banner adds a flipbook only for several frames with timings).
    for name in ["jeb-idle", "jeb-sip", "jeb-wave", "jeb-happy", "jeb-think"] + samples.map({ $0.note.sprite }) {
        let sp = BannerArt.sprite(name, art: art, still: true)
        expect(sp.frames.count == 1 && sp.seconds.isEmpty && sp.indices == [0], "still sprite \(name): \(sp.frames.count) frames, timings \(sp.seconds)")
    }

    // Rendered: each holiday, tone, panel, contrast setting and a few looks, at 2 px a point, checked unit by unit.
    let longest = subtitles.max { BannerArt.ctWidth($0, L.subtitleFont) < BannerArt.ctWidth($1, L.subtitleFont) } ?? ""
    let renderLooks = [BannerLook(), BannerLook(night: true, winter: true, area: AreaLook(palette: "amber", weather: "snowy", mood: "dusk")), BannerLook(area: AreaLook(palette: "frost", weather: "clear", mood: "noon"))]
    var rendered = 0
    for holiday in holidaySets {
        setHoliday(holiday)
        for tone in [Tone.good, .bad, .plain] { for system in [false, true] { for hard in [false, true] { for look in renderLooks {
            rendered += 1
            let dark = look.dark(system), note = plain(tone, subtitle: longest)
            let tag = "render \(label(holiday)) \(tone) \(dark ? "dark" : "light")\(hard ? " contrast" : "") \(look.night ? "night " : "")\(look.area?.palette ?? "")"
            let c = BannerArt.chrome(note, art: art, backing: 2, dark: dark, contrast: hard, look: look), pal = BannerArt.palette(note, art: art, dark: dark, contrast: hard, look: look)
            let k = L.u * 2, w = L.winW * k
            guard c.image.width == w, c.image.height == L.winH * k else { expect(false, "\(tag): image \(c.image.width)x\(c.image.height)"); continue }
            let px = pixels(c.image)
            func cell(_ ux: Int, _ uy: Int) -> UInt32? {
                let first = px[uy * k * w + ux * k]
                for dy in 0..<k { for dx in 0..<k where px[(uy * k + dy) * w + ux * k + dx] != first { return nil } }
                return first
            }
            expect(!c.truncated, "\(tag): truncated")
            expect(cell(L.frame, L.frame) == pal.panel && cell(1, 20) == pal.bevelLight && cell(40, L.cardH - 2) == pal.bevelDark, "\(tag): panel or bevel colour")
            expect(cell(L.tab.x, L.tab.y) == pal.accent, "\(tag): tab colour")
            // the ring: every unit of the 1u border round the tab is the ring colour, or the panel's when there is none
            var badRing = 0
            for uy in (L.tab.y - 1)...(L.tab.y + L.tab.h) { for ux in (L.tab.x - 1)...(L.tab.x + L.tab.w) {
                guard ux < L.tab.x || ux >= L.tab.x + L.tab.w || uy < L.tab.y || uy >= L.tab.y + L.tab.h else { continue }
                if cell(ux, uy) != (pal.ring != 0 ? pal.ring : pal.panel) { badRing += 1 }
            } }
            expect(badRing == 0, "\(tag): \(badRing) ring units wrong")
            // the rime: only on the top bevel's rows 1-2, sparse, and only when the palette has one
            var rime = 0, stray = 0
            for uy in 1..<(L.cardH - 1) { for ux in 1..<(L.cardW - 1) where cell(ux, uy) == pal.rime && pal.rime != 0 { if uy <= 2 { rime += 1 } else { stray += 1 } } }
            expect(pal.rime == 0 ? rime == 0 : rime > 0 && rime * 2 < 2 * (L.cardW - 4), "\(tag): \(rime) rime units")
            expect(pal.rime == 0 || stray == 0 || pal.rime == pal.panel || pal.rime == pal.accent, "\(tag): \(stray) rime-coloured units below the top bevel")
            // the badges: their pixels as drawn, a 2u gap before each, and nothing else on the tab row to the right of the subtitle
            let rows = L.tab.y..<(L.tab.y + L.tab.h)
            expect(c.badges == BannerArt.badges(art: art, look: look, panel: pal.panel, subtitle: note.subtitle), "\(tag): badges \(c.badges)")
            var wrong = 0, gap = 0, tabStray = 0
            for b in c.badges {
                guard let s = art.sprite(b.name) else { wrong += 1; continue }
                for sy in 0..<s.h { for sx in 0..<s.w {
                    let index = s.frames[b.frame][sy * s.w + sx]
                    if cell(b.x + sx, b.y + sy) != (index == 0 ? pal.panel : art.paletteWord(Int(index))) { wrong += 1 }
                } }
                for uy in rows { for ux in (b.x - L.badgeGap)..<b.x where !c.badges.contains(where: { ux >= $0.x && ux < $0.x + $0.w }) && cell(ux, uy) != pal.panel { gap += 1 } }
            }
            for uy in rows { for ux in ((L.textLeft + Int(L.textWidth)) / L.u)..<(L.frame + L.innerW) where !c.badges.contains(where: { ux >= $0.x && ux < $0.x + $0.w }) && cell(ux, uy) != pal.panel { tabStray += 1 } }
            expect(wrong == 0, "\(tag): \(wrong) badge units wrong")
            expect(gap == 0, "\(tag): \(gap) units in a badge's gap are not panel")
            expect(tabStray == 0, "\(tag): \(tabStray) units on the tab row where no badge is")
            expect(c.bands[0].maxX <= CGFloat((c.badges.first.map { $0.x - 2 } ?? (L.textLeft + Int(L.textWidth)) / L.u) * L.u), "\(tag): subtitle band \(c.bands[0]) runs under the badge")
        } } } }
    }
    log("banner check: \(rendered) rendered theme cases")
    log("banner check: \(samples.count) sample(s)\(h.isEmpty ? "" : " (holiday \(h.joined(separator: ", ")))"), \(JebLines.allLines.count) lines, \(checks) checks, \(failed) failed")
    return failed == 0 ? 0 : 1
}
