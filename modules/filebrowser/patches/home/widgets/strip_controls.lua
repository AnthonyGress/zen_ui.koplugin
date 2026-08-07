local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonModel = require("common/nav_button_model")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local WidgetResources = require("common/widget_resources")
local icons = require("common/inline_icon_map")

local M = {}

local function rounded_tabs_enabled()
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if plugin and type(plugin.config) == "table"
            and type(plugin.config.features) == "table" then
        return plugin.config.features.browser_cover_rounded_corners == true
    end
    local ok, config = pcall(require, "config/manager")
    local cfg = ok and type(config.get) == "function" and config.get() or nil
    return type(cfg) == "table" and type(cfg.features) == "table"
        and cfg.features.browser_cover_rounded_corners == true
end

local function visible_entries(controls)
    local entries = {}
    local seen = {}
    for _i, id in ipairs(controls.order or {}) do
        if #entries >= 7 then break end
        local entry = not seen[id] and controls.show_buttons[id] == true
            and ButtonModel.find(controls, id) or nil
        if entry then
            entries[#entries + 1] = entry
            seen[id] = true
        end
    end
    return entries
end

local function fit_face(labels, width)
    local size = Device.screen:scaleBySize(10)
    local minimum = Device.screen:scaleBySize(7)
    while size > minimum do
        local face = Font:getFace("smallinfofont", size)
        local fits = true
        for _i, label in ipairs(labels) do
            local probe = TextWidget:new{ text = label, face = face }
            local needed = probe:getSize().w
            WidgetResources.free(probe)
            if needed > width - Device.screen:scaleBySize(6) then
                fits = false
                break
            end
        end
        if fits then return face end
        size = size - 1
    end
    return Font:getFace("smallinfofont", minimum)
end

local function tap_widget(content, width, height, callback)
    if not Device:isTouchDevice() then return content end
    local input = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = {
            TapStripControl = {
                GestureRange:new{ ges = "tap", range = Geom:new{
                    x = 0, y = 0, w = Device.screen:getWidth(), h = Device.screen:getHeight(),
                } },
            },
        },
    }
    input.onTapStripControl = function(self, _arg, ges)
        if not (self.dimen and ges and ges.pos and self.dimen:contains(ges.pos)) then
            return false
        end
        callback()
        return true
    end
    input[1] = content
    return input
end

local function square_inner_corners(frame, side, width, height, radius)
    if radius <= 0 then return frame end
    local paint_to = frame.paintTo
    frame.paintTo = function(self, bb, x, y)
        paint_to(self, bb, x, y)
        local border = math.max(1, tonumber(self.bordersize) or 1)
        local color = self.color or Blitbuffer.COLOR_BLACK
        local corner_x = side == "left" and x or x + width - radius
        local edge_x = side == "left" and x or x + width - border
        if self.background then
            bb:paintRect(corner_x, y, radius, radius, self.background)
            bb:paintRect(corner_x, y + height - radius, radius, radius, self.background)
        end
        bb:paintRect(corner_x, y, radius, border, color)
        bb:paintRect(corner_x, y + height - border, radius, border, color)
        bb:paintRect(edge_x, y, border, radius, color)
        bb:paintRect(edge_x, y + height - radius, border, radius, color)
    end
    return frame
end

function M.build(opts)
    local controls = opts.controls
    local entries = visible_entries(controls)
    local height = opts.height
    local search_width = height
    local button_area = math.max(1, opts.width - search_width)
    local button_width = #entries > 0 and math.floor(button_area / #entries) or 0
    local remainder = #entries > 0 and button_area - button_width * #entries or button_area
    local labels = {}
    for _i, entry in ipairs(entries) do
        labels[#labels + 1] = entry.id == opts.active_id and opts.active_group
            or ButtonModel.label(controls, entry)
    end
    local face = fit_face(labels, math.max(1, button_width))
    local row = HorizontalGroup:new{ align = "center" }
    local targets = {}
    local radius = rounded_tabs_enabled() and Device.screen:scaleBySize(4) or 0
    local border_size = math.max(2, Device.screen:scaleBySize(1))
    local side_padding = Device.screen:scaleBySize(4)

    for index, entry in ipairs(entries) do
        local cell_width = button_width + (index <= remainder and 1 or 0)
        local active = entry.id == opts.active_id
        local label = labels[index]
        local cell = FrameContainer:new{
            width = cell_width,
            height = height,
            padding = 0,
            bordersize = border_size,
            color = Blitbuffer.COLOR_BLACK,
            radius = index == 1 and radius or 0,
            background = active and Blitbuffer.COLOR_BLACK
                or Background.tile_bg(Blitbuffer.COLOR_WHITE),
            CenterContainer:new{
                dimen = Geom:new{
                    w = math.max(1, cell_width - border_size * 2),
                    h = math.max(1, height - border_size * 2),
                },
                TextWidget:new{
                    text = label,
                    face = face,
                    padding = 0,
                    max_width = math.max(1, cell_width - side_padding * 2),
                    truncate_with_ellipsis = true,
                    fgcolor = active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                },
            },
        }
        if index == 1 then
            square_inner_corners(cell, "right", cell_width, height, radius)
        end
        local activate = function()
            if ButtonModel.isSource(entry) then
                return opts.on_source(entry)
            end
            return opts.on_action(entry)
        end
        local widget = tap_widget(cell, cell_width, height, activate)
        if type(opts.prepare_focus) == "function" then
            local target = {
                key = "strip-control:" .. tostring(entry.id),
                subrow = 0,
                col = index,
                width = cell_width,
                height = height,
                activate = activate,
            }
            widget = opts.prepare_focus(target, widget)
            targets[#targets + 1] = target
        end
        row[#row + 1] = widget
    end

    local search_content = FrameContainer:new{
        width = search_width,
        height = height,
        padding = 0,
        bordersize = border_size,
        color = Blitbuffer.COLOR_BLACK,
        radius = radius,
        background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
        CenterContainer:new{
            dimen = Geom:new{
                w = math.max(1, search_width - border_size * 2),
                h = math.max(1, height - border_size * 2),
            },
            TextWidget:new{
                text = icons.search,
                face = Font:getFace("smallinfofont", Device.screen:scaleBySize(12)),
                padding = 0,
            },
        },
    }
    if #entries > 0 then
        square_inner_corners(search_content, "left", search_width, height, radius)
    end
    local search = tap_widget(search_content, search_width, height, opts.on_search)
    if type(opts.prepare_focus) == "function" then
        local target = {
            key = "strip-control:search",
            subrow = 0,
            col = #entries + 1,
            width = search_width,
            height = height,
            activate = opts.on_search,
        }
        search = opts.prepare_focus(target, search)
        targets[#targets + 1] = target
    end
    row[#row + 1] = search
    return row, targets
end

return M
