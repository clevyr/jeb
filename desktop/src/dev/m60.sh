#!/bin/sh
# dev/m60.sh NAME [ENV=VALUE ...] | dev/m60.sh none: stops any running JebDesktop (only ever
# one), starts this build with the given env (JEB_NO_PAUSE=1 and a long idle pause by
# default), waits 8 s, then over 60 s: the app's CPU (cputime delta), RSS and
# footprint, WindowServer's cputime delta, and how much of the desktop showed (vis).
# "none" measures WindowServer with no Jeb at all, for the baseline.
cd "$(dirname "$0")/.."   # src/, where the binaries and meas/ live
name=$1; shift
mkdir -p meas
pkill -USR1 -x JebDesktop 2>/dev/null; perl -e 'select(undef,undef,undef,1.5)'
pgrep -x JebDesktop >/dev/null && { echo "a JebDesktop is still running; not measuring"; exit 1; }
ws=$(pgrep -x WindowServer)
secs() { echo "$1" | awk '{n=split($1,x,":"); print (n==3 ? x[1]*3600+x[2]*60+x[3] : x[1]*60+x[2])}'; }
if [ "$name" != none ]; then
  env JEB_NO_PAUSE=1 JEB_IDLE_SECONDS=100000 "$@" ${BIN:-./JebDesktop} 2> meas/$name.log &
  pid=$!
fi
perl -e 'select(undef,undef,undef,8)'
[ -n "$pid" ] && a=$(ps -o cputime= -p $pid)
w1=$(ps -o cputime= -p $ws)
./tools/vis 60 > meas/$name.vis &
vpid=$!
perl -e 'select(undef,undef,undef,60)'
w2=$(ps -o cputime= -p $ws)
wait $vpid
dws=$(echo "$(secs "$w2") $(secs "$w1")" | awk '{printf "%.2f", 100*($1-$2)/60}')
if [ -n "$pid" ]; then
  b=$(ps -o cputime= -p $pid); rss=$(ps -o rss= -p $pid)
  fp=$(footprint $pid 2>/dev/null | awk '/Footprint:/{sub(/.*Footprint: /, ""); print $1, $2; exit}')
  kill -USR1 $pid; wait $pid 2>/dev/null
  app=$(echo "$(secs "$b") $(secs "$a")" | awk '{printf "%.2f", 100*($1-$2)/60}')
  printf "%-22s app %5s%%  WS %6s%%  RSS %3d MB  footprint %-7s  %s  passes %s\n" "$name" "$app" "$dws" $((rss/1024)) "$fp" "$(cat meas/$name.vis)" "$(grep -o 'passes so far' meas/$name.log >/dev/null && grep -o '[0-9]* passes so far' meas/$name.log | tail -1)"
else
  printf "%-22s app     -   WS %6s%%  %s\n" "$name" "$dws" "$(cat meas/$name.vis)"
fi
