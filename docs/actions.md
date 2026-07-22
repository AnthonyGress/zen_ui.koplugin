---
title: Actions
category: Actions
summary: Zen UI dispatcher actions and where they can be triggered.
settingsPath: ''
order: 55
---

<!-- Documentation current through Zen UI v2.5.0. -->

## Overview

Zen UI registers dispatcher actions with KOReader so they can be assigned to gestures, Controls buttons, Navbar tabs, Launcher buttons, and any other KOReader feature that uses the Dispatcher action picker.

Controls, Navbar, and Launcher can also launch detected plugin menus directly. Those plugin buttons are launch shortcuts, not dispatcher actions.

## Zen UI dispatcher actions

| Action title | Available in | What it does |
| --- | --- | --- |
| Zen UI - Toggle Zen Mode | General | Turns Zen Mode on or off. If Lockdown Mode is active, Zen Mode stays on. |
| Zen UI - Toggle Lockdown Mode | General | Turns Lockdown Mode on or off. Turning it on also enables Zen Mode. |
| Zen UI - Toggle Incognito Mode | General | Turns Incognito Mode on or off. |
| Zen UI - Toggle top reader status bar | Reader | Shows or hides Zen UI's top reader status bar. |
| Zen UI - Toggle reader themes | Reader | Enables or disables the selected Zen reader themes. |
| Zen UI - Toggle bottom reader status bar | Reader | Shows or hides KOReader's bottom reader status bar, restoring the previous footer mode when shown. |
| Zen UI - Toggle reader status bars | Reader | Toggles the reader top and bottom status bars together. |
| Zen UI - Table of contents | Reader | Opens the Zen table of contents. |
| Zen UI - Home | General | Opens the Zen UI home screen. |
| Zen UI - Library | General | Opens the Zen UI Library, respecting the restore-last-location setting. |
| Zen UI - Authors | General | Opens the Zen UI authors tab. |
| Zen UI - Series | General | Opens the Zen UI series tab. |
| Zen UI - Tags | General | Opens the Zen UI tags tab. |
| Zen UI - Open folder | General | Opens your Library to the chosen folder. |
| Zen UI - Sync progress (pull + push) | General | Runs a unified KOReader sync pull and push. |

## Trigger surfaces

| Surface | How to use actions |
| --- | --- |
| Gestures | Assign any Zen UI dispatcher action from KOReader's gesture action picker. Reader-only actions only work while a book is open. |
| Controls | Go to **Zen UI > Controls > Buttons**, choose **Add > Action**, pick a dispatcher action, then set its icon and label. |
| Navbar | Go to **Zen UI > Library > Navbar > Tabs**, choose **Add > Action**, pick a dispatcher action, then set its icon and label. |
| Launcher | Go to **Zen UI > Launcher > Buttons**, choose **Add > Action**, pick a dispatcher action, then set its icon and label. |
| KOReader Dispatcher integrations | Any KOReader or plugin UI that exposes Dispatcher actions can use the same Zen UI action IDs. |

## Plugin launch shortcuts

Controls, Navbar, and Launcher also include **Add > Plugin**. This scans installed plugins for launchable menu entries and creates a shortcut to that plugin menu. Use this for plugin screens that are not exposed as dispatcher actions.
