-- Zen UI: Register all plugin icons into KOReader's icon cache at startup.
-- Copies SVGs to the user icons dir so they resolve on cold starts too.

local utils = require("common/utils")

local _plugin_root = require("common/plugin_root")

if _plugin_root then
    utils.registerPluginIcons(_plugin_root .. "/icons/", {
        -- App / settings UI
        ["zen_settings"]        = "zen_ui.svg",
        ["quicksettings"]       = "quicksettings.svg",
        ["zen_ui"]              = "zen_ui.svg",
        ["zen_ui_light"]        = "zen_ui_light.svg",
        ["zen_ui_update"]       = "zen_ui_update.svg",
        ["library"]             = "library.svg",
        ["app_launcher"]        = "app_launcher.svg",
        ["lightning"]           = "lightning.svg",
        ["folder_open"]         = "folder_open.svg",
        -- Highlight / lookup popup (shared by highlight_menu + dict_quick_lookup)
        ["lookup.highlight"]    = "lookup_highlight.svg",
        ["lookup.ai"]           = "lookup_ai.svg",
        ["lookup.vocab"]        = "lookup_vocab.svg",
        ["lookup.vocab_remove"] = "lookup_vocab_remove.svg",
        ["lookup.dictionary"]   = "lookup_dictionary.svg",
        ["lookup.search"]       = "lookup_search.svg",
        ["lookup.translate"]    = "lookup_translate.svg",
        ["lookup.wikipedia"]    = "lookup_wikipedia.svg",
    }, true)
end
