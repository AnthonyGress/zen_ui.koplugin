---
title: Extras
category: Extras
summary: Additional Zen goodies like OPDS, lighting schedules, and sleep settings
settingsPath: Zen UI > Extras
order: 60
---

## Overview

Extras collects optional addtions that fall outside of the Library/Reader. It includes Zen OPDS, TBR behavior, custom icons, Rakuyomi return behavior, lighting schedules, whole word search matching, sleep seetings, and Lockdown Mode.

## OPDS

![OPDS catalog](/images/zen_ui/opds.png)

![OPDS context menu](/images/zen_ui/opds_context.png)

Enable **Extras > Zen OPDS** to apply Zen UI styling to the OPDS catalog browser. The OPDS view inherits the same styling as your library: rounded corners, list and mosaic view, items per page, and other layout options all carry over. Each book in the catalog shows its cover.

Tap and hold any item to open the OPDS context menu for per-item actions.

## Custom Icons

Enable **Extras > Allow custom icons**, then place your icons in the `/koreader/icons` folder. Any icon that Zen UI uses will prefer the icons placed in `/koreader/icons` when enabled.

> Note: Icons placed directly inside `/koreader/plugins/zen_ui.koplugin/icons` are erased on updates, so do not put custom icons there.

## Rakuyomi

Enable **Extras > Rakuyomi > Return to chapter list on exit** to keep the current behavior: Rakuyomi-owned books return to the manga chapter list when you exit the reader.

Disable it to return to the Rakuyomi library view instead.

## Schedules

Use **Extras > Schedules** for automatic brightness, night mode, and warmth changes. Brightness and warmth schedules set separate day and night times and values; warmth is shown only on devices with natural-light support.

## Search, Sleep, And Lockdown

Use **Extras > Search** to switch library search between substring and whole-word matching.

Use **Extras > Sleep** for KOReader sleep screen controls, sleep presets, automatic dimmer, and automatic suspend integrations when available.

Use **Extras > Lockdown mode** to configure library, Controls, and reader restrictions.

## Setting reference

| Setting | Description |
| --- | --- |
| Extras > Zen OPDS | Enables Zen UI OPDS enhancements, including cover art, list/mosaic view, hold menu, and navigation changes. |
| Extras > Zen OPDS > Display mode | Selects mosaic, list, or classic OPDS display mode. |
| Extras > Include new books in TBR | Includes unread books and books modified since they were last opened in the To Be Read view. |
| Extras > Allow custom icons | Lets KOReader user icons override bundled Zen UI icons, with fallback to bundled and built-in icons. |
| Extras > Rakuyomi > Return to chapter list on exit | Returns Rakuyomi-owned books to their manga chapter list when exiting the reader. Disable this to return to Rakuyomi library view. |
| Extras > Search > Match whole words | Uses whole-word search instead of substring search. |
| Extras > Schedules > Brightness schedule | Enables automatic frontlight brightness changes and sets day/night times and values. |
| Extras > Schedules > Night mode schedule | Enables automatic night mode changes and sets on/off times. |
| Extras > Schedules > Warmth schedule | Enables automatic warmth changes and sets day/night times and values on natural-light devices. |
| Extras > Sleep | Shows supported sleep screen controls, sleep presets, automatic dimmer, and automatic suspend integrations. |
| Extras > Lockdown mode | Configures library, Controls, and reader restrictions for Lockdown Mode. |
