---
name: jeb-update
description: Update Jeb on this Mac to the newest release and report the result. Use when the user asks to update Jeb or when updates look stuck.
---

# Update Jeb

1. Run `~/.jeb/bin/jebctl update`. It checks for a release now, waits for the result (up to 30 minutes) and prints one line per phase, then `updated to vX`, `vX is current` or the reason it failed. It exits 0 for updated or current.
2. An old git-clone install (from before v1.3.0, a clone in `~/.jeb/repo` or `~/jeb`) has no bundle: run `~/.jeb/bin/jebctl install`, which installs the newest release and then moves the clone aside to `<clone>.old` and removes its entries. If `~/.jeb/current` still does not exist afterwards, follow the jeb-doctor skill.
3. Report the result in one plain line, for example "Jeb is now v1.4.0" or "Jeb was already current".
4. If it fails (a non-zero exit, "updates are paused", "the release agent is not loaded", or a download problem), follow the jeb-doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`), then run the update once more.

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, never install Homebrew, never compile (`--build-from-source`), never edit a shell profile or PATH yourself, and never pass `--repin` or `--no-agents`. PATH setup happens only through `~/.jeb/bin/jebctl add-path`, and only after you have asked the user once and they said yes (it sets up their login shell and any of zsh, bash, fish and nushell they use, backing up each file first); on no or no answer, skip it and do not ask again. A release install needs no Xcode, Command Line Tools or git.
- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- Do not pause, resume, roll back or change anything beyond the update; if updates are paused, ask the user before resuming them.
