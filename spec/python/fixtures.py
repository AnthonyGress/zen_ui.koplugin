"""Deterministic local-library fixtures for KOReader emulator scenarios."""

from __future__ import annotations

import json
import os
import shutil
import zipfile
from pathlib import Path

from PIL import Image

FIXTURE_TIME = 1_704_067_200  # 2024-01-01T00:00:00Z
EPUB_LIBRARY_FIXTURES = Path(__file__).parents[1] / "fixtures" / "library"


def stage_epub_library(root: Path) -> dict[str, Path]:
    """Copy the committed EPUB corpus with stable timestamps for goldens."""
    if not EPUB_LIBRARY_FIXTURES.is_dir():
        raise FileNotFoundError(f"missing EPUB fixtures: {EPUB_LIBRARY_FIXTURES}")

    books: dict[str, Path] = {}
    for source in sorted(EPUB_LIBRARY_FIXTURES.rglob("*.epub")):
        relative = source.relative_to(EPUB_LIBRARY_FIXTURES)
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        os.utime(destination, (FIXTURE_TIME, FIXTURE_TIME))
        books[source.stem] = destination
    if not books:
        raise RuntimeError("EPUB fixture corpus is empty")
    return books


def _write_zip(path: Path, members: dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, body in sorted(members.items()):
            info = zipfile.ZipInfo(name, date_time=(2024, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            archive.writestr(info, body)
    os.utime(path, (FIXTURE_TIME, FIXTURE_TIME))


def _epub_members(
    title: str, series: str, series_index: int, cover_bytes: bytes | None
) -> dict[str, bytes]:
    manifest = """
    <item id='chapter' href='content.xhtml' media-type='application/xhtml+xml'/>
    """
    metadata = ""
    if cover_bytes is not None:
        manifest += "<item id='cover' href='cover.png' media-type='image/png' properties='cover-image'/>"
        metadata = "<meta name='cover' content='cover'/>"
    package = f"""<?xml version='1.0' encoding='UTF-8'?>
<package version='3.0' unique-identifier='book-id'
 xmlns='http://www.idpf.org/2007/opf' xmlns:dc='http://purl.org/dc/elements/1.1/'>
  <metadata>
    <dc:identifier id='book-id'>zen-{series_index}-{title}</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:creator>Zen Author</dc:creator>
    <dc:language>en</dc:language>
    <meta id='series' property='belongs-to-collection'>{series}</meta>
    <meta refines='#series' property='collection-type'>series</meta>
    <meta refines='#series' property='group-position'>{series_index}</meta>
    {metadata}
  </metadata>
  <manifest>{manifest}</manifest>
  <spine><itemref idref='chapter'/></spine>
</package>""".encode()
    members = {
        "mimetype": b"application/epub+zip",
        "META-INF/container.xml": b"""<?xml version='1.0'?>
<container version='1.0' xmlns='urn:oasis:names:tc:opendocument:xmlns:container'>
  <rootfiles><rootfile full-path='OEBPS/content.opf'
    media-type='application/oebps-package+xml'/></rootfiles>
</container>""",
        "OEBPS/content.opf": package,
        "OEBPS/content.xhtml": (
            "<html xmlns='http://www.w3.org/1999/xhtml'><body><p>"
            + title + "</p></body></html>"
        ).encode(),
    }
    if cover_bytes is not None:
        members["OEBPS/cover.png"] = cover_bytes
    return members


def build_library(root: Path) -> dict[str, Path]:
    """Create a small, repeatable EPUB/CBZ tree without binary fixtures."""
    series = root / "Series-A"
    series.mkdir(parents=True, exist_ok=True)
    cover = root / "cover.png"
    Image.new("RGB", (60, 90), (32, 96, 192)).save(cover)
    cover_bytes = cover.read_bytes()
    cover.unlink()

    epub = series / "01 - Alpha.epub"
    _write_zip(epub, _epub_members("Alpha", "Series A", 1, cover_bytes))
    no_cover = series / "02 - No Cover.epub"
    _write_zip(no_cover, _epub_members("No Cover", "Series A", 2, None))
    finale = series / "03 - Finale.epub"
    _write_zip(finale, _epub_members("Finale", "Series A", 3, cover_bytes))
    cbz = root / "Manga.cbz"
    _write_zip(cbz, {"001.png": cover_bytes})
    hidden = root / ".hidden.epub"
    _write_zip(hidden, {"mimetype": b"application/epub+zip"})

    manifest = {
        "title": "Zen UI test library",
        "books": [str(epub), str(no_cover), str(finale), str(cbz), str(hidden)],
        "metadata": {
            str(epub): {"title": "Alpha", "authors": "Zen Author", "series": "Series A"},
            str(no_cover): {"title": "No Cover", "authors": "Zen Author", "series": "Series A"},
            str(finale): {"title": "Finale", "authors": "Zen Author", "series": "Series A"},
        },
        "series": {
            "Series A": [
                {"path": str(epub), "index": 1, "has_cover": True},
                {"path": str(no_cover), "index": 2, "has_cover": False},
                {"path": str(finale), "index": 3, "has_cover": True},
            ],
        },
    }
    (root / "fixture-manifest.json").write_text(
        json.dumps(manifest, sort_keys=True, indent=2), encoding="utf-8"
    )
    return {
        "epub": epub,
        "no_cover": no_cover,
        "finale": finale,
        "cbz": cbz,
        "hidden": hidden,
    }
