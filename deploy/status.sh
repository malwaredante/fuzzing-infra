#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# One-shot status summary.
ROOT=/root/0day_fuzz
echo "=== procs ==="
ps -eo pid,etime,%cpu,%mem,comm,args | grep -E 'fuzzer|afl-fuzz' | grep -v grep | cut -c1-140
echo "=== latest stats ==="
for l in $ROOT/*_vps.log; do
    [ -f "$l" ] || continue
    echo "--- $(basename $l)"
    tail -n 4 "$l" | grep -E 'cov:|exec/s|ERROR|SUMMARY|DONE' | tail -2
done
echo "=== crashes ==="
for d in $ROOT/crash_*_vps; do
    [ -d "$d" ] && echo "$(basename $d): $(find $d -maxdepth 1 -type f -name 'crash-*' | wc -l)"
done
echo "=== afl ==="
[ -d $ROOT/afl_out_heif_decode/default ] && grep -E 'execs_done|saved_crashes|saved_hangs' $ROOT/afl_out_heif_decode/default/fuzzer_stats 2>/dev/null
echo "=== metrics tail ==="
tail -n 8 $ROOT/metrics.log 2>/dev/null
