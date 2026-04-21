-- Quickstart slideshow page definitions.
-- build_install_pages(ctx): called on first install with { plugin, config }.
-- UPDATE_PAGES: keyed by version string; add a table for each release that
--   has noteworthy changes. Omit a key to silently skip the screen for that
--   release.
-- Each page: { title = string, image = string|nil, description = string }
-- Interactive pages also have: choice_type, choices, on_apply.

local M = {}

local _plugin_root = (function()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) ~= "@" then return "" end
    return src:sub(2):match("^(.*)/common/[^/]+%.lua$") or ""
end)()

local function img(rel)
    return _plugin_root .. "/images/quickstart/" .. rel
end

-- ---------------------------------------------------------------------------
-- ctx = { plugin = <ZenUI plugin>, config = <config table> }
-- ---------------------------------------------------------------------------

function M.build_install_pages(ctx)
    local config = ctx.config
    local plugin = ctx.plugin

    local function save_and_apply(feature)
        plugin:saveConfig()
        local ok, apply_mod = pcall(require, "settings/zen_settings_apply")
        if ok and type(apply_mod.apply_feature_toggle) == "function" then
            apply_mod.apply_feature_toggle(plugin, feature, config.features[feature] == true)
        end
    end

    -- Load screensaver presets once
    local builtin_presets = {}
    pcall(function()
        local bp_mod = require("config/screensaver_presets")
        if type(bp_mod.get) == "function" then
            builtin_presets = bp_mod.get(_plugin_root .. "/icons/")
        end
    end)

    -- Load footer presets once
    local footer_presets
    pcall(function()
        footer_presets = require("modules/reader/patches/reader-footer-presets")
    end)

    -- -----------------------------------------------------------------------
    -- Setting appliers
    -- -----------------------------------------------------------------------

    local function apply_screensaver_preset(preset)
        if type(preset) ~= "table" then return end
        local simple_keys = {
            "screensaver_type",
            "screensaver_img_background",
            "screensaver_document_cover",
            "screensaver_stretch_limit_percentage",
        }
        for _, k in ipairs(simple_keys) do
            if preset[k] ~= nil then
                G_reader_settings:saveSetting(k, preset[k])
            end
        end
        if preset.screensaver_show_message ~= nil then
            if preset.screensaver_show_message then
                G_reader_settings:makeTrue("screensaver_show_message")
            else
                G_reader_settings:makeFalse("screensaver_show_message")
            end
        end
        if preset.screensaver_stretch_images ~= nil then
            if preset.screensaver_stretch_images then
                G_reader_settings:makeTrue("screensaver_stretch_images")
            else
                G_reader_settings:makeFalse("screensaver_stretch_images")
            end
        end
    end

    local function apply_footer_preset(preset)
        if type(preset) ~= "table" then return end
        if preset.footer then
            -- Deep-copy so the shared preset table is never aliased into
            -- G_reader_settings; KOReader's footer module receives readSetting()
            -- and can write defaults back into the same object, which would
            -- silently corrupt the preset and revert font fields on next load.
            local footer
            local ok_u, util_mod = pcall(require, "util")
            if ok_u and type(util_mod.tableDeepCopy) == "function" then
                footer = util_mod.tableDeepCopy(preset.footer)
            else
                footer = {}
                for k, v in pairs(preset.footer) do footer[k] = v end
            end
            footer.text_font_face = "NotoSans-Bold.ttf"
            footer.text_font_bold = false
            G_reader_settings:saveSetting("footer", footer)
        end
        if preset.reader_footer_mode ~= nil then
            G_reader_settings:saveSetting("reader_footer_mode", preset.reader_footer_mode)
        end
        if preset.reader_footer_custom_text then
            G_reader_settings:saveSetting("reader_footer_custom_text", preset.reader_footer_custom_text)
        end
        if preset.reader_footer_custom_text_repetitions then
            G_reader_settings:saveSetting("reader_footer_custom_text_repetitions",
                preset.reader_footer_custom_text_repetitions)
        end
        if preset.zen then
            if type(config.reader_footer) ~= "table" then config.reader_footer = {} end
            if preset.zen.verbose_chapter_time ~= nil then
                config.reader_footer.verbose_chapter_time = preset.zen.verbose_chapter_time
            end
            plugin:saveConfig()
        end
    end

    local function apply_display_mode(mode)
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok_fm and FileManager and FileManager.instance
        if fm and type(fm.onSetDisplayMode) == "function" then
            pcall(fm.onSetDisplayMode, fm, mode)
        else
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if ok_bim then
                pcall(BookInfoManager.saveSetting, BookInfoManager,
                    "filemanager_display_mode", mode)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Choice defaults (read current config so defaults feel intentional)
    -- -----------------------------------------------------------------------

    local show_tabs = (type(config.navbar) == "table" and type(config.navbar.show_tabs) == "table")
        and config.navbar.show_tabs or {}

    local is_12h = true
    local raw_12h = G_reader_settings:readSetting("twelve_hour_clock")
    if raw_12h ~= nil then
        is_12h = raw_12h ~= false
    end

    -- -----------------------------------------------------------------------
    -- Page table
    -- -----------------------------------------------------------------------

    return {
        -- 1. Welcome (static)
        {
            title       = "Welcome to Zen UI",
            icon        = "zen_ui",
            description = "A minimal, clean, and simple interface for your e-reader.\n\nSwipe or tap Next to continue.",
        },

        -- 2. File Browser (static)
        {
            title       = "File Browser",
            image       = img("onboarding/library_covers.png"),
            description = "Cover images as folder thumbnails, clean mosaic and list views,\nhidden clutter, and a streamlined context menu.",
        },
           -- 5. Context Menu (static)

        {
            title       = "Context Menu",
            image       = img("onboarding/context_menu.png"),
            description = "Tap and hold any book or folder in your library to reveal details and options specific to that item.\nEdit items, manage collections, view book information and more.",
        },

        -- 3. Authors & Series (static)
        {
            title       = "Authors & Series",
            image       = img("onboarding/authors.png"),
            description = "Browse your entire library organized by author or series.\nAccess these views anytime from the navigation bar.",
        },

        -- 4. Library View (INTERACTIVE — radio)
        {
            title       = "Library View",
            description = "How would you like to browse your library?",
            choice_type = "radio",
            choices     = {
                { id = "mosaic", text = "Mosaic — large cover thumbnails",     image = img("onboarding/library_covers.png"), checked = true  },
                { id = "list",   text = "List — detailed titles and metadata", image = img("onboarding/library_list.png"),   checked = false },
            },
            on_apply = function(sel)
                if     sel["mosaic"] then apply_display_mode("mosaic_image")
                elseif sel["list"]   then apply_display_mode("list_image_meta")
                end
            end,
        },

        -- 6. Navigation Bar (static)
        {
            title       = "Navigation Bar",
            image       = img("onboarding/navbar.png"),
            description = "A clean, tab-based bar at the bottom of your library.\nConfigurable tabs: Books, Favorites, History, Collections, and more.",
        },

        -- 7. Navbar Tabs (INTERACTIVE — checkbox)
        {
            title          = "Navbar Tabs",
            description    = "Choose which tabs appear in your navigation bar.\nYou can rearrange or adjust these anytime in Settings.",
            choice_type    = "checkbox",
            max_selections = 7,
            choices        = {
                { id = "continue",    text = "Continue",    checked = show_tabs["continue"]    == true },
                { id = "history",     text = "History",     checked = show_tabs["history"]     == true },
                { id = "favorites",   text = "Favorites",   checked = show_tabs["favorites"]   == true },
                { id = "collections", text = "Collections", checked = show_tabs["collections"] == true },
                { id = "authors",     text = "Authors",     checked = show_tabs["authors"]     == true },
                { id = "series",      text = "Series",      checked = show_tabs["series"]      == true },
                { id = "to_be_read",  text = "To Be Read",  checked = show_tabs["to_be_read"]  == true },
                { id = "search",      text = "Search",      checked = show_tabs["search"]      == true },
                { id = "stats",       text = "Stats",       checked = show_tabs["stats"]       == true },
            },
            on_apply = function(sel)
                if type(config.navbar) ~= "table" then config.navbar = {} end
                if type(config.navbar.show_tabs) ~= "table" then config.navbar.show_tabs = {} end
                local tabs = { "continue", "history", "favorites", "collections",
                               "authors", "series", "to_be_read", "search", "stats" }
                for _, id in ipairs(tabs) do
                    config.navbar.show_tabs[id] = sel[id] == true
                end
                save_and_apply("navbar")
            end,
        },

        -- 8. Quick Settings (static)
        {
            title       = "Quick Settings",
            image       = img("onboarding/quicksettings.png"),
            description = "Swipe down to reach brightness, warmth, Wi-Fi, night mode, zen mode and more.\nFully configurable — reorder or hide any button.",
        },

        -- 9. Zen Mode (static)
        {
            title       = "Zen Mode",
            image       = img("onboarding/zen_mode.png"),
            description = "Turn on Zen mode to strip KOReader down to its bare essentials.\nRemoves visual clutter for a focused, distraction-free reading experience. Toggle it off to access anything that was removed.",
        },

        -- 10. Status Bars (static)
        {
            title       = "Status Bars",
            image       = img("onboarding/status_bar.png"),
            description = "Minimal status bar in the library view.\nShow only what you need: time, battery, disk space, etc.",
        },

        -- 11. Sleep Screen (INTERACTIVE — radio)
        {
            title       = "Sleep Screen",
            description = "What should your device show when it goes to sleep?",
            choice_type = "radio",
            choices     = {
                { id = "keep",          text = "Keep existing settings",         checked = true  },
                { id = "cover_black",   text = "Book cover — black background", checked = false },
                { id = "zen_white",     text = "Zen icon — white background",   checked = false },
                { id = "zen_minimal",   text = "Zen icon — minimal background", checked = false },
            },
            on_apply = function(sel)
                if sel["keep"] then return end
                local preset
                if     sel["cover_black"] then preset = builtin_presets[1]
                elseif sel["zen_white"]   then preset = builtin_presets[2]
                elseif sel["zen_minimal"] then preset = builtin_presets[3]
                end
                if preset then
                    apply_screensaver_preset(preset)
                    if type(config.sleep_screen) ~= "table" then
                        config.sleep_screen = { presets = {}, active_preset = nil }
                    end
                    config.sleep_screen.active_preset = preset.name
                    plugin:saveConfig()
                end
            end,
        },

        -- 12. Time Format (INTERACTIVE — radio)
        {
            title       = "Time Format",
            description = "Which time format do you prefer?",
            choice_type = "radio",
            choices     = {
                { id = "12h", text = "12-hour  (3:30 PM)", checked = is_12h      },
                { id = "24h", text = "24-hour  (15:30)",   checked = not is_12h  },
            },
            on_apply = function(sel)
                if sel["12h"] then
                    G_reader_settings:makeTrue("twelve_hour_clock")
                elseif sel["24h"] then
                    G_reader_settings:makeFalse("twelve_hour_clock")
                end
            end,
        },

        -- 13. Reader (static)
        {
            title       = "Reader",
            image       = img("onboarding/reader.png"),
            description = "An unobtrusive clock overlay, disabled accidental bottom menu,\nand clean footer presets for the reading view.",
        },

        -- 15. Reader Progress (INTERACTIVE — radio)
        {
            title       = "Reader Progress",
            description = "Choose a preset for your reading progress bar.",
            choice_type = "radio",
            choices     = {
                { id = "keep",     text = "Keep existing settings",                                                       checked = true  },
                { id = "kindle",   text = "Chapter Time + %",      image = img("onboarding/kindle_like.png"),        checked = false },
                { id = "pages",    text = "Pages and %",      image = img("onboarding/pages_percent.png"),      checked = false },
                { id = "full",     text = "Pages + Time + %", image = img("onboarding/pages_time_percent.png"), checked = false },
                { id = "centered", text = "Centered Pages",   image = img("onboarding/centered_pages.png"),     checked = false },
            },
            on_apply = function(sel)
                if sel["keep"] then return end
                if not footer_presets then return end
                local preset
                if     sel["kindle"]   then preset = footer_presets[1]
                elseif sel["pages"]    then preset = footer_presets[2]
                elseif sel["full"]     then preset = footer_presets[3]
                elseif sel["centered"] then preset = footer_presets[4]
                end
                if preset then apply_footer_preset(preset) end
            end,
        },

                -- 14. Page Browser (static)
        {
            title       = "Page Browser",
            image       = img("onboarding/page_browser.png"),
            description = "Swipe up from the bottom of the reader to open the Page Browser.\nSkip through pages or chapters, browse the table of contents, manage bookmarks, adjust fonts, and search your book.",
        },

        -- 16. Settings & Updates (static)
        {
            title       = "Settings & Updates",
            image       = img("onboarding/zen_ui_settings.png"),
            description = "All settings in one unified tab.\nCheck for and install Zen UI updates directly from your e-reader.",
        },

        -- 17. Finale
        {
            title       = "You're All Set",
            icon        = "zen_ui",
            finale      = true,
            description = "The best interface is the one you forget is there.\nNow go get lost in a good book.",
        },
    }
end

-- ---------------------------------------------------------------------------

M.UPDATE_PAGES = {
    -- Add per-version pages when releasing updates. Example:
    -- ["0.1.0"] = {
    --     { title = "What's New in 0.1.0", image = img("0.1.0/feature.png"), description = "..." },
    -- },
}

return M
