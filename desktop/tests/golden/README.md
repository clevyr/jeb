# Golden files for the Python-to-Swift port

These files freeze what the Python parts of Jeb do today, so each Swift (or sh) port can be checked against the same inputs.
They were produced by `sh desktop/tests/capture-goldens.sh`, which regenerates all of them deterministically;
`sh desktop/tests/capture-goldens.sh --check` regenerates into a temp dir and diffs against this folder (exit 1 on a difference).
The capture script embeds its own Python helpers and goes away together with the Python it captures; the goldens stay.

Nothing here touches the real install: every scenario runs in a throwaway HOME under one temp dir, with `JEB_HOME`, `JEB_APP_DIR`,
`JEB_LAUNCHAGENTS`, `JEB_BIN_DIR`, `JEB_PROFILE`, `JEB_SETTINGS`, `JEB_BACKUPS`, `JEB_STORE_DIR`, `JEB_TOOLS_DIR`, `CLAUDE_CONFIG_DIR`,
`JEB_RELEASE_BASE=file://<sandbox>/rel` (a release tree laid out like GitHub's `releases/latest`, `releases.atom` and
`releases/download/<tag>/...`) and `JEB_NO_LAUNCHCTL=1`; `claude`, `gh`, `launchctl` and `curl` on PATH are fakes (`curl` exits 7).
The layout is the one of `desktop/tests/bridge-sandbox.sh` (same stub, same sandbox class, same bundle tree and release signer).

## Fixed inputs

| Input | Value |
|---|---|
| Interpreter (runtime, release, tools) | `/usr/bin/python3 -I` (CPython 3.9.6, the Command Line Tools / Xcode one) |
| Interpreter (art) | `~/.claude/venvs/jeb-art/bin/python` (3.9.6, Pillow 11.3.0); override with `JEB_ART_PY`; without it `art/` is skipped |
| Clock | `time.time()` pinned at `1780000000` (2026-05-28 15:26:40 CDT, 20:26:40 UTC). `time.sleep(s)` advances it by `s` instead of sleeping |
| Time zone / locale | `TZ=America/Chicago`, `LC_ALL=C`, `LANG=C`. One exception: parity.py runs under `TZ=America/New_York` (below) |
| pid | `os.getpid()` returns `4242` |
| Random | `random.seed(7)` before the module loads (the only user, `fake.py`, seeds its own `random.Random(7)` too) |
| Host arch | the capture host's (arm64); every occurrence is written as `$ARCH` |
| Keys | three throwaway ed25519 keys made per run (`old`, `new`, `other`); public parts are written as `$PUB_old` / `$PUB_new` / `$PUB_other` (bare blobs as `$PUBBLOB_*`). The pin in most sandboxes is `OLD` = `old@example.com namespaces="git,jeb-release" $PUB_old`; releases carry `NEW3` = `OLD` + `jeb-release namespaces="jeb-release" $PUB_new` and are signed with `new` under namespace `jeb-release` |
| Stub binary | a C program standing in for `desktop/bin/jebctl`, `app/JebDesktop`, `app/detect`, `app/png2raw` and `python/bin/python3`: logs its argv to `$JEB_STUB_LOG`, exits with `$JEB_STUB_RC` (default 0) and, on `apply <ver>` with exit 0, points `$JEB_STUB_FLIP` (`~/.jeb/current`) at `versions/<basename ver>` |
| Installed bundle | `~/.jeb/versions/v1.4.0` (schema 1: `bundle.json`, `mod/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `install`, `desktop/release-signers`, the Python files copied from `desktop/`, the stub as the binaries), `~/.jeb/current -> versions/v1.4.0`, `release-state.json` = `{"failed": [], "checked": null, "last": null, "layout": "bundle", "installed": [{"tag": "v1.4.0", "stamp": null, "at": 1}], "bridge_reset": 1}`, `install-mode` = `release` |
| Published release | `v1.5.0` (schema 2) in the file:// tree: `Jeb-v1.5.0-macos-$ARCH.zip` (ditto `-c -k --norsrc --noextattr`), `Jeb-v1.5.0-manifest.json` `{"schema": 1, "repo": "clevyr/jeb", "tag", "version", "bundles": {"$ARCH": {"name", "sha256", "size"}}}`, its `.sig` from `ssh-keygen -Y sign -n jeb-release`, and `latest` = the tag |

The in-process runner loads the Python file with `importlib` after patching `time.time`, `time.localtime`, `time.gmtime`, `time.strftime`,
`time.sleep`, `os.getpid` and `random.seed`, sets `sys.argv` before the load (jebctl reads `--no-agents` at import), replaces `running()` with
an empty list (no `ps`), and makes the updater's `notify_finished` a no-op (no Notification Center). `SystemExit` messages reach stderr the
way they do on the command line. No shipped Python file was edited for this.

## Normalization

Paths and values that cannot be fixed are rewritten in every golden before it is saved: the sandbox root `$SB`, the temp dir `$T`, this
repo `$REPO`, the real home `$REALHOME`, the arch `$ARCH`, the repo's HEAD commit `$HEAD` (any prefix of 7+ hex digits), the resolved
`sys.executable` of `/usr/bin/python3` `$PYTHON3`, `gui/<uid>` -> `gui/$UID`, 64-hex digests `$SHA256`, 16-hex digest prefixes `$SHA16`,
`SHA256:<fingerprint>` `$FINGERPRINT`, step timings `(Ns)` `($Ns)`, `N KB`/`N MB` `$N KB`/`$N MB`, public keys as above. JSON files are
re-serialized with sorted keys and indent 1 (compare JSON semantically, not bytes). A port's output is compared after the same rewrite.

## File format

Each runtime/release golden is one scenario: `## rc`, `## stdout`, `## stderr`, then, when the sandbox has them after the run,
`## release-state.json`, `## update-status.json`, `## updater-state.json`, `## release.log`, `## stub.log` (argv of every stub call: the
contract between the Python follow and the native `apply`; the detached `prune-versions`/`reload-agents` calls are filtered as racy),
`## fake.log` (every `claude`/`gh`/`launchctl` call), `## ~/.jeb/current` (the symlink target) and the LaunchAgent plists as XML
(`plistlib.dumps`, so key order is canonical).

## What each area holds and what the port must match

### runtime/ (desktop/jebctl, updater.py, watchdog.py, jebhome.py, plugdirs.py, ./install, ./uninstall)

| Golden | Produced by | Match |
|---|---|---|
| `usage/jebctl-help.txt` | `jebctl --help` (the module docstring, rc 2) | exact text |
| `usage/jebctl-perf-bad-args.txt`, `jebctl-install-bad-mode.txt`, `jebctl-no-agents-wrong-command.txt`, `jebctl-release-from-bundle.txt` | the usage/refusal messages of `perf --days`, `install --mode bogus`, `status --no-agents`, `release` from a bundle | exact text and rc |
| `usage/install-bad-flag.txt`, `uninstall-bad-flag.txt` | `./install --bogus`, `./uninstall --bogus` (docstring, rc 2) | exact text |
| `usage/updater-help.txt`, `watchdog-help.txt` | `updater.py --help`, `watchdog.py --help` | exact text (argparse wording; a port may re-word, then update the golden) |
| `plists/bundle-release.txt` | `jebctl plists` from the installed bundle (writes `JEB_HOME/launchd/*.plist`) | plist semantics: same keys and values per label |
| `plists/clone-dev.txt`, `clone-release.txt` | `jebctl plists` with `CLONE` = this repo in dev / release mode | plist semantics |
| `status/bundle-fresh.txt` | `jebctl status` on the fresh bundle | exact lines |
| `status/bundle-full.txt` | `status` with telemetry CSVs (`telemetry/2026-05-28.csv`, `2026-05-27.csv`, `2026-05-23.csv`, header `epoch,stamp,pid,dt,cpu,rss,fp,sessions,class`), `updater-state.json` (last ok + two rejected stamps), `updates-paused`, `quit`, failed tags, two saved `versions/*.app` folders and a `com.jeb.desktop.plist` in LaunchAgents | exact lines |
| `status/perf-*.txt` | `jebctl perf`, `--days 2`, `--days 7 --stamp 20260526-120000`, `--stamp nope` on the same fixtures | exact table (column widths and rounding) |
| `status/pause-updates.txt`, `resume-updates.txt` | the two commands | exact text; the marker file |
| `status/clone-dev.txt`, `clone-release.txt` | `status` with `CLONE` = this repo (git-clone layout; the branch line names `$HEAD`/main) | exact lines |
| `doctor/*.txt` | `jebctl doctor` (rc 1 whenever a FIX line exists): fresh bundle, bundle with plists + app + telemetry, bundle with no pinned signers and no `latest`, paused with a failed tag, clone dev/release | exact lines and the problem count |
| `follow/*.txt` | `jebctl follow` on the installed bundle against the file:// release tree. `up-to-date`; `ok` (stub exit 0: `release-state.json` gains the install record and `last`, `update-status.json` ends `done/updated`, `current` flips, `stub.log` shows `apply <ver> --not-final --lock-held`); `ok-quick`, `ok-no-agents` (extra apply flags); `gates-rejected` (exit 2), `rolled-back` (3), `apply-error` (7); `gates-only-pass/fail`; `network-error` (no `latest`), `download-missing`; `signature-rejected` (signed by `other`); `no-pinned-signers`; `adopt-signers-*` (signers_from older / equal / unusable file); `flaw-sha/size/content/arch/json` and `flaw-replayed-manifest` (manifest names another tag); `paused`; `not-release-mode`; `dry-run`, `dry-run-current`; `failed-skipped-feed-fallback` (latest is in `failed`, `.atom` feed supplies the older tag); `straggler-reset` (failed without `failed_why`, no `bridge_reset`); `signature-retry-after-repin`; `heal-plists` (LaunchAgents naming the old Python command are rewritten to `desktop/bin/jebctl`) | stdout/stderr exact; state JSON semantically; stub.log argv exact |
| `rollback/*.txt` | `jebctl rollback` on an installed `v1.5.1` (pin `NEW3`): `floor` (previous is `v1.4.0`, under `ROLLBACK_FLOOR`), `ok`, `gates-rejected`, `download-fails`, `skips-failed-tag`, `nothing-recorded`, `dry-run` | exact text; state JSON; `current` |
| `update/*.txt` | `jebctl update --dry-run` (bundle), `update` while paused (rc 1), `update --dry-run` in a dev clone, `retry-update` with two failed tags | exact text; state JSON |
| `install/*.txt` | `./install` dry runs from the unpacked bundle at `~/.jeb/versions/v1.4.0` (plain, `--verbose`, `--no-agents`, `--repin --add-path`, `--dev` and `--build-from-source` refusals), `bundle-wrong-location` (bundle unpacked under `Downloads/`), `jebctl install --dry-run --verbose --no-agents` and `--mode dev` refusal from the bundle; from a local `git clone --no-tags` of this repo: `--dev`, release (no pin, pinned with no tags), `clone-release-dirty` (local edit refused) | exact lines (the `$PYTHON3` line is the command `./install` spawns) |
| `uninstall/*.txt` | `./uninstall` dry runs from the bundle (plain, `--verbose`, `--purge`, `--remove-files --purge-farm`, with one farm store file), `jebctl uninstall --dry-run [--purge] --verbose`, and from the clone (`--verbose`, `--remove-clone`) | exact lines |
| `watchdog/*.txt` | `watchdog.py --dry-run --no-recheck-wait --fake-procs ...`: none running (kickstart), quit marker, one running with no heartbeat (stale -> TERM + kickstart), one running with a fresh heartbeat file (pid 1, nothing to do), two running (SIGUSR1 to the newer), a `watchdog.kick` younger than 45 s | exact log lines (timestamp from the pinned clock) |
| `probes/tag-order.txt` | `tag_key` on a list of tags and the sort it gives | JSON semantics (`v1.2.0-rc1`, `v1.2`, `v01.2.3`, `foo` are not releases) |
| `probes/release-tags-canned.txt` | `release_tags()` / `head_tags()` with a canned `git tag --list` | JSON |
| `probes/failed-skip.txt` | `failed_skip`, `mark_failed`, `clear_failed`, `pin_hash` on fixed release-state shapes | JSON |
| `probes/signers-parse.txt` | `key_line` and `parse_signers` on fixed allowed_signers lines (namespaces, options, comments, blanks, ecdsa, sk keys) | JSON |
| `probes/new-tags.txt` | `new_tags(cur, skip)` against `latest` = v1.6.0 and an `.atom` feed listing v1.6.0, v1.5.0, v1.4.0 (with a duplicate and a non-release link) | JSON |
| `probes/check-sandbox.txt` | the `--no-agents` guard messages | exact strings |
| `probes/constants.txt` | `ALL_LABELS`, `INITIAL_VERSION`, `MANIFEST_MAX`, `ROLLBACK_FLOOR`, `NOTE_GROUPS`, `CPU_TARGETS`, `TAG_RE`, `CC_RE`, `labels_for`, `app_name` | values |
| `probes/release-plan.txt` | `release_plan("v1.2.0")` on canned `git log --format=%h%x00%s%x00%b%x1e` outputs: feat+fix, fix only, `feat!`, `BREAKING CHANGE:` footer, `BREAKING-CHANGE:` footer, nothing, perf/revert/scoped mix, empty, odd subjects | level and the notes markdown, exactly |
| `probes/verify-manifest.txt`, `verify-manifest-no-pin.txt` | `verify_manifest` on real signed files: good (`null`), unknown signer, replayed tag, invalid JSON, sig of another manifest, missing sig, no pin | the `(reason, kind)` pairs |
| `probes/updater-status.txt` | `updater.status()` phases -> `update-status.json` (mode 0600), `load_state()` on nothing, `bundle_stamp` on a missing app | JSON |
| `probes/jebhome.txt` | `release_base`, the path helpers, `find_claude`, `read_bundle`, `macho_archs`, `latest_tag`, `feed_tags`, `fetch` (missing, over the limit, ok) | JSON (note the empty host in `could not reach  (...)` for file:// URLs) |
| `probes/plugdirs.txt` | `plan(value, mod, remove)` table, `store_name`, `store_dir`/`store_path`/`settings_path`/`backup_dir`, `norm`, `info()`, and a dry-run transcript of `edit`, `register` (with an extra legacy entry), `sync`, `unregister` (keep / purge farm) against the fake `claude` | JSON and the transcript lines |

### release/ (./release, jebctl release, src/tools)

| Golden | Produced by | Match |
|---|---|---|
| `usage/*.txt` | `./release` with a bad command, `bundle --tag 1.2`, `bundle` with a missing app folder, `smoke 1.2.3 --dry-run`, `smoke v1.4.0 --dry-run` (under `SMOKE_MIN`) | exact text and rc |
| `steps/*.txt` | `jebctl release --dry-run --parity [--bump X]` in throwaway git repos (`git init -b main`, fixed author/committer `Golden <golden@example.com>` at `2026-05-01T12:00:00Z`, so commit ids are stable; `commit.gpgsign=false`, `user.signingkey` set; a synthetic `desktop/release-signers` and `desktop/cli/main.swift` `signerLines` that agree; `plugin.json` version 1.2.0; tag `v1.2.0` on the fixture commit, then the Conventional Commits of the case). Cases: auto minor / patch / major (`!` and footer), forced patch/major, bad `--bump`, nothing to release (and forced patch over it), mixed groups (perf, revert, scoped `fix!`, a `chore(release)` commit), first release (no tags, and forced minor), HEAD already tagged, no signing key, wrong branch, dirty tree, signer constant mismatch | exact text: the bump line, step lines, release notes, the push hint; rc |
| `tool/constants.txt` | the module constants of `./release`: `PBS_TAG`, `PBS_PY`, `PBS` (names + sha256), `TREE`, `PRUNE`, `REPO`, `SMOKE_MIN`, `SMOKE_TAG_RE`, `local_imports()`, `rosetta()`, `host_arch()` | values (`rosetta_available_on_capture_host` is this machine's) |
| `tool/smoke-dry-run*.txt` | `./release smoke --dry-run` and `smoke v1.5.0 --dry-run` (no network: the base comes from `git remote get-url origin`) | exact text |
| `tool/check-notices.txt` | `check_notices()` on this repo and on a folder without `THIRD-PARTY-NOTICES.md` | exact text |
| `bundle/v9.9.9.txt` | `./release bundle --tag v9.9.9 --out <dir> --ref HEAD --app <stage> --key <new> --signers <ONLY_NEW>` with the stub (ad-hoc codesigned) as the four app files, `HOME` = the real home only so the pinned python-build-standalone tarballs are read from `~/Library/Caches/jeb-release` (never downloaded: `curl` is the failing fake; without both cached tarballs this golden is skipped). Holds the stdout, the manifest shape, the files made, each arch's `bundle.json`, the full list of repo files in the bundle (git archive of `TREE` at `$HEAD`: changes to the tree change this list) and, for `python/`, the top-level folders, the `lib/python3.*` entries and a present/absent line per `PRUNE` glob | manifest/bundle.json semantics; file lists exact for the same HEAD; every PRUNE glob absent |
| `parity/gen.txt` | `desktop/src/tools/parity.py gen` (a copy at `<scratch>/src/tools/parity.py`, `JEB_MOD=$REPO/mod`, **`TZ=America/New_York`**: `ms()` uses `time.mktime`, and the tracked `desktop/src/fixtures/*.store.json` and `band-out.txt` were generated in that zone; under Chicago every `at`/`saidAt` is one hour off). Lists all 97 stores with sha256 and "same bytes" against the tracked fixture | every store must equal the tracked fixture byte for byte |
| `parity/gen-with-modcopy.txt` | the same with a `modcopy/tests` folder present: the generated `zz-parity.test.tsx` (full text) | exact text |
| `parity/compare.txt` | only with `--render` and a built `desktop/src/JebDesktop`: `parity.py compare desktop/src/fixtures/band-out.txt` (excluded from `--check`; not captured by default) | rc 0 and its summary |
| `tools/fake-idle.txt`, `fake-busy.txt` | `desktop/src/tools/fake.py <store> 3 idle|busy 6` with the clock advancing 0.5 s per sleep: the final store JSON and the `.writes` log | JSON semantics; the writes log (13 writes 500 ms apart) |

### art/ (mod/art/src, Pillow)

| Golden | Produced by | Match |
|---|---|---|
| `generators.txt` | `build.py <work> <work>/pixel-art.ts` and `logo.py <work>/pixel-art.ts <work>/logo <work>/icon.png` under the Pillow interpreter (`PYTHONHASHSEED=0`): stdout, and the sha256/size of the four exact-byte outputs with "same bytes" against the tracked files | `mod/hooks/pixel-art.ts`, `docs/logo.svg`, `docs/logo.png`, `mod/.claude-plugin/icon.png`: **exact bytes** (the tracked files are the reference) |
| `decoded-frames.json` | every other output (`sheets/*.png`, `gifs/*.gif`, `scene-*.png`, `scenes-all.png`; 282 images, 362 frames): size, format, loop, and per frame the GIF duration in ms and the sha256 of the frame converted to RGBA (`Image.convert("RGBA").tobytes()`, row-major, 4 bytes per pixel, no padding). `file_sha256`/`file_bytes` are informational only (encoder-dependent) | decoded-frame hashes, durations and sizes; not file bytes |

## Not captured (and why)

- `desktop/src/tools/day.py`: drives a live dev build of the app offscreen with wall-clock pacing; needs the app and real time.
- `desktop/src/tools/attach-fix.py`, `grid-fix.py`: dead one-off Swift source patchers (they `chdir` and edit `FarmScene.swift`).
- `desktop/src/tools/status.py`, `desktop/src/dev/analyze.py`, `creative/`: out of scope (being deleted / redesigned).
- `parity.py compare` is captured only with `--render` (needs a built `desktop/src/JebDesktop`); `gen` is always captured.
- `./release` with no command (that is `release auto`, a real release: it reads `user.signingkey` from the clone's git config and
  unlocks that key in an ssh-agent, so it is neither sandboxed nor deterministic); likewise the python-build-standalone download path (`fetch_python` past the cache), real tag signing, `git push`, `setup`, a non-dry
  `release`/`patch`/`minor`/`major`, non-dry `smoke` (all need the network, a signing key or GitHub). `bundle` is captured only when both
  tarballs are already cached. The `warning: Rosetta is missing` line and the "x86_64 Mach-O files are unsigned upstream" note are
  machine/tarball facts of the capture host.
- `jebctl emoji`, `screenshot`, `start`, `quit`, `reload-agents`, `migrate`, `convert_clone`, the live `update` wait, the non-dry
  `install`/`uninstall`, `follow` on a schema 1 bundle (the updater's compile/smoke/start gates need the real app and launchd).
- `jebctl status` lines that read live processes and heartbeat ages (`running()` is patched to none).
- `watchdog.py --sample-only` and the real `ps`/heartbeat/`kern.waketime` paths; its telemetry prune cutoff uses `datetime.date.today()`,
  which the harness does not pin (only the `--dry-run` supervision paths are captured).
- `jebhome.migrate` and `_rewrite_plists` (the ~/.claude/jeb-desktop -> Application Support move).
- Anything launchd-dependent (`launchctl` is a fake that records the call).

## Suspected bugs seen while capturing (not fixed)

- `jebctl rollback --dry-run` is not a dry run: `rollback_bundle()` never checks `DRY`, so it downloads, gates and flips `current`
  (`runtime/rollback/dry-run.txt` records that behaviour).
- `jebhome.fetch` error text for a `file://` URL reads `could not reach  (...)` with an empty host (cosmetic; `runtime/probes/jebhome.txt`).
- `release_plan` ignores `feat (x): ...` (space before the scope) and a subject with an empty description (`feat: `), silently
  (`runtime/probes/release-plan.txt`, case `odd-shapes`).
