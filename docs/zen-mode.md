---
title: Zen Mode
category: Zen Mode
summary: Simplify KOReader
settingsPath: Zen UI > Controls > Buttons > Zen mode
order: 30
---

<!-- Documentation current through Zen UI v2.5.0. -->

![Controls](/images/zen_ui/quicksettings.png)

![Zen Mode](/images/zen_ui/zen_mode.png)

## Introduction

Zen Mode simplifies KOReade. When you first start Zen UI, you will be in Zen Mode. This cleans up the top menu bar and replaces it with 4 powerful items: [Controls](/zen-ui/docs/controls), Zen Settings (Unified Zen + KOReader settings), [Launcher](/zen-ui/docs/launcher), and the Home button. 

Zen Mode by default also locks the home folder. This means that you can't accidentally go "back" out of your library and into the device filesystem. If you want to navigate the filesystem you can enable it in `Zen Settings > Library > Home folder > Lock home folder`

Exiting Zen Mode with the toggle in Controls (icon below) will re-enable the top KOReader menu bar icons like Settings, Tools, etc.

![Zen Mode](/images/zen_ui/zen_mode.png)

## Options

- Toggle Zen Mode from the Controls/Launcher Zen button or the `Zen UI - Toggle Zen Mode` dispatcher action.

## Setting reference

| Setting | Description |
| --- | --- |
| Controls > Zen mode button | Toggles Zen Mode from the Controls panel. |
| Dispatcher > Zen UI - Toggle Zen Mode | Provides the same toggle as a dispatcher action for gestures, custom buttons, launcher buttons, or navbar tabs. |
| Behavior > Filtered menu tabs | Hides most default KOReader menu tabs and keeps Controls available. |
| Behavior > Restart prompt | Prompts for a restart after the Zen Mode state changes. |
| Lockdown Mode > Zen Mode dependency | Lockdown Mode turns Zen Mode on and prevents turning it off while Lockdown Mode remains active. |
