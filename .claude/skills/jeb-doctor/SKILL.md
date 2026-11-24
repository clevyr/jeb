---
name: jeb-doctor
description: Diagnose a Jeb install on this Mac (app, LaunchAgents, plugin registration, store, updates) and explain how to fix problems. Use when Jeb looks broken, is not showing up, or the user asks for a health check.
---

# Jeb doctor

1. Run `~/.local/bin/jebctl doctor`, or `~/.jeb/bin/jebctl doctor` if that link is missing (both run the installed Jeb's own doctor; an old git-clone install has none: replace it with `~/.jeb/bin/jebctl install --replace-clone`). It is read-only. Each line is `ok` or `FIX <what>: <fix>`, and it ends with `all good` or `N problem(s)`.
2. Apply these fixes yourself, without asking the user to run anything, and tell them in one plain line each what was wrong and what you did:
   - `~/.local/bin/jebctl start` (the desktop was quit from the menu, or is not running);
   - `~/.local/bin/jebctl resume-updates` (updates are paused; someone paused them on purpose, so ask first);
   - `~/.local/bin/jebctl reload-agents` (the LaunchAgent plists are stale after an update);
   - updates look stuck, or the user asks to update: follow the jeb-update skill (`~/.jeb/current/.claude/skills/jeb-update/SKILL.md`);
   - repair: run the install again, `~/.jeb/current/install` with no flags (on an install older than v1.7.0, which bundles Python, run `~/.jeb/current/python/bin/python3 -I ~/.jeb/current/install` instead) (missing app, LaunchAgents or plugin registration: `jeb@jeb` not installed in `claude plugin list`, or an old Jeb entry still in `CLAUDE_CODE_PLUGIN_DIRS`, which also loads Jeb twice). If `~/.jeb/current` itself is broken, run `~/.jeb/bin/jebctl install` (or follow the jeb-install steps) to download the newest release again;
   - `FIX GitHub releases reachable`: nothing to sign in to; check the network (a VPN, proxy or firewall must allow github.com and release-assets.githubusercontent.com) and explain it.
   Anything else: explain it in plain words and do not change it without the user's approval.
3. If more detail is needed, read `~/Library/Application Support/Jeb/update.log`, `release.log` and `watchdog.log`. Older installs may still be at `~/.claude/jeb-desktop` until the next install or update moves them; the doctor's "state folder" line says which is in use. Point to logs by path only.
4. Never read or quote `~/Library/Application Support/Jeb/run.log` (or `~/.claude/jeb-desktop/run.log`) beyond lines containing "no usable art", "exited", "ROLLBACK" or "REJECTED".

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, never install Homebrew, never edit the shell profile or PATH, never use `--add-path`, and never compile (`--build-from-source`). A release install needs no Xcode, Command Line Tools or git; if a check mentions them, it is a developer install.
- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- After a fix, run the doctor again and report the result.
