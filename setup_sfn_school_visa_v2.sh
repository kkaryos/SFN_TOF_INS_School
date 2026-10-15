#!/usr/bin/env bash
# VISA Ubuntu: McStas + SFN_TOF_INS_School + selectable Jupyter kernel.
set -eo pipefail
set +u  # Conda GCC activation/deactivation hooks may reference unset variables.
ENV_NAME="${ENV_NAME:-mcstas}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/SFN_TOF_INS_School}"
REPO_URL="https://github.com/kkaryos/SFN_TOF_INS_School.git"
log(){ printf '\n==> %s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ -f /opt/conda/etc/profile.d/conda.sh ]]; then source /opt/conda/etc/profile.d/conda.sh
elif command -v conda >/dev/null 2>&1; then source "$(conda info --base)/etc/profile.d/conda.sh"
else fail 'Conda not found; expected /opt/conda or another Conda installation.'; fi

log 'Configuring Bash activation for future terminals'
conda init bash >/dev/null || echo 'WARNING: conda init bash failed; use source /opt/conda/etc/profile.d/conda.sh.' >&2

# Avoid activating/deactivating inside the installer: broken GCC hooks can abort shell scripts.
if conda env list --json | python3 -c 'import json,os,sys; e=json.load(sys.stdin)["envs"]; sys.exit(not any(os.path.basename(p)==sys.argv[1] for p in e))' "$ENV_NAME"; then
  log "Updating existing environment: $ENV_NAME"
  conda install -n "$ENV_NAME" -c conda-forge -y python=3.12 pip
else
  log "Creating new environment: $ENV_NAME"
  conda create -n "$ENV_NAME" -c conda-forge -y python=3.12 pip
fi

log 'Installing latest McStas compatible with Python 3.12 and simulation tools'
conda install -n "$ENV_NAME" -c conda-forge --strict-channel-priority -y \
  mcstas openmpi mpi4py compilers make cmake pkg-config git \
  numpy scipy pandas matplotlib h5py hdf5plugin h5netcdf \
  xarray scipp scippneutron nexusformat \
  ipython jupyterlab ipykernel jupyter_client ipywidgets ipympl \
  tqdm pyyaml requests lmfit uncertainties pint \
  seaborn plotly sympy numba joblib dask pyarrow

ENV_PREFIX="$(conda env list --json | python3 -c 'import json,os,sys; print(next(p for p in json.load(sys.stdin)["envs"] if os.path.basename(p)==sys.argv[1]))' "$ENV_NAME")"
ENV_PY="$ENV_PREFIX/bin/python"
export ENV_NAME ENV_PY
[[ -x "$ENV_PY" ]] || fail "Environment interpreter missing: $ENV_PY"

log 'Installing McStasScript and interactive plotting extras'
"$ENV_PY" -m pip install --upgrade mcstasscript mpld3

log 'Registering Python (mcstas) Jupyter kernel for VISA user'
"$ENV_PY" -m ipykernel install --user --name "$ENV_NAME" --display-name "Python ($ENV_NAME)"
"$ENV_PY" - <<'PY'
import json, os, pathlib
from jupyter_client.kernelspec import KernelSpecManager
name=os.environ.get('ENV_NAME', 'mcstas')
ks=KernelSpecManager().get_kernel_spec(name)
assert pathlib.Path(ks.argv[0]).resolve()==pathlib.Path(os.environ['ENV_PY']).resolve(), (ks.argv[0],os.environ['ENV_PY'])
print('Jupyter kernel:',ks.display_name,'->',ks.argv[0])
PY

log 'Cloning or updating the school repository'
if [[ -d "$PROJECT_DIR/.git" ]]; then git -C "$PROJECT_DIR" pull --ff-only || echo 'WARNING: Repository update skipped.' >&2
elif [[ ! -e "$PROJECT_DIR" ]]; then git clone "$REPO_URL" "$PROJECT_DIR"
else echo "WARNING: $PROJECT_DIR exists without .git; not overwriting." >&2; fi

log 'Checking repository Python and notebook imports'
if [[ -d "$PROJECT_DIR" ]]; then PROJECT_DIR="$PROJECT_DIR" "$ENV_PY" - <<'PY'
import ast, importlib.util, json, os, pathlib, sys
root=pathlib.Path(os.environ['PROJECT_DIR']); mods=set(); partial=[]
for f in [*root.rglob('*.py'),*root.rglob('*.ipynb')]:
    if any(p in {'.git','venv','.venv','__pycache__'} for p in f.parts): continue
    try:
        blocks=[f.read_text(errors='replace')] if f.suffix=='.py' else [''.join(c.get('source',[])) for c in json.loads(f.read_text()).get('cells',[]) if c.get('cell_type')=='code']
        for b in blocks:
            b='\n'.join(s for s in b.splitlines() if not s.lstrip().startswith(('!','%')))
            try: tree=ast.parse(b)
            except SyntaxError: partial.append(str(f.relative_to(root))); continue
            for n in ast.walk(tree):
                if isinstance(n,ast.Import): mods.update(a.name.split('.')[0] for a in n.names)
                elif isinstance(n,ast.ImportFrom) and n.level==0 and n.module: mods.add(n.module.split('.')[0])
    except Exception as e: partial.append(f'{f}: {e}')
missing=sorted(m for m in mods if m not in sys.stdlib_module_names and importlib.util.find_spec(m) is None and not (root/f'{m}.py').exists() and not (root/m).exists())
(root/'missing_imports_review.txt').write_text('Potential missing imports (manual review):\n'+'\n'.join(missing)+'\n\nPartially parsed notebooks:\n'+'\n'.join(partial)+'\n')
print('Missing import candidates:', ', '.join(missing) or 'None')
PY
fi

log 'Validating McStas binaries, scientific libraries and kernel'
"$ENV_PY" -c 'import numpy, scipy, pandas, matplotlib, h5py, scipp, mcstasscript, mpld3, pyarrow, ipykernel; print("Python imports: OK")'
"$ENV_PREFIX/bin/mcrun" --version
"$ENV_PY" -m pip check || echo 'WARNING: pip dependency issues detected.' >&2
"$ENV_PY" -m jupyter kernelspec list
printf '\nSUCCESS: %s\nKernel: Python (%s)\nInterpreter: %s\nRepository: %s\n' "$ENV_NAME" "$ENV_NAME" "$ENV_PY" "$PROJECT_DIR"
printf 'Refresh the VISA JupyterLab page; select Kernel > Change Kernel > Python (%s).\n' "$ENV_NAME"
printf 'In a new terminal: conda activate %s\n' "$ENV_NAME"
