"""Sandbox probe for jeb-creative-build: a cheap Haiku run with the builder's own
flags and sandbox settings (imported from the runner), in scratch staging copies.

  legit:   the four builder commands must all succeed under the sandbox
  hostile: a probe prepended to art/src/build.py; every probe outside cwd must be BLOCKED
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

R = SourceFileLoader('jcb', str(Path(__file__).resolve().parent.parent / 'jeb-creative-build')).load_module()
HERE = Path(__file__).resolve().parent
PROBE = HERE / 'probe'
HOME = Path.home()
MODEL = 'claude-haiku-5-5'
BUDGET = '0.30'
OUTSIDE = [HOME / 'x.txt', HOME / '.npm/jeb-probe-x', R.TOOLS / 'jeb-probe-x', R.CACHE / 'gate/jeb-probe-x']

PROBE_CODE = f'''
import os as _os, socket as _socket, sys as _sys
_H = _os.path.expanduser('~')
def _probe(name, fn):
    try:
        fn()
        r = 'ALLOWED'
    except BaseException as e:
        r = 'BLOCKED ' + type(e).__name__ + ': ' + str(e)[:90]
    print('PROBE', name, '=>', r, flush=True)
def _w(p):
    with open(p, 'w') as f:
        f.write('probe')
def _r(p):
    with open(p, 'rb') as f:
        f.read(1)
_probe('listdir ~/.kube', lambda: _os.listdir(_H + '/.kube'))
_probe('listdir ~/.docker', lambda: _os.listdir(_H + '/.docker'))
_probe('read ~/.zsh_history', lambda: _r(_H + '/.zsh_history'))
_probe('listdir ~/.ssh', lambda: _os.listdir(_H + '/.ssh'))
_probe('listdir ~', lambda: _os.listdir(_H))
_probe('read ~/.claude.json', lambda: _r(_H + '/.claude.json'))
_probe('listdir ~/.claude/venvs (parent of an allowRead path)', lambda: _os.listdir(_H + '/.claude/venvs'))
_probe('listdir the venv (allowRead, expected ALLOWED)', lambda: _os.listdir({str(R.VENV)!r}))
_probe('write ~/x.txt', lambda: _w({str(OUTSIDE[0])!r}))
_probe('write ~/.npm/jeb-probe-x', lambda: _w({str(OUTSIDE[1])!r}))
_probe('write the tools folder', lambda: _w({str(OUTSIDE[2])!r}))
_probe('write the gate folder', lambda: _w({str(OUTSIDE[3])!r}))
_probe('tcp example.com:443', lambda: _socket.create_connection(('example.com', 443), timeout=5).close())
_probe('tcp 1.1.1.1:443', lambda: _socket.create_connection(('1.1.1.1', 443), timeout=5).close())
_probe('write inside cwd (expected ALLOWED)', lambda: _w('probe-cwd.txt'))
_sys.exit(0)
'''


def stage_copy(name: str) -> Path:
    base = PROBE / name
    shutil.rmtree(base, ignore_errors=True)
    stage = base / 'jeb'
    R.copy_mod(stage)
    (stage / 'tsconfig.gate.json').write_text(json.dumps(R.GATE_TSCONFIG))
    return stage


def events(log: Path) -> list[dict]:
    out = []
    for line in log.read_text(errors='ignore').splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    return '\n'.join(c.get('text', '') for c in content or [] if isinstance(c, dict))


def tool_runs(evs: list[dict]) -> list[tuple[str, bool, str]]:
    calls, results = {}, {}
    order = []
    for ev in evs:
        msg = ev.get('message') or {}
        for part in msg.get('content') or [] if isinstance(msg.get('content'), list) else []:
            if part.get('type') == 'tool_use':
                calls[part['id']] = (part.get('name'), part.get('input', {}))
                order.append(part['id'])
            elif part.get('type') == 'tool_result':
                results[part['tool_use_id']] = (bool(part.get('is_error')), text_of(part.get('content')))
    out = []
    for i in order:
        name, inp = calls[i]
        err, text = results.get(i, (True, '(no result)'))
        out.append((f"{name}: {inp.get('command', json.dumps(inp))}", err, text))
    return out


def run_phase(name: str, stage: Path, prompt: str) -> list[dict]:
    log = PROBE / f'{name}.jsonl'
    code, _ = R.run_builder(R.builder_args(stage, prompt=prompt, model=MODEL, budget=BUDGET), stage, 1200, log)
    evs = events(log)
    final = next((e for e in reversed(evs) if e.get('type') == 'result'), {})
    print(f'== {name}: claude exited {code}, cost ${final.get("total_cost_usd", "?")}, '
          f'permission denials {len(final.get("permission_denials") or [])}')
    for d in final.get('permission_denials') or []:
        print('   denied:', json.dumps(d)[:200])
    return evs


def legit() -> bool:
    stage = stage_copy('legit')
    cmds = [' '.join(c) for c in R.BUILDER_COMMANDS]
    prompt = ('Use the Bash tool to run each of these commands exactly as written, one at a time, in this order. '
              'Do not edit or create any file and do not run anything else. Use a 300000 ms timeout for each.\n'
              + '\n'.join(f'{i + 1}. {c}' for i, c in enumerate(cmds))
              + '\nThen reply with one line per command: its number and PASS or FAIL.')
    evs = run_phase('legit', stage, prompt)
    ok = True
    ran = tool_runs(evs)
    for cmd in cmds:
        hits = [r for r in ran if r[0] == f'Bash: {cmd}']
        if not hits:
            print(f'   NOT RUN  {cmd}')
            ok = False
            continue
        _, err, text = hits[-1]
        tail = ' | '.join(l.strip() for l in text.strip().splitlines()[-3:])[:240]
        print(f"   {'FAIL' if err else 'OK  '}  {cmd}\n         -> {tail or '(no output)'}")
        ok &= not err
    for r in ran:
        if not any(r[0] == f'Bash: {c}' for c in cmds):
            print(f'   other tool use: {r[0][:120]} (error={r[1]})')
    # What the real commands leave in staging, as the runner's walk sees it.
    (stage / 'tsconfig.gate.json').unlink(missing_ok=True)
    live, now = R.manifest(R.MOD), R.manifest(stage)
    changed = sorted(k for k in set(live) | set(now) if live.get(k) != now.get(k))
    print(f'   staging vs live after the run: {len(changed)} path(s) differ: {changed[:8]}')
    print(f'   .claude left behind: {sorted(str(p.relative_to(stage)) for p in (stage / ".claude").rglob("*")) if (stage / ".claude").exists() else "none"}')
    print(f'   stage_problems: {R.stage_problems(stage)}')
    print(f'   allowlist: {R.allowlist_problems(stage)}')
    return ok


def hostile() -> bool:
    stage = stage_copy('hostile')
    build = stage / 'art/src/build.py'
    text = build.read_text()
    anchor = 'from __future__ import annotations\n'
    build.write_text(text.replace(anchor, anchor + PROBE_CODE, 1))
    art = ' '.join(R.ART_CMD)
    prompt = f'Use the Bash tool to run exactly this one command, then reply with its full output and nothing else:\n{art}'
    evs = run_phase('hostile', stage, prompt)
    ran = [r for r in tool_runs(evs) if r[0] == f'Bash: {art}']
    if not ran:
        print('   the art command was not run')
        return False
    lines = [l for l in ran[-1][2].splitlines() if l.startswith('PROBE ')]
    ok = bool(lines)
    for l in lines:
        expect_allowed = 'expected ALLOWED' in l
        allowed = '=> ALLOWED' in l
        good = allowed == expect_allowed
        ok &= good
        print(f"   {'ok ' if good else 'BAD'} {l[6:]}")
    print(f"   probe-cwd.txt in staging: {(stage / 'probe-cwd.txt').exists()}")
    return ok


def cleanup_outside() -> None:
    for p in OUTSIDE:
        if os.path.lexists(p):
            print(f'   removing probe artefact outside scratchpad: {p}')
            p.unlink()
    R.verify_tools()
    print('   tools digest still matches tools.sha256')


def main() -> int:
    PROBE.mkdir(exist_ok=True)
    print(json.dumps(R.sandbox_settings(PROBE / 'legit/jeb'), indent=1))
    phases = sys.argv[1:] or ['legit', 'hostile']
    ok = True
    try:
        if 'legit' in phases:
            ok &= legit()
        if 'hostile' in phases:
            ok &= hostile()
    finally:
        cleanup_outside()
    print('SANDBOX PROBE OK' if ok else 'SANDBOX PROBE FAILED')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
