#!/usr/bin/env bash
# Simple VISA / JupyterLab setup for SFN_TOF_INS_School
set -e
source /opt/conda/etc/profile.d/conda.sh

# To rebuild an older environment: CLEAN=1 bash setup_mcstas_visa.sh
if [[ "${CLEAN:-0}" == 1 ]] && conda env list | awk '{print $1}' | grep -qx mcstas; then
  conda env remove -n mcstas -y
fi

packages=(python=3.12 pip mcstas mcstasscript scipp scippneutron plopp pyarrow numpy scipy pandas matplotlib h5py hdf5plugin xarray ipykernel ipywidgets ipympl jupyterlab tqdm pyyaml)
if conda env list | awk '{print $1}' | grep -qx mcstas; then
  conda install -n mcstas --override-channels -c conda-forge --solver=libmamba -y "${packages[@]}"
else
  conda create -n mcstas --override-channels -c conda-forge --solver=libmamba -y "${packages[@]}"
fi
conda run -n mcstas python -m pip install mpld3
conda run -n mcstas python -m ipykernel install --user --name mcstas --display-name 'Python (mcstas)'
echo '--- Installation checks ---'
conda run -n mcstas mcrun --version
conda run -n mcstas python -c 'import mcstasscript, scipp, plopp, pyarrow, mpld3; print("Python packages OK")'
conda run -n mcstas python -m jupyter kernelspec list
echo 'Done. Refresh VISA JupyterLab and choose Python (mcstas).'
