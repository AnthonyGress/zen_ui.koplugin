describe("app launcher plugin scan", function()
    local plugin_dir

    before_each(function()
        plugin_dir = "/plugins/marked.koplugin"

        ZenSpec.replace("pluginloader", {
            loaded_plugins = {
                marked = { path = plugin_dir .. "/", open = function() end },
                manual = { path = "/plugins/manual.koplugin", open = function() end },
            },
            loadPlugins = function()
                return { { name = "marked" }, { name = "manual" } }
            end,
        })
        ZenSpec.unload("modules/menu/app_launcher/plugin_scan")
    end)

    after_each(function()
        ZenSpec.unload("modules/menu/app_launcher/plugin_scan")
        ZenSpec.unload("pluginloader")
    end)

    it("matches only launchable plugins with pending ZenPM database rows", function()
        local PluginScan = require("modules/menu/app_launcher/plugin_scan")
        local found = PluginScan.scan()
        assert.are.equal(2, #found)

        local zenpm = PluginScan.scanZenPM({
            { id = "package-id", install_path = plugin_dir },
        })
        assert.are.equal(1, #zenpm)
        assert.are.equal("marked", zenpm[1].key)
        assert.are.equal("package-id", zenpm[1].zenpm_package_id)
    end)
end)
