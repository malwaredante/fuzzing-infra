#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Bleeding-edge refresh: pull upstream master, incremental rebuild, restart master scope.
# Runs via fuzz-refresh.timer. Idempotent — no-op when upstream didn't move.
set -u
ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
INSTALL_M=$ROOT/install-master
LOG=$ROOT/refresh.log
JOBS=$(nproc 2>/dev/null || echo 2)

CXX_BIN=$(command -v clang++-20 || command -v clang++)
FUZZ="-fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g -O1"
export PKG_CONFIG_PATH=$INSTALL_M/lib/pkgconfig

changed=0
for repo in libheif-master libde265-master; do
    cd $SRC/$repo 2>/dev/null || continue
    old=$(git rev-parse HEAD 2>/dev/null) || continue
    git fetch -q origin master 2>/dev/null && git merge --ff-only -q origin/master 2>/dev/null
    new=$(git rev-parse HEAD 2>/dev/null) || continue
    if [ "$old" != "$new" ]; then
        echo "$(date -Is) [refresh] $repo ${old:0:9} -> ${new:0:9}" >> $LOG
        changed=1
    fi
done

if [ $changed -eq 0 ]; then
    echo "$(date -Is) [refresh] upstream unchanged" >> $LOG
    exit 0
fi

rebuild_dir() {
    [ -d $BUILD/$1 ] || return 0
    (cd $BUILD/$1 && nice -n 10 ninja -j$JOBS >> $LOG 2>&1 && ninja install >> $LOG 2>&1) \
        && echo "$(date -Is) [refresh] rebuilt $1" >> $LOG
}

rebuild_dir m-de265
if [ -d $BUILD/heif-master-codec ]; then
    rebuild_dir heif-master-codec
else
    rebuild_dir m-heif
fi

cd $ROOT
LIBS="$(pkg-config --static --libs libheif libde265) -pthread -lm"
for t in heif_decode heif_box heif_meta heif_seq heif_roundtrip; do
    [ -f $ROOT/${t}_fuzzer_harness.cpp ] || continue
    $CXX_BIN $FUZZ -I$INSTALL_M/include -I$INSTALL_M/include/libheif \
        -o $ROOT/${t}_fuzzer_master $ROOT/${t}_fuzzer_harness.cpp $LIBS >> $LOG 2>&1 \
        && echo "$(date -Is) [refresh] rebuilt ${t}_fuzzer_master" >> $LOG
done
$CXX_BIN $FUZZ -I$INSTALL_M/include -I$INSTALL_M/include/libde265 \
    -o $ROOT/libde265_fuzzer_master $ROOT/libde265_fuzzer_harness.cpp \
    $(pkg-config --static --libs libde265) -pthread -lm >> $LOG 2>&1 \
    && echo "$(date -Is) [refresh] rebuilt libde265_fuzzer_master" >> $LOG

echo "$(date -Is) [refresh] restarting fuzz-master scope" >> $LOG
bash $ROOT/start_master.sh >> $LOG 2>&1
echo "$(date -Is) [refresh] DONE" >> $LOG
