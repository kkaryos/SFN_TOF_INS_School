
#!/usr/bin/env bash
set -e

# Initialize Conda
source /opt/conda/etc/profile.d/conda.sh

# Create environment if needed
if ! conda env list | grep -Eq '^[[:space:]]*mcstas[[:space:]]'; then
    conda create -y -n mcstas python=3.12
fi

# Install McStas and school packages
conda install -y -n mcstas conda-forge::mcstas
conda install -y -n mcstas -c conda-forge \
    ipykernel ipywidgets jupyterlab \
    scipp plopp mpld3 pyarrow \
    numpy scipy matplotlib pandas h5py

# Register Jupyter kernel
conda run -n mcstas python -m ipykernel install \
    --user --name mcstas --display-name "mcstas"

echo "McStas environment ready!"
echo "Select the 'mcstas' kernel in JupyterLab."
