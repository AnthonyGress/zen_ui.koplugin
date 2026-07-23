describe("ZenPM installer asset selection", function()
    local Installer
    local original_logger
    local original_root
    local original_archiver

    before_each(function()
        original_logger = package.loaded["common/zen_logger"]
        original_root = package.loaded["common/plugin_root"]
        original_archiver = package.loaded["ffi/archiver"]
        ZenSpec.replace("common/zen_logger", { new = function() return { warn = function() end } end })
        ZenSpec.replace("common/plugin_root", "/plugins/zen_ui.koplugin")
        ZenSpec.replace("ffi/archiver", {})
        ZenSpec.unload("modules/settings/zenpm_installer")
        Installer = require("modules/settings/zenpm_installer")
    end)

    after_each(function()
        package.loaded["common/zen_logger"] = original_logger
        package.loaded["common/plugin_root"] = original_root
        package.loaded["ffi/archiver"] = original_archiver
        ZenSpec.unload("modules/settings/zenpm_installer")
    end)

    it("selects Android plugin and companion APK", function()
        local plugin, apk = Installer.select_assets({ isAndroid = function() return true end }, "Linux")
        assert.are.equal("ZenPM-koreader-android-%s.zip", plugin)
        assert.are.equal("ZenPM-android-%s.apk", apk)
    end)

    it("selects desktop assets before e-reader ABI assets", function()
        assert.are.equal("ZenPM-koreader-macos-%s.zip", Installer.select_assets({}, "OSX"))
        assert.are.equal("ZenPM-koreader-macos-%s.zip", Installer.select_assets({}, "Darwin"))
        assert.are.equal("ZenPM-koreader-linux-%s.zip", Installer.select_assets({}, "Linux"))
    end)

    it("selects e-reader assets before Linux desktop assets", function()
        local eink = { hasEinkScreen = function() return true end }
        assert.are.equal("ZenPM-koreader-ereader-%s.zip", Installer.select_assets(eink, "Linux"))
        assert.are.equal("ZenPM-koreader-linux-%s.zip", Installer.select_assets({}, "Linux"))
    end)

    it("tries an e-reader package whenever KOReader reports an e-ink screen", function()
        local eink_sdl = {
            hasEinkScreen = function() return true end,
            isSDL = function() return true end,
        }
        assert.are.equal("ZenPM-koreader-ereader-%s.zip", Installer.select_assets(eink_sdl, "Linux"))
    end)

    it("matches release assets with the filename portion before the version", function()
        assert.are.equal("ZenPM-koreader-macos-", Installer.asset_prefix("ZenPM-koreader-macos-%s.zip"))
    end)

    it("accepts the official macOS release asset URL", function()
        local name = "ZenPM-koreader-macos-1.0.0-beta120.zip"
        assert.is_true(Installer.is_valid_asset_url(
            "https://github.com/xZenLabs/zen-pm/releases/download/v1.0.0-beta120/" .. name,
            name
        ))
    end)
end)
