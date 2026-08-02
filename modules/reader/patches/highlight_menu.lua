-- Zen UI: Highlight menu
-- Replaces the default highlight popup with a clean icon row.
-- Patches the text-selection highlight menu with icon buttons.

local function apply()
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    local logger = require("common/zen_logger").new("highlight_menu")

    local _plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")

    logger.dbg("apply() called, _plugin_ref=", tostring(_plugin_ref))
    if _plugin_ref then
        local cfg = _plugin_ref.config
        logger.dbg("config=", tostring(cfg))
        if type(cfg) == "table" and type(cfg.features) == "table" then
            logger.dbg("features.highlight_lookup=",
                tostring(cfg.features.highlight_lookup))
        end
    end

    local function is_enabled()
        local features = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.features
        return type(features) == "table" and features.highlight_lookup == true
    end

    local function allow_unknown()
        local cfg = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.highlight_lookup
        return type(cfg) == "table" and cfg.allow_unknown_items == true
    end

    local function show_wikipedia()
        local cfg = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.highlight_lookup
        return type(cfg) == "table" and cfg.show_wikipedia == true
    end

    local function show_ai_assistant()
        local cfg = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.highlight_lookup
        return type(cfg) == "table" and cfg.show_ai_assistant == true
    end

    -- Find the main button registered by assistant.koplugin (AI helper).
    local function find_ai_button(self, index)
        if not self._highlight_buttons then return nil end
        for key, fn_button in pairs(self._highlight_buttons) do
            local key_name = key:match("^%d+_(.*)$") or key
            if key_name == "ai_assistant" then
                local ok, btn = pcall(fn_button, self, index)
                if ok and type(btn) == "table" and btn.callback then
                    return btn
                end
                return nil
            end
        end
        return nil
    end

    -- Only the keys we explicitly convert to icons; everything else is "other".
    -- ai_assistant is the main button registered by assistant.koplugin.
    local KNOWN_KEYS = {
        highlight = true, search = true, translate = true,
        wikipedia = true, dictionary = true,
        ai_assistant = true,
    }

    -- -------------------------------------------------------------------------
    -- Override: onShowHighlightMenu  (new text-selection popup)
    -- Build the 3-icon row directly instead of mutating existing button specs.
    -- -------------------------------------------------------------------------
    local orig_onShowHighlightMenu = ReaderHighlight.onShowHighlightMenu

    logger.dbg("orig_onShowHighlightMenu=", tostring(orig_onShowHighlightMenu))

    ReaderHighlight.onShowHighlightMenu = function(self, index)
        logger.dbg("onShowHighlightMenu called, is_enabled=",
            tostring(is_enabled()), "selected_text=", tostring(self.selected_text ~= nil))
        if not is_enabled() then
            logger.dbg("disabled, falling back to orig")
            return orig_onShowHighlightMenu(self, index)
        end
        if not self.selected_text then
            logger.dbg("no selected_text, aborting")
            return
        end

        local buttons = {{
            {
                icon = "lookup.highlight",
                enabled = self.hold_pos ~= nil,
                callback = function()
                    self:saveHighlight(true)
                    self:onClose()
                end,
            },
        }}

        if show_wikipedia() then
            table.insert(buttons[1], {
                icon = "lookup.wikipedia",
                callback = function()
                    UIManager:scheduleIn(0.1, function()
                        self:lookupWikipedia()
                    end)
                end,
            })
        end

        table.insert(buttons[1], {
            icon = "lookup.dictionary",
            callback = function()
                self.ui:handleEvent(Event:new("LookupWord", self.selected_text.text, true))
                self:onClose()
            end,
        })
        table.insert(buttons[1], {
            icon = "lookup.translate",
            callback = function()
                self:translate(index)
            end,
        })

        if show_ai_assistant() then
            local ai_btn = find_ai_button(self, index)
            if ai_btn then
                table.insert(buttons[1], {
                    icon = "lookup.ai",
                    enabled = ai_btn.enabled ~= false,
                    callback = ai_btn.callback,
                })
            end
        end

        table.insert(buttons[1], {
            icon = "lookup.search",
            callback = function()
                self:onHighlightSearch()
            end,
        })

        -- Optionally include unrecognised third-party buttons.
        if allow_unknown() and self._highlight_buttons then
            local ffiUtil = require("ffi/util")
            local extra = {}
            for key, fn_button in ffiUtil.orderedPairs(self._highlight_buttons) do
                local key_name = key:match("^%d+_(.*)$") or key
                if not KNOWN_KEYS[key_name] then
                    local ok, btn = pcall(fn_button, self, index)
                    if ok and btn then
                        if not btn.show_in_highlight_dialog_func
                            or btn.show_in_highlight_dialog_func() then
                            table.insert(extra, btn)
                        end
                    end
                end
            end
            -- Split into rows of 2 so they render properly.
            local max_cols = 2
            for i = 1, #extra, max_cols do
                local row = {}
                for j = i, math.min(i + max_cols - 1, #extra) do
                    row[#row + 1] = extra[j]
                end
                table.insert(buttons, row)
            end
        end

        self.highlight_dialog = ButtonDialog:new{
            buttons = buttons,
            anchor = function()
                return self:_getDialogAnchor(self.highlight_dialog, index)
            end,
            tap_close_callback = function()
                if self.hold_pos then
                    self:clear()
                end
            end,
        }
        logger.dbg("showing custom highlight_dialog")
        UIManager:show(self.highlight_dialog, "[ui]")
    end

    logger.dbg("onShowHighlightMenu override installed, new fn=",
        tostring(ReaderHighlight.onShowHighlightMenu))

end

return apply
