#!/bin/sh
# dev/m.sh NAME [ENV=VALUE ...] | dev/m.sh none: as dev/m60.sh, over DUR seconds (default 60), and
# also the seconds the app saw its window in view. Only ever one JebDesktop.
cd "$(dirname "$0")/.."   # src/, where the binaries and meas/ live
DUR=${DUR:-60}
name=$1; shift
mkdir -p meas
pkill -USR1 -x JebDesktop 2>/dev/null; perl -e 'select(undef,undef,undef,1.5)'
pgrep -x JebDesktop >/dev/null && { echo "a JebDesktop is still running; not measuring"; exit 1; }
ws=$(pgrep -x WindowServer); pid=
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}'; }
secs() { echo "$1" | awk '{n=split($1,x,":"); print (n==3 ? x[1]*3600+x[2]*60+x[3] : x[1]*60+x[2])}'; }
if [ "$name" != none ]; then
  env JEB_NO_PAUSE=1 JEB_IDLE_SECONDS=100000 "$@" ${BIN:-./JebDesktop} 2> meas/$name.log &
  pid=$!
fi
perl -e 'select(undef,undef,undef,8)'
[ -n "$pid" ] && a=$(ps -o cputime= -p $pid)
w1=$(ps -o cputime= -p $ws)
./tools/vis $DUR > meas/$name.vis &
vpid=$!
perl -e "select(undef,undef,undef,$DUR)"
w2=$(ps -o cputime= -p $ws)
wait $vpid
dws=$(echo "$(secs "$w2") $(secs "$w1")" | awk -v d=$DUR '{printf "%.2f", 100*($1-$2)/d}')
if [ -n "$pid" ]; then
  b=$(ps -o cputime= -p $pid); rss=$(ps -o rss= -p $pid)
  fp=$(footprint $pid 2>/dev/null | awk '/Footprint:/{sub(/.*Footprint: /, ""); print $1, $2; exit}')
  kill -USR1 $pid; wait $pid 2>/dev/null
  app=$(echo "$(secs "$b") $(secs "$a")" | awk -v d=$DUR '{printf "%.2f", 100*($1-$2)/d}')
  inview=$(grep -o "[0-9]* layers animated; paused [0-9]* s, in view [0-9]* s, of [0-9]* s" meas/$name.log | head -1)
  printf "%-20s app %5s%%  WS %6s%%  RSS %3d MB  fp %-6s  %s | %s | idle %ss\n" "$name" "$app" "$dws" $((rss/1024)) "$fp" "$inview" "$(cat meas/$name.vis)" "$(idle)"
else
  printf "%-20s app     -   WS %6s%%  %s | idle %ss\n" "$name" "$dws" "$(cat meas/$name.vis)" "$(idle)"
fi
