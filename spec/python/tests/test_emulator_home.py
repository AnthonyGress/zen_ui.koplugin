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


def _seed_history_books(ko_home: Path, books: list[Path]) -> None:
    ko_home.joinpath("history.lua").write_text(
        "return {\n"
        + "\n".join(
            "  { time = " + str(1704067200 - index)
            + ", file = " + json.dumps(str(book.resolve())) + " },"
            for index, book in enumerate(books)
        )
        + "\n}\n",
        encoding="utf-8",
    )


def _seed_history(ko_home: Path, book: Path) -> None:
    _seed_history_books(ko_home, [book])


def _seed_home_settings(
    ko_home: Path, *, show_strip_titles: bool = True, two_row_strip: bool = False
) -> None:
    settings = ko_home / "settings" / "ZenOS"
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
        interactive = true, show_description = true,
        show_status_bar = false,
        progress_meta = { left = "percent", right = "total_pages" },
      },
      stats_triplet = {},
      reading_goals = {},
      strip = {
        count = 4, interactive = true, order = "default",
        show_strip_titles = true, two_rows = false,
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
          labels = { tags = "Tags" }, custom_buttons = {}, next_custom_id = 0,
        },
      },
      quotes = {},
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
    if two_row_strip:
        source = source.replace(
            "featured = true, strip = true, quotes = true,\n"
            "        reading_goals = true, stats_triplet = true,",
            "featured = true, strip = true, quotes = false,\n"
            "        reading_goals = false, stats_triplet = false,",
        )
        source = source.replace(
            "count = 4, interactive = true, order = \"default\",",
            "count = 8, interactive = true, order = \"default\",",
        )
        source = source.replace("two_rows = false", "two_rows = true")
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


def _wait_for_home(
    driver: ZenDriver,
    required_texts: set[str] | None = None,
    required_book_paths: set[str] | None = None,
    minimum_widget_count: int = 5,
) -> dict[str, object]:
    deadline = time.monotonic() + 30
    latest: dict[str, object] = {}
    while time.monotonic() < deadline:
        response = driver.command("home_state")
        latest = response.get("home", {})
        visible_texts = {
            normalize_visible_text(str(value))
            for value in latest.get("visible_texts", [])
        }
        latest["visible_texts"] = sorted(visible_texts)
        book_paths = set(latest.get("book_paths", []))
        if latest.get("active") \
                and len(latest.get("widget_ids", [])) >= minimum_widget_count \
                and (not required_texts or required_texts <= visible_texts) \
                and (not required_book_paths or required_book_paths <= book_paths):
            return latest
        time.sleep(0.25)
    raise AssertionError(f"Home widgets did not become ready: {latest}")


def test_two_row_strip_offsets_its_bottom_anchor_by_the_home_row_gap() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-home-two-row-strip-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        library = root / "library"
        fixture = build_library(library)
        books = [fixture["epub"]]
        for index in range(2, 9):
            book = library / f"Two Row Strip {index}.epub"
            book.write_bytes(fixture["epub"].read_bytes())
            books.append(book)
        _seed_home_settings(ko_home, show_strip_titles=False, two_row_strip=True)
        _seed_bookinfo(ko_home, fixture["epub"])
        _seed_history_books(ko_home, books)
        socket_path = root / "driver.sock"
        process = launch(
            runtime,
            ko_home,
            socket_path,
            library.resolve(),
            env_overrides={
                "EMULATE_READER_W": "562",
                "EMULATE_READER_H": "725",
            },
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("activate_navbar_tab", id="home")["ok"] is True
            home = _wait_for_home(
                driver,
                required_book_paths={str(book.resolve()) for book in books[1:]},
                minimum_widget_count=2,
            )
            bottom_inset = int(home["body_height"]) - int(home["strip_bottom"])
            expected_bottom_inset = (
                int(home["top_visual_inset"]) + int(home["row_gap"])
            )
            assert abs(bottom_inset - expected_bottom_inset) <= 2, home
        finally:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


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
            assert {"Recent", "To Be Read", "Tags"} <= set(home["visible_texts"])
            assert home["page_padding"] > 0
            visual_gaps = home["visual_gaps"]
            assert len(visual_gaps) == 4
            assert max(visual_gaps) - min(visual_gaps) <= 3, visual_gaps
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


def test_home_tags_drill_from_tag_folders_into_books() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-home-tags-") as temporary:
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
            groups = _wait_for_home(driver, {"Focus", "Testing"})
            assert {"Focus", "Testing"} <= set(groups["visible_texts"])
            assert {"Focus (1)", "Testing (1)"}.isdisjoint(groups["visible_texts"])
            screenshot = root / "home-tag-folders.png"
            driver.screenshot(screenshot)
            assert screenshot.stat().st_size > 0

            assert driver.command(
                "activate_home_target", key="group:Focus"
            )["ok"] is True
            book_path = str(fixture["epub"].resolve())
            books = _wait_for_home(
                driver, {"Focus"}, required_book_paths={book_path}
            )
            assert book_path in books["book_paths"]
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
        settings_path = ko_home / "settings" / "ZenOS" / "home.lua"
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
            assert strip.get("title") == "Book strip"
            assert strip.get("status_visible") is True
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
            assert quotes.get("title") == "Quotes"
            assert quotes.get("status_visible") is True
            assert quotes.get("row_style") == quotes.get("standard_style")
            assert driver.command("close_arrange_page")["ok"] is True

            second = driver.command("open_widget_settings", page="home", id="quotes")
            assert second["opened"] is True, second
            assert driver.command("close_arrange_page")["ok"] is True

            assert driver.command("open_settings_page")["ok"] is True
            deadline = time.monotonic() + 5
            settings: dict[str, object] = {}
            while time.monotonic() < deadline:
                response = driver.command("settings_page_state")
                if response.get("ok"):
                    settings = response["settings"]
                    break
                time.sleep(0.1)
            assert settings.get("status_visible") is True

            reopened = driver.command("arrange_page_state")
            assert reopened.get("ok") is True, reopened
            assert reopened["arrange"].get("status_visible") is True
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

            for label, tap_id, tab_id in (
                ("Library", "books", None),
                ("Series", "series", "series"),
                ("Authors", "authors", "authors"),
                ("Stats", "stats", "stats"),
                ("To Be Read", "to_be_read", "to_be_read"),
                ("Collections", "collections", None),
                ("Library", "books", None),
                ("Series", "series", "series"),
            ):
                response = driver.command(
                    "tap_navbar_tab", label=label, id=tap_id, y_ratio=1384 / 1440,
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
