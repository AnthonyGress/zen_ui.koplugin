-- modules/filebrowser/patches/library_background.lua
-- Paints the configured library background image behind the file browser.
-- The hook lives on FileManager because FileChooser and its root frame are
-- rebuilt during navigation and menu refreshes.

local function apply_library_background()
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok_fm or type(FileManager) ~= "table" then return end
    if FileManager._zen_bg_patched then return end
    FileManager._zen_bg_patched = true

    local Device = require("device")
    local Background = require("common/ui/background")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local Screen = Device.screen
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function background_path()
        return Background.library_path(zen_plugin)
    end

    local function clear_backgrounds(fm)
        if not fm then return end
        Background.clearWhiteBackgrounds(fm[1], 14)
        if fm.file_chooser then
            Background.clearWhiteBackgrounds(fm.file_chooser, 14)
        end
    end

    local function is_active()
        return background_path() ~= ""
    end

    local ok_tbw, TextBoxWidget = pcall(require, "ui/widget/textboxwidget")
    if ok_tbw and TextBoxWidget and not TextBoxWidget._zen_bg_patched then
        local Blitbuffer = require("ffi/blitbuffer")
        local orig_textbox_paintTo = TextBoxWidget.paintTo
        TextBoxWidget._zen_bg_patched = true
        TextBoxWidget.paintTo = function(tbw_self, bb, x, y)
            if not (is_active() and Background.isWhite(tbw_self.bgcolor)) then
                return orig_textbox_paintTo(tbw_self, bb, x, y)
            end
            if not tbw_self._bb then
                tbw_self:_updateLayout()
            end
            if not tbw_self._bb then
                return orig_textbox_paintTo(tbw_self, bb, x, y)
            end
            tbw_self.dimen.x, tbw_self.dimen.y = x, y
            local w = tbw_self.width
            local h = tbw_self._bb:getHeight()
            if not tbw_self._zen_bg_tmp_bb
                    or tbw_self._zen_bg_tmp_bb:getWidth() ~= w
                    or tbw_self._zen_bg_tmp_bb:getHeight() ~= h then
                if tbw_self._zen_bg_tmp_bb then
                    tbw_self._zen_bg_tmp_bb:free()
                end
                tbw_self._zen_bg_tmp_bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
            end
            local tmp = tbw_self._zen_bg_tmp_bb
            tmp:fill(Blitbuffer.COLOR_WHITE)
            tmp:blitFrom(tbw_self._bb, 0, 0, 0, 0, w, h)
            tmp:invertRect(0, 0, w, h)
            bb:colorblitFromRGB32(tmp, x, y, 0, 0, w, h,
                tbw_self.fgcolor or Blitbuffer.COLOR_BLACK)
        end

        local orig_textbox_free = TextBoxWidget.free
        TextBoxWidget.free = function(tbw_self, ...)
            if tbw_self._zen_bg_tmp_bb then
                tbw_self._zen_bg_tmp_bb:free()
                tbw_self._zen_bg_tmp_bb = nil
            end
            if orig_textbox_free then
                return orig_textbox_free(tbw_self, ...)
            end
        end
    end

    local ok_iw, IconWidget = pcall(require, "ui/widget/iconwidget")
    if ok_iw and IconWidget and not IconWidget._zen_bg_patched then
        local orig_icon_init = IconWidget.init
        IconWidget._zen_bg_patched = true
        IconWidget.init = function(iw_self, ...)
            orig_icon_init(iw_self, ...)
            if is_active() and iw_self.alpha == nil then
                iw_self.alpha = true
                iw_self.original_in_nightmode = false
            end
        end
    end

    local ok_uc, UnderlineContainer = pcall(require, "ui/widget/container/underlinecontainer")
    if ok_uc and UnderlineContainer and not UnderlineContainer._zen_bg_patched then
        local Geom = require("ui/geometry")
        local orig_underline_paintTo = UnderlineContainer.paintTo
        UnderlineContainer._zen_bg_patched = true
        UnderlineContainer.paintTo = function(uc_self, bb, x, y)
            if not (is_active() and Background.isWhite(uc_self.color)) then
                return orig_underline_paintTo(uc_self, bb, x, y)
            end
            local container_size = uc_self:getSize()
            if not uc_self.dimen then
                uc_self.dimen = Geom:new{
                    x = x, y = y,
                    w = container_size.w,
                    h = container_size.h,
                }
            else
                uc_self.dimen.x = x
                uc_self.dimen.y = y
            end
            local content_size = uc_self[1]:getSize()
            local p_y = y
            if uc_self.vertical_align == "center" then
                p_y = math.floor((container_size.h - content_size.h) / 2) + y
            elseif uc_self.vertical_align == "bottom" then
                p_y = (container_size.h - content_size.h) + y
            end
            uc_self[1]:paintTo(bb, x, p_y)
        end
    end

    local orig_setupLayout = FileManager.setupLayout
    function FileManager:setupLayout(...)
        local ret = orig_setupLayout(self, ...)
        if is_active() then
            clear_backgrounds(self)
        end
        return ret
    end

    local orig_paintTo = FileManager.paintTo
    function FileManager:paintTo(bb, x, y)
        local path = background_path()
        if path ~= "" then
            clear_backgrounds(self)
            Background.paint(bb, 0, 0, Screen:getWidth(), Screen:getHeight(), path)
        end
        if orig_paintTo then
            return orig_paintTo(self, bb, x, y)
        end
        return WidgetContainer.paintTo(self, bb, x, y)
    end
end

return apply_library_background
