#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Continuous coverage/crash metrics for the running fuzzer set.
set -u
ROOT=/root/0day_fuzz
LOG="$ROOT/metrics.log"

crash_count() {
    local d="$1"
    [ -d "$d" ] && find "$d" -maxdepth 1 -type f -name 'crash-*' -o -name 'timeout-*' -o -name 'oom-*' 2>/dev/null | wc -l || echo 0
}

declare -A LOGS=(
    [heif_decode]=$ROOT/heif_decode_vps.log
    [heif_box]=$ROOT/heif_box_vps.log
    [de265]=$ROOT/de265_vps.log
    [jpeg]=$ROOT/jpeg_vps.log
    [png]=$ROOT/png_vps.log
    [webp]=$ROOT/webp_vps.log
    [afl_heif_decode]=$ROOT/afl_heif_decode.log
    [m_heif_decode]=$ROOT/heif_decode_master.log
    [m_heif_box]=$ROOT/heif_box_master.log
    [m_de265]=$ROOT/de265_master.log
    [m_heif_meta]=$ROOT/heif_meta_master.log
    [m_heif_seq]=$ROOT/heif_seq_master.log
    [m_roundtrip]=$ROOT/heif_roundtrip_master.log
    [msan_de265]=$ROOT/de265_msan.log
    [flac]=$ROOT/flac_vps.log
    [exif]=$ROOT/exif_vps.log
    [sonivox]=$ROOT/sonivox_vps.log
)
declare -A CRASH=(
    [heif_decode]=$ROOT/crash_heif_decode_vps
    [heif_box]=$ROOT/crash_heif_box_vps
    [de265]=$ROOT/crash_de265_vps
    [jpeg]=$ROOT/crash_jpeg_vps
    [png]=$ROOT/crash_png_vps
    [webp]=$ROOT/crash_webp_vps
    [afl_heif_decode]=$ROOT/afl_out_heif_decode
    [m_heif_decode]=$ROOT/crash_heif_decode_master
    [m_heif_box]=$ROOT/crash_heif_box_master
    [m_de265]=$ROOT/crash_de265_master
    [m_heif_meta]=$ROOT/crash_heif_meta_master
    [m_heif_seq]=$ROOT/crash_heif_seq_master
    [m_roundtrip]=$ROOT/crash_heif_roundtrip_master
    [msan_de265]=$ROOT/crash_de265_msan
    [flac]=$ROOT/crash_flac
    [exif]=$ROOT/crash_exif
    [sonivox]=$ROOT/crash_sonivox
)

while true; do
    ts=$(date -Iseconds)
    for fmt in "${!LOGS[@]}"; do
        logfile=${LOGS[$fmt]}
        crashes=$(crash_count "${CRASH[$fmt]}")
        cov=0; ft=0; corp=0; eps=0
        if [ -f "$logfile" ]; then
            line=$(tail -n 3 "$logfile" 2>/dev/null | tr '\n' ' ')
            cov=$(echo "$line"  | grep -o 'cov: [0-9]*'  | tail -1 | awk '{print $2}')
            ft=$(echo "$line"   | grep -o 'ft: [0-9]*'   | tail -1 | awk '{print $2}')
            corp=$(echo "$line" | grep -o 'corp: [0-9]*' | tail -1 | awk '{print $2}')
            eps=$(echo "$line"  | grep -o 'exec/s: [0-9]*' | tail -1 | awk '{print $2}')
        fi
        echo "$ts $fmt cov=${cov:-0} ft=${ft:-0} corp=${corp:-0} exec/s=${eps:-0} crashes=$crashes" >> "$LOG"
    done
    sleep 60
done
