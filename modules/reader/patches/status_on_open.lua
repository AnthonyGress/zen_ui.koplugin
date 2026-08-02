local function apply_status_on_open()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._zen_new_status_on_open_patched then return end
    ReaderUI._zen_new_status_on_open_patched = true

    local book_status = require("common/book_status")
    local orig_onReaderReady = ReaderUI.onReaderReady

    function ReaderUI:onReaderReady(...)
        if orig_onReaderReady then
            orig_onReaderReady(self, ...)
        end
        local doc_settings = self.doc_settings
        if book_status.acknowledgeNewVersion(doc_settings)
                and type(doc_settings.flush) == "function" then
            doc_settings:flush()
        end
    end
end

return apply_status_on_open
