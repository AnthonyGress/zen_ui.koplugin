-- Returns the absolute path to the zenos.koplugin root directory.
-- debug.getinfo may return a relative source path on some KOReader installs
-- (e.g. "plugins/zenos.koplugin/common/plugin_root.lua"), so we resolve it
-- against lfs.currentdir() when the path is not already absolute.
local src = debug.getinfo(1, "S").source or ""
local path = (src:sub(1, 1) == "@") and src:sub(2):match("^(.*)/common/[^/]+$") or nil
if path and path:sub(1, 1) ~= "/" then
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    local cwd = ok and lfs and lfs.currentdir()
    if cwd then path = cwd .. "/" .. path end
end
return path
