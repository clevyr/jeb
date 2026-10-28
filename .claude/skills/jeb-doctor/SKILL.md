---
name: jeb-doctor
description: Diagnose a Jeb install on this Mac (app, LaunchAgents, plugin registration, store, updates) and explain how to fix problems. Use when Jeb looks broken, is not showing up, or the user asks for a health check.
---

# Jeb doctor

1. From the clone (the folder holding `install` and `desktop/`), run `desktop/jebctl doctor`. It is read-only. Each line is `ok` or `FIX <what>: <fix>`, and it ends with `all good` or `N problem(s)`.
2. Explain each `FIX` line in plain words: what is wrong and what the fix does.
3. Offer, and ask first before running, the safe fixes the output names:
   - `desktop/jebctl start` (the desktop was quit from the menu, or is not running);
   - `desktop/jebctl resume-updates` (updates are paused);
   - `./install` (missing app, LaunchAgents or plugin registration; run with no flags).
   Do not run anything else to fix a problem without the user's approval.
4. If more detail is needed, read `~/.claude/jeb-desktop/update.log` and `~/.claude/jeb-desktop/watchdog.log`. Point to logs by path only.
5. Never read or quote `~/.claude/jeb-desktop/run.log` beyond lines containing "no usable art", "exited", "ROLLBACK" or "REJECTED".

## Rules

- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- After a fix, run `desktop/jebctl doctor` again and report the result.
