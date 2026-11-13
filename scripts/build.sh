#!/usr/bin/env bash
# Builds SnackForce_PetToss.rbxl with Rojo and runs the offline Lune test-suite against it.
set -euo pipefail
cd "$(dirname "$0")/.."
rojo build default.project.json -o SnackForce_PetToss.rbxl
test -s SnackForce_PetToss.rbxl
lune run tests/run.luau SnackForce_PetToss.rbxl
