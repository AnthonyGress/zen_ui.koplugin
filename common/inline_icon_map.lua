-- common/inline_icon_map.lua
-- Centralized NerdFont (Symbols Only) inline glyph map.
-- Rendered via SymbolsNerdFont-Regular.ttf (registered as fallback in main.lua).
-- Codepoints verified from existing usages in context_menu.lua, collections.lua,
-- opds.lua, status_bar.lua, etc. Uses \u{} escapes throughout (same as codebase).
--
-- Usage:
--   local icons = require("common/inline_icon_map")
--   text = icons.eye .. "  " .. _("View")

return {
    -- file operations (context_menu.lua)
    delete       = "\u{F0156}",  -- mdi-delete
    rename       = "\u{F0CB6}",  -- mdi-rename-box
    move         = "\u{F01BE}",  -- mdi-folder-move
    copy         = "\u{F018F}",  -- mdi-content-copy
    cut          = "\u{F0190}",  -- mdi-content-cut
    paste        = "\u{F0192}",  -- mdi-content-paste
    save         = "\u{F0193}",  -- mdi-content-save
    select       = "\u{F0489}",  -- mdi-cursor-default-click
    new_folder   = "\u{F0B9D}",  -- mdi-folder-plus
    folder_open  = "\u{F07C}",   -- mdi-folder-open
    connect      = "\u{F0337}",  -- mdi-link-variant

    -- view modes (context_menu.lua)
    view_mosaic  = "\u{F11D9}",  -- mdi-view-module
    view_list    = "\u{F148B}",  -- mdi-view-list
    view_basic   = "\u{F0279}",  -- mdi-format-list-bulleted
    display      = "\u{F06D0}",  -- mdi-monitor

    -- sorting (context_menu.lua)
    sort         = "\u{F04BF}",  -- mdi-sort
    sort_asc     = "\u{F15D}",   -- mdi-sort-ascending
    sort_desc    = "\u{F15E}",   -- mdi-sort-descending
    clear        = "\u{F099B}",  -- mdi-close-circle

    -- favourites (context_menu.lua)
    fav_add      = "\u{F04CE}",  -- mdi-star
    fav_remove   = "\u{F04D2}",  -- mdi-star-outlined

    -- read status (context_menu.lua)
    status       = "\u{F0B64}",  -- mdi-book-open-blank-variant (unread)
    reading      = "\u{F0B63}",  -- mdi-book-open
    tbr          = "\u{F0150}",  -- mdi-clock-outline (to-be-read)
    finished     = "\u{F012C}",  -- mdi-check-circle

    -- metadata sort keys (context_menu.lua / collections.lua)
    title        = "\u{F04BB}",  -- mdi-format-title
    authors      = "\u{F0013}",  -- mdi-account
    series       = "\u{F0436}",  -- mdi-library-books
    history      = "\u{F02DA}",  -- mdi-history
    keywords     = "\u{F12F7}",  -- mdi-tag-multiple

    -- details / info (context_menu.lua / opds.lua)
    details      = "\u{F02FD}",  -- mdi-information
    edit         = "\u{F090C}",  -- mdi-pencil
    label        = "\u{F04F9}",
    icon         = "\u{F02F5}",
    plugin       = "\u{F06A5}",
    action       = "\u{F140B}",

    -- network / sync (opds.lua)
    search       = "\u{F0349}",  -- mdi-magnify
    sync         = "\u{F04E6}",  -- mdi-sync
    download     = "\u{F01DA}",  -- mdi-download
    add          = "\u{F067}",   -- nf-fa-plus
    filter       = "\u{F0233}",  -- mdi-filter-variant
    refresh      = "\u{F0450}",  -- mdi-refresh

    -- status bar (status_bar.lua)
    wifi_on      = "\u{ECA8}",   -- nf-md-wifi
    wifi_off     = "\u{ECA9}",   -- nf-md-wifi-off
    ram          = "\u{EA5A}",   -- nf-cod-chip
    disk         = "\u{F0A0}",   -- mdi-harddisk

    -- screenshot dialog
    wallpaper    = "\u{F05DA}",  -- mdi-wallpaper
    send         = "\u{F048A}",  -- mdi-send

    -- Zen UI settings root
    settings_launcher = "\u{F15FC}",
    settings_quick    = "\u{F0A1A}",
    settings_library  = "\u{F125F}",
    settings_home     = "\u{F02DC}",
    settings_reader   = "\u{F14F7}",
    settings_global   = "\u{F484}",
    settings_about    = "\u{F02FD}",  -- mdi-information

    -- book status actions (book_status.lua)
    restart      = "\u{F0709}",  -- mdi-restart
    next_book    = "\u{f0054}",   -- nf-md-arrow-right

    -- misc
    update       = "\u{F01B}",   -- nf-fa-cloud-download
    check        = "\u{2713}",   -- plain checkmark
    arrow_right  = "\u{25B8}",   -- triangular bullet
    go           = "\u{F124}",   -- nf-fa-location-arrow
    bullet       = "\u{2022}",   -- bullet point
}
