local function apply_incognito_mode()
    -- Incognito mode: while active, opened books leave no trace.
    -- Suppresses ReadHistory entries (recent books list) and DocSettings.flush
    -- (per-book .sdr metadata: page position, progress, bookmarks, highlights).
    -- Gated live on config.features.incognito_mode so toggling needs no restart.

    local _plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")
    if not _plugin_ref or type(_plugin_ref.config) ~= "table" then return end

    local function is_incognito()
        local features = _plugin_ref.config.features
        return type(features) == "table" and features.incognito_mode == true
    end

    local ok_rh, ReadHistory = pcall(require, "readhistory")
    if ok_rh and ReadHistory then
        local orig_addItem = ReadHistory.addItem
        ReadHistory.addItem = function(self, ...)
            if is_incognito() then return end
            return orig_addItem(self, ...)
        end
    end

    local ok_ds, DocSettings = pcall(require, "docsettings")
    if ok_ds and DocSettings then
        local orig_flush = DocSettings.flush
        DocSettings.flush = function(self, ...)
            if is_incognito() then return end
            return orig_flush(self, ...)
        end
    end
end

return { apply = apply_incognito_mode }
