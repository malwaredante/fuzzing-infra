#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Industrial upgrade: AFL++ instrumented libs w/ dict2file, cmplog, corpus sync,
# watchdog, seed matrix. Resumable via markers in $STATE.
set -u
set -o pipefail

ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
INSTALL_AFL=$ROOT/install-afl
STATE=$ROOT/.upgrade_state
JOBS=$(nproc 2>/dev/null || echo 2)
DE265_VER=1.1.2
HEIF_VER=1.23.4
AFLCC=$SRC/AFLplusplus/afl-clang-lto
AFLCXX=$SRC/AFLplusplus/afl-clang-lto++
SAN="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1"

mkdir -p $STATE
phase() { [ -f "$STATE/$1.done" ] && { echo "== SKIP $1"; return 1; }; echo "== PHASE $1 $(date -Iseconds)"; return 0; }
mark() { touch "$STATE/$1.done"; echo "== DONE $1"; }

#########################################################################
if phase U1_webp; then
    mkdir -p $BUILD/afl-webp && cd $BUILD/afl-webp
    if [ ! -f $INSTALL_AFL/lib/libsharpyuv.a ]; then
        [ -f build.ninja ] || cmake -G Ninja -S $SRC/libwebp-1.6.0 -B . \
            -DCMAKE_C_COMPILER=$AFLCC -DCMAKE_CXX_COMPILER=$AFLCXX \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
            -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_CWEBP=OFF \
            -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
            -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_EXTRAS=OFF \
            -DCMAKE_INSTALL_PREFIX=$INSTALL_AFL
        ninja -j$JOBS
        ninja install
    fi
    mark U1_webp
fi

#########################################################################
if phase U2_dict2file_libs; then
    # rebuild de265+heif under afl-clang-lto with automatic dictionary extraction
    export AFL_LLVM_DICT2FILE=$ROOT/auto.dict
    export AFL_LLVM_DICT2FILE_NO_MAIN=1
    : > $ROOT/auto.dict
    for lib in "de265 libde265-$DE265_VER" "heif libheif-$HEIF_VER"; do
        set -- $lib; name=$1; srcdir=$2
        rm -rf $BUILD/afl-$name; mkdir -p $BUILD/afl-$name; cd $BUILD/afl-$name
        EXTRA=""
        [ $name = heif ] && EXTRA="-DWITH_LIBDE265=ON -DWITH_AOM_DECODER=OFF -DWITH_AOM_ENCODER=OFF -DWITH_X265=OFF -DWITH_LIBJPEG=OFF -DWITH_LIBPNG=OFF -DWITH_OPENJPEG=OFF -DWITH_OpenH264=OFF -DWITH_VVENC=OFF -DWITH_VVDEC=OFF -DWITH_SvtEnc=OFF -DWITH_RAV1E=OFF -DWITH_DAV1D=OFF -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF -DBUILD_TESTING=OFF -DENABLE_PLUGIN_LOADING=OFF -Dlibde265_DIR=$INSTALL_AFL/lib/cmake/libde265"
        cmake -G Ninja -S $SRC/$srcdir -B . \
            -DCMAKE_C_COMPILER=$AFLCC -DCMAKE_CXX_COMPILER=$AFLCXX \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
            -DBUILD_SHARED_LIBS=OFF \
            -DCMAKE_PREFIX_PATH=$INSTALL_AFL -DCMAKE_INSTALL_PREFIX=$INSTALL_AFL $EXTRA
        ninja -j$JOBS
        ninja install
    done
    sort -u $ROOT/auto.dict -o $ROOT/auto.dict 2>/dev/null || true
    cat $ROOT/heif.dict $ROOT/auto.dict 2>/dev/null | sort -u > $ROOT/heif_merged.dict
    echo "[+] auto.dict entries: $(wc -l < $ROOT/auto.dict 2>/dev/null || echo 0)"
    unset AFL_LLVM_DICT2FILE AFL_LLVM_DICT2FILE_NO_MAIN
    mark U2_dict2file_libs
fi

#########################################################################
if phase U3_afl_bins; then
    export PKG_CONFIG_PATH=$INSTALL_AFL/lib/pkgconfig
    mkdir -p $ROOT/afl
    DRV=$SRC/AFLplusplus/libAFLDriver.a
    for t in heif_box heif_decode libde265; do
        case $t in
            heif_box|heif_decode) INC="-I$INSTALL_AFL/include -I$INSTALL_AFL/include/libheif"; LIBS="$(pkg-config --static --libs libheif libde265 libsharpyuv)";;
            libde265) INC="-I$INSTALL_AFL/include -I$INSTALL_AFL/include/libde265"; LIBS="$(pkg-config --static --libs libde265)";;
        esac
        $AFLCXX -O1 -g $SAN $INC -o $ROOT/afl/${t}_fuzzer_afl \
            $ROOT/${t}_fuzzer_harness.cpp $DRV $LIBS -pthread -lm || echo "afl link failed: $t"
    done
    # cmplog build of the primary target (redqueen input-to-state solving)
    AFL_LLVM_CMPLOG=1 $AFLCXX -O1 -g $SAN \
        -I$INSTALL_AFL/include -I$INSTALL_AFL/include/libheif \
        -o $ROOT/afl/heif_decode_fuzzer_cmplog \
        $ROOT/heif_decode_fuzzer_harness.cpp $DRV \
        $(pkg-config --static --libs libheif libde265 libsharpyuv) -pthread -lm \
        || echo "cmplog build failed"
    for b in $ROOT/afl/*_afl $ROOT/afl/*_cmplog; do
        [ -x "$b" ] && echo "[+] $b"
    done
    mark U3_afl_bins
fi

#########################################################################
if phase U4_seed_matrix; then
    cd $ROOT
    # richer h265 seed matrix: sizes, bit depth, bframes, gop, rc modes
    i=0
    for px in 32 96 160 320; do
        for opt in "" "bframes=0" "keyint=8:min-keyint=2" "crf=35" "bitrate=50" "tune=zerolatency"; do
            i=$((i+1))
            ffmpeg -y -loglevel error -f lavfi -i "testsrc2=size=${px}x${px}:rate=10" \
                -t 0.4 -pix_fmt yuv420p -c:v libx265 -x265-params "log-level=error:$opt" \
                -f hevc corpus_h265_min/mx_${i}.h265 2>/dev/null || true
        done
    done
    # 10-bit streams (libde265 supports up to 12-bit)
    ffmpeg -y -loglevel error -f lavfi -i "testsrc2=size=64x64:rate=8" -t 0.4 \
        -pix_fmt yuv420p10le -c:v libx265 -x265-params log-level=error -f hevc \
        corpus_h265_min/mx_10bit.h265 2>/dev/null || true
    ffmpeg -y -loglevel error -f lavfi -i "mandelbrot=size=96x96:rate=6" -t 0.4 \
        -pix_fmt yuv420p -c:v libx265 -x265-params log-level=error:lossless=1 -f hevc \
        corpus_h265_min/mx_lossless.h265 2>/dev/null || true
    echo "h265 corpus: $(ls corpus_h265_min | wc -l) files"
    mark U4_seed_matrix
fi

#########################################################################
if phase U5_ops; then
    cd $ROOT
    chmod +x sync_corpus.sh watchdog.sh triage.sh
    cp -f fuzz-watchdog.service fuzz-watchdog.timer /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now fuzz-watchdog.timer 2>/dev/null || true
    # corpus sync loop
    pkill -f "bash $ROOT/sync_corpus.sh" 2>/dev/null || true
    nohup bash $ROOT/sync_corpus.sh > /dev/null 2>&1 &
    mark U5_ops
fi

#########################################################################
if phase U6_relaunch; then
    # restart libFuzzer set cleanly (new sancov bins as parents too)
    bash $ROOT/start_fuzzers.sh
    # AFL++ engine on the primary target alongside (foreign-sync -F into its corpus)
    [ -x $ROOT/afl/heif_decode_fuzzer_afl ] && bash $ROOT/start_afl.sh
    mark U6_relaunch
fi

echo "== UPGRADE COMPLETE $(date -Iseconds)"
