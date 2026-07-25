---
title: Extras
category: Extras
summary: Additional Zen goodies like OPDS, lighting schedules, and sleep settings
settingsPath: Zen UI > Extras
order: 60
---

<!-- Documentation current through Zen UI v2.5.0. -->

## Overview

Extras collects optional additions that fall outside of the Library/Reader. It includes Stats, Zen OPDS, TBR behavior, custom icons, Rakuyomi return behavior, lighting schedules, whole-word search matching, sleep settings, and Lockdown Mode.

## Stats

Open the **Stats** tab from the Navbar to view reading activity. Use **Extras > Stats** to choose and arrange the dashboard widgets, enable Edit mode for on-page adjustments, set the default text size, and choose stat separators. Widgets can show activity for today, week, month, year, all time, personal records, your library, the current book, reading trends, goals, and the reading calendar.

### Widgets and settings

Choose from Today, This week, This month, This year, All time, Personal records, Library, Current book, Reading trend, Reading goals, and Reading calendar widgets. Enable the widgets you want and hold an item in **Extras > Stats > Widgets** to arrange its position. The dashboard has six slots; the Reading calendar uses two.

The Reading trend widget can show pages or time for the past 7, 14, 30, or 90 days. Text-based widgets can use the default Stats font size or an individual override. Enable **Edit mode** to open a widget's settings directly from the Stats page, and use **Stat separators** to choose dividers, outlines, or no separation.

## OPDS

![OPDS catalog](/images/zen_ui/opds.png)

![OPDS context menu](/images/zen_ui/opds_context.png)

Enable **Extras > Zen OPDS** to apply Zen UI styling to the OPDS catalog browser. The OPDS view inherits the same styling as your library: rounded corners, list and mosaic view, items per page, and other layout options all carry over. Each book in the catalog shows its cover.

Tap and hold any item to open the OPDS context menu for per-item actions.

## To Be Read

To add one book to your To Be Read list, tap and hold it in the Library, choose **Read status**, then choose **To Be Read**. The book appears in the To Be Read Navbar tab and in To Be Read Home widgets, including the To Be Read strip when that widget is enabled.

To include every new book automatically, enable **Extras > Include new books in TBR**. This adds books with the New status to the To Be Read Navbar tab and Home widgets without changing their saved read status. New includes unread books and books modified since they were last opened.

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
| Extras > Stats > Widgets | Chooses and arranges dashboard widgets. The calendar occupies two widget slots; up to six slots can be enabled. |
| Extras > Stats > Edit mode | Enables editing supported Stats and Home widgets directly from their pages. |
| Extras > Stats > Default font size | Sets the default text size for Stats widgets. Individual supported widgets can override it. |
| Extras > Stats > Stat separators | Selects divider lines, outlines, or no separators for Stats widgets. |
| Extras > Zen OPDS | Enables Zen UI OPDS enhancements, including cover art, list/mosaic view, hold menu, and navigation changes. |
| Extras > Zen OPDS > Display mode | Selects mosaic, list, or classic OPDS display mode. |
| Extras > Include new books in TBR | Adds books with the New status to the To Be Read tab and Home widgets. New includes unread books and books modified since they were last opened. |
| Extras > Allow custom icons | Lets KOReader user icons override bundled Zen UI icons, with fallback to bundled and built-in icons. |
| Extras > Rakuyomi > Return to chapter list on exit | Returns Rakuyomi-owned books to their manga chapter list when exiting the reader. Disable this to return to Rakuyomi library view. |
| Extras > Search > Match whole words | Uses whole-word search instead of substring search. |
| Extras > Schedules > Brightness schedule | Enables automatic frontlight brightness changes and sets day/night times and values. |
| Extras > Schedules > Night mode schedule | Enables automatic night mode changes and sets on/off times. |
| Extras > Schedules > Warmth schedule | Enables automatic warmth changes and sets day/night times and values on natural-light devices. |
| Extras > Sleep | Shows supported sleep screen controls, sleep presets, automatic dimmer, and automatic suspend integrations. |
| Extras > Lockdown mode | Configures library, Controls, and reader restrictions for Lockdown Mode. |
