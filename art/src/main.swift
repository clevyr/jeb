// jebart: the art tool (the owner's side only; nothing here ships in a bundle).
//   jebart raster-check <raster-cases.json>   replay the Pillow raster fixture; exit 1 when a case differs
//   jebart diff-ts <a.ts> <b.ts> [--only <prefix>]...   compare PIXEL_SPRITES by name (size and frames); with no
//                                              --only also the palette, colour and font lines; exit 1 on a difference
//   jebart build <outdir> <pixel-art.ts>      write the runtime data (pixel-art.ts) from every sprite, and under <outdir>
//                                              sheets/, gifs/ and the scene mockups; prints the original Python's summary line and the
//                                              scene paths
//   jebart logo <pixel-art.ts> <outdir> [icon.png]   write <outdir>/logo.svg and logo.png from the runtime data, and with
//                                              icon.png the plugin icon (the original Python's arguments)
//   jebart check-frames <outdir> <expected.json>   decode every PNG and GIF under <outdir> with ImageIO and compare size,
//                                              format, frame count, delays, pixels and loop with the JSON (decoded-frames.imageio.json)
// art/build.sh builds it.
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data("""
        usage: jebart raster-check <raster-cases.json>
               jebart diff-ts <a.ts> <b.ts> [--only <prefix>]...
               jebart build <outdir> <pixel-art.ts>
               jebart logo <pixel-art.ts> <outdir> [icon.png]
               jebart check-frames <outdir> <expected.json>

        """.utf8))
    exit(2)
}

switch args.first {
case "raster-check":
    guard args.count == 2 else { usage() }
    exit(rasterCheck(args[1]))
case "diff-ts":
    guard let status = diffTsCommand(Array(args.dropFirst())) else { usage() }
    exit(status)
case "build":
    guard args.count == 3 else { usage() }
    do {
        for line in try buildAll(outDir: args[1], tsPath: args[2]) { print(line) }
    } catch {
        FileHandle.standardError.write(Data("jebart: \(error)\n".utf8))
        exit(1)
    }
case "logo":
    guard args.count == 3 || args.count == 4 else { usage() }
    do {
        try writeLogo(tsPath: args[1], outDir: args[2], iconPath: args.count == 4 ? args[3] : nil)
    } catch {
        FileHandle.standardError.write(Data("jebart: \(error)\n".utf8))
        exit(1)
    }
case "check-frames":
    guard args.count == 3 else { usage() }
    exit(checkFrames(outDir: args[1], expectedPath: args[2]))
default:
    usage()
}
