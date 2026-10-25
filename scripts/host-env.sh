# Source on an x86_64 Linux build host (context-binary generation). Needs ~15 GB RAM + ~24 GB swap.
#   export QAIRT_SDK_ROOT=~/qairt/qairt/2.48.0.260626 ; python 3.12 venv already activated
: "${QAIRT_SDK_ROOT:?set QAIRT_SDK_ROOT}"
export QNN_SDK_ROOT=$QAIRT_SDK_ROOT
export PYTHONPATH=$QAIRT_SDK_ROOT/lib/python
PYLIB=$(python3 -c 'import sysconfig;print(sysconfig.get_config_var("LIBDIR"))')
export LD_LIBRARY_PATH=$QAIRT_SDK_ROOT/lib/x86_64-linux-clang:$PYLIB
export PATH=$QAIRT_SDK_ROOT/bin/x86_64-linux-clang:$PATH
export QAIRT_TMP_DIR=${QAIRT_TMP_DIR:-$PWD/scratch}; mkdir -p "$QAIRT_TMP_DIR"
