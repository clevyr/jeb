#!/bin/sh
# gate3.sh: waits (up to 14 h) for the owner to be back (display awake, unlocked), then:
# 1) the live instance with the store-latency log and the Space watcher, for 60 min of natural use;
# 2) the alternating performance runs (perf.sh); 3) the live instance again, no extra logging.
cd "$(dirname "$0")/.."   # src/, where the binaries and meas/ live
log=meas/gate3.txt
end=$(( $(date +%s) + 50400 ))
until tools/awake; do
  [ $(date +%s) -ge $end ] && { echo "$(date +%T) gave up waiting" >> $log; exit 1; }
  perl -e 'select(undef,undef,undef,15)'
done
echo "$(date +%T) owner back" >> $log
perl -e 'select(undef,undef,undef,60)'
JEB_LATENCY_LOG=1 dev/run-live.sh >> $log 2>&1
mkdir -p runs/p3-live
WATCH_MAX_SHEETS=0 ./watch runs/p3-live > /dev/null 2>> runs/p3-live/watch.err &
w=$!
perl -e 'select(undef,undef,undef,3600)'
kill -INT $w; wait $w 2>/dev/null
python3 -I dev/analyze.py runs/p3-live >> $log 2>&1
echo "$(date +%T) perf" >> $log
./perf.sh
echo "$(date +%T) perf done" >> $log
dev/run-live.sh >> $log 2>&1
perl -e 'select(undef,undef,undef,20)'
echo "$(date +%T) live $(cat live.pid)" >> $log
