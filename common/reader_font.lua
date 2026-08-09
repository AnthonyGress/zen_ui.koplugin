local Font = require("ui/font")

local M = {}

function M.getInfo(ui, fallback_size)
    local settings_reader_font
    if ui and ui.doc_settings and type(ui.doc_settings.readSetting) == "function" then
        settings_reader_font = ui.doc_settings:readSetting("font_face")
    end
    local reader_font = ui and ui.font and ui.font.font_face
        or settings_reader_font
        or (ui and ui.document and ui.document.default_font)
    local reader_config = ui and ui.document and ui.document.configurable
        or (ui and ui.configurable)
    local reader_font_size = tonumber(reader_config and reader_config.font_size)
        or fallback_size
    local reader_font_file, reader_font_index

    if reader_font then
        local ok_cre, CreDocument = pcall(require, "document/credocument")
        if ok_cre and CreDocument then
            local ok_engine, cre = pcall(CreDocument.engineInit, CreDocument)
            if ok_engine and cre and cre.getFontFaceFilenameAndFaceIndex then
                reader_font_file, reader_font_index =
                    cre.getFontFaceFilenameAndFaceIndex(reader_font)
                if not reader_font_file then
                    reader_font_file, reader_font_index =
                        cre.getFontFaceFilenameAndFaceIndex(reader_font, nil, true)
                end
            end
        end
    end

    return {
        source = reader_font_file or reader_font or "cfont",
        index = reader_font_index,
        name = reader_font,
        size = reader_font_size,
    }
end

function M.getFace(info, size)
    local font_size = size or info.size
    local ok, face = pcall(Font.getFace, Font, info.source, font_size, info.index)
    if ok and face then return face end
    if info.source == info.name or not info.name then return nil end
    ok, face = pcall(Font.getFace, Font, info.name, font_size)
    return ok and face or nil
end

function M.withMenuFaces(info, callback, menu_faces)
    menu_faces = menu_faces or { smallinfofont = true, infont = true }
    local get_face = Font.getFace
    Font.getFace = function(font, face_name, size, index)
        if face_name and menu_faces[face_name] then
            local face = get_face(font, info.source, size, info.index)
            if face then return face end
        end
        return get_face(font, face_name, size, index)
    end

    local ok, result = pcall(callback)
    Font.getFace = get_face
    if not ok then error(result, 0) end
    return result
end

return M
