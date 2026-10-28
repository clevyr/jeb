// awake: exit 0 while the main display is awake and the session unlocked.
import CoreGraphics
let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
exit(CGDisplayIsAsleep(CGMainDisplayID()) == 0 && !locked ? 0 : 1)
