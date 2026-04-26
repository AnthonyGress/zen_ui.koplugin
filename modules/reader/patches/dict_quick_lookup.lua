-- Zen UI: Icon-only DictQuickLookup buttons
-- Replaces the dictionary popup's text button row with a compact icon row.
-- Hooks via DictButtonsReady event on ReaderHighlight (fired by DictQuickLookup).
-- When "show other items" is enabled, unknown buttons are preserved as a text row.

local function apply()
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local DictQuickLookup = require("ui/widget/dictquicklookup")
    local Translator = require("ui/translator")
    local Event = require("ui/event")
    local UIManager = require("ui/uimanager")
    local logger = require("logger")

    local _plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local features = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.features
        return type(features) == "table" and features.dict_quick_lookup == true
    end

    local function show_wikipedia()
        local cfg = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.highlight_lookup
        return type(cfg) == "table" and cfg.show_wikipedia == true
    end

    local function allow_unknown()
        local cfg = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.highlight_lookup
        return type(cfg) == "table" and cfg.allow_unknown_items == true
    end

    -- IDs we handle explicitly; everything else is "unknown".
    local KNOWN_IDS = {
        highlight = true, search = true, wikipedia = true,
        translate = true, close = true,
        vocabulary = true, prev_dict = true, next_dict = true,
    }

    -- Build a minimal icon-only spec from an original button.
    local function icon_btn(orig, icon)
        if not orig then return nil end
        return {
            id            = orig.id,
            icon          = icon,
            enabled       = orig.enabled,
            enabled_func  = orig.enabled_func,
            callback      = orig.callback,
            hold_callback = orig.hold_callback,
        }
    end

    -- Find the existing highlight index for the current selection (rolling docs).
    -- Returns nil if no match found.
    local function find_existing_highlight_index(highlight_module)
        local sel = highlight_module.selected_text
        if not sel or not sel.pos0 then return nil end
        local annotations = highlight_module.ui
            and highlight_module.ui.annotation
            and highlight_module.ui.annotation.annotations
        if not annotations then return nil end
        -- For rolling (epub) docs, pos0/pos1 are xpointer strings.
        -- For paging (pdf) docs, they are {page, x, y} tables.
        local is_rolling = highlight_module.ui.rolling ~= nil
        for i, item in ipairs(annotations) do
            if item.drawer then -- it's a saved highlight (not just a bookmark)
                if is_rolling then
                    -- xpointer string comparison
                    if item.pos0 == sel.pos0 and item.pos1 == sel.pos1 then
                        return i
                    end
                else
                    -- paging: compare page+coords (approximate)
                    local p0, p1 = item.pos0, item.pos1
                    if p0 and p1
                        and p0.page == sel.pos0.page
                        and math.abs(p0.x - sel.pos0.x) < 2
                        and math.abs(p0.y - sel.pos0.y) < 2
                        and math.abs(p1.x - sel.pos1.x) < 2
                        and math.abs(p1.y - sel.pos1.y) < 2 then
                        return i
                    end
                end
            end
        end
        return nil
    end

    -- Called by DictQuickLookup just before it builds its ButtonTable.
    -- Mutates `buttons` in-place; only sees buttons added before VocabBuilder runs.
    -- VocabBuilder appends after this, so we post-process via DictQuickLookup:init wrap below.
    ReaderHighlight.onDictButtonsReady = function(self, dict_widget, buttons)
        logger.dbg("zen-ui[dict_quick_lookup]: onDictButtonsReady, is_enabled=",
            tostring(is_enabled()), "is_wiki=", tostring(dict_widget.is_wiki),
            "is_wiki_fullpage=", tostring(dict_widget.is_wiki_fullpage))
        if not is_enabled() then return end
        if dict_widget.is_wiki or dict_widget.is_wiki_fullpage then return end

        local by_id = {}
        local unknown = {}
        for _, row in ipairs(buttons) do
            for _, btn in ipairs(row) do
                if btn.id then
                    if KNOWN_IDS[btn.id] then
                        by_id[btn.id] = btn
                    else
                        table.insert(unknown, btn)
                    end
                end
            end
        end

        -- Translate is not included in the DictButtonsReady event; build manually.
        local translate_btn = {
            id   = "translate",
            icon = "lookup.translate",
            callback = function()
                Translator:showTranslation(dict_widget.word, true)
            end,
        }

        local icon_row = {}
        local h = icon_btn(by_id["highlight"], "lookup.highlight")
        -- Wrap highlight button to toggle (delete if already highlighted).
        if h then
            local orig_cb = h.callback
            h.callback = function()
                local idx = find_existing_highlight_index(self)
                if idx then
                    self:deleteHighlight(idx)
                else
                    orig_cb() -- sets save_highlight=true; onClose() below saves it
                end
                dict_widget:onClose()
            end
        end
        -- vocab button built below after post-processing catches VocabBuilder's row
        local w = show_wikipedia() and icon_btn(by_id["wikipedia"], "lookup.wikipedia") or nil
        local s = icon_btn(by_id["search"],    "lookup.search")
        if h then table.insert(icon_row, h) end
        -- vocab slot placeholder: filled in post-process below
        if w then table.insert(icon_row, w) end
        table.insert(icon_row, translate_btn)
        if s then table.insert(icon_row, s) end

        if #icon_row == 0 then
            logger.dbg("zen-ui[dict_quick_lookup]: no known button ids found, leaving unchanged")
            return
        end

        -- Replace the entire buttons table in-place.
        -- VocabBuilder will append its row AFTER this returns (separate event handler).
        -- The DictQuickLookup:init wrap below handles the post-process cleanup.
        for i = #buttons, 1, -1 do table.remove(buttons, i) end
        table.insert(buttons, icon_row)

        -- Preserve unknown buttons as a plain text row when enabled.
        if allow_unknown() and #unknown > 0 then
            table.insert(buttons, unknown)
        end

        -- Tag the widget so the init-wrap knows to post-process.
        dict_widget._zen_icon_row = icon_row
        dict_widget._zen_allow_unknown = allow_unknown()

        logger.dbg("zen-ui[dict_quick_lookup]: replaced buttons, icon_row=",
            #icon_row, "unknown=", #unknown)
    end

    -- Wrap DictQuickLookup:init to post-process buttons after ALL DictButtonsReady
    -- handlers have run (including VocabBuilder, which appends after our handler).
    -- We temporarily wrap ui:handleEvent to observe the final buttons state.
    local orig_init = DictQuickLookup.init
    DictQuickLookup.init = function(self_dql, ...)
        local ui = self_dql.ui
        if ui and is_enabled()
            and not self_dql.is_wiki and not self_dql.is_wiki_fullpage then
            local orig_handle = ui.handleEvent
            ui.handleEvent = function(ui_self, event, ...)
                local result = orig_handle(ui_self, event, ...)
                -- Post-process after all DictButtonsReady handlers have run.
                if event and event.handler == "onDictButtonsReady"
                    and self_dql._zen_icon_row then
                    local buttons = event.args[2]
                    local icon_row = self_dql._zen_icon_row
                    -- Scan for VocabBuilder's id-less row (text contains "vocabulary").
                    local vocab_raw = nil
                    for ri = #buttons, 1, -1 do
                        local row = buttons[ri]
                        if row ~= icon_row then
                            for _, btn in ipairs(row) do
                                local t = type(btn.text) == "string" and btn.text
                                    or (type(btn.text_func) == "function" and btn.text_func())
                                if type(t) == "string" and t:lower():find("vocabulary") then
                                    vocab_raw = btn
                                    break
                                end
                            end
                            if vocab_raw then
                                table.remove(buttons, ri)
                                break
                            end
                        end
                    end
                    if vocab_raw then
                        -- Build a toggle-aware vocab icon button.
                        -- DB is cached in package.loaded by VocabBuilder on load.
                        local DB = package.loaded["db"]
                        local vocab_word = self_dql.lookupword or self_dql.word
                        local is_in_vocab = false -- start as "add" (matches VocabBuilder's own UX)

                        local function get_book_title()
                            local dui = self_dql.ui
                            return (dui and dui.doc_props and dui.doc_props.display_title)
                                or _("Dictionary lookup")
                        end

                        local function update_vocab_icon(in_vocab)
                            local btn_w = self_dql.button_table
                                and self_dql.button_table:getButtonById("vocabulary")
                            if btn_w then
                                btn_w:setIcon(
                                    in_vocab and "lookup.vocab_remove" or "lookup.vocab",
                                    btn_w.width
                                )
                            end
                            UIManager:setDirty(self_dql, "ui")
                        end

                        local v = {
                            id   = "vocabulary",
                            icon = "lookup.vocab",
                            callback = function()
                                if not is_in_vocab then
                                    -- Add: fire WordLookedUp so VocabBuilder handles insert.
                                    self_dql.ui:handleEvent(
                                        Event:new("WordLookedUp", vocab_word, get_book_title(), true)
                                    )
                                    is_in_vocab = true
                                    update_vocab_icon(true)
                                else
                                    -- Remove directly (no confirmation, matching icon-toggle UX).
                                    if DB and DB.remove then
                                        DB:remove({ word = vocab_word })
                                    end
                                    is_in_vocab = false
                                    update_vocab_icon(false)
                                end
                            end,
                        }
                        table.insert(icon_row, 2, v)
                        logger.dbg("zen-ui[dict_quick_lookup]: vocab icon inserted")
                    end
                end
                return result
            end
            local ok, err = pcall(orig_init, self_dql, ...)
            ui.handleEvent = orig_handle -- always restore
            if not ok then error(err) end
        else
            return orig_init(self_dql, ...)
        end
    end

    logger.dbg("zen-ui[dict_quick_lookup]: onDictButtonsReady handler installed")
end

return apply
