import os
import signal
import tempfile
import time
import zipfile
from pathlib import Path

import pytest
from PIL import Image, ImageChops

from zen_driver import ZenDriver, launch, wait_for_socket


pytestmark = pytest.mark.skipif(
    os.environ.get("ZEN_UI_RUN_EMULATOR") != "1",
    reason="set ZEN_UI_RUN_EMULATOR=1 to run a real KOReader emulator",
)


def _write_reader_epub(path: Path) -> None:
    container = b"""<?xml version='1.0'?>
<container xmlns='urn:oasis:names:tc:opendocument:xmlns:container' version='1.0'>
  <rootfiles><rootfile full-path='OEBPS/content.opf'
    media-type='application/oebps-package+xml'/></rootfiles>
</container>"""
    package = b"""<?xml version='1.0'?>
<package xmlns='http://www.idpf.org/2007/opf' version='3.0' unique-identifier='id'>
  <metadata xmlns:dc='http://purl.org/dc/elements/1.1/'>
    <dc:identifier id='id'>zen-reader-tools</dc:identifier>
    <dc:title>Reader Tools Fixture</dc:title><dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/>
    <item id='chapter' href='chapter.xhtml' media-type='application/xhtml+xml'/>
  </manifest>
  <spine><itemref idref='chapter'/></spine>
</package>"""
    nav = b"""<html xmlns='http://www.w3.org/1999/xhtml'><body>
<nav epub:type='toc' xmlns:epub='http://www.idpf.org/2007/ops'>
<ol><li><a href='chapter.xhtml'>Test chapter</a></li></ol></nav></body></html>"""
    paragraph = "Reader tools deterministic selection text. " * 1600
    chapter = (
        "<html xmlns='http://www.w3.org/1999/xhtml'><head><title>Test chapter</title></head>"
        f"<body><h1>Test chapter</h1><p>{paragraph}</p></body></html>"
    ).encode()
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr("META-INF/container.xml", container)
        archive.writestr("OEBPS/content.opf", package)
        archive.writestr("OEBPS/nav.xhtml", nav)
        archive.writestr("OEBPS/chapter.xhtml", chapter)


def _wait_command(
    driver: ZenDriver, kind: str, predicate, timeout: float = 20, **params: object
) -> dict[str, object]:
    deadline = time.monotonic() + timeout
    last: dict[str, object] = {}
    while time.monotonic() < deadline:
        last = driver.command(kind, **params)
        if predicate(last):
            return last
        time.sleep(0.2)
    raise AssertionError(f"{kind} did not reach expected state: {last}")


def _frames_differ(first: Path, second: Path) -> bool:
    with Image.open(first) as first_image, Image.open(second) as second_image:
        difference = ImageChops.difference(first_image.convert("RGB"), second_image.convert("RGB"))
        return difference.getbbox() is not None


def test_reader_page_browser_modes_and_aa_menu_render() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-reader-tools-") as temporary:
        root = Path(temporary)
        ko_home, library = root / "home", root / "library"
        ko_home.mkdir()
        library.mkdir()
        book = library / "reader-tools.epub"
        _write_reader_epub(book)
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, library)
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            opened = _wait_command(
                driver, "open_book", lambda result: result.get("ok") is True,
                path=str(book),
            )
            assert opened["ok"] is True, opened
            reader = _wait_command(
                driver,
                "reader_state",
                lambda result: result.get("reader", {}).get("open") is True,
            )["reader"]
            assert Path(reader["file"]).resolve() == book.resolve()

            assert driver.command(
                "activate_reader_control", name="page_browser"
            )["activated"] is True
            grid = _wait_command(
                driver,
                "page_browser_state",
                lambda result: result.get("page_browser", {}).get("layout") == "grid",
            )["page_browser"]
            assert grid["thumbnail_count"] > 0
            assert {"single", "grid", "aa"}.issubset(grid["controls"])
            grid_frame = root / "page-browser-grid.png"
            driver.screenshot(grid_frame)

            assert driver.command(
                "activate_reader_control", name="page_browser_single"
            )["activated"] is True
            single = _wait_command(
                driver,
                "page_browser_state",
                lambda result: result.get("page_browser", {}).get("layout") == "single",
            )["page_browser"]
            assert single["thumbnail_count"] == 1
            single_frame = root / "page-browser-single.png"
            driver.screenshot(single_frame)
            assert _frames_differ(grid_frame, single_frame)

            assert driver.command(
                "activate_reader_control", name="page_browser_grid"
            )["activated"] is True
            _wait_command(
                driver,
                "page_browser_state",
                lambda result: result.get("page_browser", {}).get("layout") == "grid",
            )

            assert driver.command(
                "activate_reader_control", name="page_browser_aa"
            )["activated"] is True
            overlay = _wait_command(
                driver,
                "reader_overlay_state",
                lambda result: result.get("overlays", {}).get("aa_menu") is True,
            )["overlays"]
            assert overlay["page_browser"] is False
            aa_frame = root / "reader-aa-menu.png"
            driver.screenshot(aa_frame)
            assert aa_frame.stat().st_size > 0
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


def test_reader_highlight_and_dictionary_menus_open() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-reader-lookup-") as temporary:
        root = Path(temporary)
        ko_home, library = root / "home", root / "library"
        ko_home.mkdir()
        library.mkdir()
        book = library / "reader-lookup.epub"
        _write_reader_epub(book)
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, library)
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            opened = _wait_command(
                driver, "open_book", lambda result: result.get("ok") is True,
                path=str(book),
            )
            assert opened["ok"] is True, opened
            _wait_command(
                driver,
                "reader_state",
                lambda result: result.get("reader", {}).get("open") is True,
            )

            assert driver.command(
                "activate_reader_control", name="show_highlight_menu"
            )["activated"] is True
            highlight = _wait_command(
                driver,
                "reader_overlay_state",
                lambda result: result.get("overlays", {}).get("highlight_menu") is True,
            )["overlays"]
            assert "dictionary" in highlight["highlight_controls"]

            assert driver.command(
                "activate_reader_control", name="highlight_dictionary"
            )["activated"] is True
            dictionary = _wait_command(
                driver,
                "reader_overlay_state",
                lambda result: result.get("overlays", {}).get("dictionary_menu") is True,
            )["overlays"]
            assert dictionary["highlight_menu"] is False
            dictionary_frame = root / "reader-dictionary.png"
            driver.screenshot(dictionary_frame)
            assert dictionary_frame.stat().st_size > 0
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)
