describe("ZenOS brand migration", function()
    local BrandMigration
    local lfs
    local test_root
    local plugins_dir
    local settings_dir
    local fake_lua_settings

    local function path(parent, child)
        return parent .. "/" .. child
    end

    local function write_file(filename, contents)
        local file = assert(io.open(filename, "w"))
        assert(file:write(contents or "fixture"))
        file:close()
    end

    local function read_file(filename)
        local file = assert(io.open(filename, "r"))
        local contents = assert(file:read("*a"))
        file:close()
        return contents
    end

    local function serialize(value)
        local kind = type(value)
        if kind == "string" then return string.format("%q", value) end
        if kind == "number" or kind == "boolean" then return tostring(value) end
        if kind ~= "table" then return "nil" end
        local fields = { "{" }
        for key, item in pairs(value) do
            fields[#fields + 1] = "[" .. serialize(key) .. "]="
                .. serialize(item) .. ","
        end
        fields[#fields + 1] = "}"
        return table.concat(fields)
    end

    local function entry_mode(filename)
        if type(lfs.symlinkattributes) == "function" then
            return lfs.symlinkattributes(filename, "mode")
        end
        return lfs.attributes(filename, "mode")
    end

    local function remove_tree(filename)
        local mode = entry_mode(filename)
        if mode == "file" or mode == "link" then
            os.remove(filename)
            return
        end
        if mode ~= "directory" then return end
        for entry in lfs.dir(filename) do
            if entry ~= "." and entry ~= ".." then
                remove_tree(path(filename, entry))
            end
        end
        lfs.rmdir(filename)
    end

    local function mkdir(filename)
        assert.is_true(lfs.mkdir(filename) == true
            or lfs.attributes(filename, "mode") == "directory")
        return filename
    end

    local function migration_options(plugin_root, g_settings, extra)
        local options = {
            plugin_root = plugin_root,
            settings_dir = settings_dir,
            lfs = lfs,
            g_settings = g_settings or ZenSpec.memorySettings(),
            lua_settings = fake_lua_settings,
        }
        for key, value in pairs(extra or {}) do options[key] = value end
        return options
    end

    before_each(function()
        lfs = require("libs/libkoreader-lfs")
        ZenSpec.unload("common/brand_migration")
        BrandMigration = require("common/brand_migration")
        fake_lua_settings = {
            open = function(_self, filename)
                fake_lua_settings.open_count = fake_lua_settings.open_count + 1
                local ok, data = pcall(dofile, filename)
                if not ok or type(data) ~= "table" then
                    ok, data = pcall(dofile, filename .. ".old")
                end
                local settings = {
                    data = ok and type(data) == "table" and data or {},
                    file = filename,
                }
                function settings:readSetting(key) return self.data[key] end
                function settings:saveSetting(key, value) self.data[key] = value end
                function settings:delSetting(key) self.data[key] = nil end
                function settings:backup()
                    if fake_lua_settings.rotate_on_flush
                            and not fake_lua_settings.rotated[filename]
                            and not filename:match("%.old$")
                            and lfs.attributes(filename, "mode") == "file" then
                        assert(os.rename(filename, filename .. ".old"))
                        fake_lua_settings.rotated[filename] = true
                    end
                end
                function settings:flush()
                    self:backup()
                    write_file(filename, "return " .. serialize(self.data) .. "\n")
                end
                return settings
            end,
            open_count = 0,
            rotate_on_flush = false,
            rotated = {},
        }
        test_root = os.tmpname()
        os.remove(test_root)
        mkdir(test_root)
        plugins_dir = mkdir(path(test_root, "plugins"))
        settings_dir = mkdir(path(test_root, "settings"))
        _G.__ZENOS_BRAND_MIGRATION_NOTICE = nil
        _G.__ZENOS_PLUGIN_ROOT_GUARD = nil
    end)

    after_each(function()
        remove_tree(test_root)
        _G.__ZENOS_BRAND_MIGRATION_NOTICE = nil
        _G.__ZENOS_PLUGIN_ROOT_GUARD = nil
    end)

    it("defers the legacy directory rename until plugin init", function()
        local legacy_plugin = mkdir(path(plugins_dir, "zen_ui.koplugin"))
        local legacy_settings = mkdir(path(settings_dir, "Zen UI"))
        write_file(path(legacy_plugin, "_meta.lua"), "return {}")
        write_file(path(legacy_settings, "unknown.txt"), "preserve me")

        local result = BrandMigration.detectStartup(
            nil, migration_options(legacy_plugin))

        assert.is_true(result.pending)
        assert.are.equal("directory", lfs.attributes(legacy_plugin, "mode"))
        assert.are.equal("file", lfs.attributes(
            path(legacy_plugin, "_meta.lua"), "mode"))
        assert.are.equal("directory", lfs.attributes(legacy_settings, "mode"))
        assert.is_nil(lfs.attributes(path(plugins_dir, "zenos.koplugin"), "mode"))
        assert.is_nil(lfs.attributes(path(settings_dir, "ZenOS"), "mode"))
        assert.are.equal(0, fake_lua_settings.open_count)
    end)

    it("moves the complete install and rewrites only owned persisted values", function()
        local legacy_plugin = mkdir(path(plugins_dir, "zen_ui.koplugin"))
        local legacy_settings = mkdir(path(settings_dir, "Zen UI"))
        local current_plugin = path(plugins_dir, "zenos.koplugin")
        write_file(path(legacy_plugin, "_meta.lua"), "return {}")
        write_file(path(legacy_settings, "unknown.txt"), "preserve me")
        write_file(path(legacy_settings, "config.lua"), string.format(
            "return { library_font = { font_face = %q } }\n",
            legacy_plugin .. "/fonts/Regular.ttf"))
        local reader_fixture = [[
return {
    active_preset = "(Zen UI) Chapter Time + %",
    settings = {
        reader_footer_custom_text = "Zen UI",
        footer = { text_font_face = __FONT_PATH__ },
    },
    presets = {
        ["(Zen UI) Chapter Time + %"] = {
            name = "(Zen UI) Chapter Time + %",
            reader_footer_custom_text = "Zen UI",
        },
        custom = {
            name = "custom",
            reader_footer_custom_text = "Zen UI",
        },
    },
}
]]
        reader_fixture = reader_fixture:gsub(
            "__FONT_PATH__", string.format("%q", legacy_plugin .. "/fonts/SemiBold.ttf"))
        write_file(path(legacy_settings, "reader.lua"), reader_fixture)
        local global_path = path(test_root, "settings.reader.lua")
        write_file(global_path, string.format([[
return {
    plugins_disabled = { zen_ui = false },
    footer = { text_font_face = %q },
    reader_footer_custom_text = "Zen UI",
}
]], legacy_plugin .. "/fonts/SemiBold.ttf"))
        local g_settings = fake_lua_settings:open(global_path)
        fake_lua_settings.rotate_on_flush = true

        local pending = BrandMigration.detectStartup(
            nil, migration_options(legacy_plugin, g_settings))
        local result = BrandMigration.performPending(pending)

        assert.are.equal("migrated", result.status)
        assert.is_true(result.restart)
        assert.is_nil(lfs.attributes(legacy_plugin, "mode"))
        assert.are.equal("directory", lfs.attributes(current_plugin, "mode"))
        local current_settings = path(settings_dir, "ZenOS")
        assert.are.equal("preserve me",
            read_file(path(current_settings, "unknown.txt")))

        local config = dofile(path(current_settings, "config.lua"))
        assert.are.equal(current_plugin .. "/fonts/Regular.ttf",
            config.library_font.font_face)
        assert.is_true(config._meta.zenos_brand_migration_v1)
        local reader = dofile(path(current_settings, "reader.lua"))
        assert.are.equal("(ZenOS) Chapter Time + %", reader.active_preset)
        assert.is_nil(reader.presets["(Zen UI) Chapter Time + %"])
        assert.are.equal("ZenOS",
            reader.presets["(ZenOS) Chapter Time + %"].reader_footer_custom_text)
        assert.are.equal("Zen UI", reader.presets.custom.reader_footer_custom_text)
        assert.are.equal(current_plugin .. "/fonts/SemiBold.ttf",
            g_settings:readSetting("footer").text_font_face)
        assert.are.equal("ZenOS",
            g_settings:readSetting("reader_footer_custom_text"))
        assert.is_nil(g_settings:readSetting("plugins_disabled").zen_ui)
        assert.is_false(g_settings:readSetting("plugins_disabled").zenos)
        local config_backup = dofile(path(current_settings, "config.lua.old"))
        assert.are.equal(current_plugin .. "/fonts/Regular.ttf",
            config_backup.library_font.font_face)
        assert.is_nil(config_backup._meta and
            config_backup._meta.zenos_brand_migration_v1)
        local reader_backup = dofile(path(current_settings, "reader.lua.old"))
        assert.are.equal("(ZenOS) Chapter Time + %", reader_backup.active_preset)
        assert.are.equal(current_plugin .. "/fonts/SemiBold.ttf",
            reader_backup.settings.footer.text_font_face)
        local global_backup = dofile(global_path .. ".old")
        assert.is_nil(global_backup.plugins_disabled.zen_ui)
        assert.is_false(global_backup.plugins_disabled.zenos)
        assert.are.equal(current_plugin .. "/fonts/SemiBold.ttf",
            global_backup.footer.text_font_face)
        assert.are.equal("ZenOS", global_backup.reader_footer_custom_text)

        write_file(path(current_settings, "reader.lua"), "corrupt")
        local recovered_reader = fake_lua_settings:open(
            path(current_settings, "reader.lua")).data
        assert.are.equal("(ZenOS) Chapter Time + %",
            recovered_reader.active_preset)
        write_file(global_path, "corrupt")
        local recovered_global = fake_lua_settings:open(global_path).data
        assert.are.equal(current_plugin .. "/fonts/SemiBold.ttf",
            recovered_global.footer.text_font_face)

        local open_count = fake_lua_settings.open_count
        BrandMigration.rewritePersistedPaths(
            current_settings, legacy_plugin, current_plugin,
            migration_options(current_plugin, g_settings))
        assert.are.equal(open_count + 1, fake_lua_settings.open_count)
    end)

    it("rolls the settings directory back when the plugin rename fails", function()
        local legacy_plugin = mkdir(path(plugins_dir, "zen_ui.koplugin"))
        local legacy_settings = mkdir(path(settings_dir, "Zen UI"))
        write_file(path(legacy_settings, "config.lua"), "return { preserved = true }")
        local options = migration_options(legacy_plugin, nil, {
            rename = function(from_path, to_path)
                if from_path == legacy_plugin then return nil, "injected failure" end
                return os.rename(from_path, to_path)
            end,
        })

        local pending = BrandMigration.detectStartup(nil, options)
        local result = BrandMigration.performPending(pending)

        assert.are.equal("plugin_rename_failed", result.status)
        assert.are.equal("directory", lfs.attributes(legacy_plugin, "mode"))
        assert.are.equal("directory", lfs.attributes(legacy_settings, "mode"))
        assert.are.equal(true, dofile(path(legacy_settings, "config.lua")).preserved)
        assert.is_nil(lfs.attributes(path(plugins_dir, "zenos.koplugin"), "mode"))
        assert.is_nil(lfs.attributes(path(settings_dir, "ZenOS"), "mode"))
    end)

    it("does not overwrite duplicate plugin or non-empty settings directories", function()
        local legacy_plugin = mkdir(path(plugins_dir, "zen_ui.koplugin"))
        mkdir(path(plugins_dir, "zenos.koplugin"))
        local legacy_settings = mkdir(path(settings_dir, "Zen UI"))
        local current_settings = mkdir(path(settings_dir, "ZenOS"))
        write_file(path(legacy_settings, "legacy.txt"), "legacy")
        write_file(path(current_settings, "current.txt"), "current")

        local result = BrandMigration.detectStartup(
            nil, migration_options(legacy_plugin))

        assert.are.equal("plugin_conflict", result.status)
        assert.is_true(result.inert)
        assert.are.equal("legacy", read_file(path(legacy_settings, "legacy.txt")))
        assert.are.equal("current", read_file(path(current_settings, "current.txt")))

        remove_tree(path(plugins_dir, "zenos.koplugin"))
        local pending = BrandMigration.detectStartup(
            nil, migration_options(legacy_plugin))
        local settings_result = BrandMigration.performPending(pending)
        assert.are.equal("settings_conflict", settings_result.status)
        assert.are.equal("directory", lfs.attributes(legacy_plugin, "mode"))
    end)

    it("guards plugin copies loaded from different plugin roots", function()
        local first_parent = mkdir(path(test_root, "first_plugins"))
        local second_parent = mkdir(path(test_root, "second_plugins"))
        local legacy_plugin = mkdir(path(first_parent, "zen_ui.koplugin"))
        local current_plugin = mkdir(path(second_parent, "zenos.koplugin"))

        local current = BrandMigration.detectStartup(
            nil, migration_options(current_plugin))
        assert.is_true(current.proceed)
        local legacy = BrandMigration.detectStartup(
            nil, migration_options(legacy_plugin))
        assert.are.equal("plugin_conflict", legacy.status)

        local rechecked = BrandMigration.checkRootConflict(current)
        assert.are.equal("plugin_conflict", rechecked.status)
        assert.is_true(rechecked.inert)
        assert.are.equal("directory", lfs.attributes(legacy_plugin, "mode"))
        assert.are.equal("directory", lfs.attributes(current_plugin, "mode"))
    end)

    it("replaces an empty ZenOS settings directory with the legacy tree", function()
        local legacy_settings = mkdir(path(settings_dir, "Zen UI"))
        local current_settings = mkdir(path(settings_dir, "ZenOS"))
        write_file(path(legacy_settings, "config.lua"), "return { migrated = true }")

        local result = BrandMigration.prepareSettings(settings_dir, { lfs = lfs })

        assert.are.equal("migrated", result.status)
        assert.is_nil(lfs.attributes(legacy_settings, "mode"))
        assert.are.equal(true, dofile(path(current_settings, "config.lua")).migrated)
    end)

    it("finishes reader branding after an interrupted partial migration", function()
        local current_settings = mkdir(path(settings_dir, "ZenOS"))
        local legacy_plugin = path(plugins_dir, "zen_ui.koplugin")
        local current_plugin = path(plugins_dir, "zenos.koplugin")
        write_file(path(current_settings, "config.lua"), "return { _meta = {} }")
        write_file(path(current_settings, "reader.lua"), [[
return {
    active_preset = "(ZenOS) Chapter Time + %",
    settings = { reader_footer_custom_text = "Zen UI" },
    presets = {
        ["(ZenOS) Chapter Time + %"] = {
            name = "(ZenOS) Chapter Time + %",
            reader_footer_custom_text = "Zen UI",
        },
        custom = { name = "custom", reader_footer_custom_text = "Zen UI" },
    },
}
]])
        local g_settings = ZenSpec.memorySettings({
            reader_footer_custom_text = "Zen UI",
        })

        BrandMigration.rewritePersistedPaths(
            current_settings, legacy_plugin, current_plugin,
            migration_options(current_plugin, g_settings))

        local reader = dofile(path(current_settings, "reader.lua"))
        assert.are.equal("ZenOS", reader.settings.reader_footer_custom_text)
        assert.are.equal("ZenOS",
            reader.presets["(ZenOS) Chapter Time + %"].reader_footer_custom_text)
        assert.are.equal("Zen UI", reader.presets.custom.reader_footer_custom_text)
        assert.are.equal("ZenOS",
            g_settings:readSetting("reader_footer_custom_text"))
    end)

    it("falls back to the legacy settings tree after a rename failure", function()
        local legacy_settings = mkdir(path(settings_dir, "Zen UI"))
        write_file(path(legacy_settings, "config.lua"), "return { preserved = true }")

        local result = BrandMigration.prepareSettings(settings_dir, {
            lfs = lfs,
            rename = function() return nil, "injected failure" end,
        })

        assert.is_false(result.ok)
        assert.are.equal("settings_rename_failed", result.status)
        assert.are.equal(legacy_settings, result.root)
        assert.are.equal(true, dofile(path(result.root, "config.lua")).preserved)
        assert.is_nil(lfs.attributes(path(settings_dir, "ZenOS"), "mode"))
    end)

    it("does not overwrite a broken settings destination symlink", function()
        if type(lfs.link) ~= "function" then return pending("lfs.link unavailable") end
        local legacy_settings = mkdir(path(settings_dir, "Zen UI"))
        local destination = path(settings_dir, "ZenOS")
        write_file(path(legacy_settings, "config.lua"), "return { preserved = true }")
        assert.is_true(lfs.link(path(test_root, "missing"), destination, true))

        local result = BrandMigration.prepareSettings(settings_dir, { lfs = lfs })

        assert.are.equal("settings_destination_invalid", result.status)
        assert.are.equal("directory", lfs.attributes(legacy_settings, "mode"))
        assert.are.equal("link", lfs.symlinkattributes(destination, "mode"))
    end)

    it("preserves disabled intent on a canonical manual replacement", function()
        local current_plugin = mkdir(path(plugins_dir, "zenos.koplugin"))
        local g_settings = ZenSpec.memorySettings({
            plugins_disabled = { zen_ui = true },
        })

        local result = BrandMigration.detectStartup(
            nil, migration_options(current_plugin, g_settings))

        assert.are.equal("disabled_state_migrated", result.status)
        assert.is_true(result.inert)
        assert.is_true(result.restart)
        assert.is_nil(g_settings:readSetting("plugins_disabled").zen_ui)
        assert.is_true(g_settings:readSetting("plugins_disabled").zenos)
    end)

    it("removes settings symlinks without traversing their targets", function()
        if type(lfs.link) ~= "function" then return pending("lfs.link unavailable") end
        local current_settings = mkdir(path(settings_dir, "ZenOS"))
        local outside = mkdir(path(test_root, "outside"))
        local outside_file = path(outside, "keep.txt")
        write_file(outside_file, "keep")
        assert.is_true(lfs.link(outside, path(current_settings, "linked"), true))

        assert.is_true(BrandMigration.removeSettings({
            settings_dir = settings_dir,
            lfs = lfs,
        }))

        assert.are.equal("file", lfs.attributes(outside_file, "mode"))
        assert.is_nil(lfs.attributes(current_settings, "mode"))
    end)
end)
