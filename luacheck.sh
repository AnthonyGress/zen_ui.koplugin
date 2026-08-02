#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUACHECK="$SCRIPT_DIR/.luarocks/bin/luacheck"

if [[ ! -x "$LUACHECK" ]]; then
  echo "Error: project-local LuaCheck not found at $LUACHECK" >&2
  echo "Install it with LuaRocks using LuaJIT, then run this command again." >&2
  exit 1
fi

cd "$SCRIPT_DIR"
exec "$LUACHECK" -q _meta.lua main.lua common config modules
