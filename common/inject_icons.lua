-- Zen UI: Register all plugin icons into KOReader's icon cache at startup.
-- Copies SVGs to the user icons dir so they resolve on cold starts too.

local utils = require("common/utils")

local src = debug.getinfo(1, "S").source or ""
-- File is in common/, so strip two path components to reach the plugin root.
local _plugin_root = (src:sub(1, 1) == "@") and src:sub(2):match("^(.*)/common/[^/]+$") or nil

if _plugin_root then
    utils.registerPluginIcons(_plugin_root .. "/icons/", {
        -- App / settings UI
        ["zen_settings"]        = "settings.svg",
        ["quicksettings"]       = "quicksettings.svg",
        ["zen_ui"]              = "zen_ui.svg",
        ["zen_ui_light"]        = "zen_ui_light.svg",
        ["zen_ui_update"]       = "zen_ui_update.svg",
        ["library"]             = "library.svg",
        -- Highlight / lookup popup (shared by highlight_menu + dict_quick_lookup)
        ["lookup.highlight"]    = "lookup_highlight.svg",
        ["lookup.vocab"]        = "lookup_vocab.svg",
        ["lookup.vocab_remove"] = "lookup_vocab_remove.svg",
        ["lookup.dictionary"]   = "lookup_dictionary.svg",
        ["lookup.search"]       = "lookup_search.svg",
        ["lookup.translate"]    = "lookup_translate.svg",
        ["lookup.wikipedia"]    = "lookup_wikipedia.svg",
    }, true)
end
