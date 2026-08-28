local function configured_name(ReaderHighlight, color_name)
    local plugin = rawget(ReaderHighlight, "_zen_ui_highlight_names_plugin")
    local lookup = plugin and plugin.config and plugin.config.highlight_lookup
    local names = type(lookup) == "table" and lookup.color_names
    local name = type(names) == "table" and names[color_name]
    if type(name) == "string" and name:match("%S") then return name end
end

local function apply(plugin)
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    ReaderHighlight._zen_ui_highlight_names_plugin =
        plugin or rawget(_G, "__ZEN_UI_PLUGIN")

    local original_names = rawget(ReaderHighlight, "_zen_ui_highlight_original_names")
    if type(original_names) ~= "table" then
        original_names = {}
        ReaderHighlight._zen_ui_highlight_original_names = original_names
    end

    for _i, color in ipairs(ReaderHighlight.highlight_colors or {}) do
        local color_name = color[2]
        if original_names[color_name] == nil then original_names[color_name] = color[1] end
        color[1] = configured_name(ReaderHighlight, color_name) or original_names[color_name]
    end

    if ReaderHighlight._zen_ui_highlight_names_patched then return end
    ReaderHighlight._zen_ui_highlight_names_patched = true

    local orig_get_string = ReaderHighlight.getHighlightColorString
    if type(orig_get_string) == "function" then
        ReaderHighlight.getHighlightColorString = function(self, color_name, force_orig, ...)
            if force_orig and original_names[color_name] then
                return original_names[color_name]
            end
            if not force_orig then
                local name = configured_name(ReaderHighlight, color_name)
                if name then return name end
            end
            return orig_get_string(self, color_name, force_orig, ...)
        end
    end

    local orig_get_list = ReaderHighlight.getHighlightColorList
    if type(orig_get_list) == "function" then
        ReaderHighlight.getHighlightColorList = function(self, ...)
            local colors = orig_get_list(self, ...)
            for _i, color in ipairs(colors or {}) do
                color[1] = configured_name(ReaderHighlight, color[2]) or color[1]
            end
            return colors
        end
    end
end

return apply
