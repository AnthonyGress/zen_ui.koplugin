import json
import os
import re
import signal
import sqlite3
import tempfile
import time
from pathlib import Path

import pytest

from fixtures import build_library
from zen_driver import ZenDriver, launch, normalize_visible_text, wait_for_socket


pytestmark = pytest.mark.skipif(
    os.environ.get("ZEN_UI_RUN_EMULATOR") != "1",
    reason="set ZEN_UI_RUN_EMULATOR=1 to run a real KOReader emulator",
)


def _seed_history(ko_home: Path, book: Path) -> None:
    ko_home.joinpath("history.lua").write_text(
        "return {{ time = 1704067200, file = " + json.dumps(str(book.resolve())) + " }}\n",
        encoding="utf-8",
    )


def _seed_home_settings(ko_home: Path) -> None:
    settings = ko_home / "settings" / "Zen UI"
    settings.mkdir(parents=True, exist_ok=True)
    settings.joinpath("home.lua").write_text(
        """return {
  version = 1,
  presets = {},
  settings = {
    show_status_bar = false,
    rows = {
      max_rows = 4,
      order = { "datetime", "featured_recent", "strip_recent", "quotes" },
      enabled = {
        datetime = true, featured_recent = true, strip_recent = true, quotes = true,
      },
    },
    modules = {
      datetime = { show_module_title = false },
      featured_recent = {
        interactive = true, show_description = true, show_module_title = false,
        show_status_bar = false,
        progress_meta = { left = "percent", right = "total_pages" },
      },
      strip_recent = {
        count = 4, interactive = true, order = "default",
        show_module_title = false, show_strip_titles = true, two_rows = false,
      },
      quotes = { show_module_title = false },
    },
    quotes = { manual_index = 1, show_author = true },
  },
}
""",
        encoding="utf-8",
    )


def _seed_bookinfo(ko_home: Path, book: Path) -> None:
    database = ko_home / "settings" / "bookinfo_cache.sqlite3"
    database.parent.mkdir(parents=True, exist_ok=True)
    canonical = book.resolve()
    stat = canonical.stat()
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
        """)
        connection.execute(
            """INSERT INTO bookinfo (
                directory, filename, filesize, filemtime, in_progress,
                cover_fetched, has_meta, title, authors, description,
                series, series_index, keywords
            ) VALUES (?, ?, ?, ?, 0, 'Y', 'Y', ?, ?, ?, ?, ?, ?)""",
            (
                str(canonical.parent) + "/",
                canonical.name,
                stat.st_size,
                int(stat.st_mtime),
                "Alpha Home",
                "Zen Author",
                "A deterministic featured-book description.",
                "Zen Series",
                1,
                "Focus, Testing",
            ),
        )


def _wait_for_home(driver: ZenDriver) -> dict[str, object]:
    deadline = time.monotonic() + 30
    latest: dict[str, object] = {}
    while time.monotonic() < deadline:
        response = driver.command("home_state")
        latest = response.get("home", {})
        if latest.get("active") and len(latest.get("widget_ids", [])) >= 4:
            return latest
        time.sleep(0.25)
    raise AssertionError(f"Home widgets did not become ready: {latest}")


@pytest.mark.parametrize("with_history", [True, False], ids=["history", "empty-history"])
def test_home_renders_all_core_widgets_with_and_without_history(with_history: bool) -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-home-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        fixture = build_library(root / "library")
        _seed_home_settings(ko_home)
        _seed_bookinfo(ko_home, fixture["epub"])
        if with_history:
            _seed_history(ko_home, fixture["epub"])
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, root / "library")
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("activate_navbar_tab", id="home")["ok"] is True
            home = _wait_for_home(driver)
            assert home["active_tab_label"] == "Home"
            assert set(home["widget_ids"]) >= {
                "datetime", "featured_recent", "strip_recent", "quotes",
            }
            assert home["clock_refreshers"] >= 1

            screenshot = root / "home.png"
            driver.screenshot(screenshot)
            assert screenshot.stat().st_size > 0
            assert "Alpha Home" in home["visible_texts"]
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


def _wait_for_navbar(driver: ZenDriver, label: str, tab_id: str | None) -> dict[str, object]:
    deadline = time.monotonic() + 20
    latest: dict[str, object] = {}
    while time.monotonic() < deadline:
        response = driver.command("navbar_state")
        latest = response.get("navbar", {})
        if latest.get("active_tab_label") == label:
            if tab_id is None or latest.get("top_tab_id") == tab_id or latest.get("top_name") == tab_id:
                return latest
        time.sleep(0.2)
    raise AssertionError(f"navbar did not reach {label}/{tab_id}: {latest}")


def test_navbar_tabs_navigate_to_real_library_views() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-navbar-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        fixture = build_library(root / "library")
        _seed_home_settings(ko_home)
        _seed_bookinfo(ko_home, fixture["epub"])
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, root / "library")
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("activate_navbar_tab", id="home")["ok"] is True
            _wait_for_home(driver)

            assert driver.command("activate_navbar_tab", id="books")["ok"] is True
            books = _wait_for_navbar(driver, "Library", None)
            assert Path(str(books["path"])).resolve() == (root / "library").resolve()
            assert books.get("top_tab_id") is None

            for tab_id, label in (
                ("home", "Home"),
                ("authors", "Authors"),
                ("series", "Series"),
                ("tags", "Tags"),
                ("to_be_read", "To Be Read"),
            ):
                assert driver.command("activate_navbar_tab", id=tab_id)["ok"] is True
                state = _wait_for_navbar(driver, label, tab_id if tab_id != "home" else None)
                if tab_id == "home":
                    assert state["top_name"] == "home"
                else:
                    assert state.get("top_tab_id") == tab_id or state.get("top_name") == tab_id
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


def test_mosaic_title_strip_renders_metadata_and_cover_cells() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-mosaic-strip-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        fixture = build_library(root / "library")
        book = root / "library" / "Alpha Home.epub"
        fixture["epub"].replace(book)
        _seed_bookinfo(ko_home, book)
        with sqlite3.connect(ko_home / "settings" / "bookinfo_cache.sqlite3") as connection:
            connection.execute(
                "INSERT INTO config (key, value) VALUES (?, ?)",
                ("filemanager_display_mode", "mosaic_image"),
            )
        socket_path = root / "driver.sock"
        screenshot = root / "mosaic-title-strip.png"
        zen_config = """return {
  updater = { update_auto_check = false },
  features = { automatic_series_grouping = false },
  navbar = { default_tab = "books" },
  mosaic_title_strip = { show_title = true, show_author = true },
}
"""
        process = launch(
            runtime, ko_home, socket_path, root / "library",
            zen_config_source=zen_config,
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            deadline = time.monotonic() + 30
            chooser: dict[str, object] = {}
            visible: set[str] = set()
            while time.monotonic() < deadline:
                response = driver.command("file_chooser_items")
                chooser = response.get("file_chooser", {})
                visible = {
                    normalize_visible_text(value)
                    for value in chooser.get("visible_texts", [])
                    if isinstance(value, str)
                }
                if (
                    chooser.get("display_mode_type") == "mosaic"
                    and {"Alpha Home", "Zen Author"} <= visible
                    and chooser.get("item_widget_count", 0) > 0
                    and chooser.get("image_widget_count", 0) > 0
                ):
                    break
                time.sleep(0.25)

            assert chooser["display_mode_type"] == "mosaic"
            assert {"Alpha Home", "Zen Author"} <= visible
            assert chooser["item_widget_count"] > 0
            assert chooser["image_widget_count"] > 0
            driver.screenshot(screenshot)
            assert screenshot.exists()
            assert screenshot.stat().st_size > 0
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)
