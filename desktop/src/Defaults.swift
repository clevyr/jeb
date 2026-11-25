// Which UserDefaults suite the app keeps its menu settings in. Pure, so a test compiles it alone
// (desktop/tests/run-defaults-test.sh).

import Foundation

/// The suite name for the settings, or nil for the standard domain. JEB_DEFAULTS_SUITE (non-empty) wins, so a
/// development build (dev/run) keeps its settings apart from the installed app's. Otherwise the app's own bundle
/// id uses the standard domain, which is the same one, and any other run (a bare binary) uses "com.jeb.desktop".
func defaultsSuite(bundleId: String?, env: [String: String]) -> String? {
    if let s = env["JEB_DEFAULTS_SUITE"], !s.isEmpty { return s }
    return bundleId == "com.jeb.desktop" ? nil : "com.jeb.desktop"
}
