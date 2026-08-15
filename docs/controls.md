---
title: Controls
category: Controls
summary: All your controls in one place
settingsPath: ZenOS > Controls
order: 20
---

<!-- Documentation current through ZenOS v3.0.0. -->

![Controls launcher](/images/zen_ui/quick_settings_launcher.png)

![Controls panel](/images/zen_ui/quicksettings.png)

## Overview

Controls adds a fast control panel to KOReader. It allows you to toggle Wi-Fi, frontlight, rotation, ZenOS modes, brightness, and warmth controls with a single swipe. You can also add action, plugin, and KOReader menu buttons for quick access.

## Options

- Choose and arrange up to 9 visible buttons.
- Configure the rotate button to cycle rotation or apply a fixed 90, 180, or 270 rotation.
- Add action buttons backed by dispatcher actions.
- Add plugin buttons from launchable plugin menus found on the device.
- Add KOReader menu buttons for native submenus available in the current library or reader context.
- Get an automatically suggested icon when creating an action, plugin, or KOReader menu button.
- Use the screenshot button with countdown timer.
- Show brightness and warmth sliders when the device supports those controls.
- Flip the left-hand/right-hand icon used by Controls and the Library/Home menu tab.
- Reset the button layout to defaults without deleting saved action and plugin buttons.

## Setting reference

| Setting | Description |
| --- | --- |
| Buttons > Buttons | Opens the button arranger. Disabled buttons are dimmed when the 9-button limit is reached. |
| Buttons > Built-in buttons | Includes Wi-Fi, night mode, frontlight, gyroscope, rotate, Zen Mode, Lockdown, Incognito, USB, file search, restart, exit, sleep, screenshot, sync, cloud, OPDS, Calibre, Calibre Search, Z-Library, LocalSend, Filebrowser, QuickRSS, Notion, reading streak, statistics progress, statistics calendar, battery stats, and supported game plugins when detected. |
| Buttons > Rotate action | Sets the rotate button to cycle rotation or apply 90, 180, or 270 rotation directly. |
| Buttons > Add > Action | Creates a user-defined Controls button that runs a dispatcher action, with a suggested icon. New buttons are added to the order list and shown when there is room under the 9-button limit. |
| Buttons > Add > Plugin | Scans for launchable plugin menus and adds the selected plugin menu as a Controls button with a suggested icon. |
| Buttons > Add > KOReader menu | Adds a native KOReader submenu, such as Network, Tools, or Style tweaks, with a suggested icon. Reader-only menus remain visible but dimmed in the library. |
| Action button > Action | Selects the dispatcher action run by the button. |
| Action button > Icon | Selects a bundled, KOReader, or user icon. |
| Action button > Label | Sets a custom label or leaves it empty to use the action title. |
| Plugin button > Plugin | Selects the launchable plugin menu run by the button. |
| Plugin button > Icon | Selects a bundled, KOReader, or user icon. |
| Plugin button > Label | Sets the plugin button label. |
| KOReader menu button > KOReader menu | Selects the native submenu opened by the button. |
| KOReader menu button > Icon | Selects a bundled, KOReader, or user icon. |
| KOReader menu button > Label | Sets the button label. |
| Custom button > Show | Shows or hides the button in Controls. |
| Custom button > Delete | Deletes the button and removes it from the order list. |
| Show brightness slider | Shows the frontlight brightness slider in Controls. |
| Show warmth slider | Shows the warmth slider on devices with natural light support. |
| Flip LH/RH icon | Flips the Controls and Library/Home icons. |
| Reset to defaults | Restores the default Controls button layout. Action, plugin, and KOReader menu buttons are not removed; they are disabled and kept in your saved configuration. |
