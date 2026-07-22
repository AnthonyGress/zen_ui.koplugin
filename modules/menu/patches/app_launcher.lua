        local function apply_app_launcher()
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local _ = require("gettext")

    local Dispatcher = require("dispatcher")
    local ActionFilter = require("modules/menu/app_launcher/action_filter")
    local Model = require("modules/menu/app_launcher/model")
    local PluginScan = require("modules/menu/app_launcher/plugin_scan")
    local ZenButton = require("common/ui/zen_button")
    local utils = require("common/utils")
    local library_font = require("modules/filebrowser/patches/library_font")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end
    require("modules/menu/patches/touch_menu_panel").install(zen_plugin)

    local Screen = Device.screen
    local _icons_dir
    do
        local root = require("common/plugin_root")
        if root then _icons_dir = root .. "/icons/" end
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.app_launcher == true
    end

    local DEFAULT_ENTRY_ICON = "lightning"
    local DEFAULT_FOLDER_ICON = "folder_open"

    local function icon_spec(name)
        local icon_name = (type(name) == "string" and name ~= "") and name or "app_launcher"
        local icon_path = _icons_dir and utils.resolveIcon(_icons_dir, icon_name)
        return icon_path, icon_name
    end

    local LauncherCell = InputContainer:extend{}
    local EmptyActionButton = InputContainer:extend{}

    function LauncherCell:init()
        self.dimen = self.dimen or Geom:new{ w = self.width, h = self.height }
        self.ges_events = {
            TapSelect = {
                GestureRange:new{ ges = "tap", range = self.dimen },
            },
        }
    end

    function LauncherCell:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        self[1]:paintTo(bb, x, y)
    end

    function LauncherCell:onTapSelect()
        if self.callback then
            self.callback()
        end
        return true
    end

    function LauncherCell:onFocus()
        self.frame.invert = true
        if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
        return true
    end

    function LauncherCell:onUnfocus()
        self.frame.invert = false
        if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
        return true
    end

    function EmptyActionButton:init()
        self.dimen = self.dimen or Geom:new{ w = self.width, h = self.height }
        self.ges_events = {
            TapSelect = {
                GestureRange:new{ ges = "tap", range = self.dimen },
            },
        }
    end

    function EmptyActionButton:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        ZenButton.paintFilled(bb, x, y, self.width, self.height, self.text, self.font_size, self.radius)
        if self.invert then
            bb:invertRect(x, y, self.width, self.height)
        end
    end

    function EmptyActionButton:onTapSelect()
        if self.callback then
            self.callback()
        end
        return true
    end

    function EmptyActionButton:onFocus()
        self.invert = true
        if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
        return true
    end

    function EmptyActionButton:onUnfocus()
        self.invert = false
        if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
        return true
    end

    local function make_cell(opts)
        local icon_path, icon_name = icon_spec(opts.icon)
        local icon_size = opts.icon_size
        local circle_size = opts.circle_size
        local circle_border = opts.circle_border
        local active = opts.active == true
        local label_face = opts.label_face
        local fg = opts.dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
        local show_label = opts.show_label ~= false
        local icon = IconWidget:new{
            file = icon_path or nil,
            icon = icon_path and nil or icon_name,
            width = icon_size,
            height = icon_size,
            alpha = not active,
        }
        if active then
            icon:_render()
            if icon._bb then
                local bb_copy = icon._bb:copy()
                bb_copy:invertRect(0, 0, bb_copy:getWidth(), bb_copy:getHeight())
                icon._bb = bb_copy
            end
        end
        local border = active and 0 or circle_border
        local icon_circle = FrameContainer:new{
            width = circle_size,
            height = circle_size,
            padding = 0,
            bordersize = border,
            radius = math.floor(circle_size / 2),
            background = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{
                    w = circle_size - border * 2,
                    h = circle_size - border * 2,
                },
                icon,
            },
        }
        local content_items = {
            align = "center",
            icon_circle,
        }
        if show_label then
            local label = TextWidget:new{
                text = opts.label,
                face = label_face,
                fgcolor = fg,
                max_width = opts.cell_w - opts.pad * 2,
            }
            table.insert(content_items, 1, VerticalSpan:new{ width = opts.pad })
            content_items[#content_items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
            content_items[#content_items + 1] = label
        end
        local content = VerticalGroup:new(content_items)
        local frame = FrameContainer:new{
            width = opts.cell_w,
            height = opts.cell_h,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = opts.cell_w, h = opts.cell_h },
                content,
            },
        }
        local cell = LauncherCell:new{
            width = opts.cell_w,
            height = opts.cell_h,
            dimen = Geom:new{ w = opts.cell_w, h = opts.cell_h },
            callback = opts.callback,
            frame = frame,
            frame,
        }
        return cell
    end

    local function current_entries(touch_menu)
        local cfg = Model.ensure(zen_plugin.config)
        local folder_id = touch_menu._app_launcher_folder_id
        if folder_id then
            local folder = select(3, Model.find_by_id(cfg.entries, folder_id))
            if folder and folder.type == "folder" then
                return folder.children or {}, folder
            end
            touch_menu._app_launcher_folder_id = nil
        end
        return cfg.entries, nil
    end

    local function show_unavailable()
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = _("Launcher entry is unavailable") })
    end

    local function find_app_launcher_settings_item(root_items)
        for _i, item in ipairs(root_items or {}) do
            if item._zen_settings_root == "launcher" then
                return item
            end
        end
    end

    local function find_launcher_buttons_item(items)
        for _i, item in ipairs(items or {}) do
            if item._zen_launcher_buttons then
                return item
            end
        end
    end

    local function open_app_launcher_settings(touch_menu, open_buttons)
        if not (touch_menu and type(touch_menu.updateItems) == "function") then
            return
        end
        local zen_tab_idx, zen_tab
        for i, tab in ipairs(touch_menu.tab_item_table or {}) do
            if tab.id == "zen_ui" then
                zen_tab_idx = i
                zen_tab = tab
                break
            end
        end
        if type(zen_tab) ~= "table" then
            return
        end
        touch_menu._zen_panel_refs = nil
        touch_menu._zen_panel_locked = false
        if touch_menu.bar and type(touch_menu.bar.switchToTab) == "function" and zen_tab_idx then
            touch_menu.bar:switchToTab(zen_tab_idx)
        elseif type(touch_menu.switchMenuTab) == "function" and zen_tab_idx then
            touch_menu:switchMenuTab(zen_tab_idx)
        else
            touch_menu.item_table = zen_tab
        end
        local root_items = type(touch_menu.item_table) == "table"
            and touch_menu.item_table.id == "zen_ui"
            and touch_menu.item_table
            or zen_tab
        local settings_item = find_app_launcher_settings_item(root_items)
        if not settings_item or type(settings_item.sub_item_table) ~= "table" then
            return
        end
        touch_menu.item_table_stack = touch_menu.item_table_stack or {}
        table.insert(touch_menu.item_table_stack, root_items)
        touch_menu.parent_id = nil
        touch_menu.item_table = settings_item.sub_item_table
        touch_menu:updateItems(1)
        if open_buttons then
            local buttons_item = find_launcher_buttons_item(settings_item.sub_item_table)
            if buttons_item and type(buttons_item.callback) == "function" then
                UIManager:nextTick(function()
                    buttons_item.callback(touch_menu)
                end)
            end
        end
    end

    local function is_library_launcher(touch_menu)
        return touch_menu
            and type(touch_menu.item_table) == "table"
            and touch_menu.item_table._zen_app_launcher_library == true
    end

    local function entry_hidden_in_context(entry, touch_menu, cfg)
        return type(entry) == "table"
            and entry.type == "action"
            and cfg.hide_reader_actions_in_library == true
            and is_library_launcher(touch_menu)
            and ActionFilter.has_reader_action(Dispatcher, entry.action)
    end

    local function activate_entry(touch_menu, entry)
        if not entry then return end
        if entry.enabled == false then return end
        local cfg = Model.ensure(zen_plugin.config)
        if entry_hidden_in_context(entry, touch_menu, cfg) then return end
        if entry._app_back then
            touch_menu._app_launcher_folder_id = nil
            touch_menu._app_launcher_page = 1
            touch_menu:updateItems(1)
            return
        end
        if entry.type == "folder" then
            touch_menu._app_launcher_folder_id = entry.id
            touch_menu._app_launcher_page = 1
            touch_menu:updateItems(1)
            return
        end
        if entry.type == "action" then
            touch_menu:closeMenu()
            UIManager:nextTick(function()
                if type(entry.action) == "table" and next(entry.action) then
                    Dispatcher:execute(entry.action)
                end
            end)
            return
        end
        if entry.type == "quick_setting" then
            local controls = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
            if not (controls and controls.activate and controls.activate(entry.quick_setting_id, touch_menu)) then
                show_unavailable()
            end
            return
        end
        if entry.type == "plugin" and type(entry.plugin) == "table" then
            local launch = PluginScan.resolve(entry.plugin.key, entry.plugin.method)
            if not launch then
                show_unavailable()
                return
            end
            touch_menu:closeMenu()
            UIManager:nextTick(function()
                pcall(launch)
            end)
        end
    end

    local function entry_available(entry, touch_menu, cfg)
        if entry_hidden_in_context(entry, touch_menu, cfg) then return false end
        if entry.type == "quick_setting" then
            local controls = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
            return controls and controls.has and controls.has(entry.quick_setting_id)
        end
        if entry.type ~= "plugin" then return true end
        local plugin = entry.plugin
        return type(plugin) == "table" and PluginScan.exists(plugin.key, plugin.method)
    end

    local function entry_active(entry)
        if entry.type == "quick_setting" then
            local controls = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
            return controls and controls.isActive and controls.isActive(entry.quick_setting_id)
        end
        if entry.type == "action" then
            return require("common/dispatch_action").isActionActive(entry.action, zen_plugin)
        end
        return false
    end

    local function entry_disabled(entry)
        if entry.enabled == false then return true end
        if entry.type ~= "quick_setting" then return false end
        local controls = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
        return controls and controls.isDisabled and controls.isDisabled(entry.quick_setting_id)
    end

    local function create_panel(touch_menu)
        local entries, folder = current_entries(touch_menu)
        local cfg = Model.ensure(zen_plugin.config)
        local show_labels = cfg.show_labels ~= false
        local panel_width = touch_menu.item_width
        local pad = Screen:scaleBySize(8)
        local inner_w = panel_width - pad * 2
        local min_cell_w = Screen:scaleBySize(96)
        local cols = math.max(2, math.floor(inner_w / min_cell_w))
        local cell_w = math.floor(inner_w / cols)
        local cell_h = Screen:scaleBySize(92)
        local row_gap = Screen:scaleBySize(8)
        local circle_size = Screen:scaleBySize(64)
        local icon_size = math.floor(circle_size * 0.5)
        local circle_border = Screen:scaleBySize(2)
        local label_size = Font.sizemap and Font.sizemap["xx_smallinfofont"] or 18
        local label_face = library_font.getFace(label_size)
        local rows = {}
        local row_counts = {}
        local row_widths = {}
        local layout_rows = {}
        local refs = { buttons = {}, layout_rows = layout_rows }
        local visible = {}

        if folder then
            visible[#visible + 1] = {
                id = "__back",
                label = _("Back"),
                icon = "chevron.left",
                _app_back = true,
            }
        end
        for _i, entry in ipairs(entries or {}) do
            if not entry_hidden_in_context(entry, touch_menu, cfg) then
                visible[#visible + 1] = entry
            end
        end

        -- Group visible entries into rows, honoring row-break marker entries
        -- as well as the column count. A break entry doesn't render a cell
        -- itself -- it just forces the next entry to start a new row.
        local all_rows = {}
        do
            local current_row
            local force_break = false
            for _i, entry in ipairs(visible) do
                if entry.type == "break" then
                    force_break = true
                else
                    if not current_row or #current_row >= cols or force_break then
                        current_row = {}
                        all_rows[#all_rows + 1] = current_row
                    end
                    current_row[#current_row + 1] = entry
                    force_break = false
                end
            end
        end

        -- Size every cell off the longest row (across all pages) so a short,
        -- forced-break row doesn't stretch its icons wider than a full row.
        local max_row_len = 0
        for _i, row in ipairs(all_rows) do
            if #row > max_row_len then max_row_len = #row end
        end
        local uniform_cell_w = math.floor(inner_w / math.max(1, max_row_len))

        -- Pagination: slice the grid so it never overflows the space a normal
        -- menu would use (bar + items area + footer). The footer up arrow then
        -- always stays on screen, matching KOReader's stock menu height.
        local cell_total_h = cell_h + row_gap
        local screen_h = (touch_menu.screen_size and touch_menu.screen_size.h) or Screen:getHeight()
        local menu_height = touch_menu.height
            and math.min(touch_menu.height, screen_h)
            or screen_h
        local bar_h = (touch_menu.bar and touch_menu.bar:getSize().h) or 0
        local footer_h = (touch_menu.footer and touch_menu.footer:getSize().h) or 0
        local footer_margin_h = (touch_menu.footer_top_margin and touch_menu.footer_top_margin:getSize().h) or 0
        local items_height = menu_height - bar_h - footer_h - footer_margin_h - pad * 2
        local rows_per_page = math.max(1, math.floor(items_height / cell_total_h) - 1)
        local page_num = math.max(1, math.ceil(#all_rows / rows_per_page))
        local page = touch_menu._app_launcher_page or 1
        if page > page_num then page = page_num end
        if page < 1 then page = 1 end
        touch_menu._app_launcher_page = page
        refs.page = page
        refs.page_num = page_num

        local page_rows = {}
        if #all_rows > 0 then
            local start_idx = (page - 1) * rows_per_page + 1
            local end_idx = math.min(start_idx + rows_per_page - 1, #all_rows)
            for i = start_idx, end_idx do
                page_rows[#page_rows + 1] = all_rows[i]
            end
        end

        if #visible == 0 then
            local button_w = math.min(inner_w, Screen:scaleBySize(190))
            local button_h = Screen:scaleBySize(46)
            local add_button = EmptyActionButton:new{
                width = button_w,
                height = button_h,
                dimen = Geom:new{ w = button_w, h = button_h },
                text = _("Add buttons"),
                font_size = Font.sizemap and Font.sizemap["smallinfofont"] or 22,
                radius = Screen:scaleBySize(10),
                callback = function()
                    open_app_launcher_settings(touch_menu, true)
                end,
            }
            layout_rows[#layout_rows + 1] = { add_button }
            refs.buttons[#refs.buttons + 1] = {
                widget = add_button,
                callback = function()
                    add_button.callback()
                end,
            }
            touch_menu._zen_panel_refs = refs
            return VerticalGroup:new{
                align = "center",
                VerticalSpan:new{ width = Screen:scaleBySize(16) },
                TextWidget:new{
                    text = _("Launcher"),
                    face = library_font.getFace(Font.sizemap and Font.sizemap["smallinfofont"] or 22),
                },
                VerticalSpan:new{ width = Screen:scaleBySize(12) },
                CenterContainer:new{
                    dimen = Geom:new{ w = panel_width, h = button_h },
                    add_button,
                },
                VerticalSpan:new{ width = Screen:scaleBySize(20) },
            }
        end

        local panel = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = pad },
        }

        for _i, row_entries in ipairs(page_rows) do
            rows[#rows + 1] = HorizontalGroup:new{ align = "top" }
            row_counts[#rows] = 0
            row_widths[#rows] = uniform_cell_w
            layout_rows[#layout_rows + 1] = {}
            for _j, entry in ipairs(row_entries) do
                row_counts[#rows] = row_counts[#rows] + 1
                local dim = not entry._app_back
                    and (not entry_available(entry, touch_menu, cfg) or entry_disabled(entry))
                local cell = make_cell{
                    cell_w = row_widths[#rows] or cell_w,
                    cell_h = cell_h,
                    pad = pad,
                    icon_size = icon_size,
                    circle_size = circle_size,
                    circle_border = circle_border,
                    label_face = label_face,
                    label = Model.display_label(entry),
                    show_label = show_labels,
                    icon = entry.icon or (entry.type == "folder" and DEFAULT_FOLDER_ICON or DEFAULT_ENTRY_ICON),
                    dim = dim,
                    active = not dim and entry_active(entry),
                    callback = not dim and function()
                        activate_entry(touch_menu, entry)
                    end or nil,
                }
                rows[#rows][#rows[#rows] + 1] = cell
                layout_rows[#layout_rows][#layout_rows[#layout_rows] + 1] = cell
                refs.buttons[#refs.buttons + 1] = {
                    widget = cell,
                    callback = cell.callback and function()
                        cell.callback()
                    end or nil,
                }
            end
        end

        for _i, row in ipairs(rows) do
            local used = (row_counts[_i] or 0) * (row_widths[_i] or cell_w)
            local lead = math.max(pad, math.floor((panel_width - used) / 2))
            local trail = panel_width - used - lead
            table.insert(row, 1, HorizontalSpan:new{ width = lead })
            row[#row + 1] = HorizontalSpan:new{ width = math.max(0, trail) }
            panel[#panel + 1] = row
            if _i < #rows then
                panel[#panel + 1] = VerticalSpan:new{ width = row_gap }
            end
        end
        panel[#panel + 1] = VerticalSpan:new{ width = pad }
        refs.goto_page = function(nb)
            if page_num <= 1 then return false end
            if nb > page_num then nb = 1 elseif nb < 1 then nb = page_num end
            if nb == page then return false end
            touch_menu._app_launcher_page = nb
            touch_menu:updateItems(1)
            return true
        end
        touch_menu._zen_panel_refs = refs
        return panel
    end

    rawset(_G, "__ZEN_UI_BUILD_APP_LAUNCHER_PREVIEW", function(item_width)
        return create_panel{
            item_width = item_width,
            closeMenu = function() end,
            updateItems = function() end,
        }
    end)

    local function make_app_launcher_tab(library_context)
        return {
            id = "app_launcher",
            icon = "app_launcher",
            remember = true,
            panel = create_panel,
            _zen_app_launcher_library = library_context == true,
        }
    end

    local function find_tab(tab_table, id)
        for i, tab in ipairs(tab_table or {}) do
            if tab.id == id then return i end
        end
    end

    local function sync_tab(menu_self, library_context)
        if type(menu_self.tab_item_table) ~= "table" then return end
        local existing = find_tab(menu_self.tab_item_table, "app_launcher")
        if not is_enabled() then
            if existing then
                table.remove(menu_self.tab_item_table, existing)
            end
            return
        end
        if existing then
            menu_self.tab_item_table[existing]._zen_app_launcher_library = library_context == true
            return
        end
        local zen_pos = find_tab(menu_self.tab_item_table, "zen_ui")
        local qs_pos = find_tab(menu_self.tab_item_table, "quicksettings")
        table.insert(menu_self.tab_item_table,
            zen_pos and (zen_pos + 1) or qs_pos and (qs_pos + 1) or 1,
            make_app_launcher_tab(library_context))
    end

    local function patch_menu_class(menu_class, library_context)
        if not menu_class or menu_class.__zen_app_launcher_tab_patched then return end
        menu_class.__zen_app_launcher_tab_patched = true
        local orig_sut = menu_class.setUpdateItemTable
        menu_class.setUpdateItemTable = function(self)
            orig_sut(self)
            sync_tab(self, library_context)
        end
        local orig_onShowMenu = menu_class.onShowMenu
        if type(orig_onShowMenu) == "function" then
            menu_class.onShowMenu = function(self, ...)
                sync_tab(self, library_context)
                return orig_onShowMenu(self, ...)
            end
        end
    end

    local ok_fm, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if ok_fm then patch_menu_class(FileManagerMenu, true) end
    local ok_rm, ReaderMenu = pcall(require, "apps/reader/modules/readermenu")
    if ok_rm then patch_menu_class(ReaderMenu, false) end

    local TouchMenu = require("ui/widget/touchmenu")
    if not TouchMenu.__zen_app_launcher_open_first_patched then
        TouchMenu.__zen_app_launcher_open_first_patched = true
        local orig_init = TouchMenu.init
        TouchMenu.init = function(self, ...)
            if is_enabled() and Model.ensure().open_first == true then
                local index = find_tab(self.tab_item_table, "app_launcher")
                if index then self.last_index = index end
            end
            return orig_init(self, ...)
        end
    end
    if not TouchMenu.__zen_app_launcher_back_patched then
        TouchMenu.__zen_app_launcher_back_patched = true
        local function reset_folder(self, refresh)
            if not self._app_launcher_folder_id then return false end
            self._app_launcher_folder_id = nil
            self._app_launcher_page = 1
            if refresh and self.updateItems then
                self:updateItems(1)
            end
            return true
        end

        local function leave_folder(self)
            if self.item_table and self.item_table.id == "app_launcher" then
                return reset_folder(self, true)
            end
            return false
        end

        local orig_switchMenuTab = TouchMenu.switchMenuTab
        TouchMenu.switchMenuTab = function(self, tab_num, ...)
            local current_is_launcher = self.item_table and self.item_table.id == "app_launcher"
            local next_tab = type(self.tab_item_table) == "table" and self.tab_item_table[tab_num] or nil
            if current_is_launcher and (not next_tab or next_tab.id ~= "app_launcher") then
                reset_folder(self, false)
                self._app_launcher_page = 1
            end
            return orig_switchMenuTab(self, tab_num, ...)
        end

        local orig_onCloseWidget = TouchMenu.onCloseWidget
        TouchMenu.onCloseWidget = function(self, ...)
            reset_folder(self, false)
            if orig_onCloseWidget then
                return orig_onCloseWidget(self, ...)
            end
        end

        local orig_onClose = TouchMenu.onClose
        TouchMenu.onClose = function(self, ...)
            if self.item_table and self.item_table.id == "app_launcher" then
                reset_folder(self, false)
            end
            if orig_onClose then
                return orig_onClose(self, ...)
            end
            return false
        end

        local orig_onBack = TouchMenu.onBack
        TouchMenu.onBack = function(self, ...)
            if leave_folder(self) then
                return true
            end
            return orig_onBack(self, ...)
        end

        local orig_onFocusMove = TouchMenu.onFocusMove
        TouchMenu.onFocusMove = function(self, args)
            local dx = type(args) == "table" and args[1] or 0
            if dx < 0 and self.selected and self.selected.x == 1 and leave_folder(self) then
                return true
            end
            return orig_onFocusMove(self, args)
        end
    end
end

return apply_app_launcher
