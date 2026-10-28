"""jebhome.py: where Jeb's desktop state lives, and the one-time move from the old folder.

The state folder is ~/Library/Application Support/Jeb. Older installs keep it at ~/.claude/jeb-desktop until
migrate() moves it (the old path then stays behind as a symlink, so the running app, its rollback versions and the
LaunchAgents' log paths keep working). Shared by jebctl, updater.py and watchdog.py; the Swift app resolves the
same way in Heartbeat.swift. Stdlib only; paths are computed at call time so tests can point $HOME elsewhere.
"""
import fcntl, os, plistlib, shutil

LABEL_PREFIX = "com.jeb.desktop"


def new_path():
    return os.path.expanduser("~/Library/Application Support/Jeb")


def old_path():
    return os.path.expanduser("~/.claude/jeb-desktop")


def _real_dir(p):
    return os.path.isdir(p) and not os.path.islink(p)


def resolve():
    """JEB_HOME; else the new folder if it exists; else the old one if it is a real folder; else the new one."""
    env = os.environ.get("JEB_HOME")
    if env:
        return env
    new, old = new_path(), old_path()
    if os.path.exists(new):
        return new
    return old if _real_dir(old) else new


def _swap_prefix(v, old, new):
    if isinstance(v, str):
        return new + v[len(old):] if v == old or v.startswith(old + "/") else v
    if isinstance(v, list):
        return [_swap_prefix(x, old, new) for x in v]
    if isinstance(v, dict):
        return {k: _swap_prefix(x, old, new) for k, x in v.items()}
    return v


def _rewrite_plist(path, old, new):
    try:
        with open(path, "rb") as f:
            data = plistlib.load(f)
        if not isinstance(data, dict) or not str(data.get("Label", "")).startswith(LABEL_PREFIX):
            return False
        out = _swap_prefix(data, old, new)
        if out == data:
            return False
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            plistlib.dump(out, f)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
        return True
    except (OSError, ValueError, plistlib.InvalidFileException):
        return False


def _rewrite_plists(old, new):
    agents = os.environ.get("JEB_LAUNCHAGENTS") or os.path.expanduser("~/Library/LaunchAgents")
    for d in (os.path.join(new, "launchd"), agents):
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for n in names:
            if n.startswith(LABEL_PREFIX) and n.endswith(".plist"):
                _rewrite_plist(os.path.join(d, n), old, new)


def _link_back(old, new, log):
    """Symlink old -> new; if something recreated old as a real folder meanwhile, fold it into new first."""
    for _ in range(3):
        try:
            os.symlink(new, old)
            return True
        except FileExistsError:
            if not _real_dir(old):
                break
            aside = os.path.join(new, "migrate-leftovers")
            for n in os.listdir(old):
                dest = os.path.join(new, n)
                if os.path.lexists(dest):
                    os.makedirs(aside, exist_ok=True)
                    dest = os.path.join(aside, n)
                    if os.path.lexists(dest):
                        dest += ".%d" % os.getpid()
                os.rename(os.path.join(old, n), dest)
            try:
                os.rmdir(old)
            except OSError:
                pass
        except OSError:
            break
    log(f"could not link {old} to {new}; the new folder is used regardless")
    return False


def migrate(log, dry=False):
    """Move the old state folder to the new place once. Returns "n/a", "busy", "would move", "moved" or "failed"."""
    if os.environ.get("JEB_HOME"):
        return "n/a"
    new, old = new_path(), old_path()
    if not _real_dir(old) or os.path.lexists(new):
        return "n/a"
    if dry:
        log(f"would move the state folder {old} to {new}")
        return "would move"
    locks = []
    try:
        for n in ("updater.lock", "release.lock"):
            f = open(os.path.join(old, n), "a")
            locks.append(f)
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                log(f"state folder move postponed: {n} is held; the next run retries")
                return "busy"
        try:
            os.makedirs(os.path.dirname(new), exist_ok=True)
            os.rename(old, new)
        except OSError as e:
            log(f"could not move {old} to {new}: {e}")
            return "failed"
        _link_back(old, new, log)
        _rewrite_plists(old, new)
        log(f"moved the state folder to {new}; {old} now links there")
        return "moved"
    finally:
        for f in locks:
            f.close()
