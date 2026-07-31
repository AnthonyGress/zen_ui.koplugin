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


def _select_arrange_label(driver: ZenDriver, label: str) -> None:
    arrange = driver.command("arrange_page_state")["arrange"]
    index = arrange["labels"].index(label) + 1
    items_per_page = int(arrange["items_per_page"])
    page = (index - 1) // items_per_page + 1
    if page != 1:
        assert driver.command("arrange_page_go_to", page=page)["ok"] is True
    assert driver.command("arrange_page_select", index=index)["ok"] is True


def _open_buttons_arrange(driver: ZenDriver) -> None:
    assert driver.command("open_settings_page")["ok"] is True
    for _attempt in range(3):
        if driver.command("arrange_page_state").get("ok") is True:
            return
        labels = driver.command("settings_page_state")["settings"]["labels"]
        target = "Controls" if "Controls" in labels else "Buttons"
        assert driver.command("settings_page_select", label=target)["ok"] is True
    raise AssertionError("Buttons arrange page did not open")


def test_action_selection_saves_immediately_and_x_closes_settings_stack() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-action-save-") as temporary:
        root = Path(temporary)
        ko_home, library = root / "home", root / "library"
        ko_home.mkdir()
        library.mkdir()
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, library)
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            _open_buttons_arrange(driver)
            assert driver.command("arrange_page_action")["ok"] is True
            _select_arrange_label(driver, "Action")
            _select_arrange_label(driver, "Action: (none)")
            _select_arrange_label(driver, "General")
            _select_arrange_label(driver, "History")

            actions = driver.command("custom_action_state")["actions"]
            assert len(actions) == 1
            assert actions[0]["history"] is True

            assert driver.command("arrange_page_hardware_back")["ok"] is True
            actions = driver.command("custom_action_state")["actions"]
            assert len(actions) == 1
            assert actions[0]["history"] is True

            assert driver.command("arrange_page_close_button")["ok"] is True
            stack = driver.command("zen_settings_stack_state")
            assert stack["settings_open"] is False
            assert stack["arrange_count"] == 0

            assert driver.command("open_settings_page")["ok"] is True
            assert driver.command(
                "activate_custom_control", id=actions[0]["id"]
            )["ok"] is True
            history = driver.command("history_state")
            assert history["open"] is True
            assert history["settings_open"] is False
            assert driver.command("close_history")["ok"] is True

            _open_buttons_arrange(driver)
            _select_arrange_label(driver, "History")
            _select_arrange_label(driver, "Action: History")
            _select_arrange_label(driver, "General")
            _select_arrange_label(driver, "History")
            _select_arrange_label(driver, "File browser")

            actions = driver.command("custom_action_state")["actions"]
            assert actions[0]["history"] is False
            assert actions[0]["filebrowser"] is True
            assert driver.command("arrange_page_close_button")["ok"] is True

            assert driver.command("open_settings_page")["ok"] is True
            assert driver.command(
                "activate_custom_control", id=actions[0]["id"]
            )["ok"] is True
            stack = driver.command("zen_settings_stack_state")
            assert stack["settings_open"] is False
            assert stack["arrange_count"] == 0

            assert driver.command("open_settings_page")["ok"] is True
            assert driver.command("open_koreader_history")["ok"] is True
            history = driver.command("history_state")
            assert history["open"] is True
            assert history["settings_open"] is False
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


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
            assert settings.get("has_more") is False
            assert settings.get("shortcuts_enabled") is False
            assert settings.get("row_focusable") is True
            assert settings.get("row_focus_inner_border") is True
            assert settings.get("row_focus_feedback") is True
            settings_focus_border = settings.get("row_focus_border_size")
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
            alignment_keys = {
                "text_x", "toggle_x", "toggle_right", "caret_x", "caret_right",
            }
            settings_row_alignment = settings.get("row_alignment", {})
            assert alignment_keys.issubset(settings_row_alignment)
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
            non_touch_search = driver.command("settings_page_non_touch_search")
            assert non_touch_search.get("search_button_focused") is True
            assert non_touch_search.get("close_focused_from_search") is True
            assert non_touch_search.get("search_focused_from_close") is True
            assert non_touch_search.get("search_input_focused") is True
            assert non_touch_search.get("exited") is True
            assert non_touch_search.get("close_focused") is True
            assert non_touch_search.get("search_input_focused_after_exit") is False
            assert non_touch_search.get("search_closed") is True
            assert non_touch_search.get("search_button_focused_after_close") is True

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
            pager_x = settings.get("pager_x")
            pager_y = settings.get("pager_y")
            pager_width = settings.get("pager_width")
            assert isinstance(pager_y, (int, float))
            assert pager_width == int(settings.get("screen_width", 0) * 0.92)
            footer = driver.command("settings_page_footer_tap", zone="right")
            assert footer.get("ok") is True, footer
            assert footer.get("page") == 2
            settings = driver.command("settings_page_state")["settings"]
            assert settings.get("pager_x") == pager_x
            assert settings.get("pager_y") == pager_y
            assert settings.get("pager_width") == pager_width
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
            assert arrange.get("row_alignment") == settings_row_alignment
            assert arrange.get("row_focusable") is True
            assert arrange.get("row_focus_inner_border") is True
            assert arrange.get("row_focus_feedback") is True
            assert arrange.get("row_focus_border_size") == settings_focus_border
            assert arrange.get("handle_visible") is True
            assert arrange.get("footer_cancel_hidden") is True
            assert arrange.get("footer_first_hidden") is True
            assert arrange.get("footer_last_hidden") is True
            assert arrange.get("footer_ok_hidden") is True
            driver.screenshot(arrange_screenshot)
            assert arrange_screenshot.stat().st_size > 0
            if str(arrange.get("title", "")).startswith("Buttons"):
                assert arrange.get("has_action") is True
                assert arrange.get("action_focusable") is True
                assert arrange.get("close_focusable") is True
                assert arrange.get("action_focus_feedback") is True
                assert arrange.get("close_focus_feedback") is True
                header_focus = driver.command("arrange_page_focus_header")
                assert header_focus.get("action_focused") is True
                assert header_focus.get("close_focused") is True
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

            assert driver.command("open_settings_page")["ok"] is True
            assert driver.command("settings_page_search", query="tabs")["ok"] is True
            assert driver.command("settings_page_select", label="Tabs")["ok"] is True
            time.sleep(0.2)
            arrange = driver.command("arrange_page_state")["arrange"]
            initial_labels = arrange.get("labels", [])
            assert len(initial_labels) > 1
            dragged = driver.command("arrange_page_drag", **{"from": 1, "to": 2})
            assert dragged.get("ok") is True, dragged
            assert dragged.get("marked") == 0
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange.get("labels", [])[:2] == initial_labels[1::-1]
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
            top_right = driver.command(
                "arrange_page_top_tap", x_ratio=0.97, y_ratio=0.01
            )
            assert top_right.get("ok") is True
            assert top_right.get("same_widget") is True
            assert top_right.get("title") == arrange.get("title")
            assert top_right.get("marked") == 0
            assert top_right.get("menu_open") is False
            top_center = driver.command(
                "arrange_page_top_tap",
                x_ratio=0.5,
                y_ratio=0.01,
                close_menu=True,
            )
            assert top_center.get("ok") is True
            assert top_center.get("same_widget") is True
            assert top_center.get("title") == arrange.get("title")
            assert top_center.get("marked") == 0
            assert top_center.get("menu_open") is True
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


def test_touch_arrange_drag_crosses_to_previous_page() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-touch-arrange-") as temporary:
        root = Path(temporary)
        ko_home, library = root / "home", root / "library"
        ko_home.mkdir()
        library.mkdir()
        socket_path = root / "driver.sock"
        process = launch(
            runtime,
            ko_home,
            socket_path,
            library,
            env_overrides={
                "EMULATE_READER_W": "600",
                "EMULATE_READER_H": "800",
            },
        )
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            assert driver.command("open_settings_page")["ok"] is True
            assert driver.command("settings_page_search", query="widgets")["ok"] is True
            assert driver.command("settings_page_select", label="Widgets")["ok"] is True
            time.sleep(0.2)

            arrange = driver.command("arrange_page_state")["arrange"]
            initial_labels = arrange["labels"]
            items_per_page = int(arrange["items_per_page"])
            last_page = int(arrange["page_count"])
            assert last_page > 1

            started = driver.command(
                "arrange_page_drag", **{"from": 1, "to": 1, "release": False}
            )
            assert started.get("ok") is True, started
            assert started.get("marked") == 1
            assert started.get("dragging") is True
            turned = driver.command("arrange_page_turn", direction="next")
            assert turned.get("page") == 2, turned
            assert turned.get("marked") == 0
            assert turned.get("dragging") is False
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["handle_focus_visible"] is False
            assert arrange["labels"] == initial_labels

            first_index = (last_page - 1) * items_per_page
            expected_labels = list(initial_labels)
            expected_labels.insert(first_index - 1, expected_labels.pop(first_index))
            assert driver.command("arrange_page_go_to", page=last_page)["ok"] is True
            dragged = driver.command("arrange_page_drag", **{"from": 1, "edge": "left"})
            assert dragged.get("ok") is True, dragged
            assert dragged.get("marked") == 0
            assert dragged.get("page") == last_page - 1, dragged
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["handle_focus_visible"] is False
            assert arrange["labels"] == expected_labels

            expected_labels = list(arrange["labels"])
            expected_labels.insert(first_index - 1, expected_labels.pop(first_index))
            assert driver.command("arrange_page_go_to", page=last_page)["ok"] is True
            dragged = driver.command("arrange_page_drag", **{"from": 1, "edge": "up"})
            assert dragged.get("ok") is True, dragged
            assert dragged.get("marked") == 0
            assert dragged.get("page") == last_page - 1, dragged
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["handle_focus_visible"] is False
            assert arrange["labels"] == expected_labels

            submenu_index = arrange["submenu_indices"][0]
            submenu_page = (submenu_index - 1) // items_per_page + 1
            assert driver.command("arrange_page_go_to", page=submenu_page)["ok"] is True
            assert driver.command("arrange_page_select", index=submenu_index)["ok"] is True
            submenu = driver.command("arrange_page_state")["arrange"]
            assert submenu["title"] != arrange["title"]
            assert driver.command("arrange_page_back")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["labels"] == expected_labels
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def test_touch_arrange_swipe_release_exits_drag_mode() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-arrange-swipe-release-") as temporary:
        root = Path(temporary)
        ko_home, library = root / "home", root / "library"
        ko_home.mkdir()
        library.mkdir()
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, library)
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            _open_buttons_arrange(driver)
            time.sleep(0.2)

            arrange = driver.command("arrange_page_state")["arrange"]
            initial_labels = arrange["labels"]
            assert len(initial_labels) > 1

            dragged = driver.command(
                "arrange_page_drag",
                **{
                    "from": 1,
                    "to": 2,
                    "release_gesture": "swipe",
                    "focus_without_unfocus": True,
                    "track_refresh_modes": True,
                },
            )
            assert dragged.get("ok") is True, dragged
            assert dragged.get("marked") == 0
            assert dragged.get("dragging") is False
            assert dragged.get("drag_unfocus_pending") is True

            time.sleep(0.2)
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["labels"][:2] == initial_labels[1::-1]
            assert arrange["drag_unfocus_pending"] is False
            assert arrange["handle_focus_visible"] is False
            assert arrange["drop_refresh_modes"][-1] == "ui"

            top_menu = driver.command("arrange_page_top_swipe", close_menu=True)
            assert top_menu.get("ok") is True, top_menu
            assert top_menu.get("menu_open") is True
            assert top_menu.get("marked") == 0
            assert top_menu.get("dragging") is False

            assert driver.command("close_arrange_page")["ok"] is True
            assert driver.command("close_settings_page")["ok"] is True
            _open_buttons_arrange(driver)
            time.sleep(0.2)
            reopened = driver.command("arrange_page_state")["arrange"]
            assert reopened["labels"][:2] == initial_labels[1::-1]
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def test_touch_dpad_arrange_handle_reorders_with_keys() -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    with tempfile.TemporaryDirectory(prefix="zen-ui-non-touch-arrange-") as temporary:
        root = Path(temporary)
        ko_home, library = root / "home", root / "library"
        ko_home.mkdir()
        library.mkdir()
        socket_path = root / "driver.sock"
        process = launch(runtime, ko_home, socket_path, library)
        try:
            wait_for_socket(socket_path)
            driver = ZenDriver(socket_path)
            _open_buttons_arrange(driver)
            time.sleep(0.2)

            arrange = driver.command("arrange_page_state")["arrange"]
            initial_title = arrange["title"]
            initial_labels = arrange["labels"]
            assert arrange["marked"] == 0
            assert arrange["handle_visible"] is True
            assert arrange["handle_focused"] is False
            assert arrange["item_focused"] is True
            assert arrange["item_focusable"] is True
            assert arrange["toggle_focusable"] is True
            assert arrange["toggle_focus_feedback"] is True
            assert arrange["toggle_focus_border_size"] > arrange["row_focus_border_size"]
            assert arrange["footer_cancel_hidden"] is True
            assert arrange["footer_first_hidden"] is True
            assert arrange["footer_last_hidden"] is True
            assert arrange["footer_ok_hidden"] is True

            assert driver.command("arrange_page_key", key="Left")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["handle_focused"] is True

            menu_result = driver.command(
                "arrange_page_menu", close_menu=True
            )
            assert menu_result["ok"] is True
            assert menu_result["menu_open"] is True
            assert menu_result["marked"] == 0
            assert menu_result["handle_active"] is False
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["handle_focused"] is True
            assert driver.command("arrange_page_key", key="Right")["ok"] is True
            assert driver.command("arrange_page_state")["arrange"]["item_focused"] is True

            initial_checked = arrange["checked"][0]
            assert driver.command("arrange_page_key", key="Right")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["toggle_focused"] is True
            assert arrange["focused_index"] == 1

            assert driver.command("arrange_page_key", key="Press")["ok"] is True
            assert driver.command(
                "arrange_page_key", key="Press", phase="release"
            )["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["checked"][0] != initial_checked
            assert arrange["toggle_focused"] is True

            assert driver.command("arrange_page_key", key="Down")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["toggle_focused"] is True
            assert arrange["focused_index"] == 2
            assert driver.command("arrange_page_key", key="Up")["ok"] is True
            assert driver.command("arrange_page_key", key="Left")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["item_focused"] is True
            assert arrange["focused_index"] == 1

            assert driver.command("arrange_page_key", key="Left")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["handle_focused"] is True

            assert driver.command("arrange_page_key", key="Press")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["marked"] == 1
            assert arrange["handle_active"] is True
            assert driver.command(
                "arrange_page_key", key="Press", phase="repeat"
            )["ok"] is True
            assert driver.command("arrange_page_state")["arrange"]["marked"] == 1
            assert driver.command(
                "arrange_page_key", key="Press", phase="release"
            )["ok"] is True

            assert driver.command("arrange_page_key", key="Down")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["marked"] == 2
            assert arrange["labels"][:2] == initial_labels[1::-1]

            assert driver.command("arrange_page_key", key="Press")["ok"] is True
            assert driver.command(
                "arrange_page_key", key="Press", phase="release"
            )["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["marked"] == 0
            assert arrange["handle_active"] is False
            assert arrange["handle_focused"] is True

            assert driver.command("arrange_page_key", key="Right")["ok"] is True
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["item_focused"] is True
            assert driver.command("arrange_page_key", key="Return")["ok"] is True
            time.sleep(0.2)
            arrange = driver.command("arrange_page_state")["arrange"]
            assert arrange["title"] != initial_title
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
