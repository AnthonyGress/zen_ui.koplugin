# Zen UI Locales

This folder contains gettext `.po` files for Zen UI plugin labels.

The `en.po` file is the source catalog (~254 strings). All other locale files
are translated from it. Strings with an empty `msgstr ""` fall back to English
at runtime — KOReader handles this automatically.

## Translation Progress

| Locale | Language | Status |
|--------|----------|--------|
| `en` | English | ✅ Complete (source) |
| `it` | Italian | ✅ Complete |
| `es` | Spanish | ✅ Complete |
| `fr` | French | ✅ Complete |
| `nl` | Dutch | ✅ Complete |
| `pt_BR` | Brazilian Portuguese | ✅ Complete |
| `pt_PT` | European Portuguese | ✅ Complete |
| `ro` | Romanian | ✅ Complete |
| `ru` | Russian | ✅ Complete |
| `zh_CN` | Simplified Chinese | ✅ Complete |
| `zh_TW` | Traditional Chinese | ✅ Complete |

## Contributing

To improve or correct a translation, edit the appropriate `.po` file and open a
pull request. Strings are grouped alphabetically by `msgid`. Leave `msgstr ""`
blank for any string you are not confident about — KOReader will fall back to
the English source string.
