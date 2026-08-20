# Website screenshots

`./spec/run website-screenshots` creates review artifacts only. It never writes to the
website repository or to the Calibre library.

Create the ignored local profile before capturing:

```sh
cp spec/python/website_screenshot_books.example.json .website-screenshot-books.json
```

Each book record has four required fields and an optional keyword field:

- `calibre_id`: the record verified against `metadata.db`, or `null` for a direct-only book.
- `expected_title`: the title that must agree with the Calibre record.
- `direct_path`: an optional absolute path or path relative to `calibre_root`. When supplied,
  it overrides a stale Calibre directory while ID/title verification still runs.
- `role`: `featured`, `reader`, or `library`. Exactly one featured and one reader book are
  required.
- `keywords`: a string or list of the book's actual tags. These override embedded metadata and
  are shown in Library list screenshots.

The profile contains exactly twelve books in newest-to-oldest recent order. That order drives
both the Home recent widgets and the Library's last-read sorting.

Use `--list` to inspect the tracked 19-screen catalog, `--audit` to check documentation and
carousel references, or capture with `--screen ID`, `--group GROUP`, or `--all`. OPDS and
`update_available.png` are intentionally outside the automated catalog.

Every capture clears and replaces `spec/.artifacts/screenshots/`. Website-ready PNGs are written
directly into that folder; raw frames are temporary. To also copy the screenshots to another
folder for manual website use, pass a new or empty path:

```sh
./spec/run website-screenshots --all --output ~/Desktop/zenos-website-images
```

Review `report.json` before manually copying approved images. The workflow rejects an output
path inside the website repository and never publishes images.

Each isolated session uses `settings.reader.lua`, `settings/ZenOS/config.lua`, and
`settings/ZenOS/reader.lua` from `KOREADER_DIR` as a read-only baseline when those files
exist. It copies the ZenOS stores and only the reader-layout keys from the global settings
into the temporary `KO_HOME`; device, account, startup, and unrelated plugin settings are
not inherited. Deterministic capture values then override paths, locale, light mode, and
library status content. The library uses the custom time / empty / Wi-Fi+battery status row
with the stock KOReader titlebar hidden; the Zen reader preset is applied and screenshots
open at page 10.
