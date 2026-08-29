import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import translation_utils


class TranslationUtilsTest(unittest.TestCase):
    def test_context_comments_are_complete_and_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lua_path = root / "menu.lua"
            lua_path.write_text(
                'local items = {\n    text = _("Open"),\n    cancel = _("Cancel"),\n'
                '    other_cancel = _("Cancel"),\n}\n',
                encoding="utf-8",
            )
            sources = {}
            for msgid, line, context in translation_utils.extract_from_file(str(lua_path)):
                sources.setdefault(msgid, []).append((lua_path.name, line, context))

            po_path = root / "fr.po"
            po_path.write_text(
                'msgid ""\nmsgstr ""\n"Language: fr\\n"\n\n'
                'msgid ""\n"Can"\n"cel"\n'
                'msgstr ""\n"Annu"\n"ler"\n',
                encoding="utf-8",
            )
            existing = translation_utils.parse_po(str(po_path))
            self.assertEqual({"Cancel": "Annuler"}, existing)
            translation_utils.rewrite_po(
                str(po_path), existing, sources,
                [], remove_dead=False, alphabetize=True,
            )
            first = po_path.read_text(encoding="utf-8")

            self.assertIn('#. Context: text = _("Open"), cancel = _("Cancel"),', first)
            self.assertIn("#: menu.lua:3 menu.lua:4", first)
            self.assertIn('msgstr "Annuler"', first)

            translation_utils.rewrite_po(
                str(po_path), translation_utils.parse_po(str(po_path)), sources,
                [], remove_dead=False, alphabetize=True,
            )
            self.assertEqual(first, po_path.read_text(encoding="utf-8"))

            escaped = 'Annuler "maintenant" à C:\\books\nNext\titem\r'
            self.assertEqual(
                escaped,
                translation_utils.parse_po_text(
                    translation_utils.format_entry("Cancel", escaped)
                )["Cancel"],
            )


if __name__ == "__main__":
    unittest.main()
