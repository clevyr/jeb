---
name: jeb-install
description: Set up Jeb (the Claude Code mod plus the macOS desktop app) from github.com/clevyr/jeb on a user's Mac: install, update, repair or remove it. Use when the user asks to install, update, repair or remove Jeb, or pastes the README's prompt.
---

# Set up Jeb

Set up Jeb from the clevyr/jeb release (install, update, repair or remove), doing every step yourself. Most users are not developers: never ask them to run a command. Keep progress updates to one short line per step, and explain a failure in simple words.

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, and never install Homebrew or any other tool.
- Never compile anything or use `--build-from-source`; if the install says it needs a build, report that instead.
- Never edit the shell profile or PATH, and never pass `--add-path`, `--repin` or `--no-agents`.
- Never work around a signature or hash refusal, and never set `JEB_RELEASE_*` variables.
- Never install Jeb another way (git clone, downloading zips, the by-hand steps in the docs).
- Never run `claude plugin ...` or `launchctl`, or edit `~/.claude/settings.json`, by hand; the install does those.
- Never edit the release's code to make something pass.
- Ask the user before `jebctl resume-updates`, `--purge` or `--purge-farm`.
- Always call jebctl as `~/.jeb/bin/jebctl` (this shell's PATH may not have it; the installer always creates that one). The one exception is a reinstall, which the doctor skill runs as `~/.jeb/current/desktop/bin/jebctl install`.
- Do not take screenshots of the desktop or describe what it draws.

## Install or update

If the README prompt brought you here, the installer already ran: do not run it again. Read its output and go to the list below.

Otherwise run this once, exactly as written:

`curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/install.sh | sh`

It works for a new Mac and for one that already has Jeb (it updates instead). If the download of install.sh itself fails, the command still exits 0, so always read the output:

- `Done. Start a new Claude Code session...`: go to Finish.
- `Jeb is installed: updating it`: go to Finish. If it also says `no verified release newer than`, tell the user the newest release was refused (the reason is in `~/Library/Application Support/Jeb/release.log`).
- `an old install is at <path>: run jebctl install --replace-clone`: run `~/.jeb/bin/jebctl install --replace-clone` (it moves the old clone aside itself; never move it by hand), then read that output the same way.
- `already exists; move it away first. Nothing was changed.`: tell the user an earlier replaced copy is in the way, and stop.
- `an update is running; try again in a few minutes`: wait a few minutes and run the curl line once more (this one retry is allowed even if the README prompt already ran it).
- `error: 404`, `HTTP 404` or `has no published release`: the release is missing; tell the user and stop.
- Any other `curl:` error, `Could not download jebctl`, `could not reach GitHub` or `could not fetch`: the Mac cannot reach GitHub; a network, VPN or proxy must allow github.com and release-assets.githubusercontent.com. Tell the user and stop.
- `refusing release`, `a gate failed; nothing installed`, or anything else: explain it in plain words and stop.

## Finish

Run `~/.jeb/bin/jebctl doctor --fix` and work through what its final report still lists with the doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`), ignoring "No farm data yet", "Start a new Claude Code session" and the PATH lines.

Then tell the user in one line what was set up (the desktop app, background agents that keep it running and updated, and the Claude Code plugin), and in one line to start a NEW Claude Code session so the plugin loads.

## Repair

Follow the doctor skill.

## Remove

`~/.jeb/bin/jebctl uninstall --remove-files`
