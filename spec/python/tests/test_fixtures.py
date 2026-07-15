import json
import zipfile
from pathlib import Path

from fixtures import FIXTURE_TIME, build_library, stage_epub_library


def test_library_fixture_is_repeatable_and_contains_requested_cases(tmp_path: Path) -> None:
    first = build_library(tmp_path / "first")
    second = build_library(tmp_path / "second")
    assert {name: path.read_bytes() for name, path in first.items()} == {
        name: path.read_bytes() for name, path in second.items()
    }
    assert first["hidden"].name.startswith(".")
    assert first["epub"].stat().st_mtime == FIXTURE_TIME


def test_generated_series_a_manifest_declares_metadata_and_cover_cases(tmp_path: Path) -> None:
    library = tmp_path / "library"
    build_library(library)

    manifest = json.loads((library / "fixture-manifest.json").read_text(encoding="utf-8"))
    books = manifest["series"]["Series A"]
    assert [book["index"] for book in books] == [1, 2, 3]
    assert [Path(book["path"]).name for book in books] == [
        "01 - Alpha.epub", "02 - No Cover.epub", "03 - Finale.epub",
    ]
    assert [book["has_cover"] for book in books] == [True, False, True]
    assert all(Path(book["path"]).is_file() for book in books)
    with zipfile.ZipFile(Path(books[0]["path"])) as archive:
        package = archive.read("OEBPS/content.opf").decode("utf-8")
    assert "id='series' property='belongs-to-collection'>Series A" in package
    assert "refines='#series' property='group-position'>1" in package


def test_committed_epub_fixture_library_stages_with_normalized_timestamps(tmp_path: Path) -> None:
    books = stage_epub_library(tmp_path / "library")

    assert len(books) >= 5
    assert "wasteland123456789011" in books
    assert all(book.suffix == ".epub" for book in books.values())
    assert all(book.stat().st_mtime == FIXTURE_TIME for book in books.values())
