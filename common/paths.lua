-- common/paths.lua
-- Shared path utilities: Android symlink normalization and home-dir helpers.
-- All modules that compare or gate on home_dir should use these instead of
-- inline /sdcard → /storage/emulated/0 substitutions.

local M = {}

-- Normalize the Android /sdcard symlink to its canonical /storage/emulated/0
-- form so prefix comparisons are consistent regardless of which path form
-- KOReader or the SQLite cache happens to store.
function M.normPath(p)
    if not p then return p end
    return (p:gsub("^/sdcard/", "/storage/emulated/0/")
             :gsub("^/sdcard$",  "/storage/emulated/0"))
end

-- Returns the user's home dir (library root) from G_reader_settings:
-- normalized via normPath and stripped of any trailing slash.
-- Returns nil when home_dir is not set.
function M.getHomeDir()
    local g = rawget(_G, "G_reader_settings")
    local d = g and g:readSetting("home_dir")
    if d and d ~= "" then
        return M.normPath(d:gsub("/*$", ""))
    end
    return nil
end

function M.isUnsafeFlatViewRoot(path)
    if type(path) ~= "string" then return false end
    local norm = M.normPath(path:gsub("/*$", ""))
    return norm == "/mnt/us"
        or norm == "/mnt/base-us"
        or norm == "/storage/emulated/0"
end

function M.hasUnsafeFlatViewHomeRoot()
    if M.isUnsafeFlatViewRoot(M.getHomeDir()) then return true end

    local zen_cfg = require("config/manager").get()
    local extra = type(zen_cfg) == "table" and zen_cfg.additional_home_dirs
    if type(extra) == "table" then
        for _i, dir in ipairs(extra) do
            if M.isUnsafeFlatViewRoot(dir) then return true end
        end
    end
    return false
end

-- Returns true if path is exactly one of the configured home roots
-- (primary or additional), not merely below one.
function M.isHomeRoot(path)
    if not path then return false end
    local norm = M.normPath(path:gsub("/$", ""))

    local home = M.getHomeDir()
    if home and norm == home then return true end

    local zen_cfg = require("config/manager").get()
    local extra = type(zen_cfg) == "table" and zen_cfg.additional_home_dirs
    if type(extra) == "table" then
        for _i, dir in ipairs(extra) do
            local d = M.normPath(dir:gsub("/*$", ""))
            if d ~= "" and norm == d then return true end
        end
    end
    return false
end

-- Returns true only if path is exactly the primary home_dir (library root).
-- Unlike isHomeRoot, additional home dirs are NOT matched, so they get
-- per-folder sort/display like any other folder.
function M.isPrimaryHomeRoot(path)
    if not path then return false end
    local norm = M.normPath(path:gsub("/$", ""))
    local home = M.getHomeDir()
    return home ~= nil and norm == home
end

-- Returns true if path is at or directly under home_dir,
-- or under any additional home dirs configured in zen_ui_config.
-- Both path and home_dir are normalized before the comparison.
function M.isInHomeDir(path)
    if not path then return false end
    local norm = M.normPath(path:gsub("/$", ""))

    local home = M.getHomeDir()
    if home and (norm == home or norm:sub(1, #home + 1) == home .. "/") then
        return true
    end

    -- Check additional home dirs from zen config.
    local zen_cfg = require("config/manager").get()
    local extra = type(zen_cfg) == "table" and zen_cfg.additional_home_dirs
    if type(extra) == "table" then
        for _i, dir in ipairs(extra) do
            local d = M.normPath(dir:gsub("/*$", ""))
            if d ~= "" and (norm == d or norm:sub(1, #d + 1) == d .. "/") then
                return true
            end
        end
    end

    return false
end

function M.getHomeLockMode()
    local cfg = require("config/manager").get()
    if type(cfg) ~= "table" then
        local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        cfg = plugin and plugin.config
    end
    local browser_cfg = type(cfg) == "table" and cfg.browser_hide_up_folder
    local mode = type(browser_cfg) == "table" and browser_cfg.lock_home_folder
    if mode == "off" or mode == "zen" or mode == "on" then
        return mode
    end
    return "zen"
end

function M.isHomeLocked()
    local mode = M.getHomeLockMode()
    if mode == "on" then return true end
    if mode == "off" then return false end

    local cfg = require("config/manager").get()
    if type(cfg) ~= "table" then
        local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        cfg = plugin and plugin.config
    end
    local features = type(cfg) == "table" and cfg.features
    return type(features) == "table" and features.zen_mode == true
end

return M
