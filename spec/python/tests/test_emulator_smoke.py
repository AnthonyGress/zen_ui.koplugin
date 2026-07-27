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
