---
title: Reader
category: Reader
summary: Configure reader status bars, bottom status bar presets, font access, lookup tools, and page navigation.
settingsPath: ZenOS > Reader
order: 50
---

<!-- Documentation current through ZenOS v3.0.0. -->

![Page browser menu](/images/zen_ui/page_browser_menu.png)

![Page browser table of contents](/images/zen_ui/page_browser_toc.png)

![Page browser bookmarks](/images/zen_ui/page_browser_bookmarks.png)

![Page browser search](/images/zen_ui/page_browser_search.png)

![Reader](/images/zen_ui/reader.png)

![Dictionary lookup menu](/images/zen_ui/dictionary_lookup_menu.png)

![Highlight menu](/images/zen_ui/hilight_menu.png)

> **Note:** To access the default KOReader menu from the page browser, tap the Aa icon in the top right.

![Reader menu](/images/zen_ui/reader_menu.png)

## Overview

Reader settings control ZenOS features while a book is open. They cover the top status bar, reader themes and font menu, highlight and lookup tools, bottom swipe, stable page labels, page browser, return behavior, and bottom status bar options including presets.

![Page browser](/images/zen_ui/page_browser.png)

## Options

- Configure a reader top status bar with left, center, and right item slots.
- Apply built-in or custom themes for light and dark reader modes.
- Apply prebuilt bottom status bars or save your current setup as a preset.
- Open KOReader's reader font controls from ZenOS.
- Configure Zen quick lookup, Zen highlight menu, Wikipedia, and other lookup actions.
- Enable bottom swipe and the Zen page browser.
- Use stable page labels in the page browser and table of contents when a book provides a page map.
- Restore the previous library location when leaving the reader.
- Configure bottom status bar font and CBZ/PDF hiding.

## Setting reference

| Setting | Description |
| --- | --- |
| Top status bar > Enable top status bar | Shows ZenOS's top reader status bar. |
| Top status bar > Left items | Selects and arranges time, battery, Wi-Fi, brightness, RAM usage, disk space, custom text, book title, author, or chapter for the left slot. |
| Top status bar > Center items | Selects and arranges top-bar items for the center slot. |
| Top status bar > Right items | Selects and arranges top-bar items for the right slot. |
| Top status bar > Show separator | Shows separators inside the selected slot. |
| Top status bar > Custom text | Sets custom top-bar text. Empty text falls back to the device model. |
| Top status bar > Font size | Sets the top-bar font size from 8 to 36. |
| Top status bar > Font | Sets the top-bar font face or restores the default font. |
| Top status bar > Separator | Selects a preset separator for top-bar items. |
| Top status bar > Show bottom border | Draws a separator below the reader top status bar. |
| Reader themes > Enable reader themes | Enables ZenOS reader themes. |
| Reader themes > Dark mode | Selects the theme used while KOReader night mode is active. |
| Reader themes > Light mode | Selects the theme used while KOReader night mode is inactive. |
| Reader themes > Custom themes | Creates, edits, and deletes custom themes. A custom theme can set its name, background color, text color, and font. |
| Font > Reader font menu | Opens KOReader's reader font submenu when a reader instance is active. |
| Highlight / Lookup > Zen quick lookup | Enables ZenOS quick lookup behavior. |
| Highlight / Lookup > Zen highlight menu | Enables ZenOS's highlight menu. |
| Highlight / Lookup > Show Wikipedia | Shows Wikipedia in lookup options. |
| Highlight / Lookup > Show AI assistant | Shows an Assistant plugin button in lookup and highlight menus when the plugin is installed. |
| Highlight / Lookup > Show other items | Shows non-Zen KOReader quick lookup options alongside Zen buttons. |
| Reader > Verbose time to chapter end | Shows expanded chapter time information in compatible footer layouts. |
| Reader > Enable bottom swipe | Enables bottom-swipe reader menu behavior. This is forced on while page browser is enabled. |
| Reader > Enable page browser | Enables ZenOS page browser. It requires bottom swipe and supports stable page labels when the current book provides a page map. |
| Reader > Restore library location on exit | Returns to the previous library location after leaving the reader. |
| Bottom status bar > Presets > Built-in presets | Applies a prebuilt bottom status bar layout. |
| Bottom status bar > Presets > Save current settings as preset | Saves the current bottom status bar setup as a user preset. |
| Bottom status bar > Presets > User presets | Applies or deletes saved bottom status bar presets. |
| Bottom status bar > Left items | Selects and arranges bottom-bar items for the left slot, independent of the top bar. |
| Bottom status bar > Center items | Selects and arranges bottom-bar items for the center slot. |
| Bottom status bar > Right items | Selects and arranges bottom-bar items for the right slot. |
| Bottom status bar > Font | Sets footer font face, size, and bold style. |
| Bottom status bar > Hide in CBZ/PDF files | Hides the footer for CBZ and PDF documents. |
| Bottom status bar > KOReader status bar options | Exposes KOReader's built-in footer/status bar settings. |

## Dictionary lookup menu

![Dictionary lookup menu](/images/zen_ui/dictionary_lookup_menu.png)

Tap and hold a word while reading to open the Zen quick lookup menu. It shows the dictionary definition for the selected word along with ZenOS action buttons. Enable it with **Highlight / Lookup > Zen quick lookup**. Toggle **Show Wikipedia** to add a Wikipedia button, and **Show other items** to keep KOReader's native quick lookup options alongside the Zen buttons.

## Highlight menu

![Highlight menu](/images/zen_ui/hilight_menu.png)

Tap + hold and drag to highlight a selection of text and open the Zen highlight menu. It collects highlight, lookup, and annotation actions for the selected text in a single Zen-styled menu. Enable it with **Highlight / Lookup > Zen highlight menu**.

## Stable Page Labels

ZenOS uses KOReader page-map labels when a book provides them. The reader page browser shows stable labels on page tiles and during page scrubbing, and the Zen table of contents shows the same labels beside chapter entries. Home featured widgets use the same data for current/total page progress.

## Status bars

The reader has two independent status bars: a top bar and a bottom bar. Each bar has three slots — left, center, and right — that you customize separately. Drop items like time, battery, Wi-Fi, brightness, RAM usage, disk space, custom text, book title, author, or chapter into any slot and arrange their order. The top and bottom bars are configured independently, so you can show different items in each.

## Verbose time to chapter end

Enable **Reader > Verbose time to chapter end** to show the written-out time remaining in the current chapter, the same style Kindle uses (e.g. "12 minutes left in chapter"). 
