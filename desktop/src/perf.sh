#!/bin/sh
# perf.sh: the alternating method (m.sh): none vs Jeb, 40 s each, with several live sessions
# (the real store), one idle session and three busy ones (scratch stores driven by jebgates fake).
cd "$(dirname "$0")"
[ -x ../gates/jebgates ] || sh ../gates/build.sh
export DUR=40
out=meas/p3.txt
mkdir -p meas test
echo "$(date +%H:%M:%S) start" >> $out
for i in 1 2 3 4 5 6; do dev/m.sh none >> $out 2>&1; dev/m.sh several >> $out 2>&1; done
../gates/jebgates fake $PWD/test/one.json 1 idle 1200 & f1=$!
for i in 1 2 3 4 5 6; do dev/m.sh none >> $out 2>&1; dev/m.sh one-idle JEB_STORE_PATH=$PWD/test/one.json >> $out 2>&1; done
kill $f1
../gates/jebgates fake $PWD/test/busy.json 3 busy 1200 & f2=$!
for i in 1 2 3; do dev/m.sh none >> $out 2>&1; dev/m.sh three-busy JEB_STORE_PATH=$PWD/test/busy.json >> $out 2>&1; done
kill $f2
echo "$(date +%H:%M:%S) done" >> $out
