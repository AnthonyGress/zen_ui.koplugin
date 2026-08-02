describe("filebrowser CoverBrowser subprocess compatibility patch", function()
    local BookInfoManager
    local warnings

    before_each(function()
        warnings = {}
        BookInfoManager = {}
        ZenSpec.replace("bookinfomanager", BookInfoManager)
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return {
                    warn = function(message) table.insert(warnings, message) end,
                }
            end,
        })
        ZenSpec.unload("modules/filebrowser/patches/coverbrowser_subprocess_compat")
    end)

    it("preserves successful return values for both extraction paths", function()
        BookInfoManager.extractBookInfo = function(_, value) return value, "cover" end
        BookInfoManager.extractInBackground = function() return true, 2, 3, 4, 5 end

        require("modules/filebrowser/patches/coverbrowser_subprocess_compat")()

        assert.are.same({ "book", "cover" }, {
            BookInfoManager:extractBookInfo("book"),
        })
        assert.are.same({ true, 2, 3, 4, 5 }, {
            BookInfoManager:extractInBackground(),
        })
        assert.are.same({}, warnings)
    end)

    it("swallows only the known DrawContext incompatibility", function()
        BookInfoManager.extractBookInfo = function()
            error("DrawContext: setIsolateSMask is unavailable")
        end
        require("modules/filebrowser/patches/coverbrowser_subprocess_compat")()

        assert.is_nil(BookInfoManager:extractBookInfo())
        assert.are.equal(1, #warnings)
        assert.is_truthy(warnings[1]:find("extractBookInfo", 1, true))
    end)

    it("rethrows unrelated extraction failures", function()
        BookInfoManager.extractInBackground = function() error("corrupt document") end
        require("modules/filebrowser/patches/coverbrowser_subprocess_compat")()

        local ok, err = pcall(function()
            BookInfoManager:extractInBackground()
        end)
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("corrupt document", 1, true))
        assert.are.same({}, warnings)
    end)

    it("is idempotent and tolerates absent extraction methods", function()
        local calls = 0
        BookInfoManager.extractBookInfo = function()
            calls = calls + 1
            return true
        end
        local apply = require("modules/filebrowser/patches/coverbrowser_subprocess_compat")
        apply()
        local wrapped = BookInfoManager.extractBookInfo
        apply()

        assert.is_true(rawequal(wrapped, BookInfoManager.extractBookInfo))
        assert.is_true(BookInfoManager:extractBookInfo())
        assert.are.equal(1, calls)
    end)
end)
