#!/bin/bash
# Resumable download of the PUBLIC Qualcomm AI Runtime (QAIRT) Community zip.
# By downloading you accept Qualcomm's "AI Stack License" (LICENSE.pdf inside the zip).
# Usage: get-qairt.sh [destdir]   (default ~/qairt)
set -eu
V=2.48.0.260626
SIZE=2261832373
SHA=12602a9f6f389671ef75ee5e7f37d863e47cbbe385a0020277a1d5783c496283
U="https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/$V/v$V.zip"
# Alternate host that worked for us: https://apigwx-aws.qualcomm.com/qsc/public/v1/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/$V/v$V.zip
D=${1:-$HOME/qairt}; mkdir -p "$D"; cd "$D"; F=v$V.zip
for i in $(seq 40); do
  s=$(stat -c %s "$F" 2>/dev/null || echo 0); [ "$s" -ge "$SIZE" ] && break
  curl -fL -C - -o "$F" "$U" || true; sleep 3
done
echo "$SHA  $F" | sha256sum -c -
unzip -q -n "$F"
echo "QAIRT_SDK_ROOT=$D/qairt/$V"
