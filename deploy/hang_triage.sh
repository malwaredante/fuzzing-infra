#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Classify timeout/hang artifacts: real infinite loop vs just slow input.
ROOT=/root/0day_fuzz
OUT=$ROOT/hang_report.txt
: > $OUT

check() { # bin dir pattern
    local bin=$1 dir=$2 pat=$3
    [ -d "$dir" ] || return
    for f in "$dir"/$pat; do
        [ -f "$f" ] || continue
        timeout -k 2 15 env ASAN_OPTIONS=detect_leaks=0:symbolize=0:abort_on_error=0 \
            UBSAN_OPTIONS=halt_on_error=1:symbolize=0:suppressions=$ROOT/ubsan_narrow.supp \
            "$bin" "$f" >/dev/null 2>&1
        rc=$?
        if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
            echo "HANG $f" >> $OUT
        else
            echo "ok($rc) $f" >> $OUT
        fi
    done
}

check $ROOT/heif_decode_fuzzer_x86_64_vps $ROOT/crash_heif_decode_vps 'timeout-*'
check $ROOT/libde265_fuzzer_x86_64_vps $ROOT/crash_de265_vps 'timeout-*'
check $ROOT/afl/heif_decode_fuzzer_afl $ROOT/afl_out_heif_decode/main/hangs 'id:*'
check $ROOT/heif_decode_fuzzer_x86_64_vps $ROOT/crash_heif_decode_vps 'slow-unit-*'
echo DONE >> $OUT
