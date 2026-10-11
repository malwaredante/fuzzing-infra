#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Codec upgrade: dav1d (AV1 decode) + x265 (HEVC encode) under master sanitizer stack.
# Unlocks the dead AVIF decode path and the encoder/roundtrip surface — both
# minimally covered by upstream fuzzing.
set -u
ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
INSTALL_M=$ROOT/install-master
STATE=$ROOT/.codec_state
JOBS=$(nproc 2>/dev/null || echo 2)

mkdir -p $STATE
mark() { touch $STATE/$1; }
phase() { [ -f $STATE/$1 ] && return 1 || return 0; }

CXX_BIN=$(command -v clang++-20 || command -v clang++)
CLANG_BIN="${CXX_BIN/++/}"
SAN="-fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer -g -O1"
export CC=$CLANG_BIN CXX=$CXX_BIN
export CFLAGS="$SAN" CXXFLAGS="$SAN" LDFLAGS="-fsanitize=address,undefined"
export PKG_CONFIG_PATH=$INSTALL_M/lib/pkgconfig:$INSTALL_M/lib/x86_64-linux-gnu/pkgconfig

echo "[codec] toolchain: $CXX_BIN"

if phase C1_deps; then
    apt-get update -qq && apt-get install -y -qq meson nasm ninja-build pkg-config
    mark C1_deps
fi

if phase C2_dav1d; then
    cd $SRC
    [ -d dav1d ] || git clone --depth 1 --branch 1.5.1 \
        https://code.videolan.org/videolan/dav1d.git dav1d \
        || git clone --depth 1 https://code.videolan.org/videolan/dav1d.git dav1d
    rm -rf $BUILD/dav1d-codec && meson setup $BUILD/dav1d-codec dav1d \
        --prefix=$INSTALL_M --libdir=lib --buildtype=release \
        -Ddefault_library=static -Denable_tools=false -Denable_tests=false \
        -Denable_examples=false
    nice -n 10 ninja -C $BUILD/dav1d-codec -j$JOBS && ninja -C $BUILD/dav1d-codec install
    mark C2_dav1d
fi

if phase C3_x265; then
    cd $SRC
    [ -d x265 ] || { git clone --depth 1 https://bitbucket.org/multicoreware/x265_git.git x265 || true; }
    if [ -d x265 ]; then
        mkdir -p $BUILD/x265-codec && cd $BUILD/x265-codec
        cmake -G Ninja $SRC/x265/source \
            -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
            -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
            -DCMAKE_INSTALL_PREFIX=$INSTALL_M \
            -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=OFF
        nice -n 10 ninja -j$JOBS && ninja install
        mark C3_x265
    else
        echo "[codec] x265 clone failed, skipping encoder"
    fi
fi

if phase C4_heif; then
    DAV1D_FLAG=OFF
    [ -f $INSTALL_M/lib/pkgconfig/dav1d.pc ] && DAV1D_FLAG=ON
    X265_FLAG=OFF
    [ -f $INSTALL_M/lib/pkgconfig/x265.pc ] && X265_FLAG=ON
    echo "[codec] heif rebuild: DAV1D=$DAV1D_FLAG X265=$X265_FLAG"
    mkdir -p $BUILD/heif-master-codec && cd $BUILD/heif-master-codec
    cmake -G Ninja $SRC/libheif-master \
        -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
        -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
        -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" \
        -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined" \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DWITH_LIBDE265=ON -DWITH_AOM_DECODER=OFF -DWITH_AOM_ENCODER=OFF \
        -DWITH_X265=$X265_FLAG -DWITH_DAV1D=$DAV1D_FLAG \
        -DWITH_LIBJPEG=OFF -DWITH_LIBPNG=OFF -DWITH_OPENJPEG=OFF \
        -DWITH_OpenH264=OFF -DWITH_VVDEC=OFF -DWITH_VVENC=OFF \
        -DWITH_SvtEnc=OFF -DWITH_RAV1E=OFF -DWITH_EXAMPLES=OFF \
        -DWITH_GDK_PIXBUF=OFF -DBUILD_TESTING=OFF -DENABLE_PLUGIN_LOADING=OFF \
        -Dlibde265_DIR=$INSTALL_M/lib/cmake/libde265 \
        -DCMAKE_PREFIX_PATH=$INSTALL_M -DCMAKE_INSTALL_PREFIX=$INSTALL_M
    nice -n 10 ninja -j$JOBS && ninja install
    mark C4_heif
fi

if phase C5_bins; then
    cd $ROOT
    FUZZ="-fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g -O1"
    LIBS="$(pkg-config --static --libs libheif libde265) -pthread -lm"
    for t in heif_decode heif_box heif_meta heif_seq heif_roundtrip; do
        [ -f $ROOT/${t}_fuzzer_harness.cpp ] || continue
        $CXX_BIN $FUZZ -I$INSTALL_M/include -I$INSTALL_M/include/libheif \
            -o $ROOT/${t}_fuzzer_master $ROOT/${t}_fuzzer_harness.cpp $LIBS \
            || echo "rebuild failed: $t"
    done
    ls -la $ROOT/*_fuzzer_master
    mark C5_bins
fi

echo "[codec] DONE"
