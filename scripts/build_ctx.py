#!/usr/bin/env python3
"""Build an HTP (NPU) context binary for Snapdragon X Elite (SC8380XP, v73) from a GGUF.
Run on x86_64 after `source host-env.sh`.
Usage: build_ctx.py MODEL.gguf OUTDIR [CACHEDIR]
The GGUF dir must also hold tokenizer.json / config.json from the HF model."""
import os, sys
from qairt.gen_ai_api.gen_ai_builder_factory import GenAIBuilderFactory
gguf, out = sys.argv[1], sys.argv[2]
cache = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.getcwd(), "cache")
b = GenAIBuilderFactory.create(gguf, "HTP", cache_root=cache)
print("builder", type(b).__name__)
b.set_targets(["chipset:SC8380XP"])
c = b.build()          # ~20 min on 8 cores for Llama-3.2-1B
c.save(out)
print("SAVED", out)
