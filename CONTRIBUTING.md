# Contributing

How to set up a development install of Jeb and change it.

## Setting up

You need everything from [Requirements](docs/install-and-updates.md#requirements). Then work from a clone of `main` rather than a release, and install in dev mode:

    git clone https://github.com/clevyr/jeb.git ~/jeb-dev
    cd ~/jeb-dev
    ./install --dev

Dev mode runs straight from your working tree and doesn't follow releases. The update agent watches `desktop/src` and, once your edits have been quiet for a minute, builds them, runs the full checks and swaps the new app in if they pass. Run `jebctl pause-updates` while you're in the middle of something and `resume-updates` when you want it shipped. A build that fails a check isn't tried again; if the failure was a fluke, `desktop/jebctl retry-update` runs every check on it once more and ships it if they all pass. If you already have a release install, run `./uninstall` in that clone first so there's only one.

Make your changes on a branch and open a pull request against `main`.

## The desktop app

    cd desktop/src
    JEB_OUT=JebDesktop.dev ./build.sh

Don't launch `JebDesktop.dev` directly: a new copy takes over from the running app. Look at your changes through the tools instead. `jebctl screenshot --fixture <name>` renders a test scene with your build (set `JEB_BIN=desktop/src/JebDesktop.dev`), and the checks below run it offscreen.

To run every check the updater runs (compile, smoke, parity, a scripted day, headless start) on a snapshot of your source without installing anything:

    python3 -I desktop/updater.py --gates-only --force

That takes about 8 minutes. To run one piece with your dev build, from `desktop/src`: `JEB_BIN=JebDesktop.dev python3 -I tools/day.py kinds` (or `day`, `limit`, `evening`, `again`, `night`, `all`). The parity check compares each fixture against `fixtures/band-out.txt`, which is the reference output: don't regenerate it.

## The plugin

    claude plugin validate mod
    claude plugin test mod

A few rules the plugin has to keep, and the tests check most of them:

- Hooks only observe. No network, no processes, no file writes and no notifications. `$.model` (the daily Haiku calls) is only used in `hooks/signals.ts`.
- Nothing identifying leaves a session. See [Cost and privacy](README.md#cost-and-privacy).
- A quiet tick makes no `$` calls at all.
- `tests/guard`, `tests/perf`, `tests/lore` and `tests/drops` are locked. Don't edit them; add new tests in a new file instead.

The plugin reloads in sessions started after a change.

## Art

The sprites come from `jebart`, the Swift art tool in `art/` (it needs only the Xcode command line tools):

    art/build.sh && art/jebart build mod/art/out mod/hooks/pixel-art.ts

That rewrites `mod/hooks/pixel-art.ts` and writes previews to `mod/art/out/` (not tracked). Rebuild the logo and the plugin icon with `art/jebart logo mod/hooks/pixel-art.ts docs mod/.claude-plugin/icon.png`.

## Commit messages and versions

Write commit subjects as [Conventional Commits](https://www.conventionalcommits.org), because the release reads them to pick the next version and write the release notes:

- `fix: ...` for a bug fix (patch release). `perf:` and `revert:` count the same.
- `feat: ...` for something new (minor release).
- `feat!: ...` (any type with `!`), or a `BREAKING CHANGE: ...` line in the body, for a change that breaks existing installs (major release).
- `docs:`, `test:`, `refactor:`, `chore:` and the rest don't trigger a release on their own.

A scope is fine too, like `fix(desktop): ...` or `feat(mod): ...`. Leave `"version"` in `mod/.claude-plugin/plugin.json` alone; the release sets it.
