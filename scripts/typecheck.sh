#!/usr/bin/env bash
# Strict Luau type-check of src/ against the Roblox API (luau-lsp + Rojo sourcemap).
# toolchain: mise use github:JohnnyMorganz/luau-lsp
set -euo pipefail
cd "$(dirname "$0")/.."
defs="${LUAU_ROBLOX_DEFS:-${XDG_CACHE_HOME:-$HOME/.cache}/snackforce/globalTypes.d.luau}"
if [ ! -s "$defs" ]; then
	mkdir -p "$(dirname "$defs")"
	curl -sSfL -o "$defs" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json
out=$(luau-lsp analyze --definitions=@roblox="$defs" --sourcemap=sourcemap.json src 2>&1 | grep -v '^\[' || true)
if [ -n "$out" ]; then
	echo "$out"
	exit 1
fi
echo "typecheck: no issues"
