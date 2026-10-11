#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Cross-pollination: pull new AFL queue finds into the libFuzzer corpus.
# Reverse direction is native: afl-fuzz -F watches the libFuzzer corpus dir.
set -u
ROOT=/root/0day_fuzz
STATE=$ROOT/.sync_state
mkdir -p "$STATE"

declare -A PAIRS=(
    [heif_decode]="$ROOT/afl_out_heif_decode/default/queue:$ROOT/corpus_heif_min"
    [heif_box]="$ROOT/afl_out_heif_box/default/queue:$ROOT/corpus_heif_min"
    [de265]="$ROOT/afl_out_de265/default/queue:$ROOT/corpus_h265_min"
)

while true; do
    for name in "${!PAIRS[@]}"; do
        IFS=: read -r aq lf <<< "${PAIRS[$name]}"
        [ -d "$aq" ] || continue
        marker="$STATE/$name.mark"
        touch -d '1970-01-01' "$marker" 2>/dev/null || touch "$marker"
        find "$aq" -type f -name 'id_*' -newer "$marker" | while read -r f; do
            # id_000123,src_...,+cov,... -> keep only queue entries that gained coverage
            case "$(basename "$f")" in *"+cov"*|*orig:*|*time:*) ;; *) continue;; esac
            cp -n "$f" "$lf/afl_$(basename "$f" | tr ',+' '__')" 2>/dev/null || true
        done
        touch "$marker"
    done
    sleep 300
done
