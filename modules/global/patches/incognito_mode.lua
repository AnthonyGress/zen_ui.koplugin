local M = {}
local _ = require("gettext")
local statistics_class
local PluginLoader
local plugin_ref
local timeout_callback

local MAX_TIMEOUT_MINUTES = 1440

local function get_config(plugin)
    local active_plugin = plugin or plugin_ref
    return active_plugin and active_plugin.config or nil
end

local function get_incognito_config(plugin)
    local config = get_config(plugin)
    if type(config) ~= "table" then return nil end
    if type(config.incognito) ~= "table" then config.incognito = {} end
    return config.incognito
end

local function is_incognito(plugin)
    local config = get_config(plugin)
    local features = config and config.features
    return type(features) == "table" and features.incognito_mode == true
end

local function save_config(plugin)
    local active_plugin = plugin or plugin_ref
    if active_plugin and type(active_plugin.saveConfig) == "function" then
        pcall(active_plugin.saveConfig, active_plugin)
    end
end

local function timeout_minutes(plugin)
    local config = get_incognito_config(plugin)
    local minutes = config and tonumber(config.timeout_minutes) or 0
    return math.max(0, math.min(MAX_TIMEOUT_MINUTES, math.floor(minutes)))
end

local function cancel_timeout()
    if not timeout_callback then return end
    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    if ok_ui and UIManager and type(UIManager.unschedule) == "function" then
        pcall(UIManager.unschedule, UIManager, timeout_callback)
    end
    timeout_callback = nil
end

local reconcile_timeout

local function timeout_expired()
    timeout_callback = nil
    if not is_incognito() then return end
    local config = get_incognito_config()
    local deadline = config and tonumber(config.timeout_at)
    if deadline and deadline > os.time() then
        if reconcile_timeout(nil, false) then save_config() end
        return
    end
    local ok_dispatch, DispatchAction = pcall(require, "common/dispatch_action")
    if ok_dispatch and type(DispatchAction.setIncognitoMode) == "function" then
        DispatchAction.setIncognitoMode(plugin_ref, false, { timed_out = true })
    end
end

reconcile_timeout = function(plugin, reset_deadline)
    plugin_ref = plugin or plugin_ref
    cancel_timeout()

    local config = get_incognito_config(plugin_ref)
    if not config then return false end
    local changed = false
    local minutes = timeout_minutes(plugin_ref)
    if not is_incognito(plugin_ref) or minutes == 0 then
        if config.timeout_at ~= nil then
            config.timeout_at = nil
            changed = true
        end
        return changed
    end

    local now_ts = os.time()
    local deadline = tonumber(config.timeout_at)
    if reset_deadline or not deadline then
        deadline = now_ts + minutes * 60
        config.timeout_at = deadline
        changed = true
    end
    if deadline <= now_ts then
        timeout_expired()
        return changed
    end

    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    if ok_ui and UIManager and type(UIManager.scheduleIn) == "function" then
        timeout_callback = timeout_expired
        UIManager:scheduleIn(deadline - now_ts, timeout_callback)
    end
    return changed
end

local function get_statistics_instance()
    if not PluginLoader or type(PluginLoader.getPluginInstance) ~= "function" then return nil end
    return PluginLoader:getPluginInstance("statistics")
end

local function reset_statistics(stats, now_ts)
    if type(stats) ~= "table" or type(stats.resetVolatileStats) ~= "function" then return end
    stats:resetVolatileStats(now_ts)
end

local function patch_statistics(is_private)
    local ok_loader
    ok_loader, PluginLoader = pcall(require, "pluginloader")
    if not ok_loader or not PluginLoader or type(PluginLoader.loadPlugins) ~= "function" then return end

    local enabled_plugins = PluginLoader:loadPlugins()
    if type(enabled_plugins) ~= "table" then return end
    for _i, plugin_class in ipairs(enabled_plugins) do
        if plugin_class.name == "statistics" then
            statistics_class = plugin_class
            break
        end
    end
    if not statistics_class or statistics_class._zen_incognito_guarded then return end
    statistics_class._zen_incognito_guarded = true

    local function guard(method_name, on_block)
        local original = statistics_class[method_name]
        if type(original) ~= "function" then return end
        statistics_class[method_name] = function(self, ...)
            if is_private() then
                if on_block then return on_block(self, ...) end
                return
            end
            return original(self, ...)
        end
    end

    guard("initData", function(self) self._zen_incognito_needs_init = true end)
    guard("getIdBookDB")
    guard("onPageUpdate", function(self, pageno)
        if pageno ~= false and pageno ~= nil then self.curr_page = pageno end
        reset_statistics(self)
    end)
    guard("insertDB", reset_statistics)
    guard("onAnnotationsModified")
    guard("onBookMetadataChanged")
end

local function apply_incognito_mode()
    -- Incognito mode: while active, opened books leave no trace.
    -- Suppresses ReadHistory entries (recent books list) and DocSettings.flush
    -- (per-book .sdr metadata: page position, progress, bookmarks, highlights).
    -- Also blocks Statistics book registration, tracking, and database writes.
    -- Gated live on config.features.incognito_mode so toggling needs no restart.

    plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")
    if not plugin_ref or type(plugin_ref.config) ~= "table" then return end

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

    patch_statistics(is_incognito)
    if reconcile_timeout(plugin_ref, false) then save_config(plugin_ref) end
end

local function before_enable(plugin)
    plugin_ref = plugin or plugin_ref
    local stats = get_statistics_instance()
    if type(stats) ~= "table" then return end

    if type(stats.isEnabledAndNotFrozen) == "function" and stats:isEnabledAndNotFrozen() then
        if type(stats.onPageUpdate) == "function" then pcall(stats.onPageUpdate, stats, false) end
        if type(stats.insertDB) == "function" then pcall(stats.insertDB, stats) end
    end
    reset_statistics(stats)
    stats._reading_paused_ts = nil
    stats._reading_paused_curr_page = nil
end

local function after_enable(plugin)
    plugin_ref = plugin or plugin_ref
    reconcile_timeout(plugin_ref, true)
end

local function after_disable(plugin)
    plugin_ref = plugin or plugin_ref
    cancel_timeout()
    local config = get_incognito_config(plugin_ref)
    if config then config.timeout_at = nil end

    local stats = get_statistics_instance()
    if type(stats) ~= "table" then return end

    if stats._zen_incognito_needs_init and type(stats.initData) == "function" then
        local ok_init = pcall(stats.initData, stats)
        if ok_init then stats._zen_incognito_needs_init = nil end
    end
    if type(stats.isEnabledAndNotFrozen) ~= "function" or not stats:isEnabledAndNotFrozen() then return end

    local now_ts = os.time()
    if stats.ui and type(stats.ui.getCurrentPage) == "function" then
        local ok_page, current_page = pcall(stats.ui.getCurrentPage, stats.ui)
        if ok_page and current_page ~= nil then stats.curr_page = current_page end
    end
    stats.start_current_period = now_ts
    stats._reading_paused_ts = nil
    stats._reading_paused_curr_page = nil
    reset_statistics(stats, now_ts)
end

function M.getTimeoutMinutes(plugin)
    return timeout_minutes(plugin)
end

function M.setTimeoutMinutes(plugin, minutes)
    plugin_ref = plugin or plugin_ref
    local config = get_incognito_config(plugin_ref)
    if not config then return false end
    config.timeout_minutes = math.max(0, math.min(
        MAX_TIMEOUT_MINUTES, math.floor(tonumber(minutes) or 0)))
    reconcile_timeout(plugin_ref, true)
    save_config(plugin_ref)
    return true
end

function M.timeoutMenuItems(plugin)
    return {{
        text_func = function()
            local minutes = timeout_minutes(plugin)
            local value = minutes == 0 and _("Off") or tostring(minutes) .. " " .. _("min")
            return _("Timeout") .. ": " .. value
        end,
        keep_menu_open = true,
        callback = function(touch_menu)
            local SpinWidget = require("ui/widget/spinwidget")
            local UIManager = require("ui/uimanager")
            UIManager:show(SpinWidget:new{
                title_text = _("Incognito") .. " - " .. _("Timeout"),
                value = timeout_minutes(plugin),
                value_min = 0,
                value_max = MAX_TIMEOUT_MINUTES,
                value_step = 1,
                value_hold_step = 15,
                unit = _("min"),
                callback = function(spin)
                    M.setTimeoutMinutes(plugin, spin.value)
                    if touch_menu and touch_menu.updateItems then touch_menu:updateItems() end
                end,
            })
        end,
    }}
end

function M.onSuspend()
    cancel_timeout()
end

function M.onResume(plugin)
    plugin_ref = plugin or plugin_ref
    if reconcile_timeout(plugin_ref, false) then save_config(plugin_ref) end
end

M.apply = apply_incognito_mode
M.beforeEnable = before_enable
M.afterEnable = after_enable
M.afterDisable = after_disable

return M
