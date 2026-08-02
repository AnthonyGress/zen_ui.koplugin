describe("updater repository redirects", function()
    local original_https
    local original_ltn12
    local original_archiver
    local original_icon_item
    local original_logger
    local original_network_manager
    local original_trapper
    local original_uimanager
    local config
    local logs
    local network_up
    local requests
    local scheduled

    before_each(function()
        original_https = package.loaded["ssl.https"]
        original_ltn12 = package.loaded["ltn12"]
        original_archiver = package.loaded["ffi/archiver"]
        original_icon_item = package.loaded["common/ui/icon_menu_item"]
        original_logger = package.loaded["common/zen_logger"]
        original_network_manager = package.loaded["ui/network/manager"]
        original_trapper = package.loaded["ui/trapper"]
        original_uimanager = package.loaded["ui/uimanager"]
        logs = {}
        network_up = true
        requests = {}
        scheduled = {}
        config = { updater = { update_channel = "stable" } }

        ZenSpec.replace("ffi/archiver", {})
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("config/manager", {
            load = function() return config end,
            save = function() end,
        })
        ZenSpec.replace("common/zen_logger", {
            new = function()
                local updater_logger = {}
                for _i, level in ipairs({ "dbg", "info", "warn", "err" }) do
                    local log_level = level
                    updater_logger[log_level] = function(...)
                        local parts = {}
                        for i = 1, select("#", ...) do
                            parts[#parts + 1] = tostring(select(i, ...))
                        end
                        logs[#logs + 1] = { level = log_level, text = table.concat(parts, " ") }
                    end
                end
                return updater_logger
            end,
        })
        ZenSpec.replace("ui/network/manager", {
            isWifiOn = function() return network_up end,
        })
        ZenSpec.replace("ui/trapper", {
            wrap = function(_, fn) fn() end,
            dismissableRunInSubprocess = function(_, task)
                return true, task()
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function(_, delay, callback)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback }
            end,
            unschedule = function() end,
        })
        ZenSpec.replace("ltn12", {
            sink = {
                table = function(target)
                    return function(chunk)
                        if chunk then target[#target + 1] = chunk end
                        return 1
                    end
                end,
            },
        })
        ZenSpec.replace("ssl.https", {
            request = function(request)
                requests[#requests + 1] = request.url
                assert.is_false(request.redirect)
                if #requests == 1 then
                    return 1, 301, {
                        location = "https://api.github.com/repositories/1194031944/releases?per_page=100",
                    }, "HTTP/1.1 301 Moved Permanently"
                end
                request.sink([[
                    [{
                        "url":"https://api.github.com/repos/AnthonyGress/zen-ui/releases/12345",
                        "tag_name":"v999.0.0",
                        "prerelease":false,
                        "body":"Renamed repository release",
                        "published_at":"2026-07-12T00:00:00Z",
                        "assets":[{
                            "name":"zen_ui.koplugin.zip",
                            "browser_download_url":"https://github.com/AnthonyGress/zen-ui/releases/download/v999.0.0/zen_ui.koplugin.zip",
                            "digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                        }]
                    }]
                ]])
                return 1, 200, {}, "HTTP/1.1 200 OK"
            end,
        })
        ZenSpec.unload("modules/settings/zen_updater")
    end)

    after_each(function()
        package.loaded["ssl.https"] = original_https
        package.loaded["ltn12"] = original_ltn12
        package.loaded["ffi/archiver"] = original_archiver
        package.loaded["common/ui/icon_menu_item"] = original_icon_item
        package.loaded["common/zen_logger"] = original_logger
        package.loaded["ui/network/manager"] = original_network_manager
        package.loaded["ui/trapper"] = original_trapper
        package.loaded["ui/uimanager"] = original_uimanager
        ZenSpec.unload("modules/settings/zen_updater")
        ZenSpec.unload("config/manager")
    end)

    it("follows the GitHub API rename and accepts assets from the canonical repository", function()
        local updater = require("modules/settings/zen_updater")

        assert.are.equal("ok", updater.check_for_update())
        assert.are.equal(2, #requests)
        assert.are.equal(
            "https://api.github.com/repositories/1194031944/releases?per_page=100",
            requests[2]
        )
        assert.are.equal("999.0.0", updater.latest_version())
        assert.is_true(updater.has_update())
    end)

    it("clears the update marker after a version change is acknowledged", function()
        local updater = require("modules/settings/zen_updater")
        assert.are.equal("ok", updater.check_for_update())
        assert.is_true(updater.has_update())
        assert.is_true(config.updater.update_available)

        updater.clear_update_state(config)

        assert.is_false(updater.has_update())
        assert.is_nil(updater.latest_version())
        assert.is_false(config.updater.update_available)
    end)

    it("logs one summary line for an automatic update check", function()
        local updater = require("modules/settings/zen_updater")

        updater.schedule_wakeup_check()
        assert.are.equal(0, #logs)
        assert.are.equal(1, #scheduled)

        scheduled[1].callback()

        assert.are.same({ {
            level = "info",
            text = "automatic update check status=ok has_update= true latest= 999.0.0",
        } }, logs)
    end)

    it("logs only the final automatic check result when the network stays down", function()
        network_up = false
        local updater = require("modules/settings/zen_updater")

        updater.schedule_wakeup_check()
        scheduled[1].callback()
        assert.are.equal(0, #logs)
        assert.are.equal(2, #scheduled)

        scheduled[2].callback()

        assert.are.same({ {
            level = "info",
            text = "automatic update check status=skipped reason=network_unavailable",
        } }, logs)
    end)
end)
