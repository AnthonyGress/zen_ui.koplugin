from pathlib import Path

from PIL import Image
import pytest

from zen_driver import (
    compare_frames,
    find_text,
    install_startup_alert_patch,
    normalize_visible_text,
    update_or_compare_golden,
)


def test_compare_frames_is_exact_and_writes_a_diff(tmp_path: Path) -> None:
    expected = tmp_path / "expected.png"
    actual = tmp_path / "actual.png"
    diff = tmp_path / "diff.png"
    Image.new("RGBA", (4, 4), "white").save(expected)
    Image.new("RGBA", (4, 4), "white").save(actual)
    assert compare_frames(expected, actual, diff)

    Image.new("RGBA", (4, 4), "black").save(actual)
    assert not compare_frames(expected, actual, diff)
    assert diff.exists()


def test_update_or_compare_golden_updates_only_when_explicit(tmp_path: Path) -> None:
    actual = tmp_path / "actual.png"
    expected = tmp_path / "goldens" / "frame.png"
    diff = tmp_path / "diff.png"
    Image.new("RGB", (2, 2), "white").save(actual)
    update_or_compare_golden(actual, expected, diff, update=True)
    assert expected.read_bytes() == actual.read_bytes()
    update_or_compare_golden(actual, expected, diff, update=False)

    with pytest.raises(AssertionError, match="missing committed golden"):
        update_or_compare_golden(actual, tmp_path / "missing.png", diff, update=False)


def test_find_text_returns_semantic_widget_bounds() -> None:
    tree = {
        "children": [
            {"text": "Library", "x": 10, "y": 20, "width": 100, "height": 30},
        ]
    }
    assert find_text(tree, "Library").x == 10
    assert find_text(tree, "Missing") is None


def test_normalize_visible_text_removes_bidi_formatting_controls() -> None:
    assert normalize_visible_text("\u2068#2 – Semantic Series\u2069") == (
        "#2 – Semantic Series"
    )
    assert normalize_visible_text("\u202aZen Author\u202c") == "Zen Author"


def test_startup_alert_patch_is_installed_once_and_preserves_choices(tmp_path: Path) -> None:
    patch = install_startup_alert_patch(tmp_path)
    source = patch.read_text(encoding="utf-8")
    assert 'G_reader_settings:has("quickstart_shown_version")' in source
    assert 'G_reader_settings:has("color_rendering")' in source
    assert "Device:hasColorScreen()" in source

    patch.write_text("-- existing user choice\n", encoding="utf-8")
    assert install_startup_alert_patch(tmp_path).read_text(encoding="utf-8") == (
        "-- existing user choice\n"
    )
