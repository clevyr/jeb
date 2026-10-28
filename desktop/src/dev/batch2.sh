#!/bin/sh
cd "$(dirname "$0")/.."   # src/, where the binaries and meas/ live
export DUR=30
{
dev/m.sh none
dev/m.sh static JEB_ANIMS=x JEB_NO_PASSES=1
dev/m.sh jeb-only JEB_ANIMS=jeb JEB_NO_PASSES=1
dev/m.sh clouds-only JEB_ANIMS=clouds JEB_NO_PASSES=1
dev/m.sh smoke-only JEB_ANIMS=smoke JEB_NO_PASSES=1
dev/m.sh leaves-only JEB_ANIMS=leaves JEB_NO_PASSES=1
dev/m.sh all-calm30 JEB_NO_PASSES=1
dev/m.sh all-calm10 JEB_NO_PASSES=1 JEB_CALM_FPS=10
dev/m.sh jeb-only-px JEB_ANIMS=jeb JEB_NO_PASSES=1 JEB_CALM_MOTION=pixel
dev/m.sh none
} > meas/batch2.txt 2>&1
echo done >> meas/batch2.txt
