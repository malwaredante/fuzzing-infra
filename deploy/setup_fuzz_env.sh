#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Provisions a top-tier media-codec fuzzing environment on a fresh Ubuntu VPS.
# Resumable: completed phases are marked in $STATE and skipped on re-run.
set -e
set -o pipefail

ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
INSTALL=$ROOT/install
STATE=$ROOT/.setup_state
JOBS=$(nproc 2>/dev/null || echo 2)
SAN="-fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer -g -O1"

ZLIB_VER=${ZLIB_VER:-1.3}
PNG_VER=${PNG_VER:-1.6.58}
JPEG_VER=${JPEG_VER:-3.2.0}
WEBP_VER=${WEBP_VER:-1.6.0}
DE265_VER=${DE265_VER:-1.1.2}
HEIF_VER=${HEIF_VER:-1.23.4}

mkdir -p $SRC $BUILD $INSTALL $STATE /data/local/tmp2
cd $ROOT

phase() {  # phase <name> : skip if marker exists
    [ -f "$STATE/$1.done" ] && { echo "== SKIP $1 (done)"; return 1; }
    echo "== PHASE $1 $(date -Iseconds)"
    return 0
}
mark() { touch "$STATE/$1.done"; echo "== DONE $1"; }

fetch() { curl -fSL --retry 3 --connect-timeout 15 -o "$2" "$1"; }

fetch_or_git() { # dir tarball_url repo tag
    local dir=$1 url=$2 repo=$3 tag=$4
    [ -d "$SRC/$dir" ] && return 0
    cd $SRC
    if fetch "$url" "$dir.tar.gz"; then
        tar xzf "$dir.tar.gz"
    fi
    if [ ! -d "$dir" ]; then
        git clone --depth 1 --branch "$tag" "$repo" "$dir"
    fi
    [ -d "$dir" ]
}

ccache_wrap() { :; }

#########################################################################
if phase A_toolchain; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq \
        curl wget git ca-certificates xz-utils unzip \
        cmake ninja-build build-essential nasm pkg-config \
        autoconf libtool gdb python3 ffmpeg tmux || true

    # apt.llvm.org adds newest versioned packages (unversioned meta is broken there)
    if wget -qO /tmp/llvm-snapshot.key https://apt.llvm.org/llvm-snapshot.gpg.key \
       && gpg --yes --dearmor -o /tmp/llvm.gpg /tmp/llvm-snapshot.key 2>/dev/null; then
        . /etc/os-release
        install -d /etc/apt/keyrings
        cp /tmp/llvm.gpg /etc/apt/keyrings/llvm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/${UBUNTU_CODENAME}/ llvm-toolchain-${UBUNTU_CODENAME} main" \
            > /etc/apt/sources.list.d/llvm-latest.list
    fi
    apt-get update -qq || { rm -f /etc/apt/sources.list.d/llvm-latest.list; apt-get update -qq; }

    # pick the highest versioned clang that is actually installable
    NEWEST=$(for c in $(apt-cache search '^clang-[0-9]+$' | awk '{print $1}' | sort -Vu); do
        apt-cache policy $c | grep -q 'Candidate: (none)' || echo $c
    done | tail -1)
    echo "[+] newest installable clang: ${NEWEST:-distro-default}"
    if [ -n "$NEWEST" ]; then
        apt-get install -y -qq $NEWEST ${NEWEST/clang/lld} ${NEWEST/clang/llvm} ${NEWEST/clang/llvm-dev} \
            || apt-get install -y -qq clang-20 lld-20 llvm-20 llvm-20-dev \
            || apt-get install -y -qq clang
    else
        apt-get install -y -qq clang lld llvm llvm-dev
    fi

    # newest available clang wins; unversioned /usr/bin/clang included
    CLANG_BIN=$(command -v clang || true)
    for c in $(ls /usr/bin/clang-* /usr/lib/llvm-*/bin/clang 2>/dev/null | grep -E 'clang(-[0-9]+)?$' | sort -Vu); do
        CLANG_BIN=$c
    done
    [ -n "$CLANG_BIN" ] || { echo "FATAL: no clang found"; exit 1; }
    CXX_BIN="${CLANG_BIN/clang/clang++}"
    [ -x "$CXX_BIN" ] || CXX_BIN=$(command -v clang++)

    LLVM_CONFIG=$(ls /usr/bin/llvm-config-* /usr/lib/llvm-*/bin/llvm-config 2>/dev/null | sort -Vu | tail -1)
    [ -z "${LLVM_CONFIG:-}" ] && LLVM_CONFIG=$(command -v llvm-config || true)
    echo "CLANG_BIN=$CLANG_BIN" > $STATE/toolchain.env
    echo "CXX_BIN=$CXX_BIN" >> $STATE/toolchain.env
    echo "LLVM_CONFIG=${LLVM_CONFIG:-}" >> $STATE/toolchain.env

    # llvm-symbolizer on PATH for symbolized ASan/UBSan reports
    SYS_BIN=$(ls /usr/bin/llvm-symbolizer-* /usr/lib/llvm-*/bin/llvm-symbolizer 2>/dev/null | sort -Vu | tail -1 || true)
    [ -n "${SYS_BIN:-}" ] && ln -sf "$SYS_BIN" /usr/local/bin/llvm-symbolizer || true

    $CLANG_BIN --version | head -2
    mark A_toolchain
fi
source $STATE/toolchain.env

#########################################################################
if phase B_sources; then
    cd $SRC
    fetch_or_git zlib-$ZLIB_VER \
        "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz" \
        "https://github.com/madler/zlib" "v$ZLIB_VER"
    fetch_or_git libpng-$PNG_VER \
        "https://github.com/pnggroup/libpng/archive/refs/tags/v$PNG_VER.tar.gz" \
        "https://github.com/pnggroup/libpng" "v$PNG_VER"
    fetch_or_git libjpeg-turbo-$JPEG_VER \
        "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VER/libjpeg-turbo-$JPEG_VER.tar.gz" \
        "https://github.com/libjpeg-turbo/libjpeg-turbo" "$JPEG_VER"
    fetch_or_git libwebp-$WEBP_VER \
        "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VER.tar.gz" \
        "https://chromium.googlesource.com/webm/libwebp" "v$WEBP_VER"
    fetch_or_git libde265-$DE265_VER \
        "https://github.com/strukturag/libde265/releases/download/v$DE265_VER/libde265-$DE265_VER.tar.gz" \
        "https://github.com/strukturag/libde265" "v$DE265_VER"
    fetch_or_git libheif-$HEIF_VER \
        "https://github.com/strukturag/libheif/releases/download/v$HEIF_VER/libheif-$HEIF_VER.tar.gz" \
        "https://github.com/strukturag/libheif" "v$HEIF_VER"
    ls $SRC
    mark B_sources
fi

#########################################################################
if phase C_libs; then
    build_cmake() { # name srcdir extra-args...
        local name=$1; shift
        local srcdir=$1; shift
        rm -rf "$BUILD/$name"; mkdir -p "$BUILD/$name"; cd "$BUILD/$name"
        cmake -G Ninja -S "$SRC/$srcdir" -B . \
            -DCMAKE_C_COMPILER=$CLANG_BIN -DCMAKE_CXX_COMPILER=$CXX_BIN \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" \
            -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" \
            -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined" \
            -DBUILD_SHARED_LIBS=OFF \
            -DCMAKE_PREFIX_PATH=$INSTALL -DCMAKE_INSTALL_PREFIX=$INSTALL "$@"
        ninja -j$JOBS
        ninja install
    }

    echo "[+] zlib";   build_cmake zlib zlib-$ZLIB_VER
    echo "[+] png";    build_cmake png libpng-$PNG_VER -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF
    echo "[+] jpeg";   build_cmake jpeg libjpeg-turbo-$JPEG_VER -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TESTS=0 -DCMAKE_ASM_NASM_COMPILER=/usr/bin/nasm
    echo "[+] webp";   build_cmake webp libwebp-$WEBP_VER \
        -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
        -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
        -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_EXTRAS=OFF
    echo "[+] de265";  build_cmake de265 libde265-$DE265_VER -DENABLE_SDL=OFF -DENABLE_DECODER=OFF || \
        build_cmake de265 libde265-$DE265_VER   # older cmakes lack those options
    echo "[+] heif";   build_cmake heif libheif-$HEIF_VER \
        -DWITH_LIBDE265=ON -DWITH_AOM_DECODER=OFF -DWITH_AOM_ENCODER=OFF -DWITH_X265=OFF \
        -DWITH_LIBJPEG=OFF -DWITH_LIBPNG=OFF -DWITH_OPENJPEG=OFF -DWITH_OpenH264=OFF \
        -DWITH_VVENC=OFF -DWITH_VVDEC=OFF -DWITH_SvtEnc=OFF -DWITH_RAV1E=OFF \
        -DWITH_DAV1D=OFF -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF \
        -DBUILD_TESTING=OFF -DENABLE_PLUGIN_LOADING=OFF \
        -Dlibde265_DIR=$INSTALL/lib/cmake/libde265

    export PKG_CONFIG_PATH=$INSTALL/lib/pkgconfig
    pkg-config --modversion libheif libde265 libpng libjpeg libwebp
    mark C_libs
fi

export PKG_CONFIG_PATH=$INSTALL/lib/pkgconfig

#########################################################################
if phase D_libfuzzer_bins; then
    cd $ROOT
    F="-fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g -O1"
    $CXX_BIN $F -I$INSTALL/include -I$INSTALL/include/libheif \
        -o heif_box_fuzzer_x86_64_vps heif_box_fuzzer_harness.cpp \
        $(pkg-config --static --libs libheif libde265) -pthread -lm
    $CXX_BIN $F -I$INSTALL/include -I$INSTALL/include/libheif \
        -o heif_decode_fuzzer_x86_64_vps heif_decode_fuzzer_harness.cpp \
        $(pkg-config --static --libs libheif libde265) -pthread -lm
    $CXX_BIN $F -I$INSTALL/include -I$INSTALL/include/libde265 \
        -o libde265_fuzzer_x86_64_vps libde265_fuzzer_harness.cpp \
        $(pkg-config --static --libs libde265) -pthread -lm
    $CXX_BIN $F -I$INSTALL/include -I$INSTALL/include/libheif \
        -o heif_fuzzer_x86_64_vps heif_fuzzer_harness.cpp \
        $(pkg-config --static --libs libheif libde265) -pthread -lm
    $CLANG_BIN $F -I$INSTALL/include \
        -o jpeg_fuzzer_x86_64_vps jpeg_fuzzer_harness.c \
        $(pkg-config --static --libs libjpeg) -lm
    $CLANG_BIN $F -I$INSTALL/include \
        -o png_fuzzer_x86_64_vps png_fuzzer_harness.c \
        $(pkg-config --static --libs libpng16 libpng) -lz -lm
    $CXX_BIN $F -I$INSTALL/include \
        -o webp_fuzzer_x86_64_vps webp_fuzzer_harness.cpp \
        $(pkg-config --static --libs libwebpdemux libwebpmux libwebp)
    ls -la $ROOT/*_fuzzer_x86_64_vps
    mark D_libfuzzer_bins
fi

#########################################################################
if phase E_seeds; then
    cd $ROOT
    mkdir -p corpus_heif_min corpus_h265_min corpus_jpg_min corpus_png_min corpus_webp_min

    # --- h265 elementary streams via ffmpeg/x265 ---
    for i in 1 2 3; do
        ffmpeg -y -loglevel error -f lavfi -i "testsrc2=size=$((48+16*i))x$((48+16*i)):rate=8" \
            -t 0.5 -pix_fmt yuv420p -c:v libx265 -x265-params log-level=error:keyint=4 \
            -f hevc corpus_h265_min/x265_$i.h265 || true
    done
    ffmpeg -y -loglevel error -f lavfi -i "mandelbrot=size=64x64:rate=4" -t 0.5 \
        -pix_fmt yuv420p -c:v libx265 -x265-params log-level=error:bframes=0 -f hevc \
        corpus_h265_min/x265_m.h265 || true

    # --- png/jpeg/webp seeds via ffmpeg ---
    ffmpeg -y -loglevel error -f lavfi -i "testsrc2=size=64x64" -frames:v 1 corpus_png_min/seed.png || true
    ffmpeg -y -loglevel error -f lavfi -i "gradients=size=128x128" -frames:v 1 -q:v 3 corpus_jpg_min/seed.jpg || true
    ffmpeg -y -loglevel error -f lavfi -i "testsrc2=size=64x64" -frames:v 1 -c:v libwebp corpus_webp_min/seed.webp || true

    # --- heic seeds: real samples if reachable ---
    for u in \
        "https://raw.githubusercontent.com/strukturag/libheif/v$HEIF_VER/examples/example.heic" \
        "https://raw.githubusercontent.com/strukturag/libheif/master/examples/example.heic" \
        "https://raw.githubusercontent.com/nokiatech/heif/gh-pages/content/images/autumn_1440x960.heic" \
        "https://raw.githubusercontent.com/nokiatech/heif/gh-pages/content/images/cheers_1440x960.heic" \
        ; do
        f=corpus_heif_min/$(basename "$u")
        fetch "$u" "$f" && grep -q ftyp "$f" || rm -f "$f"
    done
    # avif seeds (heif box paths still parse container)
    for u in \
        "https://raw.githubusercontent.com/strukturag/libheif/v$HEIF_VER/examples/example.avif" \
        "https://raw.githubusercontent.com/AOMediaCodec/libavif/main/tests/data/av1-avif-test-file.avif" \
        ; do
        f=corpus_heif_min/$(basename "$u")
        fetch "$u" "$f" && grep -q ftyp "$f" || rm -f "$f"
    done
    # ffmpeg heif/avif muxer (present in ffmpeg >= 7.x) — opportunistic
    if ffmpeg -muxers 2>/dev/null | grep -qE 'heif|avif'; then
        ffmpeg -y -loglevel error -f lavfi -i "testsrc2=size=64x64:rate=4" -t 0.4 \
            -pix_fmt yuv420p -c:v libx265 -f heif corpus_heif_min/ffgen.heic || true
    fi
    # minimal box skeleton (guaranteed entry into box parser even w/o samples)
    python3 - <<'PY'
import struct, os
def box(t, payload):
    return struct.pack('>I4s', 8+len(payload), t) + payload
ftyp = box(b'ftyp', b'heic' + struct.pack('>I', 0) + b'mif1heic')
hdlr = box(b'hdlr', b'\x00\x00\x00\x00' + b'\x00'*4 + b'pict' + b'\x00'*12 + b'pict\x00')
pitm = box(b'pitm', b'\x00\x00\x00\x00' + struct.pack('>H', 1))
infe = box(b'infe', b'\x02\x00\x00\x00' + struct.pack('>H', 1) + struct.pack('>H', 0) + b'hvc1' + b'\x00')
iinf = box(b'iinf', b'\x00\x00\x00\x00' + struct.pack('>H', 1) + infe)
ispe = box(b'ispe', b'\x00\x00\x00\x00' + struct.pack('>II', 64, 64))
pixi = box(b'pixi', b'\x00\x00\x00\x00' + b'\x03\x08\x08\x08')
ipco = box(b'ipco', ispe + pixi)
ipma = box(b'ipma', b'\x00\x00\x00\x00' + struct.pack('>I', 1) + struct.pack('>H', 1) + b'\x02' + b'\x81' + b'\x82')
iprp = box(b'iprp', ipco + ipma)
iloc = box(b'iloc', b'\x00\x00\x00\x00' + b'\x44\x40' + struct.pack('>H', 1) + struct.pack('>H', 1) + b'\x00' + struct.pack('>I', 0) + struct.pack('>H', 1) + struct.pack('>II', 0, 0))
meta = box(b'meta', b'\x00\x00\x00\x00' + hdlr + pitm + iinf + iprp + iloc)
mdat = box(b'mdat', b'\x00\x00\x00\x01\x26\x01' + b'\xAA'*32)
data = ftyp + meta + mdat
os.makedirs('/root/0day_fuzz/corpus_heif_min', exist_ok=True)
open('/root/0day_fuzz/corpus_heif_min/skeleton.heic','wb').write(data)
open('/root/0day_fuzz/corpus_h265_min/nal_min.h265','wb').write(b'\x00\x00\x00\x01\x40\x01\x0c\x01' + b'\x00'*16 + b'\x00\x00\x00\x01\x26\x01' + b'\x00'*32)
PY
    for d in corpus_*_min; do echo "$d: $(ls $d | wc -l) seeds"; done
    mark E_seeds
fi

#########################################################################
if phase F_afl; then
    cd $SRC
    if [ ! -d AFLplusplus ]; then
        TAG=$(git ls-remote --tags https://github.com/AFLplusplus/AFLplusplus 'v*' 2>/dev/null \
              | grep -oE 'v[0-9]+\.[0-9]+[a-z]*$' | sort -Vu | tail -1 || true)
        git clone --depth 1 --branch "${TAG:-stable}" \
            https://github.com/AFLplusplus/AFLplusplus || \
            git clone --depth 1 https://github.com/AFLplusplus/AFLplusplus
    fi
    cd AFLplusplus
    export LLVM_CONFIG
    [ -x /usr/lib/llvm-20/bin/clang ] || apt-get install -y -qq clang-20 lld-20 || true
    CC=/usr/lib/llvm-20/bin/clang CXX=/usr/lib/llvm-20/bin/clang++ \
      LLVM_CONFIG=/usr/bin/llvm-config-20 make -j$JOBS > afl_build.log 2>&1 || tail -50 afl_build.log
    if [ -x ./afl-clang-lto++ ] && [ -f ./libAFLDriver.a ]; then
        # libs for AFL must be compiled by afl-clang-lto too (bitmap instrumentation)
        INSTALL_AFL=$ROOT/install-afl
        mkdir -p $INSTALL_AFL $ROOT/afl
        build_afl_cmake() {
            local name=$1; shift; local srcdir=$1; shift
            rm -rf "$BUILD/afl-$name"; mkdir -p "$BUILD/afl-$name"; cd "$BUILD/afl-$name"
            cmake -G Ninja -S "$SRC/$srcdir" -B . \
                -DCMAKE_C_COMPILER=$SRC/AFLplusplus/afl-clang-lto \
                -DCMAKE_CXX_COMPILER=$SRC/AFLplusplus/afl-clang-lto++ \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1" \
                -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1" \
                -DBUILD_SHARED_LIBS=OFF \
                -DCMAKE_PREFIX_PATH=$INSTALL_AFL -DCMAKE_INSTALL_PREFIX=$INSTALL_AFL "$@"
            ninja -j$JOBS
            ninja install
        }
        build_afl_cmake de265 libde265-$DE265_VER
        build_afl_cmake heif libheif-$HEIF_VER \
            -DWITH_LIBDE265=ON -DWITH_AOM_DECODER=OFF -DWITH_AOM_ENCODER=OFF -DWITH_X265=OFF \
            -DWITH_LIBJPEG=OFF -DWITH_LIBPNG=OFF -DWITH_OPENJPEG=OFF -DWITH_OpenH264=OFF \
            -DWITH_VVENC=OFF -DWITH_VVDEC=OFF -DWITH_SvtEnc=OFF -DWITH_RAV1E=OFF \
            -DWITH_DAV1D=OFF -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF \
            -DBUILD_TESTING=OFF -DENABLE_PLUGIN_LOADING=OFF \
            -Dlibde265_DIR=$INSTALL_AFL/lib/cmake/libde265
        export PKG_CONFIG_PATH=$INSTALL_AFL/lib/pkgconfig
        for t in heif_box heif_decode libde265; do
            case $t in
                heif_box|heif_decode) INC="-I$INSTALL_AFL/include -I$INSTALL_AFL/include/libheif"; LIBS="$(pkg-config --static --libs libheif libde265)";;
                libde265) INC="-I$INSTALL_AFL/include -I$INSTALL_AFL/include/libde265"; LIBS="$(pkg-config --static --libs libde265)";;
            esac
            ./afl-clang-lto++ -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
                $INC -o $ROOT/afl/${t}_fuzzer_afl $ROOT/${t}_fuzzer_harness.cpp $SRC/AFLplusplus/libAFLDriver.a \
                $LIBS -pthread -lm || echo "afl build failed: $t"
        done
        export PKG_CONFIG_PATH=$INSTALL/lib/pkgconfig
    else
        echo "[!] afl-clang-lto++ missing; AFL++ LLVM mode unavailable"
    fi
    mark F_afl
fi

#########################################################################
if phase G_launch; then
    cd $ROOT
    chmod +x start_*.sh metrics.sh triage.sh status.sh 2>/dev/null || true
    mkdir -p crash_heif_box_vps crash_heif_decode_vps crash_de265_vps \
             crash_jpeg_vps crash_png_vps crash_webp_vps crash_heif_vps \
             crash_reports
    bash $ROOT/start_fuzzers.sh
    cp $ROOT/fuzzd.service /etc/systemd/system/fuzzd.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable fuzzd.service 2>/dev/null || true
    mark G_launch
fi

echo "== SETUP COMPLETE $(date -Iseconds)"
