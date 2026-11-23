# Reference

Jeb's commands, troubleshooting steps, and where its files and settings live.

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

`jebctl screenshot --fixture <name> [--out <dir>] [--hour <h>]` renders one of the test scenes to `<dir>/<name>.png` without touching the running app. `--list` shows the scene names. That's how the screenshots in the README were made (scaled up 3x with `desktop/src/tools/up <in> <out> 3`).

## Troubleshooting

Run `jebctl doctor` first. Every `FIX` line tells you what to do.

**Nothing on the desktop and no menu bar item.** It was quit, or it isn't running. Run `jebctl start`. If the LaunchAgents are gone, run the `install` in `~/.jeb/current` again (`~/.jeb/current/python/bin/python3 -I ~/.jeb/current/install`).

**A menu bar item that says "Waiting for art".** The app can't find the plugin's art (`mod/hooks/pixel-art.ts`), usually because `~/.jeb/current` is broken or was deleted. It checks every 30 seconds and carries on once the file is back. Ask Claude to install Jeb again.

**The desktop is empty.** Start a new Claude Code session. The plugin only loads in sessions started after the install, and `doctor` will tell you whether it's registered and has written any state yet.

**Updates stopped.** The app reloads the release and watchdog agents at start, and the update agent on a **Check for Updates** click, when launchd has dropped them (the `agents:` lines in `run.log` say so). `jebctl update` checks now and waits for the result, printing why if it fails. `jebctl status` shows the last release check and any failed tags. If the download is failing, look at `doctor`'s `GitHub releases reachable` line; a proxy or firewall must allow github.com and release-assets.githubusercontent.com. "app download failed; will retry" means the release couldn't be downloaded; nothing is marked failed and the next check tries again. `doctor` also tells you if updates are paused.

**An update failed.** The previous version keeps running and the failed release isn't retried. `jebctl retry-update` drops the newest failed tag and checks again. `update.log` and `release.log` say why.

All the logs live in `~/Library/Application Support/Jeb/` (older installs stay at `~/.claude/jeb-desktop` until `jebctl migrate` or the next update moves them; the old path then links to the new one): `update.log` for builds and checks, `release.log` for release checks and `watchdog.log` for restarts.

## Where things live

Code runs from `~/.jeb/current` (a link to `~/.jeb/versions/<tag>`) and state lives outside it:

- `~/Library/Application Support/Jeb`: logs, installed versions, heartbeat, telemetry, updater and release state, staging.
- `~/.claude/jeb-creative`: the builder's changelog, run log, lock and output (unused while it's off).
- `~/.claude/plugins/store/`: the plugin's state file (`jeb_jeb-*.json`; installs from before v1.5.0 used `jeb_inline-*.json`, which is copied over), which the desktop reads.

The installed app finds the plugin through the `JebMod` key in its `Info.plist`, written at build time. `JEB_MOD` overrides it, and a dev build falls back to the `mod/` folder next to `desktop/`. The bundle's icon (`Resources/Jeb.icns`) is generated at the same time from the mod's art (the app's `JEB_ICONSET` mode and `iconutil`); if that fails the bundle is built without one.

Environment variables, mostly for tests (the install sets the paths itself):

- `JEB_HOME`: desktop state folder (default `~/Library/Application Support/Jeb`).
- `JEB_HOLIDAY`: `<name>[,<name>...]` forces holidays (several can be active at once, as on the real calendar): `newyear`, `valentines`, `stpatricks`, `easter`, `july4`, `halloween`, `thanksgiving`, `christmas`; `none` turns them off. Only halloween, thanksgiving and christmas have costume sprite variants (the first active one with a costume is worn); every holiday has a banner badge, tab colour and greeting. A variant `<base>--<holiday>` must have its base's width and frame count and may be up to 8 rows taller (a costume's tall hat); it is drawn from the feet up. Holidays are always off under `JEB_BENCH` (so the checks stay deterministic) unless forced.
- `JEB_EMOJI`: `<out.gif>` writes an animated 128 px GIF of a sprite for a Slack custom emoji and exits before the app starts (what `jebctl emoji` runs). `JEB_EMOJI_SPRITE` (default `jeb-idle`), `JEB_EMOJI_ROWS` (top rows of the base sprite kept, default 20, `0` the whole sprite; a taller holiday variant adds its extra rows on top), `JEB_EMOJI_DELAY` (seconds per frame; by default `jeb-idle` keeps the desktop's blink timing and other sprites get 0.5); `JEB_HOLIDAY` picks a variant.
- `JEB_SRC`: app source for `jebctl` and `updater.py` (default `desktop/src`).
- `JEB_MOD`: the plugin folder, used to find `hooks/pixel-art.ts`.
- `JEB_BUNDLE_MOD`: the folder written into the bundle's `JebMod` key (default `JEB_MOD`). Release updates point it at `~/.jeb/current/mod`, which survives the old version's folder being deleted.
- `JEB_APP_DIR`: where `JebDesktop.app` goes (default `~/Applications`).
- `JEB_LAUNCHAGENTS`: where the LaunchAgent plists go (default `~/Library/LaunchAgents`).
- `JEB_BIN_DIR`: where `./install` links `jebctl` (default `~/.local/bin`). `JEB_PROFILE`: the shell profile it adds that folder to (default `~/.zprofile`, `~/.bash_profile` or `~/.profile` by `$SHELL`).
- `JEB_SETTINGS`, `JEB_BACKUPS`, `JEB_STORE_DIR`: the settings file, its backups and the store folder, for `./install`, `./uninstall` and `jebctl doctor`. In a sandbox, also set `CLAUDE_CONFIG_DIR` so `claude plugin ...` stays out of the real account.
