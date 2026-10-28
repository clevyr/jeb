import CoreGraphics
import Foundation
let all = CommandLine.arguments.count > 1
let opts: CGWindowListOption = all ? [.optionAll] : [.optionOnScreenOnly]
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as! [[String: Any]]
for w in list {
  let layer = w[kCGWindowLayer as String] as! Int
  if layer > 0 && !all { continue }
  if layer > 0 { continue }
  let b = w[kCGWindowBounds as String] as! [String: Any]
  print(w[kCGWindowNumber as String]!, layer, w[kCGWindowOwnerName as String] ?? "", w[kCGWindowName as String] ?? "-", w[kCGWindowIsOnscreen as String] ?? "nil", w[kCGWindowAlpha as String]!, b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, w[kCGWindowOwnerPID as String]!)
}
print("levels desktop", CGWindowLevelForKey(.desktopWindow), "desktopIcon", CGWindowLevelForKey(.desktopIconWindow), "backstop", CGWindowLevelForKey(.backstopMenu), "normal", CGWindowLevelForKey(.normalWindow), "min", CGWindowLevelForKey(.minimumWindow))
