#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Corpus distillation: -merge=1 keeps only coverage-unique inputs.
# Bloated corpora were starving throughput (master exec/s ~0-2 on 8k files).
# Runs nice'd so it never starves the live fuzzers; swaps dirs when done.
ROOT=/root/0day_fuzz
cd $ROOT

export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1:suppressions=$ROOT/ubsan_narrow.supp"
export ASAN_OPTIONS="detect_leaks=0:symbolize=1:quarantine_size_mb=16"

mkdir -p corpus_heif_dist corpus_h265_dist

echo "[distill] heif merge start $(date -Is)"
nice -n 19 ./heif_meta_fuzzer_master corpus_heif_dist corpus_heif_min \
    -merge=1 -merge_control_file=$ROOT/.merge_heif \
    -timeout=25 -rss_limit_mb=4096 > $ROOT/distill_heif.log 2>&1
echo "[distill] heif done $(date -Is): $(ls corpus_heif_dist 2>/dev/null | wc -l) files"

echo "[distill] h265 merge start $(date -Is)"
nice -n 19 ./libde265_fuzzer_master corpus_h265_dist corpus_h265_min \
    -merge=1 -merge_control_file=$ROOT/.merge_h265 \
    -timeout=25 -rss_limit_mb=4096 > $ROOT/distill_h265.log 2>&1
echo "[distill] h265 done $(date -Is): $(ls corpus_h265_dist 2>/dev/null | wc -l) files"

TS=$(date +%s)
for pair in heif h265; do
    src=corpus_${pair}_min; dst=corpus_${pair}_dist; min_n=50
    n=$(ls $dst 2>/dev/null | wc -l)
    if [ "$n" -gt "$min_n" ]; then
        mv $src ${src}.bak.$TS
        mv $dst $src
        echo "[distill] swapped $src -> $n files (backup ${src}.bak.$TS)"
    else
        echo "[distill] SKIP swap $src: only $n files" 
    fi
done

echo "DISTILL DONE $(date -Is)"
