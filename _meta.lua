local source = (debug.getinfo(1, "S").source or ""):gsub("\\", "/")
local plugin_dir = source:match("([^/]+%.koplugin)/_meta%.lua$")

return {
    name = plugin_dir == "zen_ui.koplugin" and "zen_ui" or "zenos",
    version = "3.1.0",
    fullname = "ZenOS",
    description = "A clean, minimal UI for KOReader",
}
