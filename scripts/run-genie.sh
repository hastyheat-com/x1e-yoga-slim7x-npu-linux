#!/bin/bash
# Run a prompt on the NPU with Genie. Usage: run-genie.sh CTXDIR "question"
# CTXDIR holds genie_config.json, backend_extensions.json, tokenizer.json, models/split_0/model.bin
set -eu
here=$(dirname "$(readlink -f "$0")"); . "$here/npu-env.sh"
cd "$1"
P="<|begin_of_text|><|start_header_id|>user<|end_header_id|>

$2<|eot_id|><|start_header_id|>assistant<|end_header_id|>

"
exec genie-t2t-run -c genie_config.json -p "$P" --profile profile.json
