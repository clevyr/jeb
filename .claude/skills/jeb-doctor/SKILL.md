---
name: jeb-doctor
description: Diagnose a Jeb install on this Mac (app, LaunchAgents, plugin registration, store, updates) and explain how to fix problems. Use when Jeb looks broken, is not showing up, or the user asks for a health check.
---

# Jeb doctor

1. Run `~/.jeb/bin/jebctl doctor --fix` (runs the installed Jeb's own doctor; an old git-clone install has none: replace it by running `~/.jeb/bin/jebctl install`, which moves the old clone aside itself). `--fix` runs the safe repair steps itself (install, start, quit then start, retry-update, update), each at most once and re-checking between them, then prints the full report; plain `doctor` without `--fix` is read-only. Checks are grouped (Install, Desktop app, Background agents, Claude Code, Updates); each line starts with `ok`, `FIX`, `skip` or `note`. It ends with `All good.`, or the problem count and a numbered "To fix them, in order" list, each step once. What the final report still lists was not fixed automatically. Work down it.
2. Handle what is left, and tell the user in one plain line each what was wrong and what you did. The steps `--fix` already ran need no repeat; if one failed, read the log named below and say why:
   - `~/.jeb/bin/jebctl install` (current is not a valid bundle): downloads the release again;
   - `~/.jeb/current/desktop/bin/jebctl install` (missing app, LaunchAgents, plugin or install record, or a signing key that is not pinned): reinstalls the app, background agents and plugin;
   - `~/.jeb/bin/jebctl quit`, then `~/.jeb/bin/jebctl start` (more than one Jeb running);
   - `~/.jeb/bin/jebctl start` (Jeb is not running, has stopped responding, or was quit from the menu);
   - `~/.jeb/bin/jebctl resume-updates` (updates are paused; `--fix` never runs it because someone paused them on purpose, so ask the user first);
   - `~/.jeb/bin/jebctl retry-update` (the last update was rejected or rolled back; read `update.log` first and say why);
   - `~/.jeb/bin/jebctl update` (the plugin version differs from the mod, or more than one version is on disk; it also removes the older folders). Updates that look stuck, or the user asks to update: follow the jeb-update skill (`~/.jeb/current/.claude/skills/jeb-update/SKILL.md`);
   - the PATH step (jebctl not on PATH, or another jebctl first): it only affects typing plain `jebctl` in a terminal, so leave it unless the user wants that. If they do, ask once and, on yes, run `~/.jeb/bin/jebctl add-path`;
   - "Start a new Claude Code session": tell the user; the farm data fills in once a session has run;
   - the network step (GitHub releases): nothing to sign in to; a VPN, proxy or firewall must allow github.com and release-assets.githubusercontent.com. Explain it.
   Anything else: explain it in plain words and do not change it without the user's approval.
3. If more detail is needed, read `~/Library/Application Support/Jeb/update.log`, `release.log` and `watchdog.log`. Older installs may still be at `~/.claude/jeb-desktop` until the next install or update moves them; the doctor prints a note when the older folder is still in use. Point to logs by path only.
4. Never read or quote `~/Library/Application Support/Jeb/run.log` (or `~/.claude/jeb-desktop/run.log`) beyond lines containing "no usable art", "exited", "ROLLBACK" or "REJECTED".

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, never install Homebrew, never compile (`--build-from-source`), never edit a shell profile or PATH yourself, and never pass `--repin` or `--no-agents`. PATH setup happens only through `~/.jeb/bin/jebctl add-path`, and only after you have asked the user once and they said yes (it sets up their login shell and any of zsh, bash, fish and nushell they use, backing up each file first); on no or no answer, skip it and do not ask again. A release install needs no Xcode, Command Line Tools or git; if a check mentions them, it is a developer install.
- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- After a fix, run the doctor again and report the result.
