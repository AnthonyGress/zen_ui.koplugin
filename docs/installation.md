---
title: Installation
category: Getting Started
summary: Install ZenOS by copying the plugin folder into your KOReader plugins directory.
settingsPath: ''
order: 5
---

<!-- Documentation current through ZenOS v3.0.0. -->

![zenos.koplugin folder inside the KOReader plugins directory](/images/zen_ui/plugins_folder.png)

## Prerequisites

- KOReader (version 2026.03 or later) must be installed first in order to use ZenOS. [Install KOReader](https://github.com/koreader/koreader#installation)
> Older versions *may* work but ZenOS was built and tested with the latest stable version of KOReader 2026.03
- Disable or uninstall any **other plugins/patches** that modify the UI such as Simple UI, Project: Title, or VOS, as they may conflict and cause instability.

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

The migration performs two automatic restarts and moves
`settings/Zen UI` to `settings/ZenOS`. If Zen UI is disabled, enable it once so
the migration can run. Do not manually install `zenos.koplugin` beside an
existing `zen_ui.koplugin` directory.

For a fresh installation:

1. Go to the [Releases](https://github.com/AnthonyGress/zen_ui.koplugin/releases) page and download `zenos.koplugin.zip` from the latest release.
2. Unzip the archive. You should have a **folder** named `zenos.koplugin`.
3. Copy the `zenos.koplugin` **folder** into the KOReader plugins directory for your device (see table below).
   - Make sure you are copying the unzipped **folder** and **not the .zip** file itself.
4. Restart KOReader. ZenOS will load automatically.
   - If you don't see ZenOS load, manually enable the plugin in Tools > More tools > Plugin management > ZenOS.

> The final path should look like: `.../plugins/zenos.koplugin/main.lua`

![zenos.koplugin folder inside the KOReader plugins directory](/images/zen_ui/plugins_folder.png)

## Plugins directory by device

| Device | Plugins directory |
| --- | --- |
| **Kobo** | `/mnt/onboard/.adds/koreader/plugins/` |
| **Kindle** | `/mnt/base-us/koreader/plugins/` |
| **PocketBook** | `/mnt/ext1/applications/koreader/plugins/` |
| **Android** | `/sdcard/koreader/plugins/` |
| **Desktop (Linux/macOS)** | `/koreader/plugins/` |

5. Once the folder is copied, restart KOReader and you should be guided through initial setup.

![ZenOS Startup Screen](/images/zen_ui/quickstart.png)
