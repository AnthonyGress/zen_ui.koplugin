#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
PLUGIN_DIR_NAME="$(basename "$REPO_ROOT")"

if [[ "$PLUGIN_DIR_NAME" != *.koplugin ]]; then
  echo "Error: repository folder name must end with .koplugin (found: $PLUGIN_DIR_NAME)" >&2
  exit 1
fi

for cmd in rsync zip mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
done

if ! command -v pyftsubset >/dev/null 2>&1; then
  echo "Error: pyftsubset is required to subset SymbolsNerdFont-Regular.ttf (install fonttools)" >&2
  exit 1
fi

DIST_DIR="$REPO_ROOT/dist"
OUT_ZIP="$DIST_DIR/${PLUGIN_DIR_NAME}.zip"
STAGE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/koplugin-build.XXXXXX")"
STAGE_DIR="$STAGE_PARENT/$PLUGIN_DIR_NAME"
INLINE_ICON_MAP="$REPO_ROOT/common/inline_icon_map.lua"
NERD_FONT_NAME="SymbolsNerdFont-Regular.ttf"
NERD_FONT_SRC="$REPO_ROOT/fonts/$NERD_FONT_NAME"
NERD_FONT_STAGE="$STAGE_DIR/fonts/$NERD_FONT_NAME"

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
  --exclude 'spec/' \
  --exclude 'docs/' \
  --exclude '.DS_Store' \
  --exclude '.gitignore' \
  --exclude '*.zip' \
  --exclude '*.sh' \
  --include 'LICENSE.md' \
  --exclude '*.md' \
  --exclude '*_includes/' \
  --exclude '_config.yml' \
  --exclude '*.yml/' \
  --exclude 'images/' \
  --exclude '.venv/' \
  --exclude '*.py' \
  --exclude '*.luarocks' \
  --exclude '*.luacheckrc' \
  --exclude '__pycache__' \
  --exclude '.*' \
  "$REPO_ROOT/" "$STAGE_DIR/"

UNICODE_LIST="$(mktemp "$STAGE_PARENT/nerd-font-unicodes.XXXXXX")"
unicode_escape_re='\\u\{([0-9A-Fa-f]+)\}'
while IFS= read -r line; do
  rest="$line"
  while [[ "$rest" =~ $unicode_escape_re ]]; do
    printf 'U+%s\n' "${BASH_REMATCH[1]}" >> "$UNICODE_LIST"
    rest="${rest#*${BASH_REMATCH[0]}}"
  done
done < "$INLINE_ICON_MAP"

if [[ ! -s "$UNICODE_LIST" ]]; then
  echo "Error: no inline icon codepoints found in $INLINE_ICON_MAP" >&2
  exit 1
fi

pyftsubset "$NERD_FONT_SRC" \
  --unicodes-file="$UNICODE_LIST" \
  --output-file="$NERD_FONT_STAGE" \
  --drop-tables+=PfEd \
  --name-IDs='*' \
  --name-languages='*'

rm -f "$OUT_ZIP"
(
  cd "$STAGE_PARENT"
  zip -rq "$OUT_ZIP" "$PLUGIN_DIR_NAME"
)

echo "Created KOReader plugin zip: $OUT_ZIP"
