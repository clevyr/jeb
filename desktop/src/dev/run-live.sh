#!/bin/sh
# run-live.sh: (re)starts the one live JebDesktop (phase-2 Core Animation build: one window per
# desktop Space). If one is running, the new one takes over from it once it has its own
# window on a desktop Space (the old one keeps the desktop covered until then); otherwise
# it starts fresh. The app keeps its pid in live.pid. Stop it with: kill "$(cat live.pid)"
cd "$(dirname "$0")/.."   # src/, where the binaries and meas/ live
if [ -f live.pid ] && kill -0 "$(cat live.pid)" 2>/dev/null; then
  JEB_HANDOFF_FROM="$(cat live.pid)" JEB_PID_FILE="$PWD/live.pid" nohup ./JebDesktop >/dev/null 2>> run-live.log &
  echo "started $! to take over from $(cat live.pid) on the next desktop visit"
else
  pkill -x JebDesktop 2>/dev/null # never two at once
  JEB_PID_FILE="$PWD/live.pid" nohup ./JebDesktop >/dev/null 2>> run-live.log &
  echo $! > live.pid
  echo "live PID $(cat live.pid)"
fi
