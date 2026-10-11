#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Optional: JPEG/PNG/WebP fuzzers. Run INSTEAD of start_fuzzers.sh on a 2-core box
# (or accept oversubscription if both sets run).
ROOT=/root/0day_fuzz
mkdir -p $ROOT/crash_jpeg_vps $ROOT/crash_png_vps $ROOT/crash_webp_vps /data/local/tmp2

export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1:symbolize=1:suppressions=$ROOT/ubsan_narrow.supp
export ASAN_OPTIONS=detect_leaks=0:symbolize=1:quarantine_size_mb=16:detect_odr_violation=0:abort_on_error=0

systemctl stop fuzz-media.scope 2>/dev/null || true
pkill -9 -f "jpeg_fuzzer_x86_64_vps\|png_fuzzer_x86_64_vps\|webp_fuzzer_x86_64_vps" 2>/dev/null || true
sleep 1

nohup systemd-run --scope --property=CPUQuota=140% --unit=fuzz-media \
  bash -c "cd $ROOT && \
    export UBSAN_OPTIONS='$UBSAN_OPTIONS' && \
    export ASAN_OPTIONS='$ASAN_OPTIONS' && \
    ./jpeg_fuzzer_x86_64_vps $ROOT/corpus_jpg_min -dict=$ROOT/jpeg.dict \
      -fork=1 -ignore_crashes=1 -max_len=65536 -max_total_time=86400 -timeout=25 \
      -rss_limit_mb=3072 -artifact_prefix=$ROOT/crash_jpeg_vps/ > $ROOT/jpeg_vps.log 2>&1 & \
    ./png_fuzzer_x86_64_vps $ROOT/corpus_png_min -dict=$ROOT/png.dict \
      -fork=1 -ignore_crashes=1 -max_len=65536 -max_total_time=86400 -timeout=25 \
      -rss_limit_mb=3072 -artifact_prefix=$ROOT/crash_png_vps/ > $ROOT/png_vps.log 2>&1 & \
    ./webp_fuzzer_x86_64_vps $ROOT/corpus_webp_min -dict=$ROOT/webp.dict \
      -fork=1 -ignore_crashes=1 -max_len=65536 -max_total_time=86400 -timeout=25 \
      -rss_limit_mb=3072 -artifact_prefix=$ROOT/crash_webp_vps/ > $ROOT/webp_vps.log 2>&1 & \
    wait" > $ROOT/media_start.log 2>&1 &

echo "[+] media fuzzers launched (shared 140% scope)"
