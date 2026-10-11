#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Master-branch upgrade: build libde265 + libheif from git HEAD into install-master
# with sancov+ASan+UBSan, then build master fuzzer binaries (+ new harnesses).
# Resumable via markers in $STATE.
set -u
set -o pipefail

ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
INSTALL_M=$ROOT/install-master
STATE=$ROOT/.master_state
JOBS=$(nproc 2>/dev/null || echo 2)
SAN="-fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer -g -O1"
FUZZ="-fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g -O1"

mkdir -p $STATE
phase() { [ -f "$STATE/$1.done" ] && { echo "== SKIP $1"; return 1; }; echo "== PHASE $1 $(date -Iseconds)"; return 0; }
mark() { touch "$STATE/$1.done"; echo "== DONE $1"; }

source $ROOT/.setup_state/toolchain.env

#########################################################################
if phase M1_clone; then
    cd $SRC
    [ -d libde265-master ] || git clone --depth 1 https://github.com/strukturag/libde265 libde265-master
    [ -d libheif-master ]  || git clone --depth 1 https://github.com/strukturag/libheif  libheif-master
    cd libde265-master && git log --oneline -1
    cd $SRC/libheif-master && git log --oneline -1
    mark M1_clone
fi

#########################################################################
if phase M2_libs; then
    mkdir -p $INSTALL_M
    rm -rf $BUILD/m-de265; mkdir -p $BUILD/m-de265; cd $BUILD/m-de265
    cmake -G Ninja -S $SRC/libde265-master -B . \
        -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
        -DBUILD_SHARED_LIBS=OFF -DENABLE_SDL=OFF -DENABLE_DECODER=OFF \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_M || \
    cmake -G Ninja -S $SRC/libde265-master -B . \
        -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_M
    ninja -j$JOBS && ninja install

    rm -rf $BUILD/m-heif; mkdir -p $BUILD/m-heif; cd $BUILD/m-heif
    cmake -G Ninja -S $SRC/libheif-master -B . \
        -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWITH_LIBDE265=ON -DWITH_AOM_DECODER=OFF -DWITH_AOM_ENCODER=OFF \
        -DWITH_X265=OFF -DWITH_LIBJPEG=OFF -DWITH_LIBPNG=OFF \
        -DWITH_OPENJPEG=OFF -DWITH_OpenH264=OFF -DWITH_VVENC=OFF -DWITH_VVDEC=OFF \
        -DWITH_SvtEnc=OFF -DWITH_RAV1E=OFF -DWITH_DAV1D=OFF -DWITH_EXAMPLES=OFF \
        -DWITH_GDK_PIXBUF=OFF -DBUILD_TESTING=OFF -DENABLE_PLUGIN_LOADING=OFF \
        -Dlibde265_DIR=$INSTALL_M/lib/cmake/libde265 \
        -DCMAKE_PREFIX_PATH=$INSTALL_M -DCMAKE_INSTALL_PREFIX=$INSTALL_M
    ninja -j$JOBS && ninja install
    mark M2_libs
fi

export PKG_CONFIG_PATH=$INSTALL_M/lib/pkgconfig

#########################################################################
if phase M3_bins; then
    cd $ROOT
    for t in heif_box heif_decode libde265; do
        case $t in
            heif_box|heif_decode) INC="-I$INSTALL_M/include -I$INSTALL_M/include/libheif"; LIBS="$(pkg-config --static --libs libheif libde265)";;
            libde265) INC="-I$INSTALL_M/include -I$INSTALL_M/include/libde265"; LIBS="$(pkg-config --static --libs libde265)";;
        esac
        $CXX_BIN $FUZZ $INC -o $ROOT/${t}_fuzzer_master \
            $ROOT/${t}_fuzzer_harness.cpp $LIBS -pthread -lm || echo "master build failed: $t"
    done
    # extra harnesses (compile only those present)
    for h in heif_roundtrip heif_meta; do
        [ -f $ROOT/${h}_fuzzer_harness.cpp ] || continue
        $CXX_BIN $FUZZ -I$INSTALL_M/include -I$INSTALL_M/include/libheif \
            -o $ROOT/${h}_fuzzer_master $ROOT/${h}_fuzzer_harness.cpp \
            $(pkg-config --static --libs libheif libde265) -pthread -lm \
            || echo "master build failed: $h"
    done
    ls -la $ROOT/*_fuzzer_master
    mark M3_bins
fi

echo "== MASTER UPGRADE COMPLETE $(date -Iseconds)"
