#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Industrial triage v2: dedup by ASan/UBSan signature, minimize, index into crashes.tsv.
set -u
ROOT=/root/0day_fuzz
AFL=$ROOT/src/AFLplusplus
mkdir -p "$ROOT/crash_reports"

ASAN_ENV="ASAN_OPTIONS=symbolize=1:detect_leaks=0:print_stats=0:halt_on_error=0:abort_on_error=0"
UBSAN_ENV="UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1:symbolize=1:suppressions=$ROOT/ubsan_narrow.supp"

declare -A BIN=(
    [heif_decode]=$ROOT/heif_decode_fuzzer_x86_64_vps
    [heif_box]=$ROOT/heif_box_fuzzer_x86_64_vps
    [de265]=$ROOT/libde265_fuzzer_x86_64_vps
    [jpeg]=$ROOT/jpeg_fuzzer_x86_64_vps
    [png]=$ROOT/png_fuzzer_x86_64_vps
    [webp]=$ROOT/webp_fuzzer_x86_64_vps
    [afl_heif_decode]=$ROOT/afl/heif_decode_fuzzer_afl
    [m_heif_decode]=$ROOT/heif_decode_fuzzer_master
    [m_heif_box]=$ROOT/heif_box_fuzzer_master
    [m_de265]=$ROOT/libde265_fuzzer_master
    [m_heif_meta]=$ROOT/heif_meta_fuzzer_master
    [m_heif_seq]=$ROOT/heif_seq_fuzzer_master
    [m_roundtrip]=$ROOT/heif_roundtrip_fuzzer_master
    [msan_de265]=$ROOT/libde265_fuzzer_msan
    [flac]=$ROOT/flac_fuzzer
    [exif]=$ROOT/exif_fuzzer
    [sonivox]=$ROOT/sonivox_fuzzer
)
declare -A CDIR=(
    [heif_decode]=$ROOT/crash_heif_decode_vps
    [heif_box]=$ROOT/crash_heif_box_vps
    [de265]=$ROOT/crash_de265_vps
    [jpeg]=$ROOT/crash_jpeg_vps
    [png]=$ROOT/crash_png_vps
    [webp]=$ROOT/crash_webp_vps
    [afl_heif_decode]=$ROOT/afl_out_heif_decode/main/crashes
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

INDEX=$ROOT/crash_reports/crashes.tsv
[ -f "$INDEX" ] || printf 'sig\tfmt\tfile\tsize\tfirst_seen\tsummary\n' > "$INDEX"

signature_of() {  # stack signature: sanitizer type + top frames
    grep -oE 'SUMMARY: [A-Za-z]+Sanitizer: [^ ]+' "$1" | head -1
    grep -oE '#[0-9]+ 0x[0-9a-f]+ in [^ ]+ [^ )]+' "$1" | head -3
}

process() {
    local fmt=$1
    local crashdir=${CDIR[$fmt]}
    local reports=$ROOT/crash_reports/$fmt
    local mindir=$crashdir/minimized
    [ -d "$crashdir" ] || return
    mkdir -p "$reports" "$mindir" "$ROOT/crash_reports/by_sig"
    local bin=${BIN[$fmt]}
    [ -x "$bin" ] || return

    find "$crashdir" -maxdepth 1 -type f \( -name 'crash-*' -o -name 'timeout-*' -o -name 'id:*' \) | while read -r f; do
        base=$(basename "$f")
        base=${base//:/_}  # AFL 'id:000000,sig:06,...' -> fs-safe name for reports
        [ -f "$reports/$base.txt" ] && continue
        echo "[$(date -Iseconds)] triage $fmt/$base"

        env $ASAN_ENV $UBSAN_ENV "$bin" "$f" > "$reports/$base.txt" 2>&1 || true
        sig=$(signature_of "$reports/$base.txt" | md5sum | cut -d' ' -f1)
        [ -z "$sig" ] && sig="nosig_$(echo "$base" | md5sum | cut -c1-8)"
        summary=$(grep -oE 'SUMMARY: [A-Za-z]+Sanitizer: [^ ]+.*' "$reports/$base.txt" | head -1 | tr '\t' ' ')

        mkdir -p "$ROOT/crash_reports/by_sig/$sig"
        cp -n "$f" "$ROOT/crash_reports/by_sig/$sig/$base" 2>/dev/null || true
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sig" "$fmt" "$base" "$(stat -c%s "$f")" \
            "$(date -Iseconds)" "${summary:-unknown}" >> "$INDEX"

        if [[ $fmt == afl_* && -x "$AFL/afl-tmin" ]]; then
            env $ASAN_ENV $UBSAN_ENV AFL_SKIP_CPUFREQ=1 \
                timeout 300 "$AFL/afl-tmin" -i "$f" -o "$mindir/$base" \
                -m none -t 15000 -- "$bin" @@ > "$reports/min_${base}.log" 2>&1 || true
        else
            env $ASAN_ENV $UBSAN_ENV "$bin" "$f" -minimize_crash=1 \
                -exact_artifact_path="$mindir/$base" -max_total_time=120 \
                > "$reports/min_${base}.log" 2>&1 || true
        fi
        if [ -f "$mindir/$base" ]; then
            env $ASAN_ENV $UBSAN_ENV "$bin" "$mindir/$base" \
                > "$reports/min_${base}.txt" 2>&1 || true
        fi
    done
}

while true; do
    for fmt in "${!BIN[@]}"; do process "$fmt"; done
    # dedup counter line for metrics consumers
    echo "$(date -Iseconds) unique_sigs=$(ls $ROOT/crash_reports/by_sig 2>/dev/null | wc -l)" >> $ROOT/triage_metrics.log
    sleep 60
done
