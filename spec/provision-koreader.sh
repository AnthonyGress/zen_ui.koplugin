#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?expected stable, compat, or nightly}"
CACHE_ROOT="${ZEN_UI_KOREADER_CACHE:-$ROOT/spec/.cache/koreader}"
LOCK="$ROOT/spec/koreader-lock.json"

if [[ "$TARGET" != "stable" && "$TARGET" != "compat" && "$TARGET" != "nightly" ]]; then
  echo "Target must be stable, compat, or nightly" >&2
  exit 2
fi

REF="${ZEN_UI_KOREADER_REF:-}"
if [[ "$TARGET" != "nightly" ]]; then
  REF="$(python3 - "$LOCK" "$TARGET" <<'PY'
import json
import sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
target = lock[sys.argv[2]]
print(target.get("tag") or target["commit"])
PY
)"
fi
SOURCE="$CACHE_ROOT/$TARGET/source"
RUNTIME_CACHE="$CACHE_ROOT/$TARGET/runtime"
CACHE_FORMAT="runtime-v1"

if [[ -n "$REF" && -x "$RUNTIME_CACHE/luajit" && -d "$RUNTIME_CACHE/frontend" \
    && -d "$RUNTIME_CACHE/spec/rocks" \
    && "$(cat "$RUNTIME_CACHE/.zen-ui-cache-ref" 2>/dev/null || true)" == "$CACHE_FORMAT:$REF" ]]; then
  printf '%s\n' "$RUNTIME_CACHE"
  exit 0
fi

if [[ ! -d "$SOURCE/.git" ]]; then
  mkdir -p "$(dirname "$SOURCE")"
  if [[ "$TARGET" == "nightly" ]]; then
    git clone --recurse-submodules --depth=1 https://github.com/koreader/koreader.git "$SOURCE" >&2
  else
    git clone --recurse-submodules --depth=1 --branch "$REF" https://github.com/koreader/koreader.git "$SOURCE" >&2
  fi
fi

if [[ "$TARGET" == "nightly" ]]; then
  (
    cd "$SOURCE"
    git fetch --depth=1 origin "${REF:-master}" >&2
    git reset --hard FETCH_HEAD >&2
    git submodule update --init --recursive >&2
    version="$(git describe HEAD 2>/dev/null || true)"
    if [[ ! "$version" =~ ^v[0-9]{4}\.[0-9]{2}([.-]|$) ]]; then
      # Shallow nightly clones may not include a release tag.
      commit_date="$(git log -1 --format=%cs HEAD)"
      git -c tag.gpgSign=false \
        -c user.name="Zen UI CI" \
        -c user.email="zen-ui-ci@invalid" \
        tag --annotate --force \
        --message "Nightly test build" \
        "v${commit_date:0:4}.${commit_date:5:2}" HEAD
    fi
  )
  REF="$(git -C "$SOURCE" rev-parse HEAD)"
fi

# GitLab may block Git-over-HTTPS from shared CI IPs while archive downloads still work.
python3 - "$SOURCE/base/thirdparty/djvulibre/CMakeLists.txt" "$CACHE_ROOT/$TARGET/downloads" <<'PY'
import hashlib
from pathlib import Path
import re
import sys
import time
from urllib.request import Request, urlopen

config = Path(sys.argv[1])
download_dir = Path(sys.argv[2])
if not config.is_file():
    raise SystemExit(0)
text = config.read_text(encoding="utf-8")
match = re.search(
    r"(?m)^(?P<indent>[ \t]*)DOWNLOAD GIT (?P<revision>[A-Za-z0-9._-]+)\n"
    r"[ \t]*https://gitlab\.com/koreader/djvulibre\.git[ \t]*$",
    text,
)
if match:
    revision = match.group("revision")
    filename = f"djvulibre-{revision}.tar.gz"
    url = f"https://gitlab.com/koreader/djvulibre/-/archive/{revision}/{filename}"
    archive = download_dir / filename
    temporary = archive.with_suffix(archive.suffix + ".tmp")
    download_dir.mkdir(parents=True, exist_ok=True)
    request = Request(url, headers={"User-Agent": "zen-ui-koreader-provisioner"})
    error = None
    for attempt in range(3):
        try:
            with urlopen(request, timeout=60) as response, temporary.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)
            temporary.replace(archive)
            error = None
            break
        except Exception as exc:
            error = exc
            temporary.unlink(missing_ok=True)
            if attempt < 2:
                time.sleep(2 ** attempt)
    if error is not None:
        raise error
    digest = hashlib.md5(archive.read_bytes(), usedforsecurity=False).hexdigest()
    replacement = (
        f'{match.group("indent")}DOWNLOAD URL {digest}\n'
        f'{match.group("indent")}{url}'
    )
    config.write_text(text[:match.start()] + replacement + text[match.end():], encoding="utf-8")
PY

if [[ "$(uname -s)" == "Linux" && "$(uname -m)" == "x86_64" ]]; then
  build_flags="$SOURCE/base/Makefile.defs"
  if grep -q '^  TARGET_CFLAGS = -march=native$' "$build_flags"; then
    # Keep cached emulator builds runnable across GitHub-hosted CPUs.
    sed -i 's/^  TARGET_CFLAGS = -march=native$/  TARGET_CFLAGS = -march=x86-64 -mtune=generic/' "$build_flags"
  elif ! grep -q -e '^  TARGET_CFLAGS = -march=x86-64 -mtune=generic$' \
      -e '^    TARGET_CFLAGS = -mtune=generic$' "$build_flags"; then
    echo "Unable to set portable emulator CPU flags" >&2
    exit 1
  fi
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

runtime_tmp="$(mktemp -d "$CACHE_ROOT/$TARGET/.runtime.XXXXXX")"
cleanup_runtime_tmp() {
  if [[ -n "$runtime_tmp" && -d "$runtime_tmp" ]]; then
    rm -rf "$runtime_tmp"
  fi
}
trap cleanup_runtime_tmp EXIT
cp -aL "$RUNTIME/." "$runtime_tmp/"
printf '%s\n' "$CACHE_FORMAT:$REF" > "$runtime_tmp/.zen-ui-cache-ref"
rm -rf "$RUNTIME_CACHE"
mv "$runtime_tmp" "$RUNTIME_CACHE"
runtime_tmp=""
trap - EXIT
printf '%s\n' "$RUNTIME_CACHE"
