#!/bin/bash
# Safely stop a process that is stuck waiting on the NPU.
# NEVER kill -9 it first: with fastrpc invokes in flight that crashed the cDSP for us.
# Stop the cDSP remoteproc first (fails the in-flight calls), then end the process, then restart the DSP.
# Usage: sudo npu-safe-stop.sh PID
set -u
PID=$1
RP=$(grep -l -i cdsp /sys/class/remoteproc/remoteproc*/name | head -1 | xargs dirname)
echo "cdsp remoteproc: $RP ($(cat $RP/state))"
echo stop > $RP/state; sleep 2
kill -TERM "$PID" 2>/dev/null; sleep 3
kill -0 "$PID" 2>/dev/null && kill -KILL "$PID"
echo start > $RP/state; sleep 2
echo "cdsp now: $(cat $RP/state)"
