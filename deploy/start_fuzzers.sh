#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Launches the HEIF/H.265 fuzzer set under one systemd scope (survives SSH drop).
ROOT=/root/0day_fuzz
mkdir -p $ROOT/crash_heif_box_vps $ROOT/crash_heif_decode_vps $ROOT/crash_de265_vps $ROOT/crash_flac $ROOT/crash_exif $ROOT/crash_sonivox /data/local/tmp2

cat > $ROOT/ubsan_narrow.supp <<'EOF'
nonnull-attribute:bitstream.cc
nonnull-attribute:nal-parser.cc
shift-base:exif-utils.c
EOF

UBSAN="UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1:symbolize=1:suppressions=$ROOT/ubsan_narrow.supp"
ASAN="ASAN_OPTIONS=detect_leaks=0:symbolize=1:quarantine_size_mb=16:detect_odr_violation=0:abort_on_error=0"

wait_scope_dead() {
    systemctl stop "$1" 2>/dev/null || true
    pkill -9 -f "$2" 2>/dev/null || true
    for _ in $(seq 1 120); do
        systemctl list-units --type=scope --all --no-legend 2>/dev/null | grep -q "$1" || break
        sleep 1
    done
    systemctl reset-failed "$1" 2>/dev/null || true
}
wait_scope_dead fuzz-heif.scope "fuzzer_x86_64_vps|flac_fuzzer|exif_fuzzer|sonivox_fuzzer"
wait_scope_dead fuzz-media.scope "fuzzer.*_media"
sleep 1

nohup systemd-run --scope --property=CPUQuota=40% --unit=fuzz-heif \
  bash -c "cd $ROOT; \
    export $UBSAN; \
    export $ASAN; \
    ./heif_decode_fuzzer_x86_64_vps $ROOT/corpus_heif_min -dict=$ROOT/heif_merged.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=4096 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_heif_decode_vps/ > $ROOT/heif_decode_vps.log 2>&1 & \
    ./heif_box_fuzzer_x86_64_vps $ROOT/corpus_heif_min -dict=$ROOT/heif_merged.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=4096 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_heif_box_vps/ > $ROOT/heif_box_vps.log 2>&1 & \
    ./libde265_fuzzer_x86_64_vps $ROOT/corpus_h265_min -dict=$ROOT/h265.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=4096 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_de265_vps/ > $ROOT/de265_vps.log 2>&1 & \
    [ -x ./flac_fuzzer ] && ./flac_fuzzer $ROOT/corpus_flac \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=262144 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=4096 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_flac/ > $ROOT/flac_vps.log 2>&1 & \
    [ -x ./exif_fuzzer ] && ./exif_fuzzer $ROOT/corpus_exif \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=524288 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=4096 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_exif/ > $ROOT/exif_vps.log 2>&1 & \
    [ -x ./sonivox_fuzzer ] && ./sonivox_fuzzer $ROOT/corpus_sonivox \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=1048576 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=4096 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_sonivox/ > $ROOT/sonivox_vps.log 2>&1 & \
    wait" \
  > $ROOT/fuzzers_start.log 2>&1 &

pkill -f "bash $ROOT/metrics.sh" 2>/dev/null || true
pkill -f "bash $ROOT/triage.sh" 2>/dev/null || true
nohup bash $ROOT/metrics.sh > /dev/null 2>&1 &
nohup bash $ROOT/triage.sh > /dev/null 2>&1 &

echo "[+] fuzzers launched in scope fuzz-heif (CPUQuota 40%) + metrics/triage"
