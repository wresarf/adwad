#!/usr/bin/env bash
# Builds SnackForce_PetToss.rbxl with Rojo and runs the offline Lune test-suite against it.
# If luau-lsp is installed, also runs the strict Roblox type-check first.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v luau-lsp >/dev/null 2>&1; then
	./scripts/typecheck.sh
fi
rojo build default.project.json -o SnackForce_PetToss.rbxl
test -s SnackForce_PetToss.rbxl
lune run tests/run.luau SnackForce_PetToss.rbxl
