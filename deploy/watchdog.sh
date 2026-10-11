#!/bin/bash
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
# Watchdog: restart fuzzer scopes that died. Manual stop = create /root/0day_fuzz/STOP.
set -u
ROOT=/root/0day_fuzz
[ -f $ROOT/STOP ] && exit 0

want_heif=1
want_afl=0
want_master=0
[ -f $ROOT/ENABLE_AFL ] && want_afl=1
[ -f $ROOT/ENABLE_MASTER ] && want_master=1
[ -f $ROOT/ENABLE_MEDIA ] && want_media=1 || want_media=0
[ -f $ROOT/ENABLE_MSAN ] && want_msan=1 || want_msan=0

if [ $want_heif -eq 1 ]; then
    systemctl is-active --quiet fuzz-heif.scope || {
        logger -t fuzzwatch "fuzz-heif.scope dead, restarting"
        systemd-run --no-block --unit=fuzz-launch-heif -- bash $ROOT/start_fuzzers.sh
    }
fi
if [ $want_afl -eq 1 ]; then
    systemctl is-active --quiet fuzz-afl.scope || {
        logger -t fuzzwatch "fuzz-afl.scope dead, restarting"
        systemd-run --no-block --unit=fuzz-launch-afl -- bash $ROOT/start_afl.sh
    }
fi
if [ $want_master -eq 1 ]; then
    systemctl is-active --quiet fuzz-master.scope || {
        logger -t fuzzwatch "fuzz-master.scope dead, restarting"
        systemd-run --no-block --unit=fuzz-launch-master -- bash $ROOT/start_master.sh
    }
fi
if [ $want_media -eq 1 ]; then
    systemctl is-active --quiet fuzz-media.scope || {
        logger -t fuzzwatch "fuzz-media.scope dead, restarting"
        systemd-run --no-block --unit=fuzz-launch-media -- bash $ROOT/start_media.sh
    }
fi
if [ $want_msan -eq 1 ]; then
    systemctl is-active --quiet fuzz-msan.scope || {
        logger -t fuzzwatch "fuzz-msan.scope dead, restarting"
        systemd-run --no-block --unit=fuzz-launch-msan -- bash $ROOT/start_msan.sh
    }
fi
