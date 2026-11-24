local tags = require "ass_tags.tags"

local t = hikari.i18n.t

local function style_fonts(document)
    local listed = hikari.call("styles.list", {document = document})
    local out, seen = {}, {}
    for _, style in ipairs(listed and listed.styles or {}) do
        local font = style.fontname
        if font and font ~= "" and not seen[font] then
            seen[font] = true
            out[#out + 1] = font
        end
    end
    return out
end

hikari.providers.completion(function(r)
    return tags.complete(r.text, r.offset, t, function()
        return style_fonts(r.document)
    end)
end)

hikari.providers.hover(function(r)
    return tags.hover(r.text, r.offset, t)
end)
