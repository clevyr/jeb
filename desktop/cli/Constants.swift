// Constants: the module-level values of desktop/jebctl that several commands share and the constants probe prints.
// The LaunchAgent labels (ALL_LABELS/labels_for) are in Agents.swift and the perf targets (CPU_TARGETS/RSS_TARGET/
// FP_TARGET) in Status.swift; NOTE_GROUPS and app_name belong to the release tool once it leaves jebctl.
import Foundation

/// Conventional Commits types that make a release note, and their headings.
let noteGroups: [(String, String)] = [("breaking", "Breaking changes"), ("feat", "Features"), ("fix", "Fixes"), ("perf", "Performance"), ("revert", "Reverts")]

func appName(_ tag: String) -> String { "JebDesktop-\(tag)-macos.zip" }
