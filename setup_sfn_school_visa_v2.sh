#!/usr/bin/env bash
set -euo pipefail

# Initialize Conda
source /opt/conda/etc/profile.d/conda.sh

# Create environment if needed
if ! conda env list | grep -Eq '^[[:space:]]*mcstas[[:space:]]'; then
    conda create -y -n mcstas --override-channels -c conda-forge python=3.12
fi

# Install McStas 3.10.2 and scientific packages
conda install -y -n mcstas --override-channels -c conda-forge \
    "mcstas=3.10.2" mcstasscript \
    numpy scipy matplotlib pandas h5py pyarrow mpld3 \
    scipp plopp ipympl pythreejs \
    "anywidget>=0.9.21" ipywidgets jupyterlab_widgets \
    jupyterlab ipykernel

# Register Jupyter kernel
conda run -n mcstas python -m ipykernel install \
    --user --name mcstas --display-name "McStas 3.10.2"

# Connect McStas widget extensions to VISA JupyterLab
SERVER_JUPYTER="/opt/conda/envs/jupyterlab/bin/jupyter"

if [[ -x "$SERVER_JUPYTER" ]]; then
    MCSTAS_PREFIX=$(conda run -n mcstas python -c "import sys; print(sys.prefix)")
    SRC="$MCSTAS_PREFIX/share/jupyter/labextensions"
    DST="$("$SERVER_JUPYTER" --data-dir)/labextensions"

    mkdir -p "$DST"

    for ext in anywidget jupyter-threejs jupyterlab-datawidgets jupyter-matplotlib; do
        if [[ ! -f "$SRC/$ext/package.json" ]]; then
            echo "WARNING: Missing extension in McStas: $ext"
        elif [[ -e "$DST/$ext" || -L "$DST/$ext" ]]; then
            echo "Existing extension preserved: $ext"
        else
            ln -s "$SRC/$ext" "$DST/$ext"
            echo "Linked extension: $ext"
        fi
    done

    # Verify VISA frontend extensions
    "$SERVER_JUPYTER" labextension list
else
    echo "VISA JupyterLab not detected; skipping frontend linking."
fi

# Verify McStas and visualization dependencies
conda run -n mcstas mcrun --version
conda run -n mcstas python -c \
    "import scipp, plopp, anywidget, ipympl, ipywidgets, pythreejs; print('Visualization dependencies OK')"
conda run -n mcstas python -c \
    "import shutil; assert shutil.which('mcdisplay-plopp'), 'mcdisplay-plopp not found'; print('mcdisplay-plopp available')"

echo "McStas 3.10.2 environment ready!"
echo "Restart VISA JupyterLab and select the 'McStas 3.10.2' kernel."