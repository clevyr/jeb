# Contributing

How to build Jeb from a clone and change it.

## Setting up

You need everything from [Requirements](docs/install-and-updates.md#requirements), including the developer tools. Work from a clone of `main`:

    git clone https://github.com/clevyr/jeb.git ~/jeb-dev
    cd ~/jeb-dev

There is no separate development install: the repo's `./install` and `./uninstall` only work inside a release bundle, and a working tree never follows releases. You build the pieces you are changing and check them with the tools below. A release (see [Releasing](docs/releasing.md)) is what puts a change on a Mac.

Make your changes on a branch and open a pull request against `main`.

## The desktop app

    cd desktop/src
    JEB_OUT=JebDesktop.dev ./build.sh

Don't launch `JebDesktop.dev` directly: a new copy takes over from the running app. Look at your changes through `jebctl screenshot --fixture NAME` instead, which renders one of the test scenes with your build without touching the running app. Build `jebctl` with `JEB_VERSION=dev desktop/cli/build.sh`, then:

    JEB_SRC=desktop/src JEB_BIN=desktop/src/JebDesktop.dev desktop/cli/jebctl screenshot --fixture NAME --out shots

`JEB_SRC` points it at this clone's fixtures (without it, it reads the installed ones). `--list` shows the scene names, and `--hour H` fixes the hour of day.

To run every gate a release runs (parity, a scripted day) against your build:

    sh desktop/gates/build.sh
    desktop/gates/jebgates all --bin desktop/src/JebDesktop.dev

That takes several minutes. `jebgates` also runs one piece at a time: `parity`, `day [day|kinds|limit|evening|again|night|all]`, `smoke` (every fixture renders) and `start` (twenty seconds headless). The parity check compares each fixture against `desktop/src/fixtures/band-out.txt`, which is the reference output: don't regenerate it.

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

That rewrites `mod/hooks/pixel-art.ts` and writes previews to `mod/art/out/` (not tracked). Rebuild the logo and the plugin icon with `art/jebart logo mod/hooks/pixel-art.ts docs mod/.claude-plugin/icon.png`. Sprites live in `art/src/*.swift`, and `jebart` has more subcommands (`jebart` with no arguments lists them).

## Tests

Each tool has its own suite, and each runs on its own:

    sh desktop/cli/tests/run.sh     # jebctl
    sh desktop/tests/check.sh       # the golden scenarios across the Swift tools
    sh art/tests/run.sh             # jebart
    sh creative/tests/run.sh        # the creative builder

## Commit messages and versions

Write commit subjects as [Conventional Commits](https://www.conventionalcommits.org), because the release reads them to pick the next version and write the release notes:

- `fix: ...` for a bug fix (patch release). `perf:` and `revert:` count the same.
- `feat: ...` for something new (minor release).
- `feat!: ...` (any type with `!`), or a `BREAKING CHANGE: ...` line in the body, for a change that breaks existing installs (major release).
- `docs:`, `test:`, `refactor:`, `chore:` and the rest don't trigger a release on their own.

A scope is fine too, like `fix(desktop): ...` or `feat(mod): ...`. Leave `"version"` in `mod/.claude-plugin/plugin.json` alone; the release sets it.
