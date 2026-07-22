---
title: Launcher
category: Launcher
summary: Customizable app launcher with action buttons, plugin buttons, and folders.
settingsPath: Zen UI > Launcher
order: 40
---

<!-- Documentation current through Zen UI v2.5.0. -->

![Launcher](/images/zen_ui/launcher.png)

## Overview

Launcher adds a configurable tab to the Zen UI menu. It can create shortcut buttons for Controls, dispatcher actions, and detected launchable plugins. Place these buttons inside folders for more organization.

## Options

- Enable or disable the Launcher feature.
- Show launcher button labels. This is enabled by default.
- Hide reader action buttons when the launcher is shown from the library.
- Center-align launcher buttons.
- Arrange launcher buttons.
- Add action buttons backed by dispatcher actions.
- Add buttons that run a chosen Controls control.
- Add plugin buttons from launchable plugin menus found on the device.
- Add folders and arrange buttons inside each folder.
- Insert a row break to start later buttons on a new row.
- Configure each button or folder label and icon.
- Move action and plugin buttons into folders or back to the root launcher.

## Setting reference

| Setting | Description |
| --- | --- |
| Enable | Enables or disables the Launcher feature. |
| Buttons | Opens the launcher button arranger. |
| Show labels | Shows launcher button labels. Enabled by default; disabling it hides the labels. |
| Hide reader actions in library | When enabled, action buttons bound to reader-only dispatcher actions are hidden (and inactive) while the launcher is opened from the library. Disabled by default. |
| Center align buttons | Centers launcher buttons instead of left-aligning them. |
| Buttons > Add > Control | Adds a launcher button that runs a selected Controls control. |
| Buttons > Add > Action | Adds a launcher button that runs a dispatcher action, with a suggested icon. |
| Buttons > Add > Plugin | Scans for launchable plugin menus and adds the selected plugin menu as a launcher button with a suggested icon. |
| Buttons > Add > Row break | Inserts a row break in the Launcher button layout. |
| Control button > Control | Selects the Controls control run by the button. |
| Buttons > Add > Folder | Adds a launcher folder. |
| Action button > Action | Selects the dispatcher action run by the button. |
| Action button > Icon | Selects a bundled, KOReader, or user icon. |
| Action button > Label | Sets a custom label or leaves it empty to use the action title. |
| Plugin button > Plugin | Selects the launchable plugin menu run by the button. |
| Plugin button > Icon | Selects a bundled, KOReader, or user icon. |
| Plugin button > Label | Sets the plugin button label. |
| Folder > Label | Sets the folder label. |
| Folder > Icon | Sets the folder icon. |
| Folder > Folder buttons | Opens the arranger for buttons inside the folder. |
| Folder buttons > Add > Action | Adds an action button inside the folder. |
| Folder buttons > Add > Plugin | Adds a detected plugin menu button inside the folder. |
| Button movement > Move to folder | Moves an action or plugin button into an existing launcher folder. |
| Button movement > Move out of folder | Moves a button from a folder back to the root launcher. |
| Button or folder > Delete | Deletes a button, or deletes a folder and its buttons after confirmation. |
