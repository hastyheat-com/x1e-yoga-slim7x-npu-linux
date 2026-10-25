#!/bin/bash
# Pause a long build (SIGSTOP its process group) at >= 88 C, resume at <= 75 C.
# Thin fanless-ish laptops hit 93 C during -j6 kernel builds. Usage: thermguard.sh "<pgrep -f pattern of make>"
PAT=$1; p=0
while pgrep -f "$PAT" >/dev/null; do
  t=$(sort -n /sys/class/thermal/thermal_zone*/temp | tail -1)
  PG=$(ps -o pgid= "$(pgrep -f "$PAT" | head -1)" | tr -d ' ')
  if [ $p = 0 ] && [ "$t" -ge 88000 ]; then kill -STOP -- -"$PG"; p=1; echo "paused $(date +%T) $t"; fi
  if [ $p = 1 ] && [ "$t" -le 75000 ]; then kill -CONT -- -"$PG"; p=0; echo "resumed $(date +%T) $t"; fi
  sleep 10
done
