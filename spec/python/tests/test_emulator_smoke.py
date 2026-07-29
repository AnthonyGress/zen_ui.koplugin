import os
import platform
import signal
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

from zen_driver import ZenDriver, launch, update_or_compare_golden, wait_for_socket
from fixtures import stage_epub_library


pytestmark = pytest.mark.skipif(
    os.environ.get("ZEN_UI_RUN_EMULATOR") != "1",
    reason="set ZEN_UI_RUN_EMULATOR=1 to run a real KOReader emulator",
)


def _wait_for_library(driver: ZenDriver, library: Path) -> dict[str, object]:
    deadline = time.monotonic() + 30
    latest: dict[str, object] = {}
    while time.monotonic() < deadline:
        response = driver.command("file_chooser_items")
        latest = response.get("file_chooser", {})
        if Path(str(latest.get("path", ""))).resolve() == library.resolve() and latest.get("items"):
            return latest
        time.sleep(0.25)
    raise AssertionError(f"file browser did not load fixture library: {latest}")


def _golden_root() -> Path:
    default_dir = "macos-1200x1600" if platform.system() == "Darwin" else "linux-800x600"
    return Path(os.environ.get(
        "ZEN_UI_GOLDEN_DIR",
        Path(__file__).parents[2] / "goldens" / "v2026.07" / default_dir,
    ))


def _artifact_path(name: str) -> Path:
    path = Path(__file__).parents[2] / ".artifacts" / "goldens" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _assert_golden(actual: Path, name: str) -> None:
    if platform.system() == "Darwin" and "ZEN_UI_GOLDEN_DIR" not in os.environ \
            and os.environ.get("ZEN_UI_UPDATE_GOLDENS") != "1":
        return
    expected = _golden_root() / name
    if not expected.exists() and os.environ.get("ZEN_UI_UPDATE_GOLDENS") != "1":
        return
    update_or_compare_golden(
        actual,
        expected,
        _artifact_path(f"{actual.stem}.diff.png"),
        os.environ.get("ZEN_UI_UPDATE_GOLDENS") == "1",
    )


def test_clean_emulator_renders_fixture_library_and_reader_goldens() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-emulator-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        ko_home.mkdir()
        library = root / "library"
        books = stage_epub_library(library)
        ko_home.joinpath("history.lua").write_text(
            "return {{ time = 1704067200, file = "
            + repr(str(books["wasteland123456789011"].resolve()))
            + " }}\n",
            encoding="utf-8",
        )
        socket_path = root / "driver.sock"
        library_screenshot = _artifact_path("fixture-library.png")
        settings_screenshot = _artifact_path("fixture-settings.png")
        arrange_screenshot = _artifact_path("fixture-settings-arrange.png")
        add_screenshot = _artifact_path("fixture-settings-add.png")
        reader_screenshot = _artifact_path("fixture-reader.png")
        process = launch(
            runtime,
            ko_home,
            socket_path,
            library,
            zen_config_source="""return {
  updater = { update_auto_check = false },
  features = { status_bar = false, reader_top_status_bar = false },
  navbar = { default_tab = "books" },
}
""",
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            response = driver.visible_ui()
            assert response["ok"] is True
            assert isinstance(response["ui"]["windows"], list)
            assert driver.plugin_loaded("coverbrowser")
            assert len(books) >= 5

            assert driver.command("activate_navbar_tab", id="books")["ok"] is True
            chooser = _wait_for_library(driver, library)
            assert len(chooser["items"]) >= len(books)
            driver.screenshot(library_screenshot)
            assert library_screenshot.stat().st_size > 0
            _assert_golden(library_screenshot, "fixture-library.png")

            assert driver.command("open_settings_page")["ok"] is True
            deadline = time.monotonic() + 10
            settings: dict[str, object] = {}
            while time.monotonic() < deadline:
                response = driver.command("settings_page_state")
                if response.get("ok"):
                    settings = response["settings"]
                    break
                time.sleep(0.1)
            assert settings.get("title") == "Settings"
            assert settings.get("back_visible") is False
            assert settings.get("search_focused") is False
            assert settings.get("has_search_input") is False
            assert settings.get("has_search_button") is True
            assert settings.get("shortcuts_enabled") is False
            modal_enter = driver.command("settings_modal_enter_behavior")
            assert modal_enter.get("dismissed") is True
            assert modal_enter.get("submitted") is False
            assert settings.get("row_style") == settings.get("standard_style")
            assert settings.get("title_font_size") == settings["row_style"]["font_size"]
            assert settings.get("title_bold") is True
            assert {"Controls", "Launcher", "Library", "Reader"}.issubset(
                set(settings.get("labels", []))
            )
            assert driver.command(
                "settings_page_titlebar_tap", button="search"
            )["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("has_search_input") is True
            assert driver.command("settings_page_select", label="Library")["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("title") == "Library"
            assert settings.get("back_visible") is True
            assert driver.command("settings_page_select", label="Folders")["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("title") == "Folders"
            assert driver.command("settings_page_select", label="Covers")["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("title") == "Covers"
            radio_items = [item for item in settings.get("items", []) if item["radio"]]
            assert len(radio_items) > 1
            unchecked = next(item for item in radio_items if not item["checked"])
            assert driver.command(
                "settings_page_select", label=unchecked["label"]
            )["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            selected = next(
                item for item in settings["items"] if item["label"] == unchecked["label"]
            )
            assert selected["checked"] is True
            driver.screenshot(settings_screenshot)
            assert settings_screenshot.stat().st_size > 0

            for expected_title in ("Folders", "Library", "Settings"):
                assert driver.command("settings_page_back")["ok"] is True
                settings = driver.command("settings_page_state")["settings"]
                assert settings.get("title") == expected_title
            assert settings.get("back_visible") is False

            assert driver.command(
                "settings_page_type_search", text="bu"
            )["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("search_text") == "bu"
            assert settings.get("search_focused") is True
            assert settings.get("has_search_input") is True
            assert settings.get("has_search_button") is False
            assert int(settings.get("search_text_inset", 0)) >= int(
                settings.get("search_radius", 0)
            )
            assert settings.get("shortcuts_enabled") is False

            assert driver.command("settings_page_submit_search")["ok"] is True
            time.sleep(0.4)
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("search_focused") is False
            assert settings.get("search_keyboard_visible") is False

            assert driver.command("settings_page_search", query="")["ok"] is True
            assert driver.command("settings_page_select", label="Controls")["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("has_search_input") is False
            assert settings.get("has_search_button") is True
            assert driver.command("settings_page_back")["ok"] is True

            assert driver.command(
                "settings_page_search", query="items per page"
            )["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("search_active") is True
            assert "Items per page" in settings.get("labels", [])
            search_row_style = settings.get("row_style")
            assert search_row_style == settings.get("standard_style")
            assert driver.command(
                "settings_page_search", query="widg"
            )["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("page_count", 1) > 1
            footer = driver.command("settings_page_footer_tap", zone="right")
            assert footer.get("ok") is True, footer
            assert footer.get("page") == 2
            assert driver.command(
                "settings_page_search", query="quotes"
            )["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            quotes_item = next(
                item for item in settings.get("items", [])
                if item["label"] == "Quotes widget"
            )
            assert quotes_item.get("breadcrumb") == "Home"
            assert driver.command(
                "settings_page_select", label=quotes_item["label"]
            )["ok"] is True
            time.sleep(0.2)
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange.get("title") == quotes_item["label"]
            assert driver.command("close_arrange_page")["ok"] is True
            assert driver.command("close_settings_page")["ok"] is True

            assert driver.command("open_settings_page")["ok"] is True
            time.sleep(0.2)
            assert driver.command(
                "settings_page_search", query="reading trend"
            )["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            trend_item = next(
                item for item in settings.get("items", [])
                if item["label"] == "Reading trend"
            )
            assert trend_item.get("breadcrumb") == "Extras › Stats"
            assert driver.command(
                "settings_page_select", label=trend_item["label"]
            )["ok"] is True
            time.sleep(0.2)
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange.get("title") == trend_item["label"]
            assert driver.command("close_arrange_page")["ok"] is True
            assert driver.command("close_settings_page")["ok"] is True

            assert driver.command("open_settings_page")["ok"] is True
            time.sleep(0.2)
            assert driver.command("settings_page_select", label="Launcher")["ok"] is True
            assert driver.command("settings_page_select", label="Buttons")["ok"] is True
            time.sleep(0.2)
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange.get("back_visible") is True
            assert arrange.get("has_search") is False
            assert arrange.get("has_more") is False
            assert arrange.get("has_close") is True
            assert arrange.get("page_count") == 1
            assert arrange.get("pagination_visible") is False
            assert arrange.get("row_style") == arrange.get("standard_style")
            assert arrange.get("row_style") == search_row_style
            driver.screenshot(arrange_screenshot)
            assert arrange_screenshot.stat().st_size > 0
            if str(arrange.get("title", "")).startswith("Buttons"):
                assert arrange.get("has_action") is True
                assert driver.command("arrange_page_action")["ok"] is True
                time.sleep(0.2)
                arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange.get("title") == "Add"
            driver.screenshot(add_screenshot)
            assert add_screenshot.stat().st_size > 0
            assert driver.command(
                "arrange_page_search", query="items per page"
            )["ok"] is False
            assert driver.command("close_arrange_page")["ok"] is True
            assert driver.command("close_settings_page")["ok"] is True

            assert driver.command("race_home_to_books")["ok"] is True
            deadline = time.monotonic() + 30
            cover_state: dict[str, object] = {}
            while time.monotonic() < deadline:
                cover_state = driver.command("file_chooser_cover_state").get("covers", {})
                if int(cover_state.get("files", 0)) > 0 \
                        and cover_state.get("fetched") == cover_state.get("files"):
                    break
                time.sleep(0.25)
            assert cover_state.get("fetched") == cover_state.get("files")

            deadline = time.monotonic() + 30
            cache_comparison: dict[str, object] = {}
            while time.monotonic() < deadline:
                response = driver.command("cover_cache_comparison")
                if response.get("ok"):
                    cache_comparison = response["measurement"]
                    break
                time.sleep(0.25)
            assert cache_comparison, "no visible extracted cover reached the cache"
            cold = cache_comparison["cold"]
            warm = cache_comparison["warm"]
            assert int(cold["delta"].get("full_reads", 0)) == 1
            assert int(cold["delta"].get("decode_reads", 0)) == 1
            assert int(warm["delta"].get("fast_hits", 0)) == 1
            assert int(warm["delta"].get("full_reads", 0)) == 0
            assert int(warm["delta"].get("decode_reads", 0)) == 0
            assert int(warm["delta"].get("validation_reads", 0)) == 0
            assert float(cold["elapsed_ms"]) >= 0
            assert float(warm["elapsed_ms"]) >= 0

            wasteland = books["wasteland123456789011"]
            assert driver.open_book(wasteland)["ok"] is True
            deadline = time.monotonic() + 30
            reader: dict[str, object] = {}
            while time.monotonic() < deadline:
                reader = driver.reader_state().get("reader", {})
                if reader.get("open") and Path(str(reader.get("file"))).resolve() == wasteland.resolve():
                    break
                time.sleep(0.25)
            assert reader.get("open") is True
            driver.screenshot(reader_screenshot)
            assert reader_screenshot.stat().st_size > 0
            _assert_golden(reader_screenshot, "fixture-reader.png")
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def test_settings_page_keeps_enabled_status_bar_at_top() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-settings-status-") as temporary:
        root = Path(temporary)
        ko_home = root / "home"
        library = root / "library"
        ko_home.mkdir()
        library.mkdir()
        socket_path = root / "driver.sock"
        process = launch(
            runtime,
            ko_home,
            socket_path,
            library,
            zen_config_source="""return {
  updater = { update_auto_check = false },
  features = { status_bar = true, reader_top_status_bar = false },
}
""",
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("open_settings_page")["ok"] is True
            deadline = time.monotonic() + 10
            settings: dict[str, object] = {}
            while time.monotonic() < deadline:
                response = driver.command("settings_page_state")
                if response.get("ok"):
                    settings = response["settings"]
                    break
                time.sleep(0.1)
            assert settings.get("status_visible") is True
            settings_status_y = settings.get("status_y")
            settings_status_identity = settings.get("status_identity")
            assert settings.get("status_spacer_height", 0) < settings.get("status_height", 0)
            assert driver.command("refresh_clock")["ok"] is True
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                settings = driver.command("settings_page_state")["settings"]
                if settings.get("status_identity") != settings_status_identity:
                    break
                time.sleep(0.1)
            assert settings.get("status_identity") != settings_status_identity, settings
            assert settings.get("status_spacer_height", 0) < settings.get("status_height", 0)
            settings_status_y = settings.get("status_y")
            settings_status_identity = settings.get("status_identity")
            assert driver.command("settings_page_select", label="Launcher")["ok"] is True
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("status_identity") == settings_status_identity
            assert settings.get("status_y") == settings_status_y
            assert driver.command("settings_page_select", label="Buttons")["ok"] is True
            deadline = time.monotonic() + 5
            arrange: dict[str, object] = {}
            while time.monotonic() < deadline:
                response = driver.command("arrange_page_state")
                if response.get("ok"):
                    arrange = response["arrange"]
                    break
                time.sleep(0.1)
            assert arrange.get("status_visible") is True
            assert arrange.get("status_height") == arrange.get("filemanager_status_height")
            assert settings_status_y == arrange.get("filemanager_status_y")
            status_identity = arrange.get("status_identity")
            assert driver.command("refresh_clock")["ok"] is True
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                arrange = driver.command("arrange_page_state")["arrange"]
                if arrange.get("status_identity") != status_identity:
                    break
                time.sleep(0.1)
            assert arrange.get("status_identity") != status_identity, arrange
            assert arrange.get("status_y") == arrange.get("filemanager_status_y")
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
