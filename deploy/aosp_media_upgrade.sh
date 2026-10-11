#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# AOSP standalone targets: external/libexif + external/sonivox under sancov+ASan+UBSan.
set -u
ROOT=/root/0day_fuzz
SRC=$ROOT/src
BUILD=$ROOT/build
STATE=$ROOT/.aosp_media_state
JOBS=$(nproc 2>/dev/null || echo 2)
mkdir -p $STATE $BUILD/exif-aosp $BUILD/sonivox-aosp $ROOT/crash_exif $ROOT/crash_sonivox
mark() { touch $STATE/$1; }
phase() { [ -f $STATE/$1 ] && return 1 || return 0; }

CLANG=$(command -v clang-20 || command -v clang)
SAN="-fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer -g -O1"

# Android <log/log.h> stub — silence log calls entirely for fuzzing speed.
mkdir -p $ROOT/stubs/log
cat > $ROOT/stubs/log/log.h <<'EOF'
#pragma once
#define ALOGV(...) ((void)0)
#define ALOGD(...) ((void)0)
#define ALOGI(...) ((void)0)
#define ALOGW(...) ((void)0)
#define ALOGE(...) ((void)0)
#define ALOG_FATAL(...) ((void)0)
#define ALOG(pri, tag, ...) ((void)0)
#define IF_ALOGV() (0)
#define IF_ALOGD() (0)
#define IF_ALOGI() (0)
#define IF_ALOGW() (0)
#define IF_ALOGE() (0)
#define SLOGV(...) ((void)0)
#define SLOGD(...) ((void)0)
#define SLOGE(...) ((void)0)
#define LOG_NDEBUG 1
#define android_errorWriteLog(tag, msg) ((void)0)
#define android_errorWriteWithInfoLog(tag, subtag, uid, data, datalen) ((void)0)
EOF
mkdir -p $ROOT/stubs/cutils $ROOT/stubs/media
cp $ROOT/stubs/log/log.h $ROOT/stubs/cutils/log.h
echo '#pragma once' > $ROOT/stubs/media/MediaPlayerInterface.h

# ---------- libexif ----------
if phase E1_lib; then
    cd $BUILD/exif-aosp
    ok=1
    for f in $SRC/libexif-aosp/libexif/*.c; do
        nice -n 10 $CLANG $SAN -DHAVE_CONFIG_H -I$ROOT/stubs -I$SRC/libexif-aosp -I$SRC/libexif-aosp/libexif \
            -c "$f" -o "$(basename $f .c).o" || { ok=0; break; }
    done
    [ $ok -eq 1 ] && ar rcs libexif_a.a *.o && mark E1_lib
fi

if phase E2_bin; then
    $CLANG -fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g -O1 \
        -I$ROOT/stubs -I$SRC/libexif-aosp -I$SRC/libexif-aosp/libexif \
        -o $ROOT/exif_fuzzer $ROOT/exif_fuzzer_harness.c \
        $BUILD/exif-aosp/libexif_a.a -lm && mark E2_bin
fi

if phase E3_seeds; then
    mkdir -p $ROOT/corpus_exif
    printf 'Exif\x00\x00II*\x00\x08\x00\x00\x00\x00\x00' > $ROOT/corpus_exif/min_exif.bin
    printf 'II*\x00\x08\x00\x00\x00\x01\x00\x0f\x01\x02\x00\x01\x00\x00\x00\x41\x41\x00\x00\x00\x00\x00\x00' > $ROOT/corpus_exif/tiff.bin
    printf '\xff\xd8\xff\xe1\x00\x10Exif\x00\x00II*\x00\x08\x00\x00\x00\x00\x00\xff\xd9' > $ROOT/corpus_exif/jpeg_app1.bin
    find $SRC/libexif-aosp/binary -type f 2>/dev/null | head -30 | while read f; do cp "$f" $ROOT/corpus_exif/ 2>/dev/null; done
    rm -f $ROOT/corpus_exif/Makefile.am $ROOT/corpus_exif/Makefile.in
    mark E3_seeds
fi

# ---------- sonivox ----------
SONI_SRCS="lib_src/eas_data.c lib_src/eas_dlssynth.c lib_src/eas_flog.c lib_src/eas_imelody.c \
lib_src/eas_imelodydata.c lib_src/eas_math.c lib_src/eas_mdls.c lib_src/eas_midi.c \
lib_src/eas_mididata.c lib_src/eas_mixbuf.c lib_src/eas_mixer.c lib_src/eas_ota.c \
lib_src/eas_otadata.c lib_src/eas_pan.c lib_src/eas_pcm.c lib_src/eas_pcmdata.c \
lib_src/eas_public.c lib_src/eas_reverb.c lib_src/eas_reverbdata.c lib_src/eas_rtttl.c \
lib_src/eas_rtttldata.c lib_src/eas_smf.c lib_src/eas_smfdata.c lib_src/eas_voicemgt.c \
lib_src/eas_wtengine.c lib_src/eas_wtsynth.c lib_src/eas_xmf.c lib_src/eas_xmfdata.c \
lib_src/wt_22khz.c lib_src/jet.c host_src/eas_config.c host_src/eas_hostmm.c host_src/eas_report.c"

SONI_DEFS="-DUNIFIED_DEBUG_MESSAGES -DEAS_WT_SYNTH -D_IMELODY_PARSER -D_RTTTL_PARSER \
-D_OTA_PARSER -D_XMF_PARSER -DNUM_OUTPUT_CHANNELS=2 -D_SAMPLE_RATE_22050 -DMAX_SYNTH_VOICES=64 \
-D_16_BIT_SAMPLES -D_FILTER_ENABLED -DDLS_SYNTHESIZER -D_REVERB_ENABLED -DJET_INTERFACE \
-Wno-unused-parameter -include stdbool.h"

if phase S1_lib; then
    cd $BUILD/sonivox-aosp
    ok=1
    for f in $SONI_SRCS; do
        nice -n 10 $CLANG $SAN $SONI_DEFS -I$ROOT/stubs \
            -I$SRC/sonivox-aosp/arm-wt-22k/host_src \
            -I$SRC/sonivox-aosp/arm-wt-22k/lib_src \
            -I$SRC/sonivox-aosp/arm-wt-22k/include \
            -I$SRC/sonivox-aosp/arm-wt-22k/include/libsonivox \
            -c "$SRC/sonivox-aosp/arm-wt-22k/$f" -o "$(basename $f .c).o" || { ok=0; echo "FAIL $f"; break; }
    done
    [ $ok -eq 1 ] && ar rcs libsonivox_a.a *.o && mark S1_lib
fi

if phase S2_bin; then
    $CLANG -fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g -O1 \
        -I$ROOT/stubs -I$SRC/sonivox-aosp/arm-wt-22k/host_src \
        -I$SRC/sonivox-aosp/arm-wt-22k/include \
        -I$SRC/sonivox-aosp/arm-wt-22k/include/libsonivox \
        -o $ROOT/sonivox_fuzzer $ROOT/sonivox_fuzzer_harness.c \
        $BUILD/sonivox-aosp/libsonivox_a.a -lm && mark S2_bin
fi

if phase S3_seeds; then
    mkdir -p $ROOT/corpus_sonivox
    # Minimal SMF: header + one empty track
    printf 'MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60MTrk\x00\x00\x00\x04\x00\xff\x2f\x00' > $ROOT/corpus_sonivox/min.mid
    printf 'XMF_\x00\x00\x00\x10\x00\x00\x00\x02\x00\x00\x00\x00' > $ROOT/corpus_sonivox/min.xmf
    printf '//SOUND 1\n:TONE-1\n:VERSION 1\n:FORMAT EMELODY1\n:MELODY c\n:END:MELODY\n' > $ROOT/corpus_sonivox/min.imy
    printf 'BEGIN:IMELODY\nVERSION:1.2\nFORMAT:CLASS1.0\nMELODY:c\nEND:IMELODY\n' > $ROOT/corpus_sonivox/min2.imy
    printf 'C5E5G5R5' > $ROOT/corpus_sonivox/min.rtttl
    find $SRC/sonivox-aosp -type f \( -name '*.mid' -o -name '*.xmf' -o -name '*.imy' -o -name '*.rtttl' -o -name '*.ota' \) 2>/dev/null | head -20 | while read f; do cp "$f" $ROOT/corpus_sonivox/ 2>/dev/null; done
    mark S3_seeds
fi
echo "[aosp_media] DONE"
