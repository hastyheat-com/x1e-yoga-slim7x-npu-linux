#!/bin/bash
# Quick checks: remoteproc state, fastrpc sync path, QNN DSP backend.
here=$(dirname "$(readlink -f "$0")"); . "$here/npu-env.sh"
for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name) $(cat $r/state)"; done
ls -l /dev/fastrpc-* 2>/dev/null
qnn-platform-validator --backend dsp --testBackend
