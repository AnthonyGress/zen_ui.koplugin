local plugin_root = require("common/plugin_root") or ""

local M = {}

M.BUNDLED_DEFAULT = "fonts/hyperreadable/Hyperreadable-Regular.ttf"

local plugin_dirs = {
    ["zen_ui.koplugin"] = true,
    ["zenos.koplugin"] = true,
}
local current_plugin_dir = plugin_root:match("([^/]+)$")
if current_plugin_dir then plugin_dirs[current_plugin_dir] = true end

function M.resolve(font_face)
    if type(font_face) == "string"
            and font_face:sub(1, 6) == "fonts/"
            and plugin_root ~= "" then
        return plugin_root .. "/" .. font_face
    end
    return font_face
end

function M.toConfig(font_face)
    if type(font_face) ~= "string" or font_face == "" then return font_face end
    if font_face:sub(1, 6) == "fonts/" then return font_face end

    local root_prefix = plugin_root ~= "" and plugin_root .. "/" or nil
    if root_prefix and font_face:sub(1, #root_prefix) == root_prefix then
        local relative = font_face:sub(#root_prefix + 1)
        if relative:sub(1, 6) == "fonts/" then return relative end
    end

    for plugin_dir in pairs(plugin_dirs) do
        local escaped_dir = plugin_dir:gsub("([^%w])", "%%%1")
        local relative = font_face:match("/" .. escaped_dir .. "/(fonts/.+)$")
        if relative then return relative end
    end
    return font_face
end

return M
