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
        local file = doc_settings and doc_settings.data and doc_settings.data.doc_path
        local summary = type(doc_settings and doc_settings.readSetting) == "function"
            and doc_settings:readSetting("summary") or {}
        local was_tbr = false
        if file then
            pcall(function()
                local TBRIndex = require("common/tbr_index")
                was_tbr = TBRIndex.isExplicit(file)
                if was_tbr then TBRIndex.setExplicit(file, false) end
            end)
        end
        local was_on_hold = summary.status == "abandoned"
        if was_tbr or was_on_hold then
            summary.status = "reading"
            require("apps/filemanager/filemanagerutil").saveSummary(doc_settings, summary)
            require("ui/widget/booklist").setBookInfoCacheProperty(file, "status", "reading")
            book_status.invalidate(file)
        end
        local acknowledged = book_status.acknowledgeNewVersion(doc_settings)
        if (was_tbr or was_on_hold or acknowledged)
                and type(doc_settings.flush) == "function" then
            doc_settings:flush()
        end
        pcall(function()
            if file then require("common/tbr_index").refreshPath(file, doc_settings) end
        end)
    end
end

return apply_status_on_open
