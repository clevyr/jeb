"""plugdirs.py: the shared settings.json edit for ./install and ./uninstall.

CLAUDE_CODE_PLUGIN_DIRS (the settings "env" block) is a list of plugin folders. Claude Code splits it with
Node's path.delimiter, which is ":" on macOS (confirmed in the claude binary: split(delimiter) over the
value, each entry trimmed, "~" expanded, absolute paths only). Entries are compared after expanduser/normpath.
"""
import json, os, shutil, stat, time

KEY = "CLAUDE_CODE_PLUGIN_DIRS"


def settings_path():
    return os.environ.get("JEB_SETTINGS") or os.path.expanduser("~/.claude/settings.json")


def backup_dir():
    return os.environ.get("JEB_BACKUPS") or os.path.expanduser("~/.claude/backups/jeb")


def norm(p):
    return os.path.normpath(os.path.abspath(os.path.expanduser(p.strip())))


def same(a, b):
    """Same folder: equal after expanduser/normpath, or the same inode (macOS volumes ignore case)."""
    a, b = norm(a), norm(b)
    try:
        return a == b or os.path.samefile(a, b)
    except OSError:
        return False


def load(path):
    if not os.path.exists(path):
        return {}
    try:
        data = json.load(open(path))
    except ValueError as e:
        raise SystemExit(f"{path} is not valid JSON ({e}); fix it first, nothing changed")
    if not isinstance(data, dict):
        raise SystemExit(f"{path} is not a JSON object; nothing changed")
    return data


def current(data):
    env = data.get("env")
    if env is None:
        return None
    if not isinstance(env, dict):
        raise SystemExit('settings "env" is not an object; nothing changed')
    v = env.get(KEY)
    if v is not None and not isinstance(v, str):
        raise SystemExit(f"{KEY} is not a string in settings; nothing changed")
    return v


def plan(value, mod, remove):
    """(action, new_value): action is set | append | keep | remove | drop | absent; new_value None means delete the key."""
    parts = [e for e in (value or "").split(os.pathsep) if e.strip()]
    mine = [e for e in parts if same(e, mod)]
    if remove:
        if not mine:
            return "absent", value
        rest = [e for e in parts if e not in mine]
        return ("remove", os.pathsep.join(rest)) if rest else ("drop", None)
    if mine:
        return "keep", value
    if not parts:
        return "set", mod
    return "append", os.pathsep.join(parts + [mod])


def backup(path):
    os.makedirs(backup_dir(), mode=0o700, exist_ok=True)
    dest = os.path.join(backup_dir(), "settings." + time.strftime("%Y%m%d-%H%M%S") + ".json")
    shutil.copy2(path, dest)
    return dest


def edit(mod, remove, dry, say):
    """Adds (or removes) mod in the settings' CLAUDE_CODE_PLUGIN_DIRS. Backs up first when it writes."""
    path = settings_path()
    data = load(path)
    action, new = plan(current(data), mod, remove)
    say(f"settings {path}: {KEY} {action}" + (f" -> {new}" if new else ""))
    if action in ("keep", "absent"):
        return action
    if dry:
        say("  (dry run: not written)")
        return action
    if os.path.exists(path):
        say("  backup: " + backup(path))
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    env = data.get("env") if isinstance(data.get("env"), dict) else {}     # a null env counts as missing
    data["env"] = env
    if new is None:
        del env[KEY]
        if not env:
            del data["env"]
    else:
        env[KEY] = new
    real = os.path.realpath(path)       # a symlinked settings.json stays a symlink; the target is rewritten
    tmp = real + ".jeb-tmp"
    try:
        os.unlink(tmp)                  # a stale (or planted) temp file never gets written through
    except FileNotFoundError:
        pass
    mode = stat.S_IMODE(os.stat(real).st_mode) if os.path.exists(real) else 0o600
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.fchmod(fd, mode)             # the original's mode before any content is written
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, real)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return action
