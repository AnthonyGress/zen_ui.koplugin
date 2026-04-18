local M = {}
local initialized = false

local FEATURES = {
    "navbar",
    "status_bar",
    "browser_folder_cover",
    "browser_hide_underline",
    "browser_hide_up_folder",
    "favorites",
    "collections",
    "history",
    "search",
    "partial_page_repaint",
}

local PATCH_MODULES = {
    context_menu = "modules/filebrowser/patches/context_menu",
    browser_folder_sort = "modules/filebrowser/patches/browser_folder_sort",
    disable_modal_drag = "modules/filebrowser/patches/disable_modal_drag",
    menu_single_page_scroll_guard = "modules/filebrowser/patches/menu_single_page_scroll_guard",
    partial_page_repaint = "modules/filebrowser/patches/partial_page_repaint",
    navbar = "modules/filebrowser/patches/navbar",
    status_bar = "modules/filebrowser/patches/status_bar",
    zen_scroll_bar = "common/zen_scroll_bar",
    browser_folder_cover = "modules/filebrowser/patches/browser_folder_cover",
    browser_list_item_layout = "modules/filebrowser/patches/browser_list_item_layout",
    browser_hide_underline = "modules/filebrowser/patches/browser_hide_underline",
    browser_hide_up_folder = "modules/filebrowser/patches/browser_hide_up_folder",
    favorites = "modules/filebrowser/patches/favorites",
    collections = "modules/filebrowser/patches/collections",
    history = "modules/filebrowser/patches/history",
    browser_cover_badges = "modules/filebrowser/patches/browser_cover_badges",
    browser_cover_mosaic_uniform = "modules/filebrowser/patches/browser_cover_mosaic_uniform",
    browser_cover_rounded_corners = "modules/filebrowser/patches/browser_cover_rounded_corners",
    browser_show_hidden = "modules/filebrowser/patches/browser_show_hidden",
    browser_preload_bookinfo = "modules/filebrowser/patches/browser_preload_bookinfo",
    browser_page_count = "modules/filebrowser/patches/browser_page_count",
    browser_series_badge = "modules/filebrowser/patches/browser_series_badge",
    browser_display_mode_by_path = "modules/filebrowser/patches/browser_display_mode_by_path",
    search = "modules/filebrowser/patches/search",
    authors_series = "modules/filebrowser/patches/authors_series",
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
        logger.warn("zen-ui: grouped filebrowser feature failed", feature, err)
    end
    return ok
end

local function load_patch(feature)
    local module_name = PATCH_MODULES[feature]
    if not module_name then
        return nil
    end

    local ok, patch_or_err = pcall(require, module_name)
    if not ok then
        return nil, patch_or_err
    end

    if type(patch_or_err) ~= "function" then
        return nil, "patch module did not return a function"
    end

    return patch_or_err
end

function M.init(logger, plugin)
    if initialized then
        return true
    end

    local disable_modal_drag_fn = load_patch("disable_modal_drag")
    if disable_modal_drag_fn then
        run_feature(logger, plugin, "disable_modal_drag", disable_modal_drag_fn)
    end

    local menu_single_page_scroll_guard_fn = load_patch("menu_single_page_scroll_guard")
    if menu_single_page_scroll_guard_fn then
        run_feature(logger, plugin, "menu_single_page_scroll_guard", menu_single_page_scroll_guard_fn)
    end

    -- Must run before context_menu so __ZEN_FOLDER_SORT is available.
    local browser_folder_sort_fn = load_patch("browser_folder_sort")
    if browser_folder_sort_fn then
        run_feature(logger, plugin, "browser_folder_sort", browser_folder_sort_fn)
    end

    local context_menu_fn = load_patch("context_menu")
    if context_menu_fn then
        run_feature(logger, plugin, "context_menu", context_menu_fn)
    end

    local browser_list_item_layout_fn = load_patch("browser_list_item_layout")
    if browser_list_item_layout_fn then
        run_feature(logger, plugin, "browser_list_item_layout", browser_list_item_layout_fn)
    end

    local browser_display_mode_by_path_fn = load_patch("browser_display_mode_by_path")
    if browser_display_mode_by_path_fn then
        run_feature(logger, plugin, "browser_display_mode_by_path", browser_display_mode_by_path_fn)
    end

    local browser_cover_badges_fn = load_patch("browser_cover_badges")
    if browser_cover_badges_fn then
        run_feature(logger, plugin, "browser_cover_badges", browser_cover_badges_fn)
    end

    local browser_cover_mosaic_uniform_fn = load_patch("browser_cover_mosaic_uniform")
    if browser_cover_mosaic_uniform_fn then
        run_feature(logger, plugin, "browser_cover_mosaic_uniform", browser_cover_mosaic_uniform_fn)
    end

    -- Per-paint guard reads live config; no restart needed to toggle.
    local browser_cover_rounded_corners_fn = load_patch("browser_cover_rounded_corners")
    if browser_cover_rounded_corners_fn then
        run_feature(logger, plugin, "browser_cover_rounded_corners", browser_cover_rounded_corners_fn)
    end

    local browser_show_hidden_fn = load_patch("browser_show_hidden")
    if browser_show_hidden_fn then
        run_feature(logger, plugin, "browser_show_hidden", browser_show_hidden_fn)
    end

    -- Requires CoverBrowser plugin.
    local _preload_cfg = type(plugin.config.browser_preload_bookinfo) == "table"
        and plugin.config.browser_preload_bookinfo or {}
    if _preload_cfg.preload_bookinfo ~= false then
        local browser_preload_bookinfo_fn = load_patch("browser_preload_bookinfo")
        if browser_preload_bookinfo_fn then
            run_feature(logger, plugin, "browser_preload_bookinfo", browser_preload_bookinfo_fn)
        end
    end

    local browser_page_count_fn = load_patch("browser_page_count")
    if browser_page_count_fn then
        run_feature(logger, plugin, "browser_page_count", browser_page_count_fn)
    end

    local browser_series_badge_fn = load_patch("browser_series_badge")
    if browser_series_badge_fn then
        run_feature(logger, plugin, "browser_series_badge", browser_series_badge_fn)
    end

    local authors_series_fn = load_patch("authors_series")
    if authors_series_fn then
        run_feature(logger, plugin, "authors_series", authors_series_fn)
    end

    local zen_scroll_bar_fn = load_patch("zen_scroll_bar")
    if zen_scroll_bar_fn then
        run_feature(logger, plugin, "zen_scroll_bar", zen_scroll_bar_fn)
    end

    local runtime_patches = rawget(_G, "__ZEN_UI_RUNTIME_PATCHES")
    if type(runtime_patches) ~= "table" then
        runtime_patches = {}
        _G.__ZEN_UI_RUNTIME_PATCHES = runtime_patches
    end

    for _, feature in ipairs(FEATURES) do
        if is_feature_enabled(plugin, feature) then
            local fn, err = load_patch(feature)
            if fn then
                local ok = run_feature(logger, plugin, feature, fn)
                -- Prevent double-wrap on reinit.
                if ok then
                    runtime_patches[feature] = true
                end
            elseif logger then
                logger.warn("zen-ui: grouped filebrowser patch load failed", feature, err)
            end
        end
    end

    initialized = true
    return true
end

return M
