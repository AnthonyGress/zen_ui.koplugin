local M = {}
local initialized = false

local PATCH_MODULES = {
    opening_banner = "modules/reader/patches/opening_banner",
    book_status = "modules/reader/patches/book_status",
    reader_clock = "modules/reader/patches/reader_clock",
    screensaver_cover = "modules/reader/patches/screensaver_cover",
    reader_footer_time_format = "modules/reader/patches/reader_footer_time_format",
}

local function is_feature_enabled(plugin, key)
    return plugin
        and type(plugin.config) == "table"
        and type(plugin.config.features) == "table"
        and plugin.config.features[key] == true
end

local function run_feature(logger, plugin, feature, fn)
    local prev_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    _G.__ZEN_UI_PLUGIN = plugin
    local ok, err = pcall(fn)
    _G.__ZEN_UI_PLUGIN = prev_plugin
    if not ok and logger then
        logger.warn("zen-ui: grouped reader feature failed", feature, err)
    end
    return ok
end

local function load_patch(feature)
    local module_name = PATCH_MODULES[feature]
    if not module_name then
        return nil
    end
    local ok, patch_fn = pcall(require, module_name)
    if not ok or type(patch_fn) ~= "function" then
        return nil
    end
    return patch_fn
end

function M.init(logger, plugin)
    if initialized then
        return true
    end

    -- Always apply: replaces the "Opening file..." popup with a bottom banner
    local opening_banner_fn = load_patch("opening_banner")
    if opening_banner_fn then
        run_feature(logger, plugin, "opening_banner", opening_banner_fn)
    end

    -- Always apply: custom Book Status layout + sets native end_document_action
    local book_status_fn = load_patch("book_status")
    if book_status_fn then
        run_feature(logger, plugin, "book_status", book_status_fn)
    end

    -- Always apply: replace koreader.png fallback screensaver with zen_ui.svg
    local screensaver_cover_fn = load_patch("screensaver_cover")
    if screensaver_cover_fn then
        run_feature(logger, plugin, "screensaver_cover", screensaver_cover_fn)
    end

    -- Always apply: format time_to_chapter in Kindle style ("X mins left in chapter")
    local reader_footer_time_format_fn = load_patch("reader_footer_time_format")
    if reader_footer_time_format_fn then
        run_feature(logger, plugin, "reader_footer_time_format", reader_footer_time_format_fn)
    end

    if is_feature_enabled(plugin, "reader_clock") then
        local fn = load_patch("reader_clock")
        if fn then
            run_feature(logger, plugin, "reader_clock", fn)
        elseif logger then
            logger.warn("zen-ui: reader patch module missing", "reader_clock")
        end
    end

    initialized = true
    return true
end

return M
