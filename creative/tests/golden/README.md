# Golden captures of the Python creative builder (phase E1, step 0)

Captured from creative/jeb-creative-build and creative/tools/ before the Swift port, so the E2 tests have something to compare to.

How: the Python derives HOME from the HOME variable and MOD from its own location, so it was run from a scratch copy of the repo with a
temporary HOME (symlinks to ~/.local and ~/.nvm, a copy of the pinned tools). The live mod/, the real runs.log, the real builder state
and every LaunchAgent were untouched. Nothing here called `claude -p`, the probe, or the builder.

- validate.json: `claude plugin validate --json` of the live mod, scratch paths rewritten to `<MOD>`. It carries `notes` such as
  "./register.tsx env writes: nothing", the data behind the G6 "nothing is known" quirk.
- hostile-python.txt: the output of tools/hostile_gate.py (34 cases) in the scratch copy. It makes no model call and writes only to its
  own scratch folders. One line per case with the rejection message the Python gave.
- pattern-counts.json: the G7 (forbidden) and G8 (counted) match counts over the live mod's source text.
- mod-counts.json: locked test block counts, test count, hooks bytes, tree size of the live mod.
- tools-digest.txt: the tree digest of the pinned tools folder and the recorded one; they match. The Swift treeDigest gives the same hash.
- builder-args.json, builder-args-task.json, sandbox-settings.txt, builder-commands.txt: argv, settings and commands for home
  /Users/golden (stage under it).

Caveat: the argv, settings and commands goldens are PRE-D7. They contain the venv allowRead path, the art command and its Bash rule. The
Swift output differs from them in exactly those three places (venv allowRead and the art rule gone, the art command gone). E2 must
apply D7 to the golden before comparing; the E1 check showed those are the only differences.

Skipped: nothing. (Probe output was not captured: it needs `claude -p`, so it was never run.)
