---
title: Home
category: Home
summary: Create your own E-Reader home page 
settingsPath: Zen UI > Home
order: 10
---

<!-- Documentation current through Zen UI v2.5.0. -->

![Zen UI bookshelf home](/images/zen_ui/home_bookshelf.png)

![Zen UI home](/images/zen_ui/zen_home.png)

![Zen UI home page](/images/zen_ui/home_simple.png)

## Overview

Add widgets like featured books, cover strips, reading goals, reading stats, quotes and more. Use built-in presets or save your own favorite layout.

## Options

- Show and arrange up to 5 home widgets.
- Apply, save, rename, and delete home page presets.
- Show or hide the home page top status bar.
- Configure featured, strip, reading goals, stats, and quote widgets.
- Select custom books for custom featured and strip widgets.
- Configure text styles, progress labels, interactivity, and widget-specific display options.
- Use stable page labels in featured-widget progress when a book provides a page map.

## Setting reference

| Setting | Description |
| --- | --- |
| Widgets > Widgets | Opens the widget arranger. No more than 5 widgets can be enabled. |
| Widgets > Available widgets | Includes date/time, recently read featured, custom featured, To Be Read featured, reading stats, reading goals, recently read strip, custom strip, To Be Read strip, and quotes. |
| Presets > Built-in presets | Applies bundled home page layouts. Editing a built-in preset creates an editable user copy. |
| Presets > Save current home page as preset | Saves the current home page configuration as a user preset. |
| Presets > User presets | Applies, renames, or deletes saved home page presets. |
| Home > Show top status bar | Shows or hides the top status bar on the home page. |
| Featured widgets > Show description | Shows featured-book description text. |
| Featured widgets > Interactive | Allows featured widgets to respond to selection. |
| Featured widgets > Top status bar | Shows the featured widget status bar and configures its bottom border and bold text. |
| Featured widgets > Text styles | Sets title, author, series, and description font face, size, and bold style. |
| Featured widgets > Progress labels | Selects left and right progress labels: off, percent, time to book end, current/total pages, or total pages. Current/total and total pages use stable page labels when the book provides a page map. |
| Custom featured widget > Book | Selects the book shown by the custom featured widget. |
| Custom featured widget > Clear book | Removes the selected custom featured book. |
| Featured recent and To Be Read widgets > Order | Selects default or reverse order. |
| Strip widgets > Show book titles | Shows book titles in strip widgets. |
| Strip widgets > Show badges | Shows cover badges in strip widgets. |
| Strip widgets > Interactive | Allows strip widgets to respond to selection. |
| Strip widgets > Max books shown | Sets the upper limit; narrower layouts may show fewer books. |
| Strip widgets > Two rows | Displays compatible strips across two rows. |
| Strip widgets > Center books | Centers short rows of books in compatible strip widgets. |
| Strip widgets > Order | Selects default or reverse order for recent and To Be Read strips. |
| Custom strip widget > Add book | Adds a selected book to the custom strip, up to 50 books. |
| Custom strip widget > Remove book | Removes a selected book from the custom strip. |
| Custom strip widget > Clear books | Removes all selected custom strip books. |
| Reading goals > Goal shown | Selects daily or weekly goal display. |
| Reading goals > Goals metric | Selects pages or time as the goal metric. |
| Reading goals > Daily pages goal | Sets the daily page target. |
| Reading goals > Weekly pages goal | Sets the weekly page target. |
| Reading goals > Daily time goal | Sets the daily time target in minutes. |
| Reading goals > Weekly time goal | Sets the weekly time target in minutes. |
| Reading stats widget > Stat separators | Selects dividing lines, outlined boxes, or no stat separators. |
| Reading stats widget > Font size | Sets a per-widget text size or uses the Home default. |
| Quotes widget > Quote sources | Selects any combination of default quotes, custom quotes, and annotations. |
| Quotes widget > New quote | Changes the quote daily or whenever Home refreshes. |
| Quotes widget > Show author | Shows the quote author when available. |
| Quotes widget > Show title | Shows the book title when available. |

## Stable Page Labels

Home featured widgets use KOReader page-map data when it is available. That means progress labels can show the same stable page labels used in the reader, page browser, and table of contents instead of only calculated file pages.

## Custom quotes

Add personal quotes by editing `settings/Zen UI/quotes.lua`, then enable **Custom quotes** under **Quotes widget > Quote sources**. Custom quotes can be combined with the default list and annotations. Each entry can be a `{ text, author, title }` table, the older `{ text, author }` form, or a plain string without attribution.

```lua
return {
    -- Existing formats remain supported:
    -- { text = "Quote text", author = "Author" },
    -- "Plain quote without author",

    -- The title field is optional:
    -- { text = "Quote text", author = "Author", title = "Book title" },
}
```

Annotation quotes are collected from books in KOReader's reading history and
book-information cache. Tap an annotation quote to open its book at the saved
location. Swipe horizontally on the widget to move between quotes. Quotes use a
persistent shuffled deck, so every enabled quote is shown before the list is
reshuffled.
