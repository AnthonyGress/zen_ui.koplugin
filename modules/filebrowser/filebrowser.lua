local M = {}
local Rakuyomi = require("common/rakuyomi")
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
    add_sort_title_natural = "modules/filebrowser/patches/add_sort_title_natural",
    coverbrowser_check = "modules/filebrowser/patches/coverbrowser_check",
    coverbrowser_subprocess_compat = "modules/filebrowser/patches/coverbrowser_subprocess_compat",
    context_menu = "modules/filebrowser/patches/context_menu",
    browser_flat_view_compat = "modules/filebrowser/patches/browser_flat_view_compat",
    browser_folder_sort = "modules/filebrowser/patches/browser_folder_sort",
    disable_modal_drag = "modules/filebrowser/patches/disable_modal_drag",
    menu_single_page_scroll_guard = "modules/filebrowser/patches/menu_single_page_scroll_guard",
    partial_page_repaint = "modules/filebrowser/patches/partial_page_repaint",
    rakuyomi = "modules/filebrowser/patches/rakuyomi",
    navbar = "modules/filebrowser/patches/navbar",
    status_bar = "modules/filebrowser/patches/status_bar",
    zen_scroll_bar = "common/ui/zen_scroll_bar",
    browser_folder_cover = "modules/filebrowser/patches/browser_folder_cover",
    browser_list_item_layout = "modules/filebrowser/patches/browser_list_item_layout",
    browser_hide_underline = "modules/filebrowser/patches/browser_hide_underline",
    browser_hide_up_folder = "modules/filebrowser/patches/browser_hide_up_folder",
    favorites = "modules/filebrowser/patches/favorites",
    collections = "modules/filebrowser/patches/collections",
    history = "modules/filebrowser/patches/history",
    browser_cover_badges = "modules/filebrowser/patches/browser_cover_badges",
    browser_cover_mosaic_uniform = "modules/filebrowser/patches/browser_cover_mosaic_uniform",
    mosaic_title_strip = "modules/filebrowser/patches/mosaic_title_strip",
    browser_cover_rounded_corners = "modules/filebrowser/patches/browser_cover_rounded_corners",
    browser_show_hidden = "modules/filebrowser/patches/browser_show_hidden",
    browser_page_count = "modules/filebrowser/patches/browser_page_count",
    browser_series_badge = "modules/filebrowser/patches/browser_series_badge",
    automatic_series_grouping = "modules/filebrowser/patches/automatic_series_grouping",
    browser_display_mode_by_path = "modules/filebrowser/patches/browser_display_mode_by_path",
    search = "modules/filebrowser/patches/search",
    group_view = "modules/filebrowser/patches/group_view",
    home_page = "modules/filebrowser/patches/home_page",
    status_on_open = "modules/filebrowser/patches/status_on_open",
    library_background = "modules/filebrowser/patches/library_background",
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
        logger.warn("grouped filebrowser feature failed", feature, err)
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

    local add_sort_title_natural_fn = load_patch("add_sort_title_natural")
    if add_sort_title_natural_fn then
        run_feature(logger, plugin, "add_sort_title_natural", add_sort_title_natural_fn)
    end

    local coverbrowser_check_fn = load_patch("coverbrowser_check")
    if coverbrowser_check_fn then
        run_feature(logger, plugin, "coverbrowser_check", coverbrowser_check_fn)
    end

    local coverbrowser_subprocess_compat_fn = load_patch("coverbrowser_subprocess_compat")
    if coverbrowser_subprocess_compat_fn then
        run_feature(logger, plugin, "coverbrowser_subprocess_compat", coverbrowser_subprocess_compat_fn)
    end

    local disable_modal_drag_fn = load_patch("disable_modal_drag")
    if disable_modal_drag_fn then
        run_feature(logger, plugin, "disable_modal_drag", disable_modal_drag_fn)
    end

    local browser_flat_view_compat_fn = load_patch("browser_flat_view_compat")
    if browser_flat_view_compat_fn then
        run_feature(logger, plugin, "browser_flat_view_compat", browser_flat_view_compat_fn)
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

    if is_feature_enabled(plugin, "browser_cover_mosaic_uniform") then
        local browser_cover_mosaic_uniform_fn = load_patch("browser_cover_mosaic_uniform")
        if browser_cover_mosaic_uniform_fn then
            run_feature(logger, plugin, "browser_cover_mosaic_uniform", browser_cover_mosaic_uniform_fn)
            -- Items already visible when the patch runs won't reflect uniform sizing.
            -- Defer a rebuild so they are reconstructed with the patched MosaicMenuItem.
            local ok_um, UIManager = pcall(require, "ui/uimanager")
            if ok_um then
                UIManager:nextTick(function()
                    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
                    local fm = ok_fm and FileManager and FileManager.instance
                    local fc = fm and fm.file_chooser
                    if fc and fc.display_mode_type == "mosaic" then
                        fc:updateItems(1, true)
                    end
                end)
            end
        end
    end

    -- Must run after browser_cover_mosaic_uniform so we wrap its already-patched init.
    local mosaic_title_strip_fn = load_patch("mosaic_title_strip")
    if mosaic_title_strip_fn then
        run_feature(logger, plugin, "mosaic_title_strip", mosaic_title_strip_fn)
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

    local browser_page_count_fn = load_patch("browser_page_count")
    if browser_page_count_fn then
        run_feature(logger, plugin, "browser_page_count", browser_page_count_fn)
    end

    local browser_series_badge_fn = load_patch("browser_series_badge")
    if browser_series_badge_fn then
        run_feature(logger, plugin, "browser_series_badge", browser_series_badge_fn)
    end

    local automatic_series_grouping_fn = load_patch("automatic_series_grouping")
    if automatic_series_grouping_fn then
        run_feature(logger, plugin, "automatic_series_grouping", automatic_series_grouping_fn)
    end

    local group_view_fn = load_patch("group_view")
    if group_view_fn then
        run_feature(logger, plugin, "group_view", group_view_fn)
    end

    local home_page_fn = load_patch("home_page")
    if home_page_fn then
        run_feature(logger, plugin, "home_page", home_page_fn)
    end

    local status_on_open_fn = load_patch("status_on_open")
    if status_on_open_fn then
        run_feature(logger, plugin, "status_on_open", status_on_open_fn)
    end

    -- Always apply: paints library background image (self-disables when path empty).
    local library_background_fn = load_patch("library_background")
    if library_background_fn then
        run_feature(logger, plugin, "library_background", library_background_fn)
    end

    local runtime_patches = rawget(_G, "__ZEN_UI_RUNTIME_PATCHES")
    if type(runtime_patches) ~= "table" then
        runtime_patches = {}
        _G.__ZEN_UI_RUNTIME_PATCHES = runtime_patches
    end

    local rakuyomi_fn = Rakuyomi.is_available() and load_patch("rakuyomi") or nil
    if rakuyomi_fn then
        local ok = run_feature(logger, plugin, "rakuyomi", rakuyomi_fn)
        if ok then
            runtime_patches["rakuyomi"] = true
        end
    end

    local zen_scroll_bar_fn = load_patch("zen_scroll_bar")
    if zen_scroll_bar_fn then
        run_feature(logger, plugin, "zen_scroll_bar", zen_scroll_bar_fn)
    end

    for _i, feature in ipairs(FEATURES) do
        if is_feature_enabled(plugin, feature) then
            local fn, err = load_patch(feature)
            if fn then
                local ok = run_feature(logger, plugin, feature, fn)
                -- Prevent double-wrap on reinit.
                if ok then
                    runtime_patches[feature] = true
                end
            elseif logger then
                logger.warn("grouped filebrowser patch load failed", feature, err)
            end
        end
    end

    initialized = true
    return true
end

return M
