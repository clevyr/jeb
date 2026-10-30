---
name: jeb-update
description: Update Jeb on this Mac to the newest release and report the result. Use when the user asks to update Jeb or when updates look stuck.
---

# Update Jeb

1. Run `~/.local/bin/jebctl update`. It checks for a release now, waits for the result (up to 30 minutes) and prints one line per phase, then `updated to vX`, `vX is current` or the reason it failed. It exits 0 for updated or current. If that link is missing, run `~/.jeb/bin/jebctl update`.
2. An old git-clone install (from before v1.3.0, a clone in `~/.jeb/repo` or `~/jeb`) has no bundle yet: `~/.jeb/bin/jebctl install` converts it (it runs `/usr/bin/python3 -I <clone>/desktop/jebctl follow` itself, at most twice); without that binary, run the follow command yourself. A v1.2.0 clone may need two runs; the second one converts it to the bundle layout. Run it at most twice; if `~/.jeb/current` still does not exist, follow the jeb-doctor skill.
3. Report the result in one plain line, for example "Jeb is now v1.4.0" or "Jeb was already current".
4. If it fails (a non-zero exit, "updates are paused", "the release agent is not loaded", or a download or GitHub sign-in problem), follow the jeb-doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`), then run the update once more.

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, never install Homebrew, never edit the shell profile or PATH, never use `--add-path`, and never compile (`--build-from-source`). A release install needs no Xcode, Command Line Tools or git.
- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- Do not pause, resume, roll back or change anything beyond the update; if updates are paused, ask the user before resuming them.
