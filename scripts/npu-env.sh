# Source on the X1E laptop (aarch64) before running QAIRT/Genie on the NPU.
#   export QAIRT_SDK_ROOT=~/qairt/qairt/2.48.0.260626   (where you unzipped it)
#   export DSP_USERLAND=/opt/hexagon/qcom/x1e80100/lenovo-83ED-win-c1-00075/cdsp  (your own Windows-extracted dir)
#   export FASTRPC_PREFIX=/opt/hexagon/fastrpc   (libcdsprpc built from github.com/qualcomm/fastrpc)
: "${QAIRT_SDK_ROOT:?set QAIRT_SDK_ROOT}" "${DSP_USERLAND:?set DSP_USERLAND}"
FASTRPC_PREFIX=${FASTRPC_PREFIX:-/opt/hexagon/fastrpc}
Q=$QAIRT_SDK_ROOT
export LD_LIBRARY_PATH=$FASTRPC_PREFIX/lib:$Q/lib-safe/aarch64-oe-linux-gcc11.2:$Q/lib/aarch64-oe-linux-gcc11.2
export ADSP_LIBRARY_PATH="$Q/lib-safe/hexagon-v73/unsigned;$DSP_USERLAND"
export PATH=$Q/bin/aarch64-oe-linux-gcc11.2:$PATH
