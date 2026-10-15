#!/usr/bin/env bash
# SFN_TOF_INS_School setup for Ubuntu/VISA; run with bash or source to keep activation.
set -Eeuo pipefail
ENV_NAME="${ENV_NAME:-mcstas}"
PY_VERSION="${PY_VERSION:-3.12}"
REPO_URL="${REPO_URL:-https://github.com/kkaryos/SFN_TOF_INS_School.git}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/SFN_TOF_INS_School}"
INSTALL_MCSTAS="${INSTALL_MCSTAS:-1}"

log() { printf '\n==> %s\n' "$*"; }
# VISA commonly installs Conda in /opt/conda, without shell activation initialized.
if [[ -f /opt/conda/etc/profile.d/conda.sh ]]; then
  source /opt/conda/etc/profile.d/conda.sh
elif command -v conda >/dev/null 2>&1; then
  source "$(conda info --base)/etc/profile.d/conda.sh"
elif [[ -x /opt/conda/bin/conda ]]; then
  eval "$(/opt/conda/bin/conda shell.bash hook)"
else
  echo 'Conda not found. Install Conda or check /opt/conda.' >&2; return 1 2>/dev/null || exit 1
fi
log 'Enabling conda activate for future Bash terminals'
conda init bash >/dev/null

if conda env list --json | CONDA_TARGET="$ENV_NAME" python3 -c 'import json,os,sys; d=json.load(sys.stdin)["envs"]; sys.exit(0 if any(os.path.basename(p)==os.environ["CONDA_TARGET"] for p in d) else 1)'; then
  log "Updating existing $ENV_NAME environment"
  conda install -n "$ENV_NAME" -c conda-forge -y "python=$PY_VERSION" pip
else
  log "Creating $ENV_NAME with Python $PY_VERSION and pip"
  conda create -n "$ENV_NAME" -c conda-forge -y "python=$PY_VERSION" pip
fi
conda activate "$ENV_NAME"

log 'Installing notebook, reduction, SQW and scientific dependencies'
conda install -n "$ENV_NAME" -c conda-forge -y \
  numpy scipy pandas matplotlib h5py hdf5plugin xarray scipp \
  scippneutron nexusformat mcstasscript ipython jupyterlab ipykernel \
  ipywidgets tqdm pyyaml requests lmfit uncertainties

if [[ "$INSTALL_MCSTAS" == 1 ]]; then
  log 'Installing McStas simulation binaries (may take additional time)'
  if ! conda install -n "$ENV_NAME" -c conda-forge -y mcstas; then
    echo 'WARNING: McStas binary package was not installed. Python dependencies remain available.' >&2
  fi
fi

log 'Registering VS Code / Jupyter kernel'
python -m ipykernel install --user --name "$ENV_NAME" --display-name "Python ($ENV_NAME)"

if command -v git >/dev/null 2>&1; then
  if [[ -d "$PROJECT_DIR/.git" ]]; then
    log 'Updating existing school repository'
    git -C "$PROJECT_DIR" pull --ff-only || echo 'WARNING: git pull failed; using existing files.' >&2
  elif [[ ! -e "$PROJECT_DIR" ]]; then
    log 'Cloning school repository'
    git clone "$REPO_URL" "$PROJECT_DIR" || echo 'WARNING: git clone failed (network access?).' >&2
  else
    echo "WARNING: $PROJECT_DIR exists and is not a git checkout; leaving it untouched." >&2
  fi
else
  echo 'WARNING: git is not installed; skipped repository clone.' >&2
fi

if [[ -d "$PROJECT_DIR" ]]; then
  log 'Scanning notebook and script imports for missing packages'
  PROJECT_DIR="$PROJECT_DIR" python - <<'PY'
import ast, importlib.util, json, os, pathlib, sys
root=pathlib.Path(os.environ['PROJECT_DIR']); modules=set(); skipped=[]
for file in [*root.rglob('*.py'),*root.rglob('*.ipynb')]:
    if any(part in {'.git','.venv','venv','__pycache__'} for part in file.parts): continue
    try:
        blocks=[file.read_text(errors='replace')] if file.suffix=='.py' else [''.join(c.get('source',[])) for c in json.loads(file.read_text()).get('cells',[]) if c.get('cell_type')=='code']
        for block in blocks:
            block='\n'.join(line for line in block.splitlines() if not line.lstrip().startswith(('!','%')))
            try: tree=ast.parse(block)
            except SyntaxError: skipped.append(str(file.relative_to(root))); continue
            for node in ast.walk(tree):
                if isinstance(node,ast.Import): modules.update(n.name.split('.')[0] for n in node.names)
                elif isinstance(node,ast.ImportFrom) and node.level==0 and node.module: modules.add(node.module.split('.')[0])
    except (OSError,ValueError) as err: skipped.append(f'{file}: {err}')
missing=sorted(m for m in modules if m not in sys.stdlib_module_names and importlib.util.find_spec(m) is None and not (root/(m+'.py')).exists() and not (root/m).exists())
(root/'missing_imports_review.txt').write_text('Missing import names (manual review; names may differ from pip packages):\n'+'\n'.join(missing)+'\n\nNot fully parsed:\n'+'\n'.join(skipped)+'\n')
print('Imported modules:', ', '.join(sorted(modules))); print('Missing modules:', ', '.join(missing) or 'None')
PY
fi

log 'Validating installed Python and McStas'
which python; python --version; python -m pip --version
python -c 'import numpy, scipy, pandas, matplotlib, h5py, scipp, xarray, mcstasscript; print("Core imports: OK")'
if command -v mcrun >/dev/null 2>&1; then mcrun --version || true; else echo 'mcrun not found (see McStas warning above)'; fi
python -m pip check || echo 'WARNING: pip check found dependency conflicts.' >&2
printf '\nEnvironment: %s\nPython: %s\nProject: %s\n' "$ENV_NAME" "$(command -v python)" "$PROJECT_DIR"
printf 'For a new terminal: conda activate %s\n' "$ENV_NAME"
printf 'For THIS terminal: source %s\n' "${BASH_SOURCE[0]}"
