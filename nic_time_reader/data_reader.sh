#!/bin/bash
# Like phc_cmp_log.sh but uses a custom ptp4l binary with semicolon-separated
# full stats output (offset/freq/delay min/max/mean/rms/stddev per interval).
# Default custom binary: /home/usr/devel/linuxptp/ptp4l  (override with -b)
# Phases: 1 = ptp4l init, 2 = phc2sys warmup, 3 = main capture

OUTFILE="data_$(date +%Y%m%d_%H%M%S).csv"
PTP_WARMUP=120
PHC_WARMUP=120
PTP4L_BIN=/home/usr/devel/linuxptp/ptp4l

while getopts "f:p:c:b:" opt; do
    case $opt in
        f) OUTFILE=$OPTARG ;;
        p) PTP_WARMUP=$OPTARG ;;
        c) PHC_WARMUP=$OPTARG ;;
        b) PTP4L_BIN=$OPTARG ;;
    esac
done

INTERVAL_NS=100000000   # 100 ms in nanoseconds

TMP_OSA5422=/dev/shm/phc_osa5422_$$
TMP_CM_PTP_1=/dev/shm/phc_cm_ptp_1_$$
TMP_OSA5404=/dev/shm/phc_osa5404_$$
TMP_CM_PTP_2=/dev/shm/phc_cm_ptp_2_$$
PTP4L_OSA5422_LOG=/dev/shm/ptp4l_osa5422_$$
PTP4L_CM_PTP_1_LOG=/dev/shm/ptp4l_cm_ptp_1_$$
PTP4L_OSA5404_LOG=/dev/shm/ptp4l_osa5404_$$
PTP4L_CM_PTP_2_LOG=/dev/shm/ptp4l_cm_ptp_2_$$
PHASE_FILE=/dev/shm/phc_phase_$$

cleanup() {
    echo "stopped" >/tmp/test_status
    kill "$SAMPLING_PID" "$PTP4L_OSA5422_PID" "$PTP4L_CM_PTP_1_PID" "$PTP4L_OSA5404_PID" "$PTP4L_CM_PTP_2_PID" 2>/dev/null
    wait "$SAMPLING_PID" "$PTP4L_OSA5422_PID" "$PTP4L_CM_PTP_1_PID" "$PTP4L_OSA5404_PID" "$PTP4L_CM_PTP_2_PID" 2>/dev/null
    rm -f "$TMP_OSA5422" "$TMP_CM_PTP_1" "$TMP_OSA5404" "$TMP_CM_PTP_2" \
          "$PTP4L_OSA5422_LOG" "$PTP4L_CM_PTP_1_LOG" "$PTP4L_OSA5404_LOG" "$PTP4L_CM_PTP_2_LOG" \
          "$PHASE_FILE"
}
trap cleanup EXIT

now_ns() { date -u +%s%N; }

# Parse the last semicolon-separated stats line from a ptp4l log file.
# Sets global variables named ptp4l_${prefix}_ts and ptp4l_${prefix}_<field>.
# Stats line format: ptp4l[TS]: f1;f2;...;f19
_parse_stats() {
    local log="$1" p="$2" line ts raw
    line=$(grep ';' "$log" 2>/dev/null | tail -1)
    ts=$(echo "$line"  | grep -oP '(?<=ptp4l\[)[0-9.]+(?=\])')
    raw=$(echo "$line" | grep -oP '(?<=\]: ).+')

    local f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16 f17 f18 f19
    IFS=';' read -r f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16 f17 f18 f19 <<< "$raw"

    printf -v "ptp4l_${p}_ts"             '%s' "$ts"
    printf -v "ptp4l_${p}_offset_min"     '%s' "$f1"
    printf -v "ptp4l_${p}_offset_max"     '%s' "$f2"
    printf -v "ptp4l_${p}_offset_max_abs" '%s' "$f3"
    printf -v "ptp4l_${p}_offset_mean"    '%s' "$f4"
    printf -v "ptp4l_${p}_offset_rms"     '%s' "$f5"
    printf -v "ptp4l_${p}_offset_stddev"  '%s' "$f6"
    printf -v "ptp4l_${p}_freq_min"       '%s' "$f7"
    printf -v "ptp4l_${p}_freq_max"       '%s' "$f8"
    printf -v "ptp4l_${p}_freq_max_abs"   '%s' "$f9"
    printf -v "ptp4l_${p}_freq_mean"      '%s' "$f10"
    printf -v "ptp4l_${p}_freq_rms"       '%s' "$f11"
    printf -v "ptp4l_${p}_freq_stddev"    '%s' "$f12"
    printf -v "ptp4l_${p}_delay_min"      '%s' "$f13"
    printf -v "ptp4l_${p}_delay_max"      '%s' "$f14"
    printf -v "ptp4l_${p}_delay_max_abs"  '%s' "$f15"
    printf -v "ptp4l_${p}_delay_mean"     '%s' "$f16"
    printf -v "ptp4l_${p}_delay_rms"      '%s' "$f17"
    printf -v "ptp4l_${p}_delay_stddev"   '%s' "$f18"
    printf -v "ptp4l_${p}_delay_enabled"  '%s' "$f19"
}

# Write CSV header and start sampling loop immediately.
echo "phase,timestamp_ns,\
osa5422_ts,osa5422,\
cm-ptp-1_ts,cm-ptp-1,\
osa5404_ts,osa5404,\
cm-ptp-2_ts,cm-ptp-2,\
ptp4l_osa5422_ts,ptp4l_osa5422_offset_min,ptp4l_osa5422_offset_max,ptp4l_osa5422_offset_max_abs,ptp4l_osa5422_offset_mean,ptp4l_osa5422_offset_rms,ptp4l_osa5422_offset_stddev,ptp4l_osa5422_freq_min,ptp4l_osa5422_freq_max,ptp4l_osa5422_freq_max_abs,ptp4l_osa5422_freq_mean,ptp4l_osa5422_freq_rms,ptp4l_osa5422_freq_stddev,ptp4l_osa5422_delay_min,ptp4l_osa5422_delay_max,ptp4l_osa5422_delay_max_abs,ptp4l_osa5422_delay_mean,ptp4l_osa5422_delay_rms,ptp4l_osa5422_delay_stddev,ptp4l_osa5422_delay_enabled,\
ptp4l_cm-ptp-1_ts,ptp4l_cm-ptp-1_offset_min,ptp4l_cm-ptp-1_offset_max,ptp4l_cm-ptp-1_offset_max_abs,ptp4l_cm-ptp-1_offset_mean,ptp4l_cm-ptp-1_offset_rms,ptp4l_cm-ptp-1_offset_stddev,ptp4l_cm-ptp-1_freq_min,ptp4l_cm-ptp-1_freq_max,ptp4l_cm-ptp-1_freq_max_abs,ptp4l_cm-ptp-1_freq_mean,ptp4l_cm-ptp-1_freq_rms,ptp4l_cm-ptp-1_freq_stddev,ptp4l_cm-ptp-1_delay_min,ptp4l_cm-ptp-1_delay_max,ptp4l_cm-ptp-1_delay_max_abs,ptp4l_cm-ptp-1_delay_mean,ptp4l_cm-ptp-1_delay_rms,ptp4l_cm-ptp-1_delay_stddev,ptp4l_cm-ptp-1_delay_enabled,\
ptp4l_osa5404_ts,ptp4l_osa5404_offset_min,ptp4l_osa5404_offset_max,ptp4l_osa5404_offset_max_abs,ptp4l_osa5404_offset_mean,ptp4l_osa5404_offset_rms,ptp4l_osa5404_offset_stddev,ptp4l_osa5404_freq_min,ptp4l_osa5404_freq_max,ptp4l_osa5404_freq_max_abs,ptp4l_osa5404_freq_mean,ptp4l_osa5404_freq_rms,ptp4l_osa5404_freq_stddev,ptp4l_osa5404_delay_min,ptp4l_osa5404_delay_max,ptp4l_osa5404_delay_max_abs,ptp4l_osa5404_delay_mean,ptp4l_osa5404_delay_rms,ptp4l_osa5404_delay_stddev,ptp4l_osa5404_delay_enabled,\
ptp4l_cm-ptp-2_ts,ptp4l_cm-ptp-2_offset_min,ptp4l_cm-ptp-2_offset_max,ptp4l_cm-ptp-2_offset_max_abs,ptp4l_cm-ptp-2_offset_mean,ptp4l_cm-ptp-2_offset_rms,ptp4l_cm-ptp-2_offset_stddev,ptp4l_cm-ptp-2_freq_min,ptp4l_cm-ptp-2_freq_max,ptp4l_cm-ptp-2_freq_max_abs,ptp4l_cm-ptp-2_freq_mean,ptp4l_cm-ptp-2_freq_rms,ptp4l_cm-ptp-2_freq_stddev,ptp4l_cm-ptp-2_delay_min,ptp4l_cm-ptp-2_delay_max,ptp4l_cm-ptp-2_delay_max_abs,ptp4l_cm-ptp-2_delay_mean,ptp4l_cm-ptp-2_delay_rms,ptp4l_cm-ptp-2_delay_stddev,ptp4l_cm-ptp-2_delay_enabled" \
    | tr -d '\\' | tee "$OUTFILE"

echo "1" >"$PHASE_FILE"

sampling_loop() {
    local next_ns
    next_ns=$(now_ns)
    while true; do
        local ts phase
        ts=$(date -u +%s%N)
        phase=$(<"$PHASE_FILE")

        phc_ctl ens2f0 cmp >"$TMP_OSA5422"  2>&1 &
        local PID_OSA5422=$!
        phc_ctl ens2f1 cmp >"$TMP_CM_PTP_1" 2>&1 &
        local PID_CM_PTP_1=$!
        phc_ctl ens2f2 cmp >"$TMP_OSA5404"  2>&1 &
        local PID_OSA5404=$!
        phc_ctl ens2f3 cmp >"$TMP_CM_PTP_2" 2>&1 &
        local PID_CM_PTP_2=$!
        wait "$PID_OSA5422" "$PID_CM_PTP_1" "$PID_OSA5404" "$PID_CM_PTP_2"

        local osa5422_raw cm_ptp_1_raw osa5404_raw cm_ptp_2_raw
        osa5422_raw=$(<"$TMP_OSA5422")
        cm_ptp_1_raw=$(<"$TMP_CM_PTP_1")
        osa5404_raw=$(<"$TMP_OSA5404")
        cm_ptp_2_raw=$(<"$TMP_CM_PTP_2")

        local osa5422_ts osa5422 cm_ptp_1_ts cm_ptp_1 osa5404_ts osa5404 cm_ptp_2_ts cm_ptp_2
        osa5422_ts=$(echo "$osa5422_raw"    | grep -oP '(?<=phc_ctl\[)[0-9.]+(?=\])')
        osa5422=$(echo "$osa5422_raw"       | grep -oP '[-]?\d+(?=ns)')
        cm_ptp_1_ts=$(echo "$cm_ptp_1_raw" | grep -oP '(?<=phc_ctl\[)[0-9.]+(?=\])')
        cm_ptp_1=$(echo "$cm_ptp_1_raw"    | grep -oP '[-]?\d+(?=ns)')
        osa5404_ts=$(echo "$osa5404_raw"    | grep -oP '(?<=phc_ctl\[)[0-9.]+(?=\])')
        osa5404=$(echo "$osa5404_raw"       | grep -oP '[-]?\d+(?=ns)')
        cm_ptp_2_ts=$(echo "$cm_ptp_2_raw" | grep -oP '(?<=phc_ctl\[)[0-9.]+(?=\])')
        cm_ptp_2=$(echo "$cm_ptp_2_raw"    | grep -oP '[-]?\d+(?=ns)')

        _parse_stats "$PTP4L_OSA5422_LOG"   "osa5422"
        _parse_stats "$PTP4L_CM_PTP_1_LOG"  "cm_ptp_1"
        _parse_stats "$PTP4L_OSA5404_LOG"   "osa5404"
        _parse_stats "$PTP4L_CM_PTP_2_LOG"  "cm_ptp_2"

        echo "${phase},${ts},\
${osa5422_ts},${osa5422},\
${cm_ptp_1_ts},${cm_ptp_1},\
${osa5404_ts},${osa5404},\
${cm_ptp_2_ts},${cm_ptp_2},\
${ptp4l_osa5422_ts},${ptp4l_osa5422_offset_min},${ptp4l_osa5422_offset_max},${ptp4l_osa5422_offset_max_abs},${ptp4l_osa5422_offset_mean},${ptp4l_osa5422_offset_rms},${ptp4l_osa5422_offset_stddev},${ptp4l_osa5422_freq_min},${ptp4l_osa5422_freq_max},${ptp4l_osa5422_freq_max_abs},${ptp4l_osa5422_freq_mean},${ptp4l_osa5422_freq_rms},${ptp4l_osa5422_freq_stddev},${ptp4l_osa5422_delay_min},${ptp4l_osa5422_delay_max},${ptp4l_osa5422_delay_max_abs},${ptp4l_osa5422_delay_mean},${ptp4l_osa5422_delay_rms},${ptp4l_osa5422_delay_stddev},${ptp4l_osa5422_delay_enabled},\
${ptp4l_cm_ptp_1_ts},${ptp4l_cm_ptp_1_offset_min},${ptp4l_cm_ptp_1_offset_max},${ptp4l_cm_ptp_1_offset_max_abs},${ptp4l_cm_ptp_1_offset_mean},${ptp4l_cm_ptp_1_offset_rms},${ptp4l_cm_ptp_1_offset_stddev},${ptp4l_cm_ptp_1_freq_min},${ptp4l_cm_ptp_1_freq_max},${ptp4l_cm_ptp_1_freq_max_abs},${ptp4l_cm_ptp_1_freq_mean},${ptp4l_cm_ptp_1_freq_rms},${ptp4l_cm_ptp_1_freq_stddev},${ptp4l_cm_ptp_1_delay_min},${ptp4l_cm_ptp_1_delay_max},${ptp4l_cm_ptp_1_delay_max_abs},${ptp4l_cm_ptp_1_delay_mean},${ptp4l_cm_ptp_1_delay_rms},${ptp4l_cm_ptp_1_delay_stddev},${ptp4l_cm_ptp_1_delay_enabled},\
${ptp4l_osa5404_ts},${ptp4l_osa5404_offset_min},${ptp4l_osa5404_offset_max},${ptp4l_osa5404_offset_max_abs},${ptp4l_osa5404_offset_mean},${ptp4l_osa5404_offset_rms},${ptp4l_osa5404_offset_stddev},${ptp4l_osa5404_freq_min},${ptp4l_osa5404_freq_max},${ptp4l_osa5404_freq_max_abs},${ptp4l_osa5404_freq_mean},${ptp4l_osa5404_freq_rms},${ptp4l_osa5404_freq_stddev},${ptp4l_osa5404_delay_min},${ptp4l_osa5404_delay_max},${ptp4l_osa5404_delay_max_abs},${ptp4l_osa5404_delay_mean},${ptp4l_osa5404_delay_rms},${ptp4l_osa5404_delay_stddev},${ptp4l_osa5404_delay_enabled},\
${ptp4l_cm_ptp_2_ts},${ptp4l_cm_ptp_2_offset_min},${ptp4l_cm_ptp_2_offset_max},${ptp4l_cm_ptp_2_offset_max_abs},${ptp4l_cm_ptp_2_offset_mean},${ptp4l_cm_ptp_2_offset_rms},${ptp4l_cm_ptp_2_offset_stddev},${ptp4l_cm_ptp_2_freq_min},${ptp4l_cm_ptp_2_freq_max},${ptp4l_cm_ptp_2_freq_max_abs},${ptp4l_cm_ptp_2_freq_mean},${ptp4l_cm_ptp_2_freq_rms},${ptp4l_cm_ptp_2_freq_stddev},${ptp4l_cm_ptp_2_delay_min},${ptp4l_cm_ptp_2_delay_max},${ptp4l_cm_ptp_2_delay_max_abs},${ptp4l_cm_ptp_2_delay_mean},${ptp4l_cm_ptp_2_delay_rms},${ptp4l_cm_ptp_2_delay_stddev},${ptp4l_cm_ptp_2_delay_enabled}" \
            | tr -d '\\' | tee -a "$OUTFILE"

        next_ns=$(( next_ns + INTERVAL_NS ))
        local now sleep_ns
        now=$(date -u +%s%N)
        sleep_ns=$(( next_ns - now ))
        if (( sleep_ns > 0 )); then
            sleep "$(awk "BEGIN{printf \"%.9f\", ${sleep_ns}/1000000000}")"
        fi
    done
}

sampling_loop &
SAMPLING_PID=$!

# Phase 1 — ptp4l init: start all daemons, mirror output for PTP_WARMUP s.
echo "phase 1: ptp4l init" >/tmp/test_status
echo "Phase 1: starting $PTP4L_BIN on ens2f0, ens2f1, ens2f2, and ens2f3..." >&2
"$PTP4L_BIN" -i ens2f0 -m -s -2 >"$PTP4L_OSA5422_LOG"  2>&1 &
PTP4L_OSA5422_PID=$!
"$PTP4L_BIN" -i ens2f1 -m -s -2 >"$PTP4L_CM_PTP_1_LOG" 2>&1 &
PTP4L_CM_PTP_1_PID=$!
"$PTP4L_BIN" -i ens2f2 -m -s -2 >"$PTP4L_OSA5404_LOG"  2>&1 &
PTP4L_OSA5404_PID=$!
"$PTP4L_BIN" -i ens2f3 -m -s -2 >"$PTP4L_CM_PTP_2_LOG" 2>&1 &
PTP4L_CM_PTP_2_PID=$!

tail -f "$PTP4L_OSA5422_LOG"  >&2 &
TAIL_OSA5422_PID=$!
tail -f "$PTP4L_CM_PTP_1_LOG" >&2 &
TAIL_CM_PTP_1_PID=$!
tail -f "$PTP4L_OSA5404_LOG"  >&2 &
TAIL_OSA5404_PID=$!
tail -f "$PTP4L_CM_PTP_2_LOG" >&2 &
TAIL_CM_PTP_2_PID=$!
sleep $PTP_WARMUP
kill "$TAIL_OSA5422_PID" "$TAIL_CM_PTP_1_PID" "$TAIL_OSA5404_PID" "$TAIL_CM_PTP_2_PID" 2>/dev/null
wait "$TAIL_OSA5422_PID" "$TAIL_CM_PTP_1_PID" "$TAIL_OSA5404_PID" "$TAIL_CM_PTP_2_PID" 2>/dev/null
echo "--- ptp4l output silenced ---" >&2

# Phase 2 — phc2sys warmup: discipline CLOCK_REALTIME for PHC_WARMUP s.
echo "2" >"$PHASE_FILE"
echo "phase 2: phc2sys warmup" >/tmp/test_status
echo "Phase 2: phc2sys warmup for $PHC_WARMUP seconds..." >&2
phc2sys -s ens2f0 -c CLOCK_REALTIME -m -O 0 &
PHC2SYS_PID=$!
sleep $PHC_WARMUP
kill "$PHC2SYS_PID" 2>/dev/null
wait "$PHC2SYS_PID" 2>/dev/null
echo "Warmup done." >&2

# Phase 3 — main capture.
echo "3" >"$PHASE_FILE"
echo "phase 3: capturing" >/tmp/test_status
echo "Phase 3: capturing..." >&2
wait "$SAMPLING_PID"
