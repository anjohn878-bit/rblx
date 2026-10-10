#!/usr/bin/env bash
# One-shot setup for macOS. Run from the repo folder:  bash scripts/setup-mac.sh
# Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
step() { printf "\n=== %s ===\n" "$1"; }

step "Python"
PY=""
for c in python3.13 python3; do
  if command -v $c >/dev/null && $c -c "import sys; sys.exit(sys.version_info < (3, 10))"; then PY=$c; break; fi
done
if [ -z "$PY" ]; then
  echo "Install Python 3.13 from https://www.python.org/downloads/ then re-run."; exit 1
fi
echo "Using: $PY"

step "Rokit"
if ! command -v rokit >/dev/null && [ ! -x "$HOME/.rokit/bin/rokit" ]; then
  curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
fi
export PATH="$HOME/.rokit/bin:$PATH"
rokit install

step "Rojo Studio plugin"
rojo plugin install

step "Python packages (bpy is ~400 MB)"
$PY -m pip install --upgrade pytest pillow kaggle bpy

step "Four checks"
PYTHON=$PY scripts/check.sh

printf "\nDone. Next: open Studio, run 'rojo serve' here, click Rojo > Connect. Then SETUP.md section 3 (MCP).\n"
