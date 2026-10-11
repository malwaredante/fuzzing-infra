#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Launches the master-branch (git HEAD) fuzzer set in one systemd scope.
# Shares corpora with the release set — finds cross-pollinate both directions.
ROOT=/root/0day_fuzz
mkdir -p $ROOT/crash_heif_decode_master $ROOT/crash_heif_box_master \
         $ROOT/crash_de265_master $ROOT/crash_heif_meta_master \
         $ROOT/crash_heif_seq_master $ROOT/crash_heif_roundtrip_master /data/local/tmp2

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
wait_scope_dead fuzz-master.scope "fuzzer_master"
sleep 1

nohup systemd-run --scope --property=CPUQuota=140% --unit=fuzz-master \
  bash -c "cd $ROOT; \
    export $UBSAN; \
    export $ASAN; \
    ./heif_decode_fuzzer_master $ROOT/corpus_heif_min -dict=$ROOT/heif_merged.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=3072 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_heif_decode_master/ > $ROOT/heif_decode_master.log 2>&1 & \
    ./heif_meta_fuzzer_master $ROOT/corpus_heif_min -dict=$ROOT/heif_merged.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=3072 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_heif_meta_master/ > $ROOT/heif_meta_master.log 2>&1 & \
    ./heif_box_fuzzer_master $ROOT/corpus_heif_min -dict=$ROOT/heif_merged.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=3072 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_heif_box_master/ > $ROOT/heif_box_master.log 2>&1 & \
    ./heif_seq_fuzzer_master $ROOT/corpus_heif_min -dict=$ROOT/heif_merged.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=131072 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=3072 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_heif_seq_master/ > $ROOT/heif_seq_master.log 2>&1 & \
    ./heif_roundtrip_fuzzer_master $ROOT/corpus_heif_min -dict=$ROOT/heif_merged.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=3072 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_heif_roundtrip_master/ > $ROOT/heif_roundtrip_master.log 2>&1 & \
    ./libde265_fuzzer_master $ROOT/corpus_h265_min -dict=$ROOT/h265.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=65536 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=3072 \
      -print_final_stats=1 -reduce_inputs=1 \
      -artifact_prefix=$ROOT/crash_de265_master/ > $ROOT/de265_master.log 2>&1 & \
    wait" \
  > $ROOT/master_start.log 2>&1 &

echo "[+] master fuzzers launched in scope fuzz-master (CPUQuota 140%)"
