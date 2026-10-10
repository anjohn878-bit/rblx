#!/usr/bin/env bash
# The four gates. Nothing reaches Studio until all four pass.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
echo "1/4 rojo build";  rojo build default.project.json -o build/game.rbxl >/dev/null
echo "2/4 tests"
lune run tests/run
python3 -m pytest -q tests/python
echo "3/4 selene"
if selene generate-roblox-std >/dev/null 2>&1 || [ -f roblox.yml ]; then
  selene src
else
  echo "   (Roblox API dump unreachable - using roblox_offline std)"
  selene --config selene.offline.toml src
fi
echo "4/4 stylua";      stylua --check src tests
echo "ALL CHECKS PASSED"
