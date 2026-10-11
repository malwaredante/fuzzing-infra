#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# MSan (MemorySanitizer) build of libde265 master — catches use-of-uninitialized-value.
# libde265 is self-contained (no external codec deps) so a pure-MSan build is clean.
# Markers in .msan_state let the script resume after interruption.
set -u
ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
INSTALL_MSAN=$ROOT/install-msan
STATE=$ROOT/.msan_state
JOBS=$(nproc 2>/dev/null || echo 2)

mkdir -p $STATE
mark() { touch $STATE/$1; }
phase() { [ -f $STATE/$1 ] && return 1 || return 0; }

CXX_BIN=$(command -v clang++-20 || command -v clang++)
CLANG_BIN="${CXX_BIN/++/}"
MSAN="-fsanitize=memory -fsanitize-memory-track-origins=2 -fPIE -fno-omit-frame-pointer -g -O1"

echo "[msan] using $CXX_BIN, $JOBS jobs"

if phase M1_lib; then
    mkdir -p $BUILD/de265-msan && cd $BUILD/de265-msan
    cmake -G Ninja $SRC/libde265-master \
        -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
        -DCMAKE_C_FLAGS="$MSAN" -DCMAKE_CXX_FLAGS="$MSAN" \
        -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=memory -pie" \
        -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=memory" \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_MSAN \
        -DBUILD_SHARED_LIBS=OFF -DENABLE_SDL=OFF -DENABLE_DECODER=OFF
    nice -n 10 ninja -j$JOBS && ninja install
    mark M1_lib
fi

if phase M2_bin; then
    cd $ROOT
    export PKG_CONFIG_PATH=$INSTALL_MSAN/lib/pkgconfig
    $CXX_BIN -fsanitize=fuzzer,memory -fsanitize-memory-track-origins=2 \
        -fPIE -pie -fno-omit-frame-pointer -g -O1 \
        -I$INSTALL_MSAN/include -I$INSTALL_MSAN/include/libde265 \
        -o $ROOT/libde265_fuzzer_msan $ROOT/libde265_fuzzer_harness.cpp \
        $(pkg-config --static --libs libde265) -pthread -lm \
        && mark M2_bin
fi

if phase M3_replay; then
    cd $ROOT
    mkdir -p msan_reports
    export MSAN_OPTIONS="halt_on_error=0:exit_code=86:print_stacktrace=1:symbolize=1"
    # replay the known F-002 input first
    if [ -f crash_de265_master/crash-82704a4cdb3c32ad5663cf2089d6140ea5e8b8e8 ]; then
        timeout 120 ./libde265_fuzzer_msan \
            crash_de265_master/crash-82704a4cdb3c32ad5663cf2089d6140ea5e8b8e8 \
            > msan_reports/f002_replay.log 2>&1
        echo "F-002 replay exit=$?" >> msan_reports/f002_replay.log
    fi
    # corpus scan — each file in its own process so one report doesn't kill the rest
    i=0
    for f in $(find $ROOT/corpus_h265_min -type f | head -3000); do
        i=$((i+1))
        out=$(timeout 60 ./libde265_fuzzer_msan "$f" 2>&1 | grep -A30 'WARNING: MemorySanitizer')
        if [ -n "$out" ]; then
            sig=$(echo "$out" | grep -oE '[a-z_]+\.cc:[0-9]+' | head -1)
            echo "$f :: $sig" >> msan_reports/msan_hits.txt
            echo "$out" > "msan_reports/$(basename $f).log"
        fi
        [ $((i % 200)) -eq 0 ] && echo "[msan] scanned $i files" >> msan_reports/progress.txt
    done
    mark M3_replay
fi

echo "[msan] DONE"
