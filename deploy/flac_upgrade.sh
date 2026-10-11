#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# AOSP external/flac (Android's libFLAC) — standalone build under sancov+ASan+UBSan.
set -u
ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
INSTALL_F=$ROOT/install-flac
STATE=$ROOT/.flac_state
JOBS=$(nproc 2>/dev/null || echo 2)
mkdir -p $STATE
mark() { touch $STATE/$1; }
phase() { [ -f $STATE/$1 ] && return 1 || return 0; }

CLANG_BIN=$(command -v clang-20 || command -v clang)
CXX_BIN=$(command -v clang++-20 || command -v clang++ || command -v g++)
SAN="-fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer -g -O1"

if phase F1_lib; then
    mkdir -p $BUILD/flac-aosp && cd $BUILD/flac-aosp
    cmake -G Ninja $SRC/flac-aosp \
        -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
        -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
        -DBUILD_DOCS=OFF -DWITH_OGG=OFF -DINSTALL_MANPAGES=OFF \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_F
    nice -n 10 ninja -j$JOBS && ninja install || { echo "[flac] F1 build failed"; exit 1; }
    mark F1_lib
fi

if phase F2_bin; then
    cd $ROOT
    export PKG_CONFIG_PATH=$INSTALL_F/lib/pkgconfig
    ${CLANG_BIN} -fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g -O1 \
        -I$INSTALL_F/include -o $ROOT/flac_fuzzer $ROOT/flac_fuzzer_harness.c \
        $INSTALL_F/lib/libFLAC.a -pthread -lm && mark F2_bin
fi

if phase F3_seeds; then
    mkdir -p $ROOT/corpus_flac $ROOT/crash_flac
    if command -v ffmpeg >/dev/null; then
        for i in 1 2 3; do
            ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=$((300*i*7)):duration=0.3" \
                -f lavfi -i "anoisesrc=d=0.2:c=pink" \
                -filter_complex amerge -c:a flac $ROOT/corpus_flac/seed$i.flac 2>/dev/null || true
        done
        ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=440:duration=0.2" \
            -c:a flac -compression_level 12 $ROOT/corpus_flac/seed_hc.flac 2>/dev/null || true
    fi
    printf 'fLaC\x00\x00\x00\x22' > $ROOT/corpus_flac/magic.bin
    mark F3_seeds
fi
echo "[flac] DONE"
