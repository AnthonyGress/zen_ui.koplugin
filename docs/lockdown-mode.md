---
title: Lockdown Mode
category: Lockdown Mode
summary: Restrict library, Controls, and reader interactions for a controlled reading setup.
settingsPath: Zen Settings > Extras > Lockdown mode
order: 65
---

<!-- Documentation current through ZenOS v3.0.0. -->

![Lockdown Mode](/images/zen_os/lockdown_mode.webp)

## Overview

Lockdown Mode applies restrictions across ZenOS and KOReader. It is toggled from Controls or the `ZenOS: Toggle Lockdown Mode` dispatcher action, while its behavior is configured under Extras.

## Options

- Turning Lockdown Mode on also turns Zen Mode on.
- The Zen Mode Controls button is disabled while Lockdown Mode is active.
- Lockdown Mode prompts for a restart after the mode changes.
- Magnify UI saves the current library density, switches mosaic layout to 2x2 and list mode to 3 items per page, then restores the saved density when Lockdown Mode turns off.
- Library, Controls, and Reader restrictions can be configured independently.

## Setting reference

| Setting | Description |
| --- | --- |
| Activation > Controls Lockdown button | Toggles Lockdown Mode from the Controls panel. |
| Activation > Dispatcher action | Toggles Lockdown Mode through the `ZenOS: Toggle Lockdown Mode` dispatcher action. |
| Activation > Zen Mode dependency | Enables Zen Mode when Lockdown Mode turns on and keeps Zen Mode enabled while Lockdown Mode is active. |
| Activation > Restart prompt | Prompts for a KOReader restart after Lockdown Mode changes. |
| Lockdown mode > Magnify UI | Saves the current library density, applies 2x2 mosaic and 3-item list density while enabled, and restores the saved density when disabled. |
| Library > Disable context menu | Blocks library context menu access while Lockdown Mode is active. |
| Controls > Require hold to toggle buttons | Requires a hold gesture before Controls buttons toggle while Lockdown Mode is active. |
| Controls > Disable settings panel | Blocks opening the settings panel from Controls while Lockdown Mode is active. |
| Reader > Disable bottom menu swipe | Blocks reader bottom-swipe menu and page-browser access while Lockdown Mode is active. |
| Reader > Disable multi-word selection | Blocks hold-pan selection expansion while Lockdown Mode is active. |
| Reader > Disable word search on hold | Blocks reader hold search and lookup while Lockdown Mode is active. |
