---
title: Actions
category: Actions
summary: ZenOS dispatcher actions and where they can be triggered.
settingsPath: ''
order: 55
---

<!-- Documentation current through ZenOS v3.0.0. -->

## Overview

ZenOS registers dispatcher actions with KOReader so they can be assigned to gestures, Controls buttons, Navbar tabs, Launcher buttons, and any other KOReader feature that uses the Dispatcher action picker.

Controls, Navbar, and Launcher can also launch detected plugin menus directly. Those plugin buttons are launch shortcuts, not dispatcher actions.

## ZenOS dispatcher actions

| Action title | Available in | What it does |
| --- | --- | --- |
| ZenOS: Toggle Zen Mode | General | Turns Zen Mode on or off. If Lockdown Mode is active, Zen Mode stays on. |
| ZenOS: Toggle Lockdown Mode | General | Turns Lockdown Mode on or off. Turning it on also enables Zen Mode. |
| ZenOS: Toggle Incognito Mode | General | Turns Incognito Mode on or off. |
| ZenOS: Toggle top reader status bar | Reader | Shows or hides ZenOS's top reader status bar. |
| ZenOS: Toggle reader themes | Reader | Enables or disables the selected Zen reader themes. |
| ZenOS: Toggle bottom reader status bar | Reader | Shows or hides KOReader's bottom reader status bar, restoring the previous footer mode when shown. |
| ZenOS: Toggle reader status bars | Reader | Toggles the reader top and bottom status bars together. |
| ZenOS: Table of contents | Reader | Opens the Zen table of contents. |
| ZenOS: Home | General | Opens the ZenOS home screen. |
| ZenOS: Library | General | Opens the ZenOS Library, respecting the restore-last-location setting. |
| ZenOS: Authors | General | Opens the ZenOS authors tab. |
| ZenOS: Series | General | Opens the ZenOS series tab. |
| ZenOS: Tags | General | Opens the ZenOS tags tab. |
| ZenOS: Open folder | General | Opens your Library to the chosen folder. |
| ZenOS: Sync progress (pull + push) | General | Runs a unified KOReader sync pull and push. |

## Trigger surfaces

| Surface | How to use actions |
| --- | --- |
| Gestures | Assign any ZenOS dispatcher action from KOReader's gesture action picker. Reader-only actions only work while a book is open. |
| Controls | Go to **ZenOS > Controls > Buttons**, choose **Add > Action**, pick a dispatcher action, then set its icon and label. |
| Navbar | Go to **ZenOS > Navbar > Tabs**, choose **Add > Action**, pick a dispatcher action, then set its icon and label. |
| Launcher | Go to **ZenOS > Launcher > Buttons**, choose **Add > Action**, pick a dispatcher action, then set its icon and label. |
| KOReader Dispatcher integrations | Any KOReader or plugin UI that exposes Dispatcher actions can use the same ZenOS action IDs. |

## Plugin launch shortcuts

Controls, Navbar, and Launcher also include **Add > Plugin Menu**. This scans installed plugins for launchable menu entries and creates a shortcut to that plugin menu. Use this for plugin screens that are not exposed as dispatcher actions.
