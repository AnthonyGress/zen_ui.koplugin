---
title: Installation
category: Getting Started
summary: Install ZenOS by copying the plugin folder into your KOReader plugins directory.
settingsPath: ''
order: 5
---

<!-- Documentation current through ZenOS v3.0.0. -->

![zenos.koplugin folder inside the KOReader plugins directory](/images/zen_os/plugins_folder.png)

## Prerequisites

- KOReader 2026.03 or later must be installed first. ZenOS is tested against KOReader 2026.07 and compatibility-tested against 2026.03. [Install KOReader](https://github.com/koreader/koreader#installation)
- Disable or remove Project: Title before starting ZenOS. ZenOS automatically disables Simple UI, QuickMenu, Appearance, etc and known conflicting user patches, then asks you to restart KOReader.

## Migrating from Project Title

If you previously used [Project Title](https://github.com/joshuacant/ProjectTitle), keep reading. Otherwise skip to the [Install](#install) section.

 If you have Project Title installed, you must disable or remove it before using ZenOS. Both plugins patch the Cover Browser, and having both active at the same time will cause conflicts.

Choose one of the following:

- **Remove it** — Delete the `projecttitle.koplugin` folder from your KOReader plugins directory.
- **Disable it** — Rename the folder to `projecttitle.koplugin.disabled`. KOReader will ignore it on next launch.

After disabling or removing Project Title, restart KOReader and ZenOS will load cleanly.

## Install

Already using Zen UI? Update from its settings page instead of copying ZenOS
beside it. The updater preserves your settings and completes the rename after
restarting KOReader.

The migration performs two automatic restarts. It keeps `settings/Zen UI` as an
unchanged rollback snapshot and migrates a separate copy to `settings/ZenOS`.
If Zen UI is disabled, enable it once so the migration can run. Do not manually
install `zenos.koplugin` beside an existing `zen_ui.koplugin` directory.

For a fresh installation:

1. Go to the [Releases](https://github.com/AnthonyGress/zen_ui.koplugin/releases) page and download `zenos.koplugin.zip` from the latest release.
2. Unzip the archive. You should have a **folder** named `zenos.koplugin`.
3. Copy the `zenos.koplugin` **folder** into the KOReader plugins directory for your device (see table below).
   - Make sure you are copying the unzipped **folder** and **not the .zip** file itself.
4. Restart KOReader. ZenOS will load automatically.
   - If you don't see ZenOS load, manually enable the plugin in Tools > More tools > Plugin management > ZenOS.
   - On first launch, ZenOS guides you through setup and a short top-menu tour.

> The final path should look like: `.../plugins/zenos.koplugin/main.lua`

![zenos.koplugin folder inside the KOReader plugins directory](/images/zen_os/plugins_folder.png)

## Plugins directory by device

| Device | Plugins directory |
| --- | --- |
| **Kobo** | `/mnt/onboard/.adds/koreader/plugins/` |
| **Kindle** | `/mnt/base-us/koreader/plugins/` |
| **PocketBook** | `/mnt/ext1/applications/koreader/plugins/` |
| **Android** | `/sdcard/koreader/plugins/` |
| **Desktop (Linux/macOS)** | `/koreader/plugins/` |

![ZenOS Startup Screen](/images/zen_os/quickstart.png)
