<p align="center">
  <img src="docs/logo.svg" alt="Jeb" width="400">
</p>

Jeb is a little farm that lives on your Mac's desktop and keeps track of your Claude Code sessions. A Claude Code plugin watches what your sessions get up to, and a desktop app draws it.

Jeb is made by Clevyr and licensed under the [PolyForm Internal Use License 1.0.0](LICENSE): you may use and change it for your own and your company's internal use, but not redistribute or sell it.

**Latest release:** [github.com/clevyr/jeb/releases/latest](https://github.com/clevyr/jeb/releases/latest). The downloads, `Jeb-<tag>-macos-arm64.zip` and `Jeb-<tag>-macos-x86_64.zip`, are listed under **Assets** at the bottom of that page. You don't need to download them yourself: the install below picks up the newest release, and Jeb keeps itself up to date after that.

![farm-day](docs/screenshots/farm-day.png)

## Getting Jeb

You need a Mac and Claude Code. Claude does the rest, and it takes about five minutes. You don't need Homebrew, Xcode, the Command Line Tools, git, an administrator password or any Terminal setup.

**1. Ask Claude to set it up.** Open Claude Code in any folder and paste this in:

    Set up or update Jeb for me from github.com/clevyr/jeb. Do every step yourself, without asking me
    to run anything. Never ask me for an administrator password or sudo, to edit my shell profile or
    PATH, to install Homebrew, or to accept the Xcode license, and never compile anything. Run:
    mkdir -p ~/.jeb/bin && curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/jebctl-macos -o ~/.jeb/bin/jebctl.new && chmod +x ~/.jeb/bin/jebctl.new && mv -f ~/.jeb/bin/jebctl.new ~/.jeb/bin/jebctl && ~/.jeb/bin/jebctl install
    It installs Jeb or updates it. Read what it prints and fix any FIX line it reports, following
    https://raw.githubusercontent.com/clevyr/jeb/main/.claude/skills/jeb-install/SKILL.md.

Claude does the whole setup itself. When it's finished it tells you whether everything is healthy. `jebctl install` checks the release's signature against the signer pinned inside it before anything runs, so a download that was tampered with is refused. The same prompt works later to update or repair Jeb. From then on every action is a `jebctl` command (`update`, `doctor`, `status`, `uninstall`); `~/.local/bin/jebctl` is the link the install makes, and `~/.jeb/bin/jebctl` always works.

**2. Start a new Claude Code session.** Jeb only joins sessions started after the install. The farm looks pretty empty at first and fills in as you work.

![farm-built](docs/screenshots/farm-built.png)

## Using Jeb

There's nothing to run. Jeb starts when you log in, comes back on its own if it stops, and updates itself in the background.

It adds an item to the menu bar with:

- A status line showing whether it's running and at what frame rate, or why it's paused.
- **Pause / Resume** to stop and start drawing.
- **Frame rate**: Adaptive (the default, which slows down when nothing's moving), 60 fps or 30 fps.
- **Check for Updates**, above Reload art, with a line showing the installed version and when Jeb last checked (a development install shows its build instead). It runs the update check now instead of waiting for the next one; the same checks apply. While an update runs it shows its progress ("Update in Progress — gate parity (3 of 6), 45 s"), then the result ("Up to date · 14:02", "Update failed: …", "Rolled back: …"), so a check that finds nothing still answers; Jeb also posts a macOS notification when a run ends (updated, failed, rolled back or an error, and "up to date" only for a check you started from the menu), once per run; the details are in `update-status.json` in the state folder. It says "Checking for Updates…" for up to a minute after a click, then "Couldn't start the update — run jebctl doctor", "Update taking longer than expected — see jebctl status" after 30 minutes, and "Updates Paused" after `jebctl pause-updates`.
- **Reload art** to pick up new plugin art without restarting.
- **Save Screenshot**, which saves a picture per screen to `~/Pictures/Jeb/` and shows it in Finder. It only saves what Jeb draws, never your other windows.
- **Restart** to start a fresh copy.
- **Quit Jeb Desktop**, which stops it until you next log in.

![jeb-banjo](docs/screenshots/jeb-banjo.png)

## Updating

Jeb updates itself at login and every 6 hours. **Check for Updates** in the menu checks right now, and so does `jebctl update` in Terminal (it waits for the result). To have Claude do it and report back, paste this into Claude Code:

    Update Jeb: follow ~/.jeb/current/.claude/skills/jeb-update/SKILL.md.

If you installed Jeb before v1.3.0 (a git clone), run `jebctl install` (or click **Check for Updates**, let it finish, then click it once more): it converts the install to the bundle layout.

## If something looks wrong

Run `jebctl doctor`: one line per check, and every `FIX` line says what to do. The easiest fix is to ask Claude. Paste this into Claude Code, and it finds and fixes the problem itself:

    Check my Jeb install: follow ~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md and fix what it finds.

It runs a health check and explains each problem in plain words. Some common ones:

- **Nothing on the desktop and no menu bar item.** Jeb was quit or isn't running. Log out and back in, or ask Claude to check your Jeb install.
- **The menu bar says "Waiting for art".** Jeb can't find its files, usually because the `~/.jeb` folder was moved or deleted. Ask Claude to install Jeb again.
- **The desktop is empty.** Start a new Claude Code session; Jeb only joins sessions started after the install.

## Removing Jeb

In Terminal:

    ~/.local/bin/jebctl uninstall --remove-files

That removes the app, takes Jeb out of Claude Code and deletes the `~/.jeb` folder. Your farm is kept in case you come back; add `--purge --purge-farm` to remove everything. Installs from before the bundle layout keep a git clone in `~/.jeb/repo` (or `~/jeb`); `--remove-files` removes it too when it has no local changes, otherwise it tells you to drag it to the Trash.

![jeb-idle](docs/art/jeb-idle.gif) ![jeb-hoe](docs/art/jeb-hoe.gif) ![jeb-sip](docs/art/jeb-sip.gif) ![jeb-banjo](docs/art/jeb-banjo.gif) ![blue-run](docs/art/blue-run.gif) ![cow](docs/art/cow.gif) ![hen](docs/art/hen.gif) ![owl](docs/art/owl.gif) ![fire](docs/art/fire.gif)

---

# For developers

Everything below is detail for people who want to know how Jeb works, install it by hand, or change it.

## What's in the repo

- `mod/` is the Claude Code plugin, listed by `.claude-plugin/marketplace.json` (a marketplace named `jeb`, plugin id `jeb@jeb`). Its hooks watch your sessions and write anonymized state to the plugin store.
- `desktop/` is the macOS app (Swift), plus the Python scripts that install, update and look after it.
- `desktop/cli/` is the native `jebctl` (Swift, Foundation and CryptoKit only). In a release bundle it replaces the `desktop/bin/jebctl` shell launcher and forwards every command to the bundle's Python `desktop/jebctl`; as the standalone `~/.jeb/bin/jebctl` it also runs `install` itself. Build it with `JEB_VERSION=dev desktop/cli/build.sh` (`JEB_OUT` names the output, default `desktop/cli/jebctl`; `JEB_UNIVERSAL=1` builds arm64 and x86_64 and joins them with `lipo`). The release builds the universal one itself.
- `creative/` is a scheduled builder that can extend the plugin. It's switched off, `./install` doesn't touch it, and nothing in here starts it.

## Requirements

- macOS, logged in to a desktop session.
- macOS 12 or later, logged in to a desktop session. A release install needs nothing else from the system: Jeb ships its own Python, and the release carries the prebuilt app and helper tools, so there's no Xcode, Command Line Tools, git, Homebrew or compiler on a teammate's Mac, and nothing is compiled or notarized.
- Claude Code, signed in with your own account.
- Access to github.com and release-assets.githubusercontent.com. Installs and updates download releases over plain HTTPS: no GitHub account, sign-in or `gh`. Python updates trust `/etc/ssl/cert.pem`; behind a TLS-inspecting proxy, export its root certificate into a bundle file and set `SSL_CERT_FILE` to it.
- Developers also need the Xcode Command Line Tools (`xcode-select --install`): Swift for development installs and `--build-from-source`, git for working on the repo, and `lipo` and `swiftc` for `./release`.

## Installing by hand

Two lines install Jeb; `jebctl` does everything else. The download goes to a new file that is renamed over the old one, since overwriting a signed binary in place can get it killed:

    mkdir -p ~/.jeb/bin && curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/jebctl-macos -o ~/.jeb/bin/jebctl.new && chmod +x ~/.jeb/bin/jebctl.new && mv -f ~/.jeb/bin/jebctl.new ~/.jeb/bin/jebctl
    ~/.jeb/bin/jebctl install

`jebctl install [--dry-run] [--no-agents] [--verbose]` reads the newest release from `releases/latest` (a plain web redirect: no sign-in, no API), downloads its manifest, signature and this Mac's zip, verifies them, unpacks the zip and runs the bundle's own `install`. If Jeb is already installed it runs `jebctl update` and the doctor instead, and it converts an old git-clone install. `--dry-run` prints the plan and changes nothing. The curled `jebctl-macos` is trusted through TLS to github.com; from then on everything is checked against the signer pinned in it, including later copies of jebctl, which arrive inside signed bundles. To check that first copy as well, verify the manifest and `.sig` as below and compare `plutil -extract jebctl.sha256 raw -o - Jeb-$tag-manifest.json` with `shasum -a 256 ~/.jeb/bin/jebctl`. These are the steps it performs (the install skill, `.claude/skills/jeb-install/SKILL.md`, lists the same ones). Pick `arm64` or `x86_64` for `<arch>` (`sysctl -n hw.optional.arm64` prints 1 on Apple silicon):

    tag=$(curl -fsSLo /dev/null -w '%{url_effective}' https://github.com/clevyr/jeb/releases/latest); tag=${tag##*/}
    d=$(mktemp -d) && cd "$d"
    for f in Jeb-$tag-manifest.json Jeb-$tag-manifest.json.sig "Jeb-$tag-macos-<arch>.zip"; do curl -fsSLO "https://github.com/clevyr/jeb/releases/download/$tag/$f"; done
    echo 'anthony@clevyr.com namespaces="jeb-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrfSJyAm3dy3vkC1jKbk2YIxJk9BvoThi605ul1gMZC' > signers
    ssh-keygen -Y verify -f signers -I anthony@clevyr.com -n jeb-release -s Jeb-$tag-manifest.json.sig < Jeb-$tag-manifest.json
    plutil -extract bundles.<arch>.sha256 raw -o - Jeb-$tag-manifest.json     # must equal the next line
    shasum -a 256 "Jeb-$tag-macos-<arch>.zip"
    mkdir -p ~/.jeb/versions/"$tag" && ditto -x -k "Jeb-$tag-macos-<arch>.zip" ~/.jeb/versions/"$tag"
    ~/.jeb/versions/"$tag"/python/bin/python3 -I ~/.jeb/versions/"$tag"/install
    ~/.local/bin/jebctl doctor

The release is a zip per architecture holding the app, the Claude Code plugin, Jeb's scripts and a pinned Python, plus a signed manifest (see [Signed releases](#signed-releases)). It's unpacked into `~/.jeb/versions/<tag>`, and `~/.jeb/current` is a link to the version in use. The bundle's own `./install --dry-run` shows every step without changing anything. It prints one short line per step; add `--verbose` for every command and detail. A teammate never needs git: updates download and verify the next zip the same way, then move the `current` link.

The install:

1. Checks it runs on macOS and finds the plugin.
2. Pins the release signer (see [Signed releases](#signed-releases)) and records the install state.
3. Runs a quick set of checks on the release's prebuilt app (smoke test, headless start), then installs the LaunchAgents, which run the bundled Python, and starts it. If a check fails, nothing gets installed. A release install never compiles and refuses `--dev` and `--build-from-source`.
4. Registers the mod through Claude Code's own plugin system: `claude plugin marketplace add ~/.jeb/current` (a local marketplace named `jeb`) and `claude plugin install jeb@jeb`, so it shows up in `/plugin`. Options and the farm from an earlier install carry over, and Jeb's old `CLAUDE_CODE_PLUGIN_DIRS` entry is removed from `~/.claude/settings.json` (backed up to `~/.claude/backups/jeb/` first; your other entries stay). Updates run `claude plugin update jeb@jeb`. Without Claude Code installed this step is skipped with a note. Running it twice is harmless. `--dev` still loads the working tree through `CLAUDE_CODE_PLUGIN_DIRS`, for hot reload.
5. Links `jebctl` into `~/.local/bin`. If that folder isn't on your PATH, run it by its full path, or `~/.jeb/current/python/bin/python3 -I ~/.jeb/current/desktop/jebctl` (`./install --add-path` adds it to your shell profile, for developers who want plain `jebctl`).

Installs from before the bundle layout (a git clone in `~/.jeb/repo` or `~/jeb`) convert themselves on their next update (`jebctl install` runs the clone's `follow`, at most twice): the update downloads the bundle, switches over and leaves the old clone, which `./uninstall --remove-files` or you can delete.

`./uninstall` keeps `~/Library/Application Support/Jeb` unless you pass `--purge`, and keeps the plugin's state file unless you pass `--purge-farm`, which backs it up before removing it. It also runs `claude plugin uninstall jeb@jeb` and `claude plugin marketplace remove jeb`, and takes any Jeb `mod/` folder back out of `CLAUDE_CODE_PLUGIN_DIRS` (backing up your settings first) and removes the `jebctl` link; `--remove-files` deletes `~/.jeb` (`jebctl uninstall --remove-files` and `--purge-farm` run this script with every flag). `--dry-run` shows what it would do, and `--verbose` prints every command and detail.

## Commands

    jebctl status            # app, heartbeat, mode, last update, LaunchAgents
    jebctl doctor            # health check, one ok/FIX line per check
    jebctl start             # start it again after Quit
    jebctl quit              # same as Quit in the menu
    jebctl pause-updates     # stop following releases
    jebctl resume-updates
    jebctl rollback          # go back to the previous version (downloads it again)
    jebctl reload-agents     # re-write and reload the LaunchAgents after an update
    jebctl screenshot        # same as Save Screenshot, prints the paths
    jebctl emoji             # animated GIF of Jeb sipping moonshine for a Slack custom emoji (--sprite jeb-idle for the plain head), in ~/Pictures/Jeb

`jebctl screenshot --fixture <name> [--out <dir>] [--hour <h>]` renders one of the test scenes to `<dir>/<name>.png` without touching the running app. `--list` shows the scene names. That's how the screenshots in this README were made (scaled up 3x with `desktop/src/tools/up <in> <out> 3`).

## Troubleshooting

Run `jebctl doctor` first. Every `FIX` line tells you what to do.

**Nothing on the desktop and no menu bar item.** It was quit, or it isn't running. Run `jebctl start`. If the LaunchAgents are gone, run the `install` in `~/.jeb/current` again (`~/.jeb/current/python/bin/python3 -I ~/.jeb/current/install`).

**A menu bar item that says "Waiting for art".** The app can't find the plugin's art (`mod/hooks/pixel-art.ts`), usually because `~/.jeb/current` is broken or was deleted. It checks every 30 seconds and carries on once the file is back. Ask Claude to install Jeb again.

**The desktop is empty.** Start a new Claude Code session. The plugin only loads in sessions started after the install, and `doctor` will tell you whether it's registered and has written any state yet.

**Updates stopped.** `jebctl update` checks now and waits for the result, printing why if it fails. `jebctl status` shows the last release check and any failed tags. If the download is failing, look at `doctor`'s `GitHub releases reachable` line; a proxy or firewall must allow github.com and release-assets.githubusercontent.com. "app download failed; will retry" means the release couldn't be downloaded; nothing is marked failed and the next check tries again. `doctor` also tells you if updates are paused.

**An update failed.** The previous version keeps running and the failed release isn't retried. `jebctl retry-update` drops the newest failed tag and checks again. `update.log` and `release.log` say why.

All the logs live in `~/Library/Application Support/Jeb/` (older installs stay at `~/.claude/jeb-desktop` until `jebctl migrate` or the next update moves them; the old path then links to the new one): `update.log` for builds and checks, `release.log` for release checks and `watchdog.log` for restarts.

![rain](docs/screenshots/rain.png)

## Updates

Jeb uses [Semantic Versioning](https://semver.org): releases are tags like `v1.4.2`, and installs follow the highest one. Pre-release tags (`v1.5.0-rc.1`) are never picked up. A LaunchAgent (`com.jeb.desktop.release`) checks at login and every 6 hours:

1. It asks github.com which release is the latest (`/releases/latest`, a plain web request: no sign-in, no API token or rate limit).
2. If the latest is newer than yours, it downloads the manifest, its signature and the zip for your Mac's architecture. The manifest has to be signed by a pinned signer for the `jeb-release` namespace, and the zip's SHA-256 and size have to match it. One that fails is logged and skipped, and the next check takes the newest older release from the releases feed, so a bad release can't block the real ones.
3. The zip is unpacked into `~/.jeb/versions/<tag>`, refusing anything that isn't a plain file or folder or that would land outside it. The release's prebuilt app then goes through the quick checks: smoke test and a headless start. Parity and the scripted day run once, on the owner's Mac, when the release is cut.
4. If everything passes, `~/.jeb/current` moves to the new version (open sessions reload the plugin), the new app replaces the old one and the LaunchAgents are rewritten if they changed. Only one version is kept on disk, so the old folder is deleted. If the new app crashes or stops reporting in the next few minutes, the old one comes back and that tag is never tried again.

Nothing is compiled and no git is involved: a release update only downloads, verifies and unpacks. `jebctl status` shows the install mode, the current release, the last check and any failed tags; `jebctl follow --dry-run` shows what the next check would do, and `jebctl rollback` downloads the previous release again and goes back to it. A development install still builds from source.

### Signed releases

Each release carries a signed manifest, and installs only trust signers pinned on that machine, so a release published by anyone else is ignored. Releasing stays with the owner: `jebctl release` refuses to run in a release bundle, and without the owner's signing key nothing it produced would be accepted by an install.

- `Jeb-<tag>-manifest.json` lists, per architecture, the zip's name, size and SHA-256, and the Python it carries, plus a `jebctl` entry (name `jebctl-macos`, size and SHA-256 of the universal native jebctl); `Jeb-<tag>-manifest.json.sig` is its SSH signature in the `jeb-release` namespace.
- `jebctl-macos` is the first thing a new teammate downloads (with curl; no sign-in). It is the same binary every bundle carries as `desktop/bin/jebctl`, ad-hoc signed, and it pins the `jeb-release` signer in its source (`signerLine` in `desktop/cli/main.swift`); `./release` refuses to tag when that line differs from `desktop/release-signers`. It checks every release it installs against that pin.
- `desktop/release-signers` lists the allowed signers (`ssh-keygen` allowed_signers format, namespaces `git,jeb-release`). The key above in this README is the same one, so you can check a download before running anything from it.
- The install copies the file to `~/Library/Application Support/Jeb/release-signers` (mode 0600) if there isn't one already, and widens an older pin of the same key to cover `jeb-release`. It never adds a key. Later releases can't replace it, so trust is fixed at install time.
- To rotate keys, update `desktop/release-signers` in a release, then run `install --repin` on each machine.
- With no signer pinned, installs don't update at all. `status` and `doctor` show whether one is pinned.

![farm-night](docs/screenshots/farm-night.png)

## Contributing

### Setting up

You need everything from [Requirements](#requirements). Then work from a clone of `main` rather than a release, and install in dev mode:

    git clone https://github.com/clevyr/jeb.git ~/jeb-dev
    cd ~/jeb-dev
    ./install --dev

Dev mode runs straight from your working tree and doesn't follow releases. The update agent watches `desktop/src` and, once your edits have been quiet for a minute, builds them, runs the full checks and swaps the new app in if they pass. Run `jebctl pause-updates` while you're in the middle of something and `resume-updates` when you want it shipped. A build that fails a check isn't tried again; if the failure was a fluke, `desktop/jebctl retry-update` runs every check on it once more and ships it if they all pass. If you already have a release install, run `./uninstall` in that clone first so there's only one.

Make your changes on a branch and open a pull request against `main`.

### The desktop app

    cd desktop/src
    JEB_OUT=JebDesktop.dev ./build.sh

Don't launch `JebDesktop.dev` directly: a new copy takes over from the running app. Look at your changes through the tools instead. `jebctl screenshot --fixture <name>` renders a test scene with your build (set `JEB_BIN=desktop/src/JebDesktop.dev`), and the checks below run it offscreen.

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

That rewrites `mod/hooks/pixel-art.ts` and writes previews to `mod/art/out/` (not tracked). Rebuild the logo and the plugin icon with `python3 mod/art/src/logo.py mod/hooks/pixel-art.ts docs mod/.claude-plugin/icon.png`.

### Commit messages and versions

Write commit subjects as [Conventional Commits](https://www.conventionalcommits.org), because the release reads them to pick the next version and write the release notes:

- `fix: ...` for a bug fix (patch release). `perf:` and `revert:` count the same.
- `feat: ...` for something new (minor release).
- `feat!: ...` (any type with `!`), or a `BREAKING CHANGE: ...` line in the body, for a change that breaks existing installs (major release).
- `docs:`, `test:`, `refactor:`, `chore:` and the rest don't trigger a release on their own.

A scope is fine too, like `fix(desktop): ...` or `feat(mod): ...`. Leave `"version"` in `mod/.claude-plugin/plugin.json` alone; the release sets it.

![ridges-home](docs/screenshots/ridges-home.png)

## Releasing

Releases are cut locally by the owner; there's no CI. Releases are signed, so once, from the clone:

    ./release setup

If this clone has no signing key yet, it makes one at `~/.ssh/jeb_signing` (it asks you for a passphrase) and points this clone's git at it. Then it writes `desktop/release-signers` from your git email and that key, with the namespaces `git,jeb-release`. Commit and push that file before the first release, and put the same line in the install prompt and steps above. Back the key up somewhere safe, like a password manager: if it's lost, every install has to run `install --repin` to trust a new one. Git asks for the passphrase once each time you release, and `ssh-keygen` once more to sign the manifest.

To get a "Verified" badge on the tags on GitHub, also add `~/.ssh/jeb_signing.pub` to your account as a *Signing Key* (Settings, then SSH and GPG keys). Installs don't need it.

From a clean checkout of `main`, one command cuts a release and puts it on GitHub:

    ./release

It works out the version the way release-please does, from the [commit messages](#commit-messages-and-versions) since the last release: any breaking change makes it a major release, otherwise any `feat` makes it minor, otherwise any `fix`, `perf` or `revert` makes it a patch. If there's nothing releasable it says so and stops. The release notes are built from the same commits. The very first release is 1.0.0. The version always comes from the release tags and the commits, never from a number you set; the release writes it into `mod/.claude-plugin/plugin.json` for the record.

Add `--dry-run` to see the version and notes it would use without changing anything. To force a level, pass it: `./release patch`, `./release minor` or `./release major`.

It validates and tests the plugin, does a universal release build (arm64 and x86_64) and runs the parity checks on that binary. Only if all of that passes does it write the new version to `plugin.json`, commit it as `chore(release): v<version>` and make a signed `v<version>` tag. A failed check leaves nothing behind. It then builds one bundle per architecture: the tag's tree (`git archive`), the prebuilt app and helper tools, and a pinned relocatable Python from [python-build-standalone](https://github.com/astral-sh/python-build-standalone) (release `20261013`, Python 3.12.15, `install_only_stripped`, SHA-256 checked against the pins in `release`, pruned, every Mach-O signature checked, and its standard-library imports smoke-tested). To change the Python, edit the pins at the top of `release` (`PBS_TAG`, `PBS_PY` and the two hashes, taken from that release's `SHA256SUMS`). The zips and a manifest listing their hashes are signed with your signing key, and the manifest is verified against `desktop/release-signers` before anything is published. If building a bundle fails, the local tag stays, nothing is pushed, and it says how to continue.

It then asks once, and on `y` pushes the branch and tag and publishes the GitHub release with the notes, the manifest, its signature, both zips and `jebctl-macos` (the universal native jebctl, built from `desktop/cli` with the version baked in next to the app zip, and copied into every bundle as `desktop/bin/jebctl`). The old `JebDesktop-<tag>-macos.zip` and the tag message's `app-sha256` are still published while older installs that update from a git clone convert to the bundle layout; they can be dropped later. That last step needs `gh` signed in. Without a terminal it prints the commands instead. `./release bundle --tag <tag> --app <dir> --key <key> --out <dir>` builds the bundles on their own (`--from-tree` uses the working tree instead of a tag).

It doesn't use release-please itself because that tool creates tags on GitHub's side, unsigned, and installs only trust releases signed by a pinned key.

To check a published release the way a new user gets it, run `./release smoke` (or `./release smoke v1.2.0` for another tag; `--dry-run` prints the plan). It works in a sandbox under `.git/jeb-smoke/<tag>/` with a fake home folder, so your own install is never touched: it downloads the release's manifest, signature and `jebctl-macos` over HTTPS (`JEB_RELEASE_BASE` overrides where releases are read), verifies them against `desktop/release-signers`, checks that `jebctl-macos` matches the manifest and reports the tag from `--version`, then runs that `jebctl-macos install --no-agents`, which downloads this Mac's zip, unpacks it into the sandbox's `.jeb/versions/<tag>` and runs the bundle's own install (no LaunchAgent, `launchctl` or PATH change). Releases older than v1.5.0 are refused: their `jebctl-macos` installs with gh. It checks that the prebuilt app is signed and points at the bundle's mod, that `current` and the plugin setting are right, and that exactly one version is on disk. It then runs `jebctl follow --dry-run` (the Python HTTPS path) and `jebctl doctor` read-only. An earlier sandbox is moved aside to `old-<time>`, not deleted. A pre-release tag (`v1.5.0-rc.1`) is smoked only when it is the newest tag or named explicitly.

Existing installs pick the release up on their next check either way. On GitHub, it's worth protecting `v*` tags and `main` so only the owner can create or move them.

## Cost and privacy

The plugin calls Haiku at most 9 times a day, on your own Claude account.

No work names, paths or text ever leave a session. The plugin keeps an area key (a keyed SipHash-2-4 hash, truncated, under a secret unique to your install) and a handful of coarse values. Ticket keys, repo names, prompts and tool output are reduced to those before anything is written, and the tests check that the raw strings never show up in the stored state.

## Where things live

Code runs from `~/.jeb/current` (a link to `~/.jeb/versions/<tag>`) and state lives outside it:

- `~/Library/Application Support/Jeb`: logs, installed versions, heartbeat, telemetry, updater and release state, staging.
- `~/.claude/jeb-creative`: the builder's changelog, run log, lock and output (unused while it's off).
- `~/.claude/plugins/store/`: the plugin's state file (`jeb_jeb-*.json`; installs from before v1.5.0 used `jeb_inline-*.json`, which is copied over), which the desktop reads.

The installed app finds the plugin through the `JebMod` key in its `Info.plist`, written at build time. `JEB_MOD` overrides it, and a dev build falls back to the `mod/` folder next to `desktop/`. The bundle's icon (`Resources/Jeb.icns`) is generated at the same time from the mod's art (the app's `JEB_ICONSET` mode and `iconutil`); if that fails the bundle is built without one.

Environment variables, mostly for tests (the install sets the paths itself):

- `JEB_HOME`: desktop state folder (default `~/Library/Application Support/Jeb`).
- `JEB_HOLIDAY`: `<name>` forces a holiday's sprite variants (`newyear`, `valentines`, `stpatricks`, `easter`, `july4`, `halloween`, `thanksgiving`, `christmas`), `none` turns them off. A variant `<base>--<holiday>` must have its base's width and frame count and may be up to 8 rows taller (a costume's tall hat); it is drawn from the feet up. Holidays are always off under `JEB_BENCH` (so the checks stay deterministic) unless forced.
- `JEB_EMOJI`: `<out.gif>` writes an animated 128 px GIF of a sprite for a Slack custom emoji and exits before the app starts (what `jebctl emoji` runs). `JEB_EMOJI_SPRITE` (default `jeb-idle`), `JEB_EMOJI_ROWS` (top rows of the base sprite kept, default 20, `0` the whole sprite; a taller holiday variant adds its extra rows on top), `JEB_EMOJI_DELAY` (seconds per frame; by default `jeb-idle` keeps the desktop's blink timing and other sprites get 0.5); `JEB_HOLIDAY` picks a variant.
- `JEB_SRC`: app source for `jebctl` and `updater.py` (default `desktop/src`).
- `JEB_MOD`: the plugin folder, used to find `hooks/pixel-art.ts`.
- `JEB_BUNDLE_MOD`: the folder written into the bundle's `JebMod` key (default `JEB_MOD`). Release updates point it at `~/.jeb/current/mod`, which survives the old version's folder being deleted.
- `JEB_APP_DIR`: where `JebDesktop.app` goes (default `~/Applications`).
- `JEB_LAUNCHAGENTS`: where the LaunchAgent plists go (default `~/Library/LaunchAgents`).
- `JEB_BIN_DIR`: where `./install` links `jebctl` (default `~/.local/bin`). `JEB_PROFILE`: the shell profile it adds that folder to (default `~/.zprofile`, `~/.bash_profile` or `~/.profile` by `$SHELL`).
- `JEB_SETTINGS`, `JEB_BACKUPS`, `JEB_STORE_DIR`: the settings file, its backups and the store folder, for `./install`, `./uninstall` and `jebctl doctor`. In a sandbox, also set `CLAUDE_CONFIG_DIR` so `claude plugin ...` stays out of the real account.
