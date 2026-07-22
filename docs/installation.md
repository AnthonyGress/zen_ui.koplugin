---
title: Installation
category: Getting Started
summary: Install Zen UI by copying the plugin folder into your KOReader plugins directory.
settingsPath: ''
order: 5
---

<!-- Documentation current through Zen UI v2.5.0. -->

![zen_ui.koplugin folder inside the KOReader plugins directory](/images/zen_ui/plugins_folder.png)

## Prerequisites

- KOReader (version 2026.03 or later) must be installed first in order to use Zen UI. [Install KOReader](https://github.com/koreader/koreader#installation)
> Older versions *may* work but Zen UI was built and tested with the latest stable version of KOReader 2026.03
- Disable or uninstall any **other plugins/patches** that modify the UI such as Simple UI, Project: Title, or VOS, as they may conflict and cause instability.

## Migrating from Project Title

If you previously used [Project Title](https://github.com/joshuacant/ProjectTitle), keep reading. Otherwise skip to the [Install](#install) section.

 If you have Project Title installed, you must disable or remove it before using Zen UI. Both plugins patch the Cover Browser, and having both active at the same time will cause conflicts.

Choose one of the following:

- **Remove it** — Delete the `projecttitle.koplugin` folder from your KOReader plugins directory.
- **Disable it** — Rename the folder to `projecttitle.koplugin.disabled`. KOReader will ignore it on next launch.

After disabling or removing Project Title, restart KOReader and Zen UI will load cleanly.

## Install

1. Go to the [Releases](https://github.com/AnthonyGress/zen_ui.koplugin/releases) page and download `zen_ui.koplugin.zip` from the latest release.
2. Unzip the archive. You should have a **folder** named `zen_ui.koplugin`.
3. Copy the `zen_ui.koplugin` **folder** into the KOReader plugins directory for your device (see table below).
   - Make sure you are copying the unzipped **folder** and **not the .zip** file itself.
4. Restart KOReader. Zen UI will load automatically.
   - If you don't see Zen UI load, manually enable the plugin in Tools > More tools > Plugin management > Zen UI.

> The final path should look like: `.../plugins/zen_ui.koplugin/main.lua`

## Plugins directory by device

| Device | Plugins directory |
| --- | --- |
| **Kobo** | `/mnt/onboard/.adds/koreader/plugins/` |
| **Kindle** | `/mnt/base-us/koreader/plugins/` |
| **PocketBook** | `/mnt/ext1/applications/koreader/plugins/` |
| **Android** | `/sdcard/koreader/plugins/` |
| **Desktop (Linux/macOS)** | `/koreader/plugins/` |

5. Once the folder is copied, restart KOReader and you should be guided through initial setup.

![Zen UI Startup Screen](/images/zen_ui/quickstart.png)

