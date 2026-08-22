local function apply_reader_footer_cbz_hide()
    -- Keeps the bottom status bar hidden across reader reloads and, optionally,
    -- while reading CBZ/PDF files.

    local ReaderFooter = require("apps/reader/modules/readerfooter")
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function get_config()
        local plugin = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        return plugin and plugin.config and plugin.config.reader_footer
    end

    local function is_status_bar_disabled()
        local cfg = get_config()
        return type(cfg) == "table" and cfg.status_bar_enabled == false
    end

    local function hide_in_image_docs()
        local cfg = get_config()
        return type(cfg) == "table" and cfg.hide_in_cbz == true
    end

    local function is_image_doc(ui)
        if not (ui and ui.document) then return false end
        local file = ui.document.file:lower() or ""
        return file:match("%.cbz$") ~= nil or file:match("%.pdf$") ~= nil
    end

    -- Hide footer on document load.
    local orig_onReaderReady = ReaderFooter.onReaderReady
    ReaderFooter.onReaderReady = function(self)
        orig_onReaderReady(self)
        if is_status_bar_disabled() then
            local off_mode = self.mode_list and self.mode_list.off or 0
            self:applyFooterMode(off_mode)
            self:refreshFooter(true, true)
        elseif hide_in_image_docs() and is_image_doc(self.ui) then
            self.view.footer_visible = false
            self:refreshFooter(true, true)
        end
    end

    -- Keep footer hidden through tap-to-toggle while setting is on.
    -- (Caller always does a repaint after applyFooterMode, so no extra refresh needed.)
    local orig_applyFooterMode = ReaderFooter.applyFooterMode
    ReaderFooter.applyFooterMode = function(self, mode)
        orig_applyFooterMode(self, mode)
        if is_status_bar_disabled()
                or hide_in_image_docs() and is_image_doc(self.ui) then
            self.view.footer_visible = false
        end
    end
end

return apply_reader_footer_cbz_hide
