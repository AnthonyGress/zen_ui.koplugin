describe("reader book status", function()
    local dependencies = {
        "modules/reader/patches/book_status",
        "ui/widget/bookstatuswidget",
        "common/library_navigation",
        "gettext",
        "ui/size",
        "device",
        "ui/uimanager",
        "ui/widget/iconbutton",
        "ui/widget/button",
        "ui/widget/container/centercontainer",
        "ui/event",
        "ui/geometry",
        "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan",
        "ui/widget/verticalgroup",
        "ui/widget/verticalspan",
    }
    local saved_modules
    local saved_defaults
    local saved_reader_settings
    local BookStatusWidget
    local next_file_opens
    local library_opens
    local closed

    local function widget_class()
        return {
            new = function(_, values)
                values = values or {}
                values.getSize = values.getSize or function(self)
                    return { w = self.width or 0, h = self.height or 20 }
                end
                return values
            end,
        }
    end

    local function make_status()
        return {
            key_events = {},
            ui = {
                document = {},
                doc_settings = { flush = function() end },
                status = {
                    onOpenNextOrPreviousFileInFolder = function()
                        next_file_opens = next_file_opens + 1
                    end,
                },
            },
            genHeader = function()
                return { {} }
            end,
            generateRateGroup = function()
                return {}
            end,
            genBookInfoGroup = function(self)
                return self:generateRateGroup(300, 0, 0)
            end,
            genSummaryGroup = function()
                return {}
            end,
            genStatisticsGroup = function()
                return {}
            end,
            generateSwitchGroup = function()
                return {}
            end,
        }
    end

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(dependencies) do
            saved_modules[name] = package.loaded[name] or false
        end
        saved_defaults = _G.G_defaults
        saved_reader_settings = _G.G_reader_settings
        next_file_opens = 0
        library_opens = 0
        closed = 0

        BookStatusWidget = {
            generateRateGroup = function()
                return {}
            end,
        }
        ZenSpec.replace("ui/widget/bookstatuswidget", BookStatusWidget)
        ZenSpec.replace("common/library_navigation", {
            showFromReader = function()
                library_opens = library_opens + 1
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/size", {
            padding = { default = 8 },
            span = { vertical_default = 4 },
        })
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_, value) return value end },
            input = { group = { PgFwd = { "PgFwd" } } },
            hasKeys = function() return true end,
        })
        ZenSpec.replace("ui/uimanager", {
            close = function() closed = closed + 1 end,
            scheduleIn = function(_, _, callback) callback() end,
        })
        ZenSpec.replace("ui/widget/iconbutton", widget_class())
        ZenSpec.replace("ui/widget/button", widget_class())
        ZenSpec.replace("ui/widget/container/centercontainer", widget_class())
        ZenSpec.replace("ui/widget/horizontalgroup", widget_class())
        ZenSpec.replace("ui/widget/horizontalspan", widget_class())
        ZenSpec.replace("ui/widget/verticalgroup", widget_class())
        ZenSpec.replace("ui/widget/verticalspan", widget_class())
        ZenSpec.replace("ui/event", { new = function(_, name) return { name = name } end })
        ZenSpec.replace("ui/geometry", { new = function(_, values) return values end })

        _G.G_defaults = { readSetting = function() return 24 end }
        _G.G_reader_settings = ZenSpec.memorySettings()
    end)

    after_each(function()
        _G.G_defaults = saved_defaults
        _G.G_reader_settings = saved_reader_settings
        for _i, name in ipairs(dependencies) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("opens the next sequential file on page-forward from book status", function()
        G_reader_settings:saveSetting("collate", "natural")
        require("modules/reader/patches/book_status")()
        local status = make_status()

        BookStatusWidget.getStatusContent(status, 400)

        assert.is_not_nil(status.key_events.ZenOpenNextFile)
        assert.is_nil(status.key_events.ZenGoLibrary)
        assert.is_true(status:onZenOpenNextFile())
        assert.are.equal(1, next_file_opens)
        assert.are.equal(1, closed)
        assert.are.equal(0, library_opens)
    end)

    it("keeps page-forward at the library fallback for non-sequential collation", function()
        G_reader_settings:saveSetting("collate", "access")
        require("modules/reader/patches/book_status")()
        local status = make_status()

        BookStatusWidget.getStatusContent(status, 400)

        assert.is_nil(status.key_events.ZenOpenNextFile)
        assert.is_not_nil(status.key_events.ZenGoLibrary)
        assert.is_true(status:onZenGoLibrary())
        assert.are.equal(0, next_file_opens)
        assert.are.equal(1, closed)
        assert.are.equal(1, library_opens)
    end)
end)
