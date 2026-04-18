local M = {}
local initialized = false

local FEATURES = {
    "navbar",
    "status_bar",
    "zen_pagination_bar",
    "browser_folder_cover",
    "browser_hide_underline",
    "browser_hide_up_folder",
}

local PATCH_MODULES = {
    context_menu = "modules/filebrowser/patches/context_menu",
    disable_modal_drag = "modules/filebrowser/patches/disable_modal_drag",
    partial_page_repaint = "modules/filebrowser/patches/partial_page_repaint",
    navbar = "modules/filebrowser/patches/navbar",
    status_bar = "modules/filebrowser/patches/status_bar",
    zen_pagination_bar = "modules/filebrowser/patches/zen_pagination_bar",
    browser_folder_cover = "modules/filebrowser/patches/browser_folder_cover",
    browser_list_item_layout = "modules/filebrowser/patches/browser_list_item_layout",
    browser_hide_underline = "modules/filebrowser/patches/browser_hide_underline",
    browser_hide_up_folder = "modules/filebrowser/patches/browser_hide_up_folder",
    browser_cover_badges = "modules/filebrowser/patches/browser_cover_badges",
    browser_cover_mosaic_uniform = "modules/filebrowser/patches/browser_cover_mosaic_uniform",
    browser_cover_rounded_corners = "modules/filebrowser/patches/browser_cover_rounded_corners",
    browser_show_hidden = "modules/filebrowser/patches/browser_show_hidden",
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

    -- Always apply: disable all MovableContainer drag gestures so no modal
    -- can be dragged around the screen.
    local disable_modal_drag_fn = load_patch("disable_modal_drag")
    if disable_modal_drag_fn then
        run_feature(logger, plugin, "disable_modal_drag", disable_modal_drag_fn)
    end

    -- Always apply: replaces the long-hold context menu with a minimal layout
    local context_menu_fn = load_patch("context_menu")
    if context_menu_fn then
        run_feature(logger, plugin, "context_menu", context_menu_fn)
    end

    -- Always apply: full repaint when landing on a partial page to clear
    -- e-ink ghost images left by the previous page's items.
    local partial_page_repaint_fn = load_patch("partial_page_repaint")
    if partial_page_repaint_fn then
        run_feature(logger, plugin, "partial_page_repaint", partial_page_repaint_fn)
    end

    -- Always apply: custom layout for detailed list mode (title / author / series
    -- on the left, progress % or folder item count on the right).
    local browser_list_item_layout_fn = load_patch("browser_list_item_layout")
    if browser_list_item_layout_fn then
        run_feature(logger, plugin, "browser_list_item_layout", browser_list_item_layout_fn)
    end

    -- Always apply: remove dog-ears, move favorite star to top-left in mosaic,
    -- add optional progress % badge at top-right in mosaic, hide list dog-ear.
    local browser_cover_badges_fn = load_patch("browser_cover_badges")
    if browser_cover_badges_fn then
        run_feature(logger, plugin, "browser_cover_badges", browser_cover_badges_fn)
    end

    -- Always apply: uniform portrait (2:3) sizing for native book covers in
    -- mosaic mode – prevents landscape covers from rendering wider than others.
    local browser_cover_mosaic_uniform_fn = load_patch("browser_cover_mosaic_uniform")
    if browser_cover_mosaic_uniform_fn then
        run_feature(logger, plugin, "browser_cover_mosaic_uniform", browser_cover_mosaic_uniform_fn)
    end

    -- Always apply: rounded corner masks on mosaic covers (book + folder).
    -- The per-paint guard reads the live config, so no restart is needed.
    local browser_cover_rounded_corners_fn = load_patch("browser_cover_rounded_corners")
    if browser_cover_rounded_corners_fn then
        run_feature(logger, plugin, "browser_cover_rounded_corners", browser_cover_rounded_corners_fn)
    end

    -- Always apply: dynamically enforce show_hidden based on home dir boundary
    -- when the developer option is enabled.
    local browser_show_hidden_fn = load_patch("browser_show_hidden")
    if browser_show_hidden_fn then
        run_feature(logger, plugin, "browser_show_hidden", browser_show_hidden_fn)
    end

    -- Ensure the runtime-patches registry exists (zen_settings_apply.lua creates
    -- it, but initialise defensively here in case load order ever changes).
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
                -- Mark as applied so zen_settings_apply.lua's ensure_patch_loaded()
                -- does not re-run the patch (which would double-wrap all hooks and
                -- corrupt the widget tree, causing a crash on the next reinit).
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
