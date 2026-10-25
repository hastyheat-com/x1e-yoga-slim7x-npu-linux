# LLMs on the Hexagon NPU of a Snapdragon X Elite laptop under Linux

**Lenovo Yoga Slim 7x (83ED, X1E80100), mainline-based kernel 7.2.9, October 2026**

This is our write-up of getting the Hexagon NPU (cDSP / HTP v73) in a Snapdragon X Elite laptop to run an LLM under plain Linux, with no Windows and no Android. It covers what works, what still doesn't, the exact steps we took, and the patches and scripts we used.

> **Nothing from Qualcomm is redistributed here.** No SDK, no libraries, no DSP firmware and no DSP userland are included. Every reader downloads the Qualcomm SDK themselves under Qualcomm's licence (step 3), and copies the DSP firmware and userland from their **own** Windows install (step 1). This repo only has our own scripts and configs, plus GPL kernel patches.

## TL;DR

| Path | Status | Llama-3.2-1B-Instruct Q4_0 (prompt / generation tok/s) |
|---|---|---|
| **NPU via QAIRT 2.48.0.260626 + Genie 1.19 (QnnHtp)** | **Works** | **194.6 / 11.7** (TTFT 123 ms, init 0.97 s, temp 53-54 C) |
| GPU via llama.cpp b11876 Vulkan (Adreno X1-85) | Works | 273.1 / 37.8 (pp128 / tg32) |
| NPU via llama.cpp `ggml-hexagon` (HTP0, dspqueue) | **Hangs** at the first compute round-trip (needs kernel DSPSIGNAL; see below) | - |

What made the NPU path work:

1. **Kernel `7.2.9-yoga-lean-npu1`**: our 7.2.9 config plus Shawn Guo's fastrpc patch *"Drop unhandled DSP PD exit notification" v2* (`patches/kernel/0001-*`). It removes the `No context ID matches response` errors.
2. **Matching cDSP firmware and DSP userland, both `CDSP.HT.2.9.c1-00075`**, taken from the laptop's own Windows driver package.
3. **libcdsprpc** built from [qualcomm/fastrpc](https://github.com/qualcomm/fastrpc), plus a udev rule and a machine config.
4. **QAIRT 2.48.0.260626** (the public Community edition). We built the context binary on an x86_64 host and ran it with `genie-t2t-run` on the laptop.

Be honest with yourself about the speed. On this 1B model the NPU is slower than the GPU, especially at generation (11.7 vs 37.8 tok/s). What it does do is leave the GPU and CPU free and stay cool. The single-graph build we used (ar1 + ar64, cl 4096, one split) is a first working baseline. It is not tuned.

---

## 0. Hardware and software baseline

- Lenovo Yoga Slim 7x 14Q8X9 (83ED), X1E80100, 32 GB RAM
- Kernel 7.2.9 (stable) with our "lean" config: `CONFIG_QCOM_FASTRPC=m`, `CONFIG_DMA_CMA=y`, `CONFIG_DMABUF_HEAPS_SYSTEM/CMA=y`
- Kernel command line used: `clk_ignore_unused pd_ignore_unused cma=128M efi=noruntime`
- Mesa 26.0.8, linux-firmware 20260319, Ubuntu-based userland
- A separate **x86_64 Linux** box (8 cores, 15 GB RAM **plus 24 GB swap**; it OOMs without the swap) to build the NPU context binary. QAIRT's GenAI builder only ships x86_64 host binaries.

## 1. DSP firmware and DSP userland (from your own Windows install)

The cDSP **firmware** (`qccdsp8380.mbn`) and the DSP-side **userland** (`fastrpc_shell_unsigned_3` and friends) **must come from the same release**. A mismatch was one of our early failures. The packaged `linux-firmware` `.zst` for 83ED is `c2-00051`, while the Windows NPU driver ships `c1-00075`.

1. Mount the Windows partition read-only: `sudo mount -o ro /dev/nvme0n1p3 /mnt/win`. Your partition number may differ.
2. Look in `/mnt/win/Windows/System32/DriverStore/FileRepository/` for the `qcnspmcdm_ext_cdsp8380.inf_arm64_*` directories. Identify the version with `strings qccdsp8380.mbn | grep CDSP.HT`. We used the **c1-00075** package. It contains `qccdsp8380.mbn`, `cdsp_dtbs.elf` and a `CDSP/` directory with `fastrpc_shell_unsigned_3` and the skel libraries.
3. Put the firmware where the kernel prefers it, under `updates/` so it overrides the packaged file:
   `/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED/qccdsp8380.mbn` (and `cdsp_dtbs.elf`)
4. Put the DSP userland (the contents of `CDSP/`) at `/opt/hexagon/qcom/x1e80100/lenovo-83ED-win-c1-00075/cdsp/`.
5. Rebuild the initramfs, for example `sudo dracut --force` or `update-initramfs -u`, and check that it contains the `updates/` firmware.
6. After a reboot, `dmesg | grep -i cdsp` should show the remoteproc loading a firmware of the same size as the file you installed (ours is 3195304 bytes). `cat /sys/class/remoteproc/remoteproc*/name` and `state` should show cdsp `running`.

Do **not** share these files. They are Qualcomm/Lenovo binaries.

## 2. Kernel: 7.2.9 + fastrpc PD-exit patch ("npu1")

```bash
cd linux-7.2.9                       # tree with the config of your working kernel
git apply patches/kernel/0001-misc-fastrpc-drop-unhandled-DSP-PD-exit-notification-v2.patch   # or: patch -p1 <
scripts/config --set-str LOCALVERSION -yoga-lean-npu1
make olddefconfig
make -j6 Image modules dtbs          # see scripts/thermguard.sh - our thin laptop hit 93 C
sudo make modules_install
sudo cp arch/arm64/boot/Image /boot/vmlinuz-7.2.9-yoga-lean-npu1
sudo cp System.map .config /boot/   # rename with the -npu1 suffix
# use the SAME dtb as your working kernel
sudo dracut --force /boot/initrd.img-7.2.9-yoga-lean-npu1 7.2.9-yoga-lean-npu1
sudo update-grub
sudo grub-reboot "<menu id of the new entry>"   # one-shot boot; keep your default as fallback
```

Keep your current kernel as the GRUB default until the new one has proven itself. On first boot, check that the keyboard and touchpad (i2c-hid) work. Also check that `dmesg` no longer shows `No context ID matches response`. The only fastrpc message left for us was the harmless `no reserved DMA memory for FASTRPC`.

## 3. Getting the Qualcomm AI Runtime (QAIRT) SDK yourself

We used **QAIRT 2.48.0.260626**, "Qualcomm AI Runtime – Community". It contains the QNN HTP backend, the Genie LLM runtime (libGenie 1.19.0) and the GenAI builder.

### Option A: direct public download (what we did; no account needed)

1. Read the licence first. The zip contains `LICENSE.pdf`, Qualcomm's **"AI Stack License"**. By downloading and using the SDK you accept it. Among other things it allows use for developing your own applications and benchmarking. It does **not** allow redistributing the SDK on its own, which is why it isn't in this repo.
2. Download the zip (2,261,832,373 bytes). `scripts/get-qairt.sh` does this with resume, because our downloads broke several times:
   ```
   https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/2.48.0.260626/v2.48.0.260626.zip
   ```
   We actually fetched it from the equivalent `https://apigwx-aws.qualcomm.com/qsc/public/v1/api/download/...` path with the same version components.
3. Verify the download:
   `sha256 = 12602a9f6f389671ef75ee5e7f37d863e47cbbe385a0020277a1d5783c496283`
4. Install: `unzip v2.48.0.260626.zip -d ~/qairt` gives you `~/qairt/qairt/2.48.0.260626`. Use that path as `QAIRT_SDK_ROOT`. Unzip it on **both** machines: the x86_64 build host and the laptop.

### Option B: Qualcomm Package Manager (needs a Qualcomm ID)

1. Create a Qualcomm ID. Go to <https://qpm.qualcomm.com>, choose *Sign in → Register*, use your email address and confirm it.
2. Sign in, open **Tools**, search for "Qualcomm AI Runtime" and pick **Qualcomm AI Runtime – Community Edition**.
3. Pick version **2.48.0.260626** from the version list, accept the licence prompt, then click **Download** (web) or **Extract** (QPM desktop).
4. Or use the CLI: `qpm-cli --login <you>`, then `qpm-cli --license-activate qualcomm_ai_runtime_sdk`, then `qpm-cli --install qualcomm_ai_runtime_sdk --version 2.48.0.260626`.
5. Point `QAIRT_SDK_ROOT` at the extracted `qairt/2.48.0.260626` directory.

### Verify the SDK

On the **laptop**, once steps 1, 2 and 4 are done:

```bash
export QAIRT_SDK_ROOT=~/qairt/qairt/2.48.0.260626
export DSP_USERLAND=/opt/hexagon/qcom/x1e80100/lenovo-83ED-win-c1-00075/cdsp
. scripts/npu-env.sh
qnn-platform-validator --backend dsp --testBackend
# expect: "Unit Test: Passed" / "QNN is supported for backend DSP"
genie-t2t-run --help >/dev/null && echo genie ok
```

On the **x86_64 host**: `ls $QAIRT_SDK_ROOT/bin/x86_64-linux-clang` and `python3 -c "import qairt"` (after `. scripts/host-env.sh`).

Notes:
- The binaries that run on the laptop are in `bin/aarch64-oe-linux-gcc11.2` and `lib/aarch64-oe-linux-gcc11.2`. The DSP side is in **`lib-safe/hexagon-v73/unsigned`** (X1E is HTP **v73**). For runtime libraries, use `lib-safe/aarch64-oe-linux-gcc11.2` ahead of `lib/`, the same as the working ThinkPad T14s recipe.
- No `cdsprpcd` daemon was needed with our libcdsprpc and `ADSP_LIBRARY_PATH`.
- You do **not** need the Hexagon SDK for any of this.

## 4. libcdsprpc, udev and machine config (laptop)

```bash
git clone https://github.com/qualcomm/fastrpc && cd fastrpc   # we used d247519
./gitcompile   # or: autoreconf -fi
./configure --prefix=/opt/hexagon/fastrpc --with-config-base-dir=/opt/hexagon/qcom/
make -j4 && sudo make install
sudo mkdir -p /opt/hexagon/qcom/conf.d
sudo cp config/fastrpc-machine-yoga-slim7x.yaml /opt/hexagon/qcom/conf.d/
sudo groupadd -f fastrpc && sudo usermod -aG fastrpc $USER
sudo cp config/60-fastrpc.rules /etc/udev/rules.d/ && sudo udevadm control --reload && sudo udevadm trigger -s misc
```

Sanity test of the **synchronous** FastRPC path:
`LD_LIBRARY_PATH=/opt/hexagon/fastrpc/lib:/opt/hexagon/fastrpc/lib/fastrpc_test /opt/hexagon/fastrpc/bin/fastrpc_test -d 3 -U 1 -a v68`
The calculator test passed (Sum=499500) and multithreading passed. `hap_example` MEM dmahandle failed with 0x4e.

## 5. Build the NPU context binary (x86_64 host)

```bash
uv venv --python 3.12 && . .venv/bin/activate
# $QAIRT_SDK_ROOT/bin/check-python-dependency refuses non-Ubuntu hosts; we installed by hand:
uv pip install torch transformers onnx onnxruntime onnxscript onnx_ir onnxruntime_genai \
    jinja2 islpy sentencepiece msgpack zstandard gguf "numpy<2"
sudo apt install libc++1 libc++abi1
export QAIRT_SDK_ROOT=~/qairt/qairt/2.48.0.260626; . scripts/host-env.sh
# model: bartowski/Llama-3.2-1B-Instruct-GGUF  Llama-3.2-1B-Instruct-Q4_0.gguf
#   sha256 fa0390e7c043f89ae1847bd6682d748041a99d4ef3de0e0b27d33b6af97a8be8
# plus tokenizer.json / config.json / generation_config.json / tokenizer_config.json
#   from unsloth/Llama-3.2-1B-Instruct, in the same folder
python3 scripts/build_ctx.py llama1b/Llama-3.2-1B-Instruct-Q4_0.gguf out-llama1b cache-llama1b
```

The versions we ran: torch 2.14.1, transformers 5.20.2, onnx 1.23.2, onnxruntime 1.31.0, numpy 1.26.4, gguf 0.19.0, Python 3.12.15.

The builder is `GGUFBuilderHTP`, targeting `chipset:SC8380XP`. It produced the SHA graphs `ar1` and `ar64`, context 4096 and 1 split, in about 20 minutes. The output is `models/split_0/model.bin` (1.41 GB), `backend_extensions.json` (soc_model 60, v73) and `tokenizer.json`. You'll see warnings that some ops fall back to float and that `split_embedding` is not enabled. Both are expected.

Copy `genie/genie_config.json` from this repo into the output folder. We wrote it by hand: basic dialog, QnnHtp, kv-dim 64, rope-dim 32, llama3 rope scaling, `ctx-bins: ["models/split_0/model.bin"]`. Then copy the whole folder to the laptop and check its sha256 on both ends.

## 6. Run on the NPU (laptop)

```bash
scripts/run-genie.sh ~/npu-genie/out-llama1b "What is a fireplace grate heater? Answer in two sentences."
```

Our result: `libGenie 1.19.0`, init 0.97 s, prompt 24 tokens at **194.6 tok/s** (TTFT 123 ms), 77 tokens generated at **11.70 tok/s**. The answer was coherent. The temperature went from 52.8 to 54.1 C. cdsp stayed `running` and the kernel logged no errors.

## ⚠️ Safety: never SIGKILL a process that is waiting on the NPU

When a process with FastRPC invokes still in flight is killed with `kill -9`, the cDSP crashes. We saw `sleep_statsi.c:537`, after which the remoteproc auto-recovered. The next session then failed to open (`HTP0 failed to open session ... 0xffffffff`). Also make sure you kill the **real** PID: our first timeout wrapper killed its own subshell and left the hung process running. On our distro, uutils `timeout` segfaulted and enforced nothing.

What to do instead: **stop the cDSP remoteproc first**, then end the process, then start the cDSP again. `scripts/npu-safe-stop.sh` does exactly this. Caveat: this is the documented safe order, but we have not yet tested it against a hung process ourselves.

## Known issue: llama.cpp `ggml-hexagon` (HTP0) hangs, because DSPSIGNAL is not in mainline

With llama.cpp b11876's official `snapdragon` arm64 build, `--list-devices` shows `HTP0 v73` and the session opens. Then the first compute round-trip never returns. The host sits in `dspqueue_read` / `futex_wait` and the DSP never consumes the request. We saw it with Qwen3-1.7B Q4_0 (hung for 13 minutes), and earlier with gemma-4-26B and Qwen3.6-35B, which also hit `rpcmem_alloc 918MB` failures.

Root cause, as tracked in [qualcomm/fastrpc#377](https://github.com/qualcomm/fastrpc/issues/377) and [llama.cpp discussion #23887](https://github.com/ggml-org/llama.cpp/discussions/23887): the dspqueue completion path needs either `FASTRPC_IOCTL_DSPSIGNAL_*` in the kernel, or kernel-side routing of the DSP's `0xabcdabcd` broadcast. Neither exists in mainline. The 2024 *"[PATCH v1 00/16] Add missing features to FastRPC driver"* series, which included *"14/16 Add DSP signal support"*, was never merged. Upstream libcdsprpc also stubs `ioctl_signal_*` as `AEE_EUNSUPPORTED`.

**Experimental:** `patches/kernel/0002-*` forward-ports that DSP-signal patch to 7.2.9, and `patches/fastrpc-userspace/0001-*` wires up libcdsprpc to match. It uses a **private** ioctl number, so it is not ABI-stable. It builds, but at the time of publishing it had **not been boot-tested**. Note that the reporter of #377 backported the dspsignal ioctls on X2 Elite and still saw the hang. Treat this as a test vehicle, not a fix. We will update this README with the X1E result.

The Surface Pro 11 guide by denisix runs HTP0 on Jens Glathe's 7.1.3 kernel with a patched `fastrpc.ko` ("GLINK framing fix") that isn't published. We compared Jens' public 7.1.y / 7.2rc branches and found no DSPSIGNAL or uapi changes there.

## Bug list (what we hit, in order)

1. cDSP firmware and DSP userland mismatch (`c2-00051` packaged vs `c1-00075` Windows). Fix: use the matching Windows pair (step 1).
2. `No context ID matches response` from fastrpc, because the DSP PD-exit notification has ctx `0xABCDABCD`. Fix: PD-exit patch v2 (`0001`).
3. llama.cpp HTP0 hangs at the first dspqueue round-trip because mainline has no DSPSIGNAL. **Open.** See above, #377 and `0002`.
4. SIGKILLing an NPU-waiting process crashes the cDSP, and the next session open fails. Workaround: stop the remoteproc first.
5. `rpcmem_alloc` of 918 MB fails for big models with CMA at 128M. Open; not pursued, since big models went to the GPU.
6. `hap_example` MEM dmahandle test fails (0x4e) in `fastrpc_test`. Open, minor.
7. uutils `timeout` segfaults and doesn't enforce timeouts. Use a shell loop or the `scripts/bench-llamacpp.sh` cap.
8. `check-python-dependency` refuses non-Ubuntu x86 hosts. Install the deps by hand (step 5).
9. The context-binary build OOMs at 15 GB RAM. Add about 24 GB of swap.
10. A kernel build at -j6 hits 93 C on this thin laptop. Use `scripts/thermguard.sh` (SIGSTOP at 88 C, resume at 75 C).
11. The QAIRT download keeps dropping. Resume with `curl -C -` (`scripts/get-qairt.sh`).

## Repo layout

```
patches/kernel/0001-...pd-exit-v2.patch         upstream-posted fix (Shawn Guo, Qualcomm), GPL-2.0
patches/kernel/0002-EXPERIMENTAL-...dspsignal   our forward-port of the 2024 DSP-signal patch, GPL-2.0
patches/fastrpc-userspace/0001-...              libcdsprpc side of the experiment (BSD-3-Clause, like qualcomm/fastrpc)
config/                                         udev rule, fastrpc machine yaml
genie/                                          genie_config.json, example backend_extensions.json
scripts/                                        download/verify, env, build, run, safety, thermal guard, bench
```

## Credits

The Qualcomm fastrpc and kernel developers: Shawn Guo for the PD-exit patch, and Ekansh Gupta and Anandu Krishnan E for the 2024 DSP-signal patch. Also UnsignedChad (the T14s QAIRT/Genie path), denisix (the Surface Pro 11 guide), Jens Glathe (the X1E kernel trees), and the participants in llama.cpp #23887 and fastrpc #377.

Licence: our scripts and docs are MIT. The kernel patches are GPL-2.0. The userspace patch follows qualcomm/fastrpc (BSD-3-Clause). Qualcomm software stays under Qualcomm's terms, and none of it is included here.

— Hasty Heat
