#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# AFL++ engine on heif_decode: LTO instrumentation + CmpLog (redqueen) + foreign sync.
# Runs alongside the libFuzzer set; corpora cross-pollinate via -F and sync_corpus.sh.
ROOT=/root/0day_fuzz
AFL=$ROOT/src/AFLplusplus
BIN=$ROOT/afl/heif_decode_fuzzer_afl
CMPLOG_BIN=$ROOT/afl/heif_decode_fuzzer_cmplog

[ -x "$BIN" ] || { echo "AFL binary missing: $BIN"; exit 1; }

[ -f $ROOT/heif_merged.dict ] && DICT=$ROOT/heif_merged.dict || DICT=$ROOT/heif.dict

# -F expects <dir>/<name>/queue/* — wrap the flat libFuzzer corpus accordingly
mkdir -p $ROOT/foreign/lf_heif
ln -sfn $ROOT/corpus_heif_min $ROOT/foreign/lf_heif/queue

mkdir -p $ROOT/afl_out_heif_decode $ROOT/corpus_afl_heif
cp -n $ROOT/corpus_heif_min/* $ROOT/corpus_afl_heif/ 2>/dev/null || true

UBSAN="UBSAN_OPTIONS=halt_on_error=1:abort_on_error=1:symbolize=0:suppressions=$ROOT/ubsan_narrow.supp"
ASAN="ASAN_OPTIONS=detect_leaks=0:symbolize=0:abort_on_error=1:allocator_may_return_null=1"

wait_scope_dead() {
    systemctl stop "$1" 2>/dev/null || true
    pkill -9 -f "$2" 2>/dev/null || true
    for _ in $(seq 1 120); do
        systemctl list-units --type=scope --all --no-legend 2>/dev/null | grep -q "$1" || break
        sleep 1
    done
    systemctl reset-failed "$1" 2>/dev/null || true
}
wait_scope_dead fuzz-afl.scope "afl-fuzz"
sleep 1

CMPL=""
[ -x "$CMPLOG_BIN" ] && CMPL="-c $CMPLOG_BIN"

nohup systemd-run --scope --property=CPUQuota=40% --unit=fuzz-afl \
  bash -c "cd $ROOT && \
    export AFL_SKIP_CPUFREQ=1 AFL_NO_UI=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
           AFL_IMPORT_FIRST=1 AFL_FAST_CAL=1 AFL_AUTORESUME=1 && \
    export $UBSAN && \
    export $ASAN && \
    $AFL/afl-fuzz -i $ROOT/corpus_afl_heif -o $ROOT/afl_out_heif_decode \
      -M main -F $ROOT/foreign -x $DICT $CMPL -m none -t 20000+ -V 86400 \
      -p rare -- $BIN" > $ROOT/afl_heif_decode.log 2>&1 &

echo "[+] afl-fuzz launched on heif_decode (dict=$DICT, cmplog=${CMPL:-off}, -F=foreign/)"
