#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
PLUGIN_DIR_NAME="$(basename "$REPO_ROOT")"

if [[ "$PLUGIN_DIR_NAME" != *.koplugin ]]; then
  echo "Error: repository folder name must end with .koplugin (found: $PLUGIN_DIR_NAME)" >&2
  exit 1
fi

WITH_DICT=0
DICT_SOURCE=""
for arg in "$@"; do
  case "$arg" in
    --with-dict)    WITH_DICT=1 ;;
    --with-dict=*)  WITH_DICT=1; DICT_SOURCE="${arg#--with-dict=}" ;;
  esac
done

for cmd in rsync zip mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
done

DIST_DIR="$REPO_ROOT/dist"
OUT_ZIP="$DIST_DIR/${PLUGIN_DIR_NAME}.zip"
STAGE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/koplugin-build.XXXXXX")"
STAGE_DIR="$STAGE_PARENT/$PLUGIN_DIR_NAME"

cleanup() {
  rm -rf "$STAGE_PARENT"
}
trap cleanup EXIT

# Start each build from a clean output directory.
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$STAGE_DIR"

# Stage only distributable plugin files.
rsync -a \
  --exclude '.git/' \
  --exclude '.github/' \
  --exclude '.vscode/' \
  --exclude 'dist/' \
  --exclude '.DS_Store' \
  --exclude '.gitignore' \
  --exclude '*.zip' \
  --exclude '*.sh' \
  --exclude '*.md' \
  --exclude '*_includes/' \
  --exclude '*.yml/' \
  --exclude '.venv/' \
  --exclude '*.py' \
  --exclude '*.luarocks' \
  "$REPO_ROOT/" "$STAGE_DIR/"

if [[ "$WITH_DICT" -eq 1 ]]; then
  DICT_DEST="$STAGE_DIR/modules/settings/dict_installer.lua"
  if [[ "$DICT_SOURCE" == http://* || "$DICT_SOURCE" == https://* ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "Error: curl is required for --with-dict URL downloads" >&2; exit 1
    fi
    echo "  Downloading dict_installer.lua from: $DICT_SOURCE"
    curl -fsSL "$DICT_SOURCE" -o "$DICT_DEST" || { echo "Error: failed to download dict_installer.lua" >&2; exit 1; }
  else
    DICT_REPO="${DICT_SOURCE:-$REPO_ROOT/../dictionary_installer}"
    DICT_REPO="$(cd "$DICT_REPO" && pwd)"
    DICT_SRC="$DICT_REPO/dict_installer.lua"
    if [[ ! -f "$DICT_SRC" ]]; then
      echo "Error: dict_installer.lua not found at $DICT_SRC" >&2; exit 1
    fi
    cp "$DICT_SRC" "$DICT_DEST"
    echo "  Included dictionary installer from: $DICT_REPO"
  fi
fi

rm -f "$OUT_ZIP"
(
  cd "$STAGE_PARENT"
  zip -rq "$OUT_ZIP" "$PLUGIN_DIR_NAME"
)

echo "Created KOReader plugin zip: $OUT_ZIP"
