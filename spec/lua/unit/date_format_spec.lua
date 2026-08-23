describe("date format", function()
    local date_stub
    local original_datetime
    local original_gettext
    local original_settings

    local function install_date(day, month, year, month_name, weekday)
        date_stub = stub(os, "date")
        date_stub.on_call_with("*t").returns({
            day = day, month = month, year = year, wday = 7,
        })
        date_stub.on_call_with("%B").returns(month_name)
        date_stub.on_call_with("%A").returns(weekday or "Saturday")
    end

    local function load_formatter(language, template, translated_month)
        _G.G_reader_settings = ZenSpec.memorySettings({ language = language })
        ZenSpec.replace("gettext", function(text)
            if text == "%1, %2 %3" then return template or text end
            return text
        end)
        ZenSpec.replace("datetime", {
            weekDays = { [7] = "Sat" },
            shortDayOfWeekToLongTranslation = { Sat = "Saturday" },
            longMonthTranslation = { August = translated_month or "August" },
        })
        ZenSpec.unload("common/date_format")
        return require("common/date_format")
    end

    before_each(function()
        original_datetime = package.loaded["datetime"]
        original_gettext = package.loaded["gettext"]
        original_settings = rawget(_G, "G_reader_settings")
    end)

    after_each(function()
        if date_stub then date_stub:revert() end
        date_stub = nil
        ZenSpec.unload("common/date_format")
        package.loaded["datetime"] = original_datetime
        package.loaded["gettext"] = original_gettext
        _G.G_reader_settings = original_settings
    end)

    it("uses month-first short dates for KOReader English", function()
        install_date(23, 8, 2026, "August")
        local formatter = load_formatter("C")

        assert.are.equal("08/23/26", formatter.format("short"))
    end)

    it("uses day-first short dates for other locales", function()
        install_date(23, 8, 2026, "August")
        local formatter = load_formatter("en_GB")

        assert.are.equal("23/08/26", formatter.format("short"))
    end)

    it("adds English ordinal suffixes to the long format", function()
        install_date(8, 8, 2026, "August")
        local formatter = load_formatter("en_US")

        assert.are.equal("August 8th", formatter.format("long"))
        assert.are.equal("Saturday, August 8", formatter.formatLongWithWeekday())
    end)

    it("uses the existing translated date grammar for Spanish", function()
        install_date(15, 8, 2026, "August")
        local formatter = load_formatter("es", "%1, %3 de %2", "Agosto")

        assert.are.equal("15 de agosto", formatter.format("long"))
    end)

    it("removes trailing weekday punctuation in Chinese", function()
        install_date(8, 8, 2026, "August")
        local formatter = load_formatter("zh_CN", "%2%3日，%1", "八月")

        assert.are.equal("八月8日", formatter.format("long"))
    end)

    it("removes the empty weekday parentheses in Japanese", function()
        install_date(8, 8, 2026, "August")
        local formatter = load_formatter("ja", "%2%3日（%1）", "8月")

        assert.are.equal("8月8日", formatter.format("long"))
    end)
end)
