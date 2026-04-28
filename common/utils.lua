local M = {}

function M.deepcopy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for k, v in pairs(value) do
        result[M.deepcopy(k)] = M.deepcopy(v)
    end
    return result
end

function M.deepmerge(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return src
    end

    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            M.deepmerge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = M.deepcopy(v)
        end
    end

    return dst
end

function M.set_at_path(tbl, path, value)
    local node = tbl
    for i = 1, #path - 1 do
        local key = path[i]
        if type(node[key]) ~= "table" then
            node[key] = {}
        end
        node = node[key]
    end
    node[path[#path]] = value
end

--- Resolve an icon name to an absolute file path (checks .svg then .png).
--- @param icons_dir string  absolute path ending with "/"
--- @param name      string  icon name without extension
--- @return          string|nil
function M.resolveLocalIcon(icons_dir, name)
    if not icons_dir or not name then return nil end
    local lfs = require("libs/libkoreader-lfs")
    for _, ext in ipairs({ ".svg", ".png" }) do
        local p = icons_dir .. name .. ext
        if lfs.attributes(p, "mode") == "file" then return p end
    end
    return nil
end

--- Absolute path (with trailing slash) to KOReader's user icons directory.
function M.getUserIconsDir()
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage then return nil end
    return DataStorage:getDataDir() .. "/icons/"
end

local _custom_icons_enabled
function M.isCustomIconsEnabled()
    if _custom_icons_enabled ~= nil then return _custom_icons_enabled end
    _custom_icons_enabled = false
    pcall(function()
        local ConfigManager = require("config/manager")
        local cfg = ConfigManager.load()
        if cfg and cfg.features and cfg.features.custom_icons_enabled == true then
            _custom_icons_enabled = true
        end
    end)
    return _custom_icons_enabled
end

--- Resolve an icon honouring the custom-icons toggle: user dir first when enabled,
--- falls back to the plugin's bundled icons dir.
--- @param plugin_icons_dir string  absolute path ending with "/"
--- @param name             string  icon name without extension
--- @return                 string|nil
function M.resolveIcon(plugin_icons_dir, name)
    if not plugin_icons_dir or not name then return nil end
    if M.isCustomIconsEnabled() then
        local user_dir = M.getUserIconsDir()
        if user_dir then
            local p = M.resolveLocalIcon(user_dir, name)
            if p then return p end
        end
    end
    return M.resolveLocalIcon(plugin_icons_dir, name)
end

--- Register plugin icons so short names resolve via IconWidget at runtime.
--- Optionally copies files to the user icons dir for cold-start resolution.
---
--- @param icons_dir        string   absolute path to the plugin icons dir, ending with "/"
--- @param icons            table    { [icon_name] = "filename.ext", ... }
--- @param copy_to_user_dir boolean  also copy files to DataStorage icons dir
function M.registerPluginIcons(icons_dir, icons, copy_to_user_dir)
    if not icons_dir or type(icons) ~= "table" then return end
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        local user_icons_dir = M.isCustomIconsEnabled() and M.getUserIconsDir() or nil

        if copy_to_user_dir then
            pcall(function()
                local DataStorage = require("datastorage")
                local ffiutil = require("ffi/util")
                local user_icons_dir = DataStorage:getDataDir() .. "/icons"
                if lfs.attributes(user_icons_dir, "mode") ~= "directory" then
                    lfs.mkdir(user_icons_dir)
                end
                for name, filename in pairs(icons) do
                    -- Use icon short-name as dest so ICONS_DIRS lookup finds it by name
                    local ext = filename:match("%.[^%.]+$") or ".svg"
                    local dst = user_icons_dir .. "/" .. name .. ext
                    if lfs.attributes(dst, "mode") ~= "file" then
                        local src = icons_dir .. filename
                        if lfs.attributes(src, "mode") == "file" then
                            ffiutil.copyFile(src, dst)
                        end
                    end
                end
            end)
        end

        -- Inject into IconWidget's runtime upvalue caches
        local iw = require("ui/widget/iconwidget")
        local iw_init = rawget(iw, "init")
        if type(iw_init) ~= "function" then return end
        local icons_path, icons_dirs
        for i = 1, 64 do
            local uname, uval = debug.getupvalue(iw_init, i)
            if uname == nil then break end
            if uname == "ICONS_PATH" and type(uval) == "table" then
                icons_path = uval
            elseif uname == "ICONS_DIRS" and type(uval) == "table" then
                icons_dirs = uval
            end
            if icons_path and icons_dirs then break end
        end
        -- Ensure user icons dir is in ICONS_DIRS (may have been absent at widget load time)
        if icons_dirs and copy_to_user_dir then
            pcall(function()
                local DataStorage = require("datastorage")
                local user_dir = DataStorage:getDataDir() .. "/icons"
                local found = false
                for _, d in ipairs(icons_dirs) do
                    if d == user_dir then found = true; break end
                end
                if not found then table.insert(icons_dirs, 1, user_dir) end
            end)
        end
        if not icons_path then return end
        for name, filename in pairs(icons) do
            if not icons_path[name] then
                local user_p = user_icons_dir and M.resolveLocalIcon(user_icons_dir, name) or nil
                if user_p then
                    icons_path[name] = user_p
                else
                    local p = icons_dir .. filename
                    if lfs.attributes(p, "mode") == "file" then
                        icons_path[name] = p
                    end
                end
            end
        end
    end)
end

--- Override built-in KOReader icons by name at runtime (does not modify disk).
--- @param overrides table  map of icon_name → absolute replacement path
function M.overrideIcons(overrides)
    local lfs = require("libs/libkoreader-lfs")
    local user_icons_dir = M.isCustomIconsEnabled() and M.getUserIconsDir() or nil
    local valid = {}
    for name, path in pairs(overrides) do
        local user_p = user_icons_dir and M.resolveLocalIcon(user_icons_dir, name) or nil
        local chosen = user_p or path
        if lfs.attributes(chosen, "mode") == "file" then
            valid[name] = chosen
        end
    end
    if not next(valid) then return end

    local iw = require("ui/widget/iconwidget")
    local orig_init = iw.init
    function iw:init()
        orig_init(self)
        if valid[self.icon] then
            self.file = valid[self.icon]
        end
    end
end

-- Module-level cache so pgettext is resolved only once (lazy, safe for early require).
local _C_cache
local function _C(ctx, msgid)
    if not _C_cache then
        local _cg = rawget(_G, "C_")
        if type(_cg) == "function" then
            _C_cache = _cg
        else
            local ok_gt, gt = pcall(require, "gettext")
            if ok_gt and gt and type(gt.pgettext) == "function" then
                _C_cache = function(c, m) return gt.pgettext(c, m) end
            else
                _C_cache = function(_, m) return m end
            end
        end
    end
    return _C_cache(ctx, msgid)
end

--- Localised page-count label (abbreviated or full word form).
--- @param pages number
--- @param long  boolean|nil  true for full form ("pages"), false for short ("p.")
--- @return string
function M.formatPageCount(pages, long)
    local ctx = long and "page_count_long" or "page_count"
    local msgid = long and "pages" or "p."
    return tostring(pages) .. "\u{00A0}" .. _C(ctx, msgid)
end

-- Close all UIManager window-stack entries above `anchor_widget`.
-- Collects first to avoid mutating the stack during iteration.
function M.closeWidgetsAbove(anchor_widget)
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack
    if not stack or not anchor_widget then return end
    local to_close = {}
    for i = #stack, 1, -1 do
        local entry = stack[i]
        if not entry or entry.widget == anchor_widget then break end
        table.insert(to_close, entry.widget)
    end
    for _, w in ipairs(to_close) do UIManager:close(w) end
end

return M
