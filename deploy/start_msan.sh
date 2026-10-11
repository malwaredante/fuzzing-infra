#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Guided MemorySanitizer fuzzing of libde265 master — third sanitizer class.
# report_umrs catches use-of-uninitialized-value that ASan/UBSan cannot see.
ROOT=/root/0day_fuzz
mkdir -p $ROOT/crash_de265_msan /data/local/tmp2

wait_scope_dead() {
    systemctl stop "$1" 2>/dev/null || true
    pkill -9 -f "$2" 2>/dev/null || true
    for _ in $(seq 1 120); do
        systemctl list-units --type=scope --all --no-legend 2>/dev/null | grep -q "$1" || break
        sleep 1
    done
    systemctl reset-failed "$1" 2>/dev/null || true
}
wait_scope_dead fuzz-msan.scope "fuzzer_msan"
sleep 1

MSAN="MSAN_OPTIONS=halt_on_error=1:exit_code=77:print_stacktrace=1:symbolize=1:report_umrs=1"

nohup systemd-run --scope --property=CPUQuota=20% --unit=fuzz-msan \
  bash -c "cd $ROOT; \
    export $MSAN; \
    ./libde265_fuzzer_msan $ROOT/corpus_h265_min -dict=$ROOT/h265.dict \
      -use_value_profile=1 -fork=1 -ignore_crashes=1 -max_len=131072 \
      -max_total_time=86400 -timeout=25 -rss_limit_mb=3072 \
      -print_final_stats=1 \
      -artifact_prefix=$ROOT/crash_de265_msan/ > $ROOT/de265_msan.log 2>&1" \
  > $ROOT/msan_start.log 2>&1 &

echo "[+] msan fuzzer launched in scope fuzz-msan (CPUQuota 20%)"
