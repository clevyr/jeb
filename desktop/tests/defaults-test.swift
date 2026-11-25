// Checks defaultsSuite (desktop/src/Defaults.swift). Compiled with that file alone by run-defaults-test.sh.

import Foundation

var failures = 0
func check(_ name: String, _ got: String?, _ want: String?) {
    if got == want { print("ok    \(name)") } else { print("FAIL  \(name): got \(got ?? "nil"), want \(want ?? "nil")"); failures += 1 }
}

check("bundle id, no env: standard", defaultsSuite(bundleId: "com.jeb.desktop", env: [:]), nil)
check("no bundle id: com.jeb.desktop", defaultsSuite(bundleId: nil, env: [:]), "com.jeb.desktop")
check("other bundle id: com.jeb.desktop", defaultsSuite(bundleId: "x.y", env: [:]), "com.jeb.desktop")
check("env wins over a bare binary", defaultsSuite(bundleId: nil, env: ["JEB_DEFAULTS_SUITE": "com.jeb.desktop.dev"]), "com.jeb.desktop.dev")
check("env wins over the app's bundle id", defaultsSuite(bundleId: "com.jeb.desktop", env: ["JEB_DEFAULTS_SUITE": "com.jeb.desktop.dev"]), "com.jeb.desktop.dev")
check("empty env ignored (bundle id)", defaultsSuite(bundleId: "com.jeb.desktop", env: ["JEB_DEFAULTS_SUITE": ""]), nil)
check("empty env ignored (bare binary)", defaultsSuite(bundleId: nil, env: ["JEB_DEFAULTS_SUITE": ""]), "com.jeb.desktop")

exit(failures == 0 ? 0 : 1)
