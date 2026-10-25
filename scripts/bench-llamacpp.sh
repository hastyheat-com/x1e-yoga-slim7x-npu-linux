#!/bin/bash
# llama.cpp GPU (Vulkan) vs HTP (dspqueue) bench with a REAL time cap.
# Note: HTP0 hangs on mainline kernels (see README "dspqueue hang"); this script stops the cDSP
# before killing a hung run instead of SIGKILLing it.
# Usage: bench-llamacpp.sh MODEL.gguf  (env: LLAMA_VK=dir of vulkan build, LLAMA_HTP=dir of snapdragon build)
M=$1; CAP=${CAP:-180}
st(){ echo "## $(date +%T) maxtemp=$(sort -n /sys/class/thermal/thermal_zone*/temp|tail -1)"; }
run(){ "$@" & local p=$!; for i in $(seq $CAP); do kill -0 $p 2>/dev/null || { wait $p; echo rc=$?; return; }; sleep 1; done
  echo "TIMEOUT: stopping cdsp first"; sudo "$(dirname "$0")/npu-safe-stop.sh" $p; }
st; LD_LIBRARY_PATH=$LLAMA_VK run $LLAMA_VK/llama-bench -m "$M" -dev Vulkan0 -ngl 99 -p 128 -n 32 -r 2 -o md
st; LD_LIBRARY_PATH=$LLAMA_HTP/lib:/opt/hexagon/fastrpc/lib ADSP_LIBRARY_PATH=$LLAMA_HTP/lib \
  run $LLAMA_HTP/bin/llama-bench -m "$M" -dev HTP0 -ngl 99 -t 6 -p 128 -n 32 -r 2 -o md
