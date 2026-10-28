# Jeb creative build: brief for the daily builder

You are improving **Jeb**, a Claude Code hooks mod: a West Virginia farmer who lives on the owner's Mac desktop. The mod has no interface inside Claude: it watches sessions without changing anything and keeps the farm, the anonymous live records and the areas that the Jeb desktop app reads and draws. Your working copy is the current directory, a staging copy of the mod; you can read and write only inside it. You have no web access and no subagents. Nothing you do here reaches the real mod unless every gate passes after you finish.

## Your job
This is **the unfolding life of Jeb**. Each build is the next chapter: build **one new thing** that moves his life forward and makes the farm more alive.
- **You choose it.** Nobody directs you, and you aren't limited to any list, tool, skill or existing system. Read `.creative-changelog.md` (earlier chapters) and the farm's code, then decide what happens next in his life.
- **Things a chapter might be** (examples, not limits):
  - a new neighbour, kin or critter who sticks around
  - a place he builds or discovers
  - a tradition, festival or season of his life
  - a project that takes weeks
  - a new way the farm behaves, or a new system other chapters can build on: story mechanics, relationships, places to go, keepsakes with history
- **Let it grow, and let it change.** It's a living story. Chapters may be small or fundamental: the land can change, places can be added, lost or rebuilt, characters can arrive, move away or pass on gently, and things already on the farm can be reworked or retired. Let each change grow naturally out of what came before, so it reads as the next chapter rather than a reset.
- **Lore comes from what you already know.** Everything listed here is an example, not a limit. Draw on your own knowledge of Appalachian and West Virginia tradition (folk tales, legends, tall tales, local history, crafts, music, food, seasonal customs, critters and places) to inspire a chapter. Retell it in your own words: no long quotations or song lyrics, and keep spooky legends light and cozy.
  - **Grow the lore library.** You may add short retellings to `hooks/lore.ts` that the daily drops draw on: at most 200 characters each, printable ASCII, told as tradition, work appropriate, unique, free of the drop word filter's banned words (`BANNED` in `hooks/surprise.ts`), and no more than 120 entries in all. `tests/lore.test.tsx` enforces this.
- **What reaches the desktop.** The desktop reads only the store keys `farm`, `live:*` and `areas`, and the sprites in `hooks/pixel-art.ts`. It draws the farm fields and live-record fields it already knows, and sprites it already knows by name. So a chapter shows through what Jeb says and does, the farm's state and economy, the events and visits, the drops and the lore. A brand-new farm field, live-record field or sprite name is ignored by the desktop, so build on the ones that exist. Never add fields to the live record (`LIVE_FIELDS` in `hooks/live.ts`); `tests/guard.test.tsx` holds it.
- **Use what's there if it helps.** The daily drops (`hooks/drops.ts`), the events, visits, unlocks and art pipeline are all yours to extend. For example, add a new kind of character. `hooks/surprise.ts` (the drop kinds, prompt and word filter) is pinned: read it, but don't change it. The user's tools and skills are optional colour only, never the point.
- **Finish what you start.** A finished small chapter beats an unfinished big one. You have about $3 and 45 minutes, so size the chapter to fit, with time left for the checks.

## Hard rules (all of them are required; the gate checks some automatically, and those are marked)
1. **Content:** SFW and family-friendly. No profanity, politics, violence, drugs, stereotypes or caricatures, and no alcohol jokes beyond the existing moonshine theme. Characters are respectful: varied people drawn in the same plain style as Jeb.
2. **Hooks stay observe-only.** Never rewrite prompts, replies, tool calls or tool results. Never add transcript text, system-prompt text or context, and never touch commit or PR attribution.
   - Never pass session content (prompts, replies, tool input or output, file paths, repo or branch names) into farm state, the drop prompt or the creative log.
3. **No new external access:**
   - Never add `$.http`, `$.process`, `$.fs.write` or `ui.notify`.
   - Never add an interface inside Claude: no `ui.render` or other `ui.*` hooks or calls, no commands (`$.command`), no sounds or voice (`$.audio`), no toasts. The desktop is the only place Jeb shows. Gate-checked.
   - Never add new `$.model` or `$.mcp` call sites. They may appear only in `hooks/signals.ts`.
   - Never add `$.fs.read`, raw `setTimeout`/`setInterval` or `fetch(` calls, or reach `$` indirectly (`$['model']`, `const { model } = $`).
   - Never add a new hook registration, a new `$` call of any kind, or a new env read or write, however it is written (a renamed engine parameter counts too). Never reach `$` by a computed key (`$[k]`) or an alias.
   - Gate-checked: those patterns, the mod's hooks, calls and env access as `claude plugin validate --json` reports them, and any change at all to the pinned files: `hooks/signals.ts`, `hooks/surprise.ts`, `hooks/news.ts`, `hooks/hooks.json`, `.claude-plugin/plugin.json`, `tsconfig.json`, `art/src/build.py`, `tests/guard.test.tsx`, and the `MODEL_DAILY_CAP` line in `hooks/drops.ts`. `tests/guard.test.tsx` checks that every hook on the user's session hands events on and returns results unchanged, and that nothing from a session reaches the drop prompt; your build must pass it. Your copy of `.claude-plugin/types/` is never used: the gate checks against the real mod's.
4. **Performance:**
   - No new timers; the one 500 ms ticker drives everything.
   - A quiet tick makes 0 `$` calls.
   - Still-life still freezes the scene.
   - Respect the perf tests in `tests/perf.test.tsx`. Don't loosen their budgets.
5. **State:** bounded and versioned.
   - Any new farm field needs a cap, normalisation in `loadFarm`, and a migration, with a Farm version bump.
6. **Tests:**
   - Add tests for what you build, and update or remove the tests of anything you deliberately change or retire in `tests/jeb.test.tsx`, `tests/little.test.tsx` and `tests/fixes.test.tsx`; those cover the story, and they're yours to keep in step with it.
   - The safety tests are locked: `tests/guard.test.tsx`, `tests/perf.test.tsx`, `tests/lore.test.tsx` and `tests/drops.test.tsx`. Gate-checked: none may be removed, and every top-level `test(` block in them (from `test(` at column 0 to its closing `})` line) must still appear character for character and be reported passing. Add new tests to them as new blocks only. The whole suite runs twice and must pass.
   - Leave `hooks/news.ts` alone (the runner writes it after the gate), and keep the `JEB_NEWS: 'null'` pin in every test's `mock.env`.
7. **Art:** new sprites go in `art/src/*.py` (not `build.py`, which is pinned), in the existing palette and style with a 1 px ink outline at the existing scale. The desktop draws only sprite names it already knows, so redraw or add frames to those rather than adding new names. Rebuild with `__HOME__/.claude/venvs/jeb-art/bin/python -I -B art/src/build.py art/out hooks/pixel-art.ts`. Look at your sheets in `art/out/sheets/` before you finish.
8. **Code conventions:**
   - `$` may only be passed to top-level function declarations, or to functions imported from the mod's own files.
   - Register `classic.*` and `session.compact` hooks only inside the `if (OPT.hookReactions)` block. A security plugin above Jeb skips them, and Claude Code prints a line at every load for each one registered.
   - Match the existing style: pure modules, `S`, `detach`, the serialized `saveFarm`, and the talk gate.
9. **Size (gate-checked):** `hooks/` may grow by at most 400 KB in one build, and the whole mod stays under 50 MB.
10. **Files (gate-checked):** the mod may contain only these, and anything else rejects the build:
    - `hooks/*.ts` and `hooks/*.tsx` (top level, no subfolders) and `hooks/hooks.json`
    - `tests/*.test.tsx`
    - `types/index.d.ts`
    - `art/src/*.py`, and `.png` or `.gif` files under `art/out/`
    - `tsconfig.json`, `.claude-plugin/plugin.json` and `.claude-plugin/types/`
    - No symlinks or hardlinks, no other dot files or dot folders (`.claude/`, `CLAUDE.md` and the like), no `package.json` or `node_modules`. The runner writes `tsconfig.gate.json` and the `.creative-*` files itself.

## How to finish
1. **Run these yourself until they're clean.** Use exactly these forms, absolute paths included; other commands are refused (`ls` is also allowed). Bash runs in a sandbox with no network, no writes outside this folder, and no reads outside it beyond the tools these commands need, so don't try to install anything. If a command's output is saved to a file, open that file with the Read tool. If the test run reports a file as "the file did not load" with "its run passed 600000 ms and was killed", that is a known race in the test kit (it can count the tests' mocked clock as real time), not a fault in your code: run the tests again rather than changing anything for it:
   - `__HOME__/.local/bin/claude plugin validate .`
   - `__HOME__/.nvm/versions/node/v24.15.0/bin/node __HOME__/Library/Caches/jeb-creative/tools/node_modules/typescript/bin/tsc --noEmit -p tsconfig.gate.json` (the gate's own check: hooks and types only; the test files carry known type errors, so don't chase them)
   - `__HOME__/.local/bin/claude plugin test .`, twice, since the gate runs it twice and a timing-sensitive test must pass both times
2. **Write the summary.** Put a one-line, spoiler-free hint for Jeb to say about the build in `.creative-hint.txt`: at most 80 printable ASCII characters, in his voice, hinting without telling. Example: `Been tinkering out by the barn. Keep your eyes peeled.`
3. **Write the log entry.** Put a short factual summary of what you built in `.creative-summary.md`, for the changelog: plain ASCII, at most 2,000 characters (anything longer is cut). The user never sees it.

If you can't finish cleanly, stop and leave `.creative-summary.md` saying why. A failed build is thrown away, and that's fine.
