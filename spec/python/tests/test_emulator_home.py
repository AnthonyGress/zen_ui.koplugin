import json
import os
import re
import signal
import sqlite3
import tempfile
import time
from pathlib import Path

import pytest
from PIL import Image

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


def _seed_home_settings(ko_home: Path, *, show_strip_titles: bool = True) -> None:
    settings = ko_home / "settings" / "Zen UI"
    settings.mkdir(parents=True, exist_ok=True)
    source = """return {
  version = 1,
  presets = {},
  settings = {
    show_status_bar = false,
    rows = {
      capacity_units = 10,
      layout_schema_version = 2,
      order = { "featured", "strip", "quotes", "reading_goals", "stats_triplet" },
      enabled = {
        featured = true, strip = true, quotes = true,
        reading_goals = true, stats_triplet = true,
      },
    },
    modules = {
      featured = {
        default_source = { kind = "recent" },
        interactive = true, show_description = true, show_module_title = false,
        show_status_bar = false,
        progress_meta = { left = "percent", right = "total_pages" },
      },
      stats_triplet = { show_module_title = false },
      reading_goals = { show_module_title = false },
      strip = {
        count = 4, interactive = true, order = "default",
        show_module_title = false, show_strip_titles = true, two_rows = false,
        default_source = { kind = "recent" },
        sources = {
          recent = {
            filter_unread = false, filter_tbr = false, filter_finished = false,
          },
          custom = { paths = {} }, tag = { tag = nil },
        },
        controls = {
          enabled = true,
          order = { "recent", "to_be_read", "tags" },
          show_buttons = { recent = true, to_be_read = true, tags = true },
          labels = { tags = "Genres" }, custom_buttons = {}, next_custom_id = 0,
        },
      },
      quotes = { show_module_title = false },
    },
    quotes = {
      rotation = "daily", show_author = true, show_title = true,
      sources = { default = true },
    },
  },
}
"""
    source = source.replace(
        "show_strip_titles = true",
        f"show_strip_titles = {str(show_strip_titles).lower()}",
    )
    settings.joinpath("home.lua").write_text(
        source,
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


def _seed_page_count_sidecar(book: Path) -> None:
    sidecar = book.with_suffix(".sdr")
    sidecar.mkdir()
    sidecar.joinpath("metadata.epub.lua").write_text(
        "return { doc_pages = 120, pagemap_use_page_labels = true, "
        "pagemap_doc_pages = 85 }\n",
        encoding="utf-8",
    )


def _wait_for_home(driver: ZenDriver) -> dict[str, object]:
    deadline = time.monotonic() + 30
    latest: dict[str, object] = {}
    while time.monotonic() < deadline:
        response = driver.command("home_state")
        latest = response.get("home", {})
        if latest.get("active") and len(latest.get("widget_ids", [])) >= 5:
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
        library = root / "library"
        fixture = build_library(library)
        book = library / "Alpha Home.epub"
        fixture["epub"].replace(book)
        fixture["epub"] = book
        _seed_home_settings(ko_home)
        _seed_bookinfo(ko_home, fixture["epub"])
        if with_history:
            _seed_history(ko_home, fixture["epub"])
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, library.resolve())
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("activate_navbar_tab", id="home")["ok"] is True
            home = _wait_for_home(driver)
            assert home["active_tab_label"] == "Home"
            assert set(home["widget_ids"]) >= {
                "featured", "strip", "quotes", "reading_goals", "stats_triplet",
            }
            assert {"Recent", "To Be Read", "Genres"} <= set(home["visible_texts"])
            assert home["page_padding"] > 0
            visual_gaps = home["visual_gaps"]
            assert len(visual_gaps) == 4
            assert max(visual_gaps) - min(visual_gaps) <= 2, visual_gaps
            screenshot = root / "home.png"
            driver.screenshot(screenshot)
            assert screenshot.stat().st_size > 0
            if with_history:
                assert "Alpha Home" in home["visible_texts"]
            else:
                assert "Alpha Home" not in home["visible_texts"]
                assert "Start reading a book to fill this space." in home["visible_texts"]
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


def test_home_genres_drills_from_tag_folders_into_books() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-home-genres-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        library = root / "library"
        fixture = build_library(library)
        _seed_home_settings(ko_home, show_strip_titles=False)
        _seed_bookinfo(ko_home, fixture["epub"])
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, library.resolve())
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("activate_navbar_tab", id="home")["ok"] is True
            _wait_for_home(driver)

            assert driver.command(
                "activate_home_target", key="strip-control:tags"
            )["ok"] is True
            groups = _wait_for_home(driver)
            assert {"Focus", "Testing"} <= set(groups["visible_texts"])
            assert {"Focus (1)", "Testing (1)"}.isdisjoint(groups["visible_texts"])
            screenshot = root / "home-genre-folders.png"
            driver.screenshot(screenshot)
            assert screenshot.stat().st_size > 0

            assert driver.command(
                "activate_home_target", key="group:Focus"
            )["ok"] is True
            books = _wait_for_home(driver)
            assert "Alpha Home" in books["visible_texts"]
            assert {"Recent", "To Be Read", "Focus"} <= set(books["visible_texts"])

            assert driver.command(
                "activate_home_target", key="strip-control:tags"
            )["ok"] is True
            _wait_for_home(driver)
            assert driver.command(
                "activate_home_target", key="group:Focus", action="context"
            )["ok"] is True
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


def test_home_edit_mode_reopens_widget_settings_after_close() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-home-edit-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        build_library(root / "library")
        _seed_home_settings(ko_home)
        settings_path = ko_home / "settings" / "Zen UI" / "home.lua"
        settings_path.write_text(
            settings_path.read_text(encoding="utf-8").replace(
                "show_status_bar = false,",
                "show_status_bar = false, edit_mode = true,",
            ),
            encoding="utf-8",
        )
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, root / "library")
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("activate_navbar_tab", id="home")["ok"] is True
            _wait_for_home(driver)

            held = driver.command(
                "activate_home_target", key="strip-control:recent", action="context"
            )
            assert held["ok"] is True, held
            deadline = time.monotonic() + 5
            strip: dict[str, object] = {}
            while time.monotonic() < deadline:
                response = driver.command("arrange_page_state")
                if response.get("ok"):
                    strip = response["arrange"]
                    break
                time.sleep(0.1)
            assert strip.get("title") == "Strip widget"
            assert driver.command("close_arrange_page")["ok"] is True

            first = driver.command("open_widget_settings", page="home", id="quotes")
            assert first["opened"] is True, first
            deadline = time.monotonic() + 5
            quotes: dict[str, object] = {}
            while time.monotonic() < deadline:
                response = driver.command("arrange_page_state")
                if response.get("ok"):
                    quotes = response["arrange"]
                    break
                time.sleep(0.1)
            assert quotes.get("title") == "Quotes widget"
            assert quotes.get("row_style") == quotes.get("standard_style")
            assert driver.command("close_arrange_page")["ok"] is True

            second = driver.command("open_widget_settings", page="home", id="quotes")
            assert second["opened"] is True, second
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
        process = launch(
            runtime, ko_home, socket_path, root / "library",
            zen_config_source="""return {
  updater = { update_auto_check = false },
  navbar = { default_tab = "home" },
}
""",
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            home = _wait_for_home(driver)
            assert home["active_tab_label"] == "Home"

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


def test_navbar_tabs_remain_tappable_with_library_background() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-background-tabs-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        library = root / "library"
        fixture = build_library(library)
        _seed_home_settings(ko_home)
        _seed_bookinfo(ko_home, fixture["epub"])
        background = root / "background.jpg"
        Image.new("RGB", (600, 800), "gray").save(background)
        socket_path = root / "driver.sock"
        process = launch(
            runtime, ko_home, socket_path, library,
            zen_config_source=f"""return {{
  updater = {{ update_auto_check = false }},
  navbar = {{
    default_tab = "home", show_icons = true, show_labels = true,
    show_tabs = {{
      books = true, home = false, authors = true, series = true,
      stats = true, to_be_read = true, collections = true,
    }},
    tab_order = {{
      "books", "series", "authors", "stats", "to_be_read", "collections",
    }},
  }},
  library_background = {{ enabled = true, path = {json.dumps(str(background))} }},
}}
""",
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            _wait_for_home(driver)

            for label, tab_id in (
                ("Library", None),
                ("Series", "series"),
                ("Authors", "authors"),
                ("Stats", "stats"),
                ("To Be Read", "to_be_read"),
                ("Collections", None),
                ("Library", None),
                ("Series", "series"),
            ):
                response = driver.command(
                    "tap_navbar_tab", label=label, y_ratio=1384 / 1440,
                )
                assert response["ok"] is True, response
                _wait_for_navbar(driver, label, tab_id)
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


def test_navbar_recovers_when_the_library_background_disappears() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-missing-background-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        library = root / "library"
        fixture = build_library(library)
        _seed_home_settings(ko_home)
        _seed_bookinfo(ko_home, fixture["epub"])
        background = root / "background.jpg"
        Image.new("RGB", (600, 800), "gray").save(background)
        socket_path = root / "driver.sock"
        process = launch(
            runtime, ko_home, socket_path, library,
            zen_config_source=f"""return {{
  updater = {{ update_auto_check = false }},
  navbar = {{ default_tab = "home" }},
  library_background = {{ enabled = true, path = {json.dumps(str(background))} }},
}}
""",
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            _wait_for_home(driver)

            background.rename(root / "renamed.jpg")

            assert driver.command("activate_navbar_tab", id="books")["ok"] is True
            _wait_for_navbar(driver, "Library", None)
            assert driver.command("activate_navbar_tab", id="authors")["ok"] is True
            _wait_for_navbar(driver, "Authors", "authors")
            assert driver.command("activate_navbar_tab", id="home")["ok"] is True
            _wait_for_navbar(driver, "Home", None)
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
        _seed_page_count_sidecar(book)
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
  browser_page_count = { show_page_count = true },
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
                    and "85\N{NO-BREAK SPACE}p." in chooser.get("page_badges", [])
                    and chooser.get("item_widget_count", 0) > 0
                    and chooser.get("image_widget_count", 0) > 0
                ):
                    break
                time.sleep(0.25)

            assert chooser["display_mode_type"] == "mosaic"
            assert {"Alpha Home", "Zen Author"} <= visible
            assert "85\N{NO-BREAK SPACE}p." in chooser["page_badges"]
            assert chooser["item_widget_count"] > 0
            assert chooser["image_widget_count"] > 0
            driver.screenshot(screenshot)
            assert screenshot.exists()
            assert screenshot.stat().st_size > 0
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)
