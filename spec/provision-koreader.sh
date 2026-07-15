#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?expected stable or master}"
CACHE_ROOT="${ZEN_UI_KOREADER_CACHE:-$ROOT/spec/.cache/koreader}"
LOCK="$ROOT/spec/koreader-lock.json"

if [[ "$TARGET" != "stable" && "$TARGET" != "master" ]]; then
  echo "Target must be stable or master" >&2
  exit 2
fi

REF="$(python3 - "$LOCK" "$TARGET" <<'PY'
import json
import sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
target = lock[sys.argv[2]]
print(target.get("tag") or target["commit"])
PY
)"
SOURCE="$CACHE_ROOT/$TARGET/source"

if [[ ! -d "$SOURCE/.git" ]]; then
  mkdir -p "$(dirname "$SOURCE")"
  if [[ "$TARGET" == "master" ]]; then
    git clone --recurse-submodules --depth=1 https://github.com/koreader/koreader.git "$SOURCE" >&2
  else
    git clone --recurse-submodules --depth=1 --branch "$REF" https://github.com/koreader/koreader.git "$SOURCE" >&2
  fi
fi

if [[ "$TARGET" == "master" ]]; then
  (
    cd "$SOURCE"
    git fetch --depth=1 origin "$REF" >&2
    git checkout --detach "$REF" >&2
    git submodule update --init --recursive >&2
  )
fi

(
  cd "$SOURCE"
  ./kodev build >&2
)

RUNTIME="$(find "$SOURCE" \( -type f -o -type l \) -path '*/koreader/luajit' -perm -111 -print -quit | xargs -n1 dirname)"
if [[ -z "$RUNTIME" ]]; then
  echo "KOReader build completed without a runnable emulator" >&2
  exit 1
fi
printf '%s\n' "$RUNTIME"
