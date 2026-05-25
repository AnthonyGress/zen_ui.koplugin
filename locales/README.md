---
---

# Zen UI Locales

This folder contains gettext `.po` files for Zen UI plugin labels.

The `en.po` file is the source catalog (~254 strings). All other locale files
are translated from it. Strings with an empty `msgstr ""` fall back to English
at runtime — KOReader handles this automatically.

## Translations

| Locale | Language |
|--------|----------|
| `en` | English |
| `it` | Italian |
| `es` | Spanish |
| `fr` | French |
| `nl` | Dutch |
| `bg` | Bulgarian |
| `cs` | Czech |
| `pt_BR` | Brazilian Portuguese |
| `pt_PT` | European Portuguese |
| `ro` | Romanian |
| `ru` | Russian |
| `zh_CN` | Simplified Chinese |
| `zh_TW` | Traditional Chinese |

## Contributing

To improve or correct a translation, edit the appropriate `.po` file and open a
pull request. Strings are grouped alphabetically by `msgid`. Leave `msgstr ""`
blank for any string you are not confident about — KOReader will fall back to
the English source string.
