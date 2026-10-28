<p align="center">
  <img src="docs/logo.svg" alt="Jeb" width="400">
</p>

Jeb is a little farm that lives on your Mac's desktop and keeps track of your Claude Code sessions. A Claude Code plugin watches what your sessions get up to, and a desktop app draws it.

It's internal to Clevyr. The repo is private and proprietary (see [LICENSE](LICENSE)), so please don't share it outside the company.

![farm-day](docs/screenshots/farm-day.png)

## What's in the repo

- `mod/` is the Claude Code plugin. Its hooks watch your sessions and write anonymized state to the plugin store.
- `desktop/` is the macOS app (Swift), plus the Python scripts that install, update and look after it.
- `creative/` is a scheduled builder that can extend the plugin. It's switched off, `./install` doesn't touch it, and nothing in here starts it.

## Installing

Jeb installs from a release. The easy way is to let Claude do it. Paste this into Claude Code from any folder:

    Install Jeb for me. Clone the latest release of github.com/clevyr/jeb into ~/jeb (or use it if it is
    already there), then follow the jeb-install skill in that clone's .claude/skills/jeb-install/SKILL.md:
    check the requirements, run ./install with no flags, run desktop/jebctl doctor, and explain anything
    that fails.

It checks you have everything, downloads the release, runs the install and a health check, and tells you in plain words if something needs fixing. Once it's done, start a new Claude Code session so the plugin loads.

### What you need

- macOS, logged in to a desktop session.
- Xcode Command Line Tools (`xcode-select --install`). The app is built from source on your machine, so there's no signing or notarization to deal with.
- `/usr/bin/python3` (comes with the Command Line Tools) and `git`.
- Claude Code (`claude` on your PATH), signed in with your own account.
- The GitHub CLI (`brew install gh`), signed in with access to this repo. Run `gh auth login`, then `gh auth setup-git` so git uses it too. Updates fetch in the background, so git has to reach the repo without asking for anything.

### Doing it by hand

    tag=$(gh release view --repo clevyr/jeb --json tagName --jq .tagName)
    git clone --branch "$tag" https://github.com/clevyr/jeb.git ~/jeb
    cd ~/jeb
    ./install
    desktop/jebctl doctor

That clones the latest release (git will mention a "detached HEAD", which is expected). It has to be a git clone rather than a downloaded zip, because that's how Jeb updates itself. You can put it anywhere; the install remembers where. `./install --dry-run` shows every step without changing anything.

The install:

1. Checks the requirements and stops with a message if anything's missing.
2. Pins the release signers and moves the clone to the newest signed release (see [Updates](#updates)). It needs a clean clone for this.
3. Builds the app, runs a quick set of checks (compile, smoke test, headless start), then installs the LaunchAgents and starts it. If a check fails, the clone goes back to where it was and nothing gets installed.
4. Adds the clone's `mod/` folder to `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`. It backs that file up to `~/.claude/backups/jeb/` first and leaves your other entries alone. Running it twice is harmless.

The farm will look pretty empty until you've run a session with the plugin loaded.

![farm-built](docs/screenshots/farm-built.png)

## Using it

There's not much to do. Jeb starts at login, a watchdog brings it back if it stops, and only one copy ever runs.

It adds an item to the menu bar with:

- A status line showing whether it's running and at what frame rate, or why it's paused.
- **Pause / Resume** to stop and start drawing.
- **Frame rate**: Adaptive (the default, which slows down when nothing's moving), 60 fps or 30 fps.
- **Reload art** to pick up new plugin art without restarting.
- **Save Screenshot**, which saves a PNG per screen to `~/Pictures/Jeb/` and shows it in Finder. It only saves what Jeb draws, never your other windows, so it doesn't need Screen Recording permission.
- **Restart** to start a fresh copy that takes over from the old one.
- **Quit Jeb Desktop**, which stops it until you next log in or run `desktop/jebctl start`.

![jeb-banjo](docs/screenshots/jeb-banjo.png)

### Commands

From the clone:

    desktop/jebctl status            # app, heartbeat, mode, last update, LaunchAgents
    desktop/jebctl doctor            # health check, one ok/FIX line per check
    desktop/jebctl start             # start it again after Quit
    desktop/jebctl quit              # same as Quit in the menu
    desktop/jebctl pause-updates     # stop following releases
    desktop/jebctl resume-updates
    desktop/jebctl rollback          # go back to the previous version
    desktop/jebctl screenshot        # same as Save Screenshot, prints the paths

`desktop/jebctl screenshot --fixture <name> [--out <dir>] [--hour <h>]` renders one of the test scenes to `<dir>/<name>.png` without touching the running app. `--list` shows the scene names. That's how the screenshots in this README were made (scaled up 3x with `desktop/src/tools/up <in> <out> 3`).

![jeb-idle](docs/art/jeb-idle.gif) ![jeb-hoe](docs/art/jeb-hoe.gif) ![jeb-sip](docs/art/jeb-sip.gif) ![jeb-banjo](docs/art/jeb-banjo.gif) ![blue-run](docs/art/blue-run.gif) ![cow](docs/art/cow.gif) ![hen](docs/art/hen.gif) ![owl](docs/art/owl.gif) ![fire](docs/art/fire.gif)

## Troubleshooting

Run `desktop/jebctl doctor` first. Every `FIX` line tells you what to do.

**Nothing on the desktop and no menu bar item.** It was quit, or it isn't running. Run `desktop/jebctl start`. If the LaunchAgents are gone, run `./install` again.

**A menu bar item that says "Waiting for art".** The app can't find the plugin's art (`mod/hooks/pixel-art.ts`), usually because the clone moved or was deleted. It checks every 30 seconds and carries on once the file is back. If you moved the clone, run `./install` from the new spot.

**The desktop is empty.** Start a new Claude Code session. The plugin only loads in sessions started after the install, and `doctor` will tell you whether it's registered and has written any state yet.

**Updates stopped.** `desktop/jebctl status` shows the last release check and any failed tags. Updates skip a clone with local changes or one that's on a branch, so commit or stash your changes, or run `./install` again. If the fetch is failing, check `gh auth status` and run `gh auth setup-git`. `doctor` also tells you if updates are paused.

**An update failed.** The previous version keeps running and the failed release isn't retried. `update.log` and `release.log` say why.

All the logs live in `~/.claude/jeb-desktop/`: `update.log` for builds and checks, `release.log` for release checks and `watchdog.log` for restarts.

![rain](docs/screenshots/rain.png)

## Updates

Jeb uses [Semantic Versioning](https://semver.org): releases are tags like `v1.4.2`, and installs follow the highest one. Pre-release tags (`v1.5.0-rc.1`) are never picked up. A LaunchAgent (`com.jeb.desktop.release`) checks at login and every 6 hours:

1. It runs `git fetch --tags origin` with your own credentials.
2. It looks at each newer tag, newest first. A tag has to be signed by a pinned signer and point at a commit on the default branch. One that fails is logged and skipped, so a bad tag can't block the real ones.
3. The first good tag is exported (`git archive <sha>`) into `~/.claude/jeb-desktop/staging/<tag>/`, refusing anything that isn't a plain file or folder or that would land outside it. The new build then goes through the full checks: compile, smoke, parity, a scripted day and a headless start.
4. If everything passes, the clone moves to that commit (open sessions reload the plugin) and the new app replaces the old one. If the new app crashes or stops reporting in the next few minutes, the old one comes back and that tag is never tried again.

Updates leave the clone alone if it has local changes or is on a branch. `jebctl status` shows the install mode, the current release, the last check and any failed tags, and `jebctl follow --dry-run` shows what the next check would do.

### Signed releases

Releases are signed tags, and installs only trust signers pinned on that machine, so a tag pushed by anyone else is ignored.

- `desktop/release-signers` lists the allowed signers (`ssh-keygen` allowed_signers format, namespace `git`).
- The install copies it to `~/.claude/jeb-desktop/release-signers` (mode 0600) if there isn't one already. Later tags and pulls can't replace it, so trust is fixed at install time.
- To rotate keys, update `desktop/release-signers` in a release, then run `./install --repin` on each machine.
- With no signer pinned, installs don't update at all. `status` and `doctor` show whether one is pinned.

![farm-night](docs/screenshots/farm-night.png)

## Uninstalling

    cd ~/jeb
    ./uninstall

This removes the LaunchAgents and the app, and takes this clone's `mod/` back out of `CLAUDE_CODE_PLUGIN_DIRS` (backing up your settings first). It keeps `~/.claude/jeb-desktop` unless you pass `--purge`, and keeps the plugin's state file unless you pass `--purge-farm`, which backs it up before removing it. The clone itself stays put. `--dry-run` shows what it would do.

## Contributing

### Setting up

You need everything from [What you need](#what-you-need). Then work from a clone of `main` rather than a release, and install in dev mode:

    git clone https://github.com/clevyr/jeb.git ~/jeb-dev
    cd ~/jeb-dev
    ./install --dev

Dev mode runs straight from your working tree and doesn't follow releases. The update agent watches `desktop/src` and, once your edits have been quiet for a minute, builds them, runs the full checks and swaps the new app in if they pass. Run `desktop/jebctl pause-updates` while you're in the middle of something and `resume-updates` when you want it shipped. A build that fails a check isn't tried again; if the failure was a fluke, `desktop/jebctl retry-update` runs every check on it once more and ships it if they all pass. If you already have a release install, run `./uninstall` in that clone first so there's only one.

Make your changes on a branch and open a pull request against `main`.

### The desktop app

    cd desktop/src
    JEB_OUT=JebDesktop.dev ./build.sh

Don't launch `JebDesktop.dev` directly: a new copy takes over from the running app. Look at your changes through the tools instead. `desktop/jebctl screenshot --fixture <name>` renders a test scene with your build (set `JEB_BIN=desktop/src/JebDesktop.dev`), and the checks below run it offscreen.

To run every check the updater runs (compile, smoke, parity, a scripted day, headless start) on a snapshot of your source without installing anything:

    python3 -I desktop/updater.py --gates-only --force

That takes about 8 minutes. To run one piece with your dev build, from `desktop/src`: `JEB_BIN=JebDesktop.dev python3 -I tools/day.py kinds` (or `day`, `limit`, `evening`, `again`, `night`, `all`). The parity check compares each fixture against `fixtures/band-out.txt`, which is the reference output: don't regenerate it.

### The plugin

    claude plugin validate mod
    claude plugin test mod

A few rules the plugin has to keep, and the tests check most of them:

- Hooks only observe. No network, no processes, no file writes and no notifications. `$.model` (the daily Haiku calls) is only used in `hooks/signals.ts`.
- Nothing identifying leaves a session. See [Cost and privacy](#cost-and-privacy).
- A quiet tick makes no `$` calls at all.
- `tests/guard`, `tests/perf`, `tests/lore` and `tests/drops` are locked. Don't edit them; add new tests in a new file instead.

The plugin reloads in sessions started after a change.

### Art

The sprites come from `mod/art/src/build.py`, which needs Pillow (`python3 -m pip install --user Pillow`):

    python3 mod/art/src/build.py mod/art/out mod/hooks/pixel-art.ts

That rewrites `mod/hooks/pixel-art.ts` and writes previews to `mod/art/out/` (not tracked). Rebuild the logo with `python3 mod/art/src/logo.py mod/hooks/pixel-art.ts docs`.

### Commit messages and versions

Write commit subjects as [Conventional Commits](https://www.conventionalcommits.org), because the release reads them to pick the next version and write the release notes:

- `fix: ...` for a bug fix (patch release). `perf:` and `revert:` count the same.
- `feat: ...` for something new (minor release).
- `feat!: ...` (any type with `!`), or a `BREAKING CHANGE: ...` line in the body, for a change that breaks existing installs (major release).
- `docs:`, `test:`, `refactor:`, `chore:` and the rest don't trigger a release on their own.

A scope is fine too, like `fix(desktop): ...` or `feat(mod): ...`. Leave `"version"` in `mod/.claude-plugin/plugin.json` alone; the release sets it.

![ridges-home](docs/screenshots/ridges-home.png)

## Releasing

Releases are cut locally by the owner; there's no CI. Releases are signed tags, so once, from the clone:

    ./release setup

If this clone has no signing key yet, it makes one at `~/.ssh/jeb_signing` (it asks you for a passphrase) and points this clone's git at it. Then it writes `desktop/release-signers` from your git email and that key. Commit and push that file before the first release. Back the key up somewhere safe, like a password manager: if it's lost, every install has to run `./install --repin` to trust a new one. Git asks for the passphrase once each time you release.

To get a "Verified" badge on the tags on GitHub, also add `~/.ssh/jeb_signing.pub` to your account as a *Signing Key* (Settings, then SSH and GPG keys). Installs don't need it.

From a clean checkout of `main`, one command cuts a release and puts it on GitHub:

    ./release

It works out the version the way release-please does, from the [commit messages](#commit-messages-and-versions) since the last release: any breaking change makes it a major release, otherwise any `feat` makes it minor, otherwise any `fix`, `perf` or `revert` makes it a patch. If there's nothing releasable it says so and stops. The release notes are built from the same commits, grouped into breaking changes, features and fixes. The very first release uses the version already in `mod/.claude-plugin/plugin.json`.

Add `--dry-run` to see the version and notes it would use without changing anything. To force a level, pass it: `./release patch`, `./release minor` or `./release major`.

It validates and tests the plugin, does a dev build and runs the parity checks. Only if all of that passes does it write the new version to `plugin.json` (the one place the version lives), commit it as `chore(release): v<version>` and make a signed `v<version>` tag. A failed check leaves nothing behind. It then asks once, and on `y` pushes the branch and tag and publishes the GitHub release with those notes, which is what new installs clone. That last step needs `gh` signed in. If the release can't be created, the tag is still pushed and it prints the command to retry.

It doesn't use release-please itself because that tool creates tags on GitHub's side, unsigned, and installs only follow tags signed by a pinned key.

Existing installs pick the tag up on their next check either way. On GitHub, it's worth protecting `v*` tags and `main` so only the owner can create or move them.

## Cost and privacy

The plugin calls Haiku at most 9 times a day, on your own Claude account.

No work names, paths or text ever leave a session. The plugin keeps an area key (a keyed SipHash-2-4 hash, truncated, under a secret unique to your install) and a handful of coarse values. Ticket keys, repo names, prompts and tool output are reduced to those before anything is written, and the tests check that the raw strings never show up in the stored state.

## Where things live

Code runs from the clone and state lives outside it:

- `~/.claude/jeb-desktop`: logs, installed versions, heartbeat, telemetry, updater and release state, staging.
- `~/.claude/jeb-creative`: the builder's changelog, run log, lock and output (unused while it's off).
- `~/.claude/plugins/store/`: the plugin's state file, which the desktop reads.

The installed app finds the plugin through the `JebMod` key in its `Info.plist`, written at build time. `JEB_MOD` overrides it, and a dev build falls back to the `mod/` folder next to `desktop/`.

Environment variables, mostly for tests (the install sets the paths itself):

- `JEB_HOME`: desktop state folder (default `~/.claude/jeb-desktop`).
- `JEB_SRC`: app source for `jebctl` and `updater.py` (default `desktop/src`).
- `JEB_MOD`: the plugin folder, used to find `hooks/pixel-art.ts`.
- `JEB_BUNDLE_MOD`: the folder written into the bundle's `JebMod` key (default `JEB_MOD`). Release updates point it at the clone's `mod/`, since the staged copy is deleted afterwards.
- `JEB_APP_DIR`: where `JebDesktop.app` goes (default `~/Applications`).
- `JEB_LAUNCHAGENTS`: where the LaunchAgent plists go (default `~/Library/LaunchAgents`).
- `JEB_SETTINGS`, `JEB_BACKUPS`, `JEB_STORE_DIR`: the settings file, its backups and the store folder, for `./install`, `./uninstall` and `jebctl doctor`.
