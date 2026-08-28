---
---

# ZenOS Locales

This folder contains gettext `.po` files for ZenOS plugin labels.

The `en.po` file is the source catalog. All other locale files
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
| `de` | German |
| `bg` | Bulgarian |
| `cs` | Czech |
| `hu` | Hungarian |
| `pt_BR` | Brazilian Portuguese |
| `pt_PT` | European Portuguese |
| `ro` | Romanian |
| `ru` | Russian |
| `uk` | Ukrainian |
| `el` | Greek |
| `ja` | Japanese |
| `vi` | Vietnamese |
| `zh_CN` | Simplified Chinese |
| `zh_TW` | Traditional Chinese |
| `zh_HK` | Traditional Chinese (Hong Kong) |
| `zh_MO` | Traditional Chinese (Macau) |

## Contributing

To improve or correct a translation, edit the appropriate `.po` file and open a
pull request. Strings are grouped alphabetically by `msgid`. Leave `msgstr ""`
blank for any string you are not confident about — KOReader will fall back to
the English source string.

## Maintenance

Synchronize every catalog with the Lua source in one command:

```sh
python3 translation_utils.py --sync
```

This removes dead entries, adds missing entries, translates empty `msgstr`
values, and alphabetizes each catalog. Untranslated English strings are sent to
Google Translate; existing translations are preserved. Use `--locale LOCALE`
to process only one catalog.
