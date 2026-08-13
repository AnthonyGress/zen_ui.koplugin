import os
import signal
import sqlite3
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path

import pytest

from zen_driver import ZenDriver, install_startup_alert_patch, wait_for_socket


pytestmark = pytest.mark.skipif(
    os.environ.get("ZEN_UI_RUN_EMULATOR") != "1",
    reason="set ZEN_UI_RUN_EMULATOR=1 to run a real KOReader emulator",
)


def _write_readable_epub(path: Path) -> None:
    container = b"""<?xml version='1.0'?>
<container version='1.0' xmlns='urn:oasis:names:tc:opendocument:xmlns:container'>
  <rootfiles><rootfile full-path='OEBPS/content.opf'
    media-type='application/oebps-package+xml'/></rootfiles>
</container>"""
    package = b"""<?xml version='1.0' encoding='UTF-8'?>
<package version='2.0' unique-identifier='book-id'
  xmlns='http://www.idpf.org/2007/opf'
  xmlns:dc='http://purl.org/dc/elements/1.1/'>
  <metadata>
    <dc:identifier id='book-id'>zen-reader-navigation</dc:identifier>
    <dc:title>Reader Navigation</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id='chapter' href='chapter.xhtml' media-type='application/xhtml+xml'/>
  </manifest>
  <spine><itemref idref='chapter'/></spine>
</package>"""
    chapter = b"""<html xmlns='http://www.w3.org/1999/xhtml'><head>
<title>Reader Navigation</title></head><body>
<h1>Reader Navigation</h1><p>This book verifies the real reader transition.</p>
</body></html>"""
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("mimetype", b"application/epub+zip")
        archive.writestr("META-INF/container.xml", container)
        archive.writestr("OEBPS/content.opf", package)
        archive.writestr("OEBPS/chapter.xhtml", chapter)


def _seed_mosaic_mode(ko_home: Path) -> None:
    database = ko_home / "settings" / "bookinfo_cache.sqlite3"
    database.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as connection:
        connection.executescript("""
            PRAGMA user_version=20201210;
            CREATE TABLE bookinfo (
                bcid INTEGER PRIMARY KEY AUTOINCREMENT,
                directory TEXT NOT NULL, filename TEXT NOT NULL,
                filesize INTEGER, filemtime INTEGER, in_progress INTEGER,
                unsupported TEXT, cover_fetched TEXT, has_meta TEXT,
                has_cover TEXT, cover_sizetag TEXT, ignore_meta TEXT,
                ignore_cover TEXT, pages INTEGER, title TEXT, authors TEXT,
                series TEXT, series_index REAL, language TEXT, keywords TEXT,
                description TEXT, cover_w INTEGER, cover_h INTEGER,
                cover_bb_type INTEGER, cover_bb_stride INTEGER, cover_bb_data BLOB
            );
            CREATE UNIQUE INDEX dir_filename ON bookinfo(directory, filename);
            CREATE TABLE config (key TEXT PRIMARY KEY, value TEXT);
            INSERT INTO config (key, value)
                VALUES ('filemanager_display_mode', 'mosaic_image');
        """)


def _launch(
    runtime: Path, ko_home: Path, socket_path: Path, library: Path, default_tab: str
) -> subprocess.Popen[str]:
    settings_dir = ko_home / "settings" / "Zen UI"
    settings_dir.mkdir(parents=True, exist_ok=True)
    install_startup_alert_patch(ko_home)
    (ko_home / "settings.reader.lua").write_text(
        'return { ["home_dir"] = ' + repr(str(library.resolve())) + " }\n",
        encoding="utf-8",
    )
    (settings_dir / "config.lua").write_text(
        "return { updater = { update_auto_check = false }, "
        "features = { restore_library_view = true }, "
        "navbar = { default_tab = " + repr(default_tab) + ", "
        "show_tabs = { home = true, series = true }, "
        "tab_order = { 'home', 'series', 'books' } } }\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env.update({
        "KO_HOME": str(ko_home),
        "ZEN_UI_TEST_SOCKET": str(socket_path),
        "ZEN_UI_TESTING": "1",
    })
    return subprocess.Popen(
        [str(runtime / "reader.lua")], cwd=runtime, env=env, text=True
    )


def _wait_for_reader(driver: ZenDriver, expected_file: Path) -> dict[str, object]:
    deadline = time.monotonic() + 30
    last: dict[str, object] = {}
    while time.monotonic() < deadline:
        try:
            response = driver.reader_state()
        except (ConnectionError, FileNotFoundError, OSError):
            time.sleep(0.1)
            continue
        state = response.get("reader", {})
        if isinstance(state, dict):
            last = state
            if state.get("open") is True and Path(str(state.get("file", ""))).resolve() == expected_file.resolve():
                return state
        time.sleep(0.1)
    raise AssertionError(f"book did not open in ReaderUI: {last}")


def _wait_for_file_manager(driver: ZenDriver) -> dict[str, object]:
    deadline = time.monotonic() + 30
    last: dict[str, object] = {}
    while time.monotonic() < deadline:
        try:
            response = driver.command("file_chooser_items")
        except (ConnectionError, FileNotFoundError, OSError):
            time.sleep(0.1)
            continue
        state = response.get("file_chooser", {})
        if isinstance(state, dict):
            last = state
            if response.get("ok") is True:
                return state
        time.sleep(0.1)
    raise AssertionError(f"file manager did not return: {last}")


def _wait_for_folder_cover(driver: ZenDriver, folder: Path) -> dict[str, object]:
    deadline = time.monotonic() + 30
    expected = str(folder.resolve())
    last: dict[str, object] = {}
    while time.monotonic() < deadline:
        response = driver.command("file_chooser_items")
        state = response.get("file_chooser", {})
        if isinstance(state, dict):
            last = state
            for widget in state.get("folder_widgets", []):
                if widget.get("path") == expected and widget.get("processed") is True:
                    return widget
        time.sleep(0.1)
    raise AssertionError(f"folder cover did not render: {last}")


def _wait_for_navbar_view(
    driver: ZenDriver, expected_name: str | None, expected_label: str
) -> dict[str, object]:
    deadline = time.monotonic() + 30
    last: dict[str, object] = {}
    while time.monotonic() < deadline:
        response = driver.command("navbar_state")
        state = response.get("navbar", {})
        if isinstance(state, dict):
            last = state
            stack_names = state.get("stack_names", [])
            if state.get("active_tab_label") == expected_label \
                    and (expected_name is None or expected_name in stack_names):
                return state
        time.sleep(0.1)
    raise AssertionError(f"navbar view did not return: {last}")


@pytest.mark.parametrize(
    ("default_tab", "expected_label"),
    [
        ("home", "Home"),
        ("series", "Series"),
        ("books", "Library"),
    ],
)
def test_book_opens_in_reader_and_home_returns_to_library(
    default_tab: str, expected_label: str
) -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-reader-navigation-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        library = root / "library"
        library.mkdir()
        book = library / "Reader Navigation.epub"
        _write_readable_epub(book)
        folder = library / "Folder"
        folder.mkdir()
        _write_readable_epub(folder / "Nested.epub")
        _seed_mosaic_mode(ko_home)
        socket_path = root / "driver.sock"
        process = _launch(runtime, ko_home, socket_path, library, default_tab)
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            before = _wait_for_file_manager(driver)
            activated = driver.command("activate_navbar_tab", id=default_tab)
            assert activated.get("ok") is True, activated
            expected_name = None if default_tab == "books" else default_tab
            _wait_for_navbar_view(driver, expected_name, expected_label)
            assert before.get("path") == str(library.resolve())
            assert before.get("page") == 1
            if default_tab == "books":
                _wait_for_folder_cover(driver, folder)

            opened = driver.open_book(book)
            assert opened.get("ok") is True, opened
            reader = _wait_for_reader(driver, book)
            assert reader.get("page") == 1
            assert reader.get("active_tab_label") == expected_label

            returned = driver.reader_menu_home()
            assert returned.get("ok") is True, returned
            after = _wait_for_file_manager(driver)
            _wait_for_navbar_view(driver, expected_name, expected_label)
            reader_after = driver.reader_state().get("reader", {})
            assert reader_after.get("open") is False, reader_after
            assert after.get("path") == before.get("path")
            assert after.get("page") == before.get("page")
            if default_tab == "books":
                _wait_for_folder_cover(driver, folder)
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
