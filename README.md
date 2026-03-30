# Zen UI

A clean, minimal UI overhaul for [KOReader](https://github.com/koreader/koreader). Zen UI removes visual clutter and replaces it with a focused, distraction-free reading experience — without touching the KOReader core.

---

## Philosophy

Zen UI is built on one idea: **less is more.** Every feature either removes noise or adds something genuinely useful. Nothing ships by default that isn't worth having. All settings live in one place. The plugin loads fast, stays out of the way, and can be recovered from in seconds if something goes wrong.

Throughout development, three things were non-negotiable: **performance**, **stability**, and **battery life**. Patches are applied lazily and only when their feature is enabled. No background timers, no unnecessary redraws. On e-ink devices where every refresh costs power and every frame counts, that matters.

---

## Features

### Bottom Navigation Bar
A clean, tab-based navigation bar at the bottom of the file browser. Configurable tabs (Books, Favorites, History, Collections, and more), with optional labels, custom icons, and sortable layout.

### Quick Settings Panel
A swipe-up panel in the reader for the controls you actually use — frontlight, warmth, WiFi, night mode, sleep, rotation, and more. Fully configurable: reorder, show/hide individual buttons.

### Custom Status Bar
A minimal reading status bar in the reader. Shows only what you want: time, battery, progress, disk space, RAM — all optional and individually toggled.

### File Browser Improvements
- Cover images as folder thumbnails
- Clean mosaic and list view options with configurable density
- Hide the "up folder" entry for a cleaner look
- Remove underlines from file list items
- Configurable sort order, items per page, and landscape/portrait layout

### Context Menu
A streamlined context menu in the file browser with quick access to read status, favorites, move, rename, and delete (optional).

### Reader Clock
An unobtrusive clock overlay inside the reader. Toggle 12/24-hour format independently of the system setting.

### Zen Mode
Strips down the reader interface to its bare essentials. Disables top-menu swipe zones to prevent accidental menu triggers while reading.

### Zen Pagination Bar
A subtle, minimal page progress indicator — no numbers, no noise.

### Built-in Updater
Check for and install new Zen UI releases directly from the settings menu, without leaving KOReader.

### Safe Mode
If a patch causes a crash or conflict, Zen UI's safe mode disables all hooks so you can get back into KOReader and fix the issue.

---

## Installation

1. Go to the [Releases](https://github.com/AnthonyGress/zen_ui.koplugin/releases) page and download `zen_ui.koplugin.zip` from the latest release.
2. Unzip the archive. You should have a folder named `zen_ui.koplugin`.
3. Copy the `zen_ui.koplugin` folder into the KOReader plugins directory for your device:

| Device | Plugins directory |
|--------|-------------------|
| **Kobo** | `/mnt/onboard/.adds/koreader/plugins/` |
| **Kindle** | `/mnt/us/extensions/koreader/plugins/` |
| **PocketBook** | `/mnt/ext1/applications/koreader/plugins/` |
| **Android** | `sdcard/koreader/plugins/` |
| **Desktop (Linux/macOS)** | `~/.config/koreader/plugins/` |

4. Restart KOReader. Zen UI will load automatically.
5. Open **Zen UI Settings** from the file browser menu or the top menu to configure features.

> The final path should look like: `.../plugins/zen_ui.koplugin/main.lua`

---

## Settings

All settings are in one place: **Menu → Zen UI Settings**

Settings are grouped by feature area (File Browser, Navbar, Quick Settings, Status Bar, Reader). Every feature can be toggled independently. Changes that require a restart will prompt you automatically.

---

## Localization

Zen UI is fully translated into:

| Locale | Language |
|--------|----------|
| `en` | English |
| `it` | Italian |
| `es` | Spanish |
| `fr` | French |
| `nl` | Dutch |
| `pt_BR` | Brazilian Portuguese |
| `pt_PT` | European Portuguese |
| `ro` | Romanian |
| `ru` | Russian |
| `zh_CN` | Simplified Chinese |
| `zh_TW` | Traditional Chinese |

To contribute a translation or fix an existing one, see [locales/README.md](locales/README.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Credits

Zen UI is original work, but it wouldn't exist without the broader KOReader community. Several open source projects provided direct inspiration, reference implementations, or code that was adapted and built upon:

- **[sebdelsol/KOReader.patches](https://github.com/sebdelsol/KOReader.patches)** — Patches and UI techniques that informed several of Zen UI's features.
- **[qewer33/koreader-patches](https://github.com/qewer33/koreader-patches)** — Additional patch approaches and ideas, particularly around UI customization, specifically the navbar and quicksettings .
- **[joshuacant/ProjectTitle](https://github.com/joshuacant/ProjectTitle)** — The OG plugin that started it all for me. This was my first experience with KOReader plugins and an alternative UI.
- **[doctorhetfield-cmd/simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin)** — A fellow KOReader UI plugin that served as an inspiration as well as a model for how to apply language translations throughout the plugin.

Thank you to everyone who published their KOReader work openly.

---

## Contributing

Bug reports, feature requests, translations, and code contributions are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Security

See [SECURITY.md](SECURITY.md) for how to report vulnerabilities.

## License

[GPL-3.0](LICENSE)
