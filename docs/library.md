---
title: Library
category: Library
summary: All your books in one place
settingsPath: Zen UI > Library
order: 30
---

![Library cover view](/images/zen_ui/library_covers_full.png)

![Library list view](/images/zen_ui/library_list_full.png)

![Context menu](/images/zen_ui/context_menu.png)

## Overview

Library settings control the KOReader library. Customize the top status bar, layout, folder display, background image, and cover metadata. Tap and hold on any item in the Library or the Navbar and it will bring up the Context Menu. This is a detailed menu of actions for the currently selected item.

## Options

- Configure the top status bar with left, center, and right item slots.
- Set the library font face and font size.
- Choose display mode, mosaic density, list density, item underlines, and list borders.
- Configure the navbar tabs, default tab, labels, icons, and active-tab styling.
- Configure folder covers, folder labels, hidden up-folder rows, and automatic series grouping.
- Configure cover badges, progress indicators, uniform cover ratios, rounded corners, title and author text, and finished-book dimming.
- Configure the scroll bar as a bar, dots, or page number.
- Set a custom Library background image.
- Set and lock the home folder, add extra home folders, and control delete access.

## Navbar

![Navbar](/images/zen_ui/navbar.png)

The Navbar adds a bottom navigation bar to the library. Tabs can open library views, folders, plugin integrations, page controls, menu actions, custom dispatcher actions, or launchable plugin menus.

Navbar settings live under **Zen UI > Library > Navbar**.

### Navbar Options

- Show and arrange up to 7 visible tabs.
- Hide or show icons.
- Add custom tabs with dispatcher actions, plugin menus, icons, and labels.
- Select the default tab used when the navbar opens.
- Configure Books, Home, Manga, and News tab labels or actions.
- Control active-tab styling, top border, label size, and icon size.

### Manga And News Tabs

The Manga and News tabs are flexible launchers. Each one can open a dedicated plugin or jump straight to a folder of your choice.

- **Manga tab** opens [Rakuyomi](https://github.com/tachibana-shin/rakuyomi), another manga reader, or a folder. Set the destination with **Manga tab action**, and use **Manga folder presets** to pin it to the home folder, the last folder, or the current folder.
- **News tab** opens QuickRSS, KOReader's built-in RSS Reader, or a folder. Set the destination with **News tab action**, and use **News folder presets** for the same home, last, or current folder shortcuts.

Folder mode makes either tab a one-tap shortcut to wherever you keep that content, even if you do not use the associated plugin.

### Grouped Views

The Authors, Series, and Tags tabs group your library by metadata instead of by folder. Each grouped view keeps its own display mode, sort field, and sort direction, so you can browse Authors as a list sorted A-Z while Series stays a cover grid sorted by recently read.

- **Authors** groups books by author. Independent display mode and sort/reverse.
- **Series** groups books by series, ordered by series position inside each group. Independent display mode and sort/reverse.
- **Tags** groups books by tag/keyword. Independent display mode plus a global tag sort and direction.

Adjust a grouped view's display and sort from its context menu while that tab is open. Changes are saved per view.

## Setting reference

| Setting | Description |
| --- | --- |
| Status bar > Enable custom status bar | Shows Zen UI's library status bar. |
| Status bar > Custom text | Sets custom status text. Empty text falls back to the device model. |
| Status bar > Show bottom border | Draws a separator below the status bar. |
| Status bar > Bold text | Uses bold text in the status bar. |
| Status bar > Colored status icons | Uses colored status icons when supported. |
| Status bar > Left items | Selects and arranges Wi-Fi, disk space, RAM usage, brightness, battery, time, or custom text for the left slot. |
| Status bar > Center items | Selects and arranges status items for the center slot. |
| Status bar > Right items | Selects and arranges status items for the right slot. |
| Status bar > Separator | Selects dot, bar, dash, bullet, space, small space, none, or a custom separator. |
| Font > Font | Sets the global Zen UI font family, or restores the default font. Applies everywhere except the reader. |
| Font > Font size | Sets the global base text size from 10 to 40. |
| Font > Bold | Renders Zen UI text in bold. |
| Layout > Display mode | Selects classic, mosaic with covers, mosaic with text, detailed list with covers and metadata, detailed list with metadata, or detailed list with covers and filenames. |
| Layout > Items per page | Sets portrait mosaic columns and rows, landscape mosaic columns and rows, and list items per page. |
| Navbar | Opens navbar tab, action, label, icon, default-tab, and styling settings. |
| Navbar > Tabs | Opens the tab arranger. At least 1 tab must remain visible and no more than 7 tabs can be visible. |
| Navbar > Tabs > Built-in tabs | Includes Library, Manga, News, Continue, History, Favorites, Collections, Authors, Series, Home, Tags, To Be Read, Search, Calibre Search, Stats, Exit, Previous page, Next page, and Menu. |
| Navbar > Tabs > Add > Action | Adds a user-defined tab that runs a dispatcher action. |
| Navbar > Tabs > Add > Plugin | Scans for launchable plugin menus and adds the selected plugin menu as a tab. |
| Navbar > Custom tabs > Show in navbar | Shows or hides a custom tab. |
| Navbar > Custom tabs > Action | Selects the dispatcher action run by an action tab. |
| Navbar > Custom tabs > Plugin | Selects the launchable plugin menu run by a plugin tab. |
| Navbar > Custom tabs > Icon | Selects a bundled, KOReader, or user icon for the custom tab. |
| Navbar > Custom tabs > Label | Sets a custom label or leaves the label empty to use the action or plugin title. |
| Navbar > Custom tabs > Delete | Deletes the custom tab and removes it from the order list. |
| Navbar > Default tab | Selects the tab Zen UI treats as the default destination. |
| Navbar > Tabs > Home > Label | Sets the Home tab label. |
| Navbar > Tabs > Books > Label | Sets the Library tab label to Books, Home, Library, or custom text. |
| Navbar > Tabs > Manga | Opens Rakuyomi, another manga reader, or a selected folder. |
| Navbar > Tabs > Manga > Folder presets | Sets the Manga folder to the home folder, last folder, or current folder. |
| Navbar > Tabs > News | Opens QuickRSS, RSS Reader, or a selected folder. |
| Navbar > Tabs > News > Folder presets | Sets the News folder to the home folder, last folder, or current folder. |
| Navbar > Styling > Show top border | Draws a line above the navbar. |
| Navbar > Styling > Labels > Show labels | Shows tab labels. This cannot be disabled when icons are hidden. |
| Navbar > Styling > Labels > Label size | Sets navbar label text size from 10 to 28. |
| Navbar > Styling > Icons > Show icons | Shows tab icons. This cannot be disabled when labels are hidden. |
| Navbar > Styling > Icons > Icon size | Sets navbar icon size from 24 to 48. |
| Navbar > Styling > Active tab > Underline | Adds an underline to the active tab. |
| Navbar > Styling > Active tab > Underline above icon | Places the active underline above the icon. |
| Navbar > Styling > Active tab > Colored | Uses an accent color for the active tab. |
| Navbar > Styling > Active tab > Active tab color | Sets the active tab color from presets or custom RGB values. |
| Layout > Show item underline | Shows or hides the underline between browser items. |
| Layout > Hide list borders | Hides borders in list display modes. |
| Folders > Hide up folder | Hides the parent-folder row. |
| Folders > Group book series into folders | Automatically groups books that share series metadata into generated series folders, sorted by series position. The folders are virtual — they reorganize the view without moving files on disk. |
| Folders > Covers | Selects gallery, first cover image, stack, or folder-name-only folder covers. Override per folder with a custom cover image (see below). |
| Folders > Show spine lines | Shows book-spine lines on stacked folder covers. |
| Folders > Show item count | Shows item counts on folder covers. |
| Folders > Folder name | Controls folder name visibility, opaque background, and center or bottom placement. |
| Covers > Badge size | Sets badge size to compact, normal, large, or extra large. |
| Covers > Badge color | Sets the badge color from presets or custom RGB values. |
| Covers > Show page count | Shows page count badges on covers. |
| Covers > Show series number on covers | Shows series position badges on covers. |
| Covers > Show favorite badge | Shows a favorite badge on favorite books. |
| Covers > Show new banner | Shows a new-book banner on recently added books. |
| Covers > Show KOReader progress bar | Shows KOReader's native progress bar on covers. |
| Covers > Show progress percent on mosaic covers | Shows reading progress percentage on mosaic covers. |
| Covers > Uniform covers | Enables uniform mosaic cover sizing. |
| Covers > Uniform cover ratio | Selects 2:3 standard covers or 3:4 Kindle covers. |
| Covers > Dim finished books | Dims finished books in cover views. |
| Covers > Rounded cover corners | Rounds cover corners in supported cover views. |
| Covers > Show title below cover (mosaic) | Shows title text below mosaic covers. |
| Covers > Show author below cover (mosaic) | Shows author text below mosaic covers. |
| Scroll bar > Style | Selects bar, dots, or page number scrolling. |
| Scroll bar > Page number format | Shows the current page only or page x / y when page-number style is active. |
| Scroll bar > Hold to skip | Sets page-number long-press behavior to skip 10 pages, skip 20 pages, or jump to beginning/end. |
| Background > Enable | Shows the selected background image behind Library surfaces. |
| Background > Image | Opens a file chooser for a JPG or JPEG background image. Hold this row to clear the selected image. |
| Home folder > Set home folder | Opens a folder chooser for the primary library root. |
| Home folder > Lock home folder | Prevents navigation outside of the home folder. |
| Home folder > Additional home folders | Adds or removes extra library roots. |
| Library > Allow delete | Enables or disables delete actions in the library context menu. |

## Fonts

The library **Font** settings set the global Zen UI font. You can change the font family, base size, and bold style, and it applies across the whole interface — library, navbar, home, menus, status bars — everything except the reader.

The reader has its own separate font controls, so you can give the reading view a different font, size, and bold setting from the rest of the UI.

## Custom folder covers

Override the featured image shown on a folder's cover by placing an image file inside that folder. Supported names are `cover.png`, `cover.jpg`, or `cover.jpeg`. To rotate through multiple images, add `cover1`, `cover2`, `cover3`, and `cover4` (with any supported extension). When present, these override the automatic cover generated from the folder's contents.

## Library Background

Use **Background > Enable** and **Background > Image** to add a custom JPG/JPEG background to the Library. Changing or clearing the background refreshes the Library, Home, and Navbar surfaces so the new image is applied without hunting through separate settings.

## Context menu

Tap and hold any book, folder, or the current folder in the Library/Navbar. This opens the context menu. It collects details, file management, read status, sorting, filtering, and display actions for the selected item. Available actions depend on what you held — a book, a folder, or empty space in the current folder.

![Context menu](/images/zen_ui/context_menu.png)

## Display mode & sorting
Tap + Hold on the Navbar (or any empty space) to open the context menu for the folder you are viewing (including your libraries Home folder). From here you can change the folder's display mode, sorting, and status filter on the fly. Each folder remembers its own display and sorting preferences independently, so you can browse one folder as a mosaic sorted by title and another as a detailed list sorted by recently read, and each keeps its settings across sessions.

## Filesystem
If you want to navigate your filesystem (inside or out of Zen mode) you should disable the locking of the home folder. Settings > Library > Home folder > Lock home folder. This will allow you to freely navigate the filesystem on your device.

### Book actions

| Action | Description |
| --- | --- |
| Details | Shows the book's cover, title, author, series, page count, and description in a fullscreen view. |
| Book information | Opens KOReader's full metadata screen for the book. |
| Read status | Sets the book to Unread, Reading, To Be Read, or Finished. Setting Unread also clears reading progress (percent, last page, and position). |
| Add to collection | Adds the book to a chosen collection, including Favorites. |
| Remove from collection | Removes the book from the collection when viewed inside one. |
| Edit > Select | Enters multi-select mode for batch actions on multiple items. |
| Edit > Cut | Cuts the book to the clipboard for moving. |
| Edit > Copy | Copies the book to the clipboard. |
| Edit > Paste | Pastes a clipboard item into the current location. |
| Edit > Refresh | Clears and rebuilds the book's cached metadata and cover. |
| Edit > Delete | Deletes the book after confirmation. Only shown when Allow delete is enabled. |

### Folder actions

| Action | Description |
| --- | --- |
| Details | Shows a folder cover preview and the recursive book count. |
| Rename | Renames the folder. |
| New folder | Creates a new folder inside the current location. |
| Move | Moves the folder to a chosen destination. |
| Sort library by | Sets the library-wide sort: Title, Authors, Series, or Recently read, with a forward or reverse order. Shown on the home folder. |
| Sort folder by | Sets a sort override for this folder only, independent of the library sort. Includes a Clear action to remove the override. |
| Edit > Cut, Copy, Paste | Moves or copies the folder using the clipboard. |
| Edit > Delete | Deletes the folder after confirmation. Only shown when Allow delete is enabled. |

### Current folder actions

Hold on empty space to bring up the Context Menu for the folder you are viewing.

| Action | Description |
| --- | --- |
| Display | Sets the display mode for the current folder: Mosaic, List (detailed), or List (basic). This per-folder override is independent of the global display mode. |
| Filter by status | Filters the current view by read status: All, Unread, Reading, To Be Read, or Finished. Multiple statuses can be combined; selecting all or none clears the filter. The filter persists across sessions. |
| Sort folder by | Sets a per-folder sort override for the current folder. |
