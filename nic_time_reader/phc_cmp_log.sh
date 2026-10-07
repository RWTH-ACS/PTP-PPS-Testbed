#!/bin/bash
# Sample phc_ctl cmp for ens2f0 (osa5422), ens2f1 (cm-ptp-1), ens2f2 (osa5404), ens2f3 (cm-ptp-2) at 10 Hz, write to CSV.
# Phases: 1 = ptp4l init, 2 = phc2sys warmup, 3 = main capture

# does vs code break chmod permissions? No, i guess?

OUTFILE="phc_cmp_$(date +%Y%m%d_%H%M%S).csv"
PTP_WARMUP=120
PHC_WARMUP=30

while getopts "f:p:c:" opt; do
    case $opt in
        f) OUTFILE=$OPTARG ;;
        p) PTP_WARMUP=$OPTARG;;
        c) PHC_WARMUP=$OPTARG;;
    esac
done

#OUTFILE="phc_cmp_$(date +%Y%m%d_%H%M%S).csv"
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

# Write CSV header and start sampling loop immediately.
echo "phase,timestamp_ns,osa5422_ts,osa5422,cm-ptp-1_ts,cm-ptp-1,osa5404_ts,osa5404,cm-ptp-2_ts,cm-ptp-2,ptp4l_osa5422_ts,ptp4l_osa5422_rms,ptp4l_osa5422_max_offset,ptp4l_osa5422_freq,ptp4l_osa5422_freq_dev,ptp4l_osa5422_delay,ptp4l_osa5422_delay_dev,ptp4l_cm-ptp-1_ts,ptp4l_cm-ptp-1_rms,ptp4l_cm-ptp-1_max_offset,ptp4l_cm-ptp-1_freq,ptp4l_cm-ptp-1_freq_dev,ptp4l_cm-ptp-1_delay,ptp4l_cm-ptp-1_delay_dev,ptp4l_osa5404_ts,ptp4l_osa5404_rms,ptp4l_osa5404_max_offset,ptp4l_osa5404_freq,ptp4l_osa5404_freq_dev,ptp4l_osa5404_delay,ptp4l_osa5404_delay_dev,ptp4l_cm-ptp-2_ts,ptp4l_cm-ptp-2_rms,ptp4l_cm-ptp-2_max_offset,ptp4l_cm-ptp-2_freq,ptp4l_cm-ptp-2_freq_dev,ptp4l_cm-ptp-2_delay,ptp4l_cm-ptp-2_delay_dev" | tee "$OUTFILE"

echo "1" >"$PHASE_FILE"

sampling_loop() {
    local next_ns
    next_ns=$(now_ns)
    while true; do
        local ts phase
        ts=$(date -u +%s%N)
        phase=$(<"$PHASE_FILE")

        phc_ctl ens2f0 cmp >"$TMP_OSA5422"   2>&1 &
        local PID_OSA5422=$!
        phc_ctl ens2f1 cmp >"$TMP_CM_PTP_1"  2>&1 &
        local PID_CM_PTP_1=$!
        phc_ctl ens2f2 cmp >"$TMP_OSA5404"   2>&1 &
        local PID_OSA5404=$!
        phc_ctl ens2f3 cmp >"$TMP_CM_PTP_2"  2>&1 &
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

        local ptp4l_osa5422_line ptp4l_cm_ptp_1_line ptp4l_osa5404_line ptp4l_cm_ptp_2_line
        ptp4l_osa5422_line=$(tail -1 "$PTP4L_OSA5422_LOG"   2>/dev/null)
        ptp4l_cm_ptp_1_line=$(tail -1 "$PTP4L_CM_PTP_1_LOG" 2>/dev/null)
        ptp4l_osa5404_line=$(tail -1 "$PTP4L_OSA5404_LOG"   2>/dev/null)
        ptp4l_cm_ptp_2_line=$(tail -1 "$PTP4L_CM_PTP_2_LOG" 2>/dev/null)

        local ptp4l_osa5422_ts ptp4l_osa5422_rms ptp4l_osa5422_max_offset ptp4l_osa5422_freq ptp4l_osa5422_freq_dev ptp4l_osa5422_delay ptp4l_osa5422_delay_dev
        ptp4l_osa5422_ts=$(echo "$ptp4l_osa5422_line"         | grep -oP '(?<=ptp4l\[)[0-9.]+(?=\])')
        ptp4l_osa5422_rms=$(echo "$ptp4l_osa5422_line"        | grep -oP 'rms\s+\K[-+]?\d+')
        ptp4l_osa5422_max_offset=$(echo "$ptp4l_osa5422_line" | grep -oP 'max\s+\K[-+]?\d+')
        ptp4l_osa5422_freq=$(echo "$ptp4l_osa5422_line"       | grep -oP 'freq\s+\K[-+]?\d+')
        ptp4l_osa5422_freq_dev=$(echo "$ptp4l_osa5422_line"   | grep -oP 'freq\s+[-+]?\d+\s*\+/-\s*\K\d+')
        ptp4l_osa5422_delay=$(echo "$ptp4l_osa5422_line"      | grep -oP 'delay\s+\K[-+]?\d+')
        ptp4l_osa5422_delay_dev=$(echo "$ptp4l_osa5422_line"  | grep -oP 'delay\s+\d+\s*\+/-\s*\K\d+')

        local ptp4l_cm_ptp_1_ts ptp4l_cm_ptp_1_rms ptp4l_cm_ptp_1_max_offset ptp4l_cm_ptp_1_freq ptp4l_cm_ptp_1_freq_dev ptp4l_cm_ptp_1_delay ptp4l_cm_ptp_1_delay_dev
        ptp4l_cm_ptp_1_ts=$(echo "$ptp4l_cm_ptp_1_line"             | grep -oP '(?<=ptp4l\[)[0-9.]+(?=\])')
        ptp4l_cm_ptp_1_rms=$(echo "$ptp4l_cm_ptp_1_line"            | grep -oP 'rms\s+\K[-+]?\d+')
        ptp4l_cm_ptp_1_max_offset=$(echo "$ptp4l_cm_ptp_1_line"     | grep -oP 'max\s+\K[-+]?\d+')
        ptp4l_cm_ptp_1_freq=$(echo "$ptp4l_cm_ptp_1_line"           | grep -oP 'freq\s+\K[-+]?\d+')
        ptp4l_cm_ptp_1_freq_dev=$(echo "$ptp4l_cm_ptp_1_line"       | grep -oP 'freq\s+[-+]?\d+\s*\+/-\s*\K\d+')
        ptp4l_cm_ptp_1_delay=$(echo "$ptp4l_cm_ptp_1_line"          | grep -oP 'delay\s+\K[-+]?\d+')
        ptp4l_cm_ptp_1_delay_dev=$(echo "$ptp4l_cm_ptp_1_line"      | grep -oP 'delay\s+\d+\s*\+/-\s*\K\d+')

        local ptp4l_osa5404_ts ptp4l_osa5404_rms ptp4l_osa5404_max_offset ptp4l_osa5404_freq ptp4l_osa5404_freq_dev ptp4l_osa5404_delay ptp4l_osa5404_delay_dev
        ptp4l_osa5404_ts=$(echo "$ptp4l_osa5404_line"         | grep -oP '(?<=ptp4l\[)[0-9.]+(?=\])')
        ptp4l_osa5404_rms=$(echo "$ptp4l_osa5404_line"        | grep -oP 'rms\s+\K[-+]?\d+')
        ptp4l_osa5404_max_offset=$(echo "$ptp4l_osa5404_line" | grep -oP 'max\s+\K[-+]?\d+')
        ptp4l_osa5404_freq=$(echo "$ptp4l_osa5404_line"       | grep -oP 'freq\s+\K[-+]?\d+')
        ptp4l_osa5404_freq_dev=$(echo "$ptp4l_osa5404_line"   | grep -oP 'freq\s+[-+]?\d+\s*\+/-\s*\K\d+')
        ptp4l_osa5404_delay=$(echo "$ptp4l_osa5404_line"      | grep -oP 'delay\s+\K[-+]?\d+')
        ptp4l_osa5404_delay_dev=$(echo "$ptp4l_osa5404_line"  | grep -oP 'delay\s+\d+\s*\+/-\s*\K\d+')

        local ptp4l_cm_ptp_2_ts ptp4l_cm_ptp_2_rms ptp4l_cm_ptp_2_max_offset ptp4l_cm_ptp_2_freq ptp4l_cm_ptp_2_freq_dev ptp4l_cm_ptp_2_delay ptp4l_cm_ptp_2_delay_dev
        ptp4l_cm_ptp_2_ts=$(echo "$ptp4l_cm_ptp_2_line"             | grep -oP '(?<=ptp4l\[)[0-9.]+(?=\])')
        ptp4l_cm_ptp_2_rms=$(echo "$ptp4l_cm_ptp_2_line"            | grep -oP 'rms\s+\K[-+]?\d+')
        ptp4l_cm_ptp_2_max_offset=$(echo "$ptp4l_cm_ptp_2_line"     | grep -oP 'max\s+\K[-+]?\d+')
        ptp4l_cm_ptp_2_freq=$(echo "$ptp4l_cm_ptp_2_line"           | grep -oP 'freq\s+\K[-+]?\d+')
        ptp4l_cm_ptp_2_freq_dev=$(echo "$ptp4l_cm_ptp_2_line"       | grep -oP 'freq\s+[-+]?\d+\s*\+/-\s*\K\d+')
        ptp4l_cm_ptp_2_delay=$(echo "$ptp4l_cm_ptp_2_line"          | grep -oP 'delay\s+\K[-+]?\d+')
        ptp4l_cm_ptp_2_delay_dev=$(echo "$ptp4l_cm_ptp_2_line"      | grep -oP 'delay\s+\d+\s*\+/-\s*\K\d+')

        echo "${phase},${ts},${osa5422_ts},${osa5422},${cm_ptp_1_ts},${cm_ptp_1},${osa5404_ts},${osa5404},${cm_ptp_2_ts},${cm_ptp_2},${ptp4l_osa5422_ts},${ptp4l_osa5422_rms},${ptp4l_osa5422_max_offset},${ptp4l_osa5422_freq},${ptp4l_osa5422_freq_dev},${ptp4l_osa5422_delay},${ptp4l_osa5422_delay_dev},${ptp4l_cm_ptp_1_ts},${ptp4l_cm_ptp_1_rms},${ptp4l_cm_ptp_1_max_offset},${ptp4l_cm_ptp_1_freq},${ptp4l_cm_ptp_1_freq_dev},${ptp4l_cm_ptp_1_delay},${ptp4l_cm_ptp_1_delay_dev},${ptp4l_osa5404_ts},${ptp4l_osa5404_rms},${ptp4l_osa5404_max_offset},${ptp4l_osa5404_freq},${ptp4l_osa5404_freq_dev},${ptp4l_osa5404_delay},${ptp4l_osa5404_delay_dev},${ptp4l_cm_ptp_2_ts},${ptp4l_cm_ptp_2_rms},${ptp4l_cm_ptp_2_max_offset},${ptp4l_cm_ptp_2_freq},${ptp4l_cm_ptp_2_freq_dev},${ptp4l_cm_ptp_2_delay},${ptp4l_cm_ptp_2_delay_dev}" | tee -a "$OUTFILE"

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

# Phase 1 — ptp4l init: start all daemons, mirror output for 120 s.
echo "phase 1: ptp4l init" >/tmp/test_status
echo "Phase 1: starting ptp4l on ens2f0, ens2f1, ens2f2, and ens2f3..." >&2
ptp4l -i ens2f0 -m -s -2 >"$PTP4L_OSA5422_LOG"   2>&1 &
PTP4L_OSA5422_PID=$!
ptp4l -i ens2f1 -m -s -2 >"$PTP4L_CM_PTP_1_LOG"  2>&1 &
PTP4L_CM_PTP_1_PID=$!
ptp4l -i ens2f2 -m -s -2 >"$PTP4L_OSA5404_LOG"   2>&1 &
PTP4L_OSA5404_PID=$!
ptp4l -i ens2f3 -m -s -2 >"$PTP4L_CM_PTP_2_LOG"  2>&1 &
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

# Phase 2 — phc2sys warmup: discipline CLOCK_REALTIME for 30 s.
echo "2" >"$PHASE_FILE"
echo "phase 2: phc2sys warmup" >/tmp/test_status
echo "Phase 2: phc2sys warmup for $(PHC_WARMUP) seconds..." >&2
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
