local base64 = require "ebustl.base64"
local notice = require "ebustl.notice"
local stl = require "ebustl.stl"

local function today()
    local ok, date = pcall(function() return os.date("%y%m%d") end)
    return ok and date or nil
end

hikari.formats.exporter("ebu-stl", function(doc, options)
    local frameRate = options.frameRate
    if frameRate == hikari.null then frameRate = nil end
    local bytes, report = stl.build(doc, {frameRate = frameRate, date = today()})
    local warning = notice.text(report, hikari.i18n.t)
    if warning then
        hikari.notify(warning, "warning")
    end
    return base64.encode(bytes), "base64"
end)
