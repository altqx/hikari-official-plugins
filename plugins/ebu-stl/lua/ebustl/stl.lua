local text = require "ebustl.text"

local M = {}

local TEXT_BYTES = 112
local ITALIC_ON, ITALIC_OFF, UNDERLINE_ON, UNDERLINE_OFF = "\128", "\129", "\130", "\131"
local DOUBLE_HEIGHT, START_BOX, END_BOX, NEW_ROW = "\13", "\11\11", "\10\10", "\138\138"
local LAST_ROW, BOTTOM_MARGIN, ROWS_PER_ROW = 23, 2, 2

-- EBU Tech 3264 Appendix 3; ISO 639-1 codes and English names.
local LANGUAGES = {
    sq = 0x01, br = 0x02, ca = 0x03, hr = 0x04, cy = 0x05, cs = 0x06, da = 0x07, de = 0x08, en = 0x09, es = 0x0A,
    eo = 0x0B, et = 0x0C, eu = 0x0D, fo = 0x0E, fr = 0x0F, fy = 0x10, ga = 0x11, gd = 0x12, gl = 0x13, is = 0x14,
    it = 0x15, se = 0x16, la = 0x17, lv = 0x18, lb = 0x19, lt = 0x1A, hu = 0x1B, mt = 0x1C, nl = 0x1D, no = 0x1E,
    nb = 0x1E, nn = 0x1E, oc = 0x1F, pl = 0x20, pt = 0x21, ro = 0x22, rm = 0x23, sr = 0x24, sk = 0x25, sl = 0x26,
    fi = 0x27, sv = 0x28, tr = 0x29,
    albanian = 0x01, breton = 0x02, catalan = 0x03, croatian = 0x04, welsh = 0x05, czech = 0x06, danish = 0x07,
    german = 0x08, english = 0x09, spanish = 0x0A, esperanto = 0x0B, estonian = 0x0C, basque = 0x0D,
    faroese = 0x0E, french = 0x0F, frisian = 0x10, irish = 0x11, gaelic = 0x12, galician = 0x13,
    icelandic = 0x14, italian = 0x15, latin = 0x17, latvian = 0x18, luxembourgish = 0x19, lithuanian = 0x1A,
    hungarian = 0x1B, maltese = 0x1C, dutch = 0x1D, norwegian = 0x1E, occitan = 0x1F, polish = 0x20,
    portuguese = 0x21, romanian = 0x22, romansh = 0x23, serbian = 0x24, slovak = 0x25, slovenian = 0x26,
    finnish = 0x27, swedish = 0x28, turkish = 0x29,
}

local function info(doc, key)
    for _, entry in ipairs(doc.info or {}) do
        if type(entry) == "table" and entry.key == key then return entry.value end
    end
    return nil
end

function M.language(value)
    if type(value) ~= "string" then return 0 end
    local key = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return LANGUAGES[key] or LANGUAGES[key:match("^(%a%a)[_%-]") or ""] or 0
end

-- 25 or 30: the timebase EBU STL has nearest the video's frame rate.
function M.timebase(frameRate)
    local fps = tonumber(frameRate) or 25
    return math.abs(fps - 30) < math.abs(fps - 25) and 30 or 25
end

local function frames(ms, fps)
    return math.floor(ms * fps / 1000 + 0.5)
end

local function timecode(ms, fps)
    local f = frames(math.max(ms, 0), fps)
    local seconds = math.floor(f / fps)
    return math.floor(seconds / 3600) % 24, math.floor(seconds / 60) % 60, seconds % 60, f % fps
end

local function encodeRow(row, unsupported)
    local out = {DOUBLE_HEIGHT, START_BOX}
    local italic, underline = false, false
    for _, cell in ipairs(row) do
        if cell.italic ~= italic then
            out[#out + 1] = cell.italic and ITALIC_ON or ITALIC_OFF
            italic = cell.italic
        end
        if cell.underline ~= underline then
            out[#out + 1] = cell.underline and UNDERLINE_ON or UNDERLINE_OFF
            underline = cell.underline
        end
        local bytes = text.encode(cell.ch)
        if not bytes then
            unsupported[1] = true
            bytes = "?"
        end
        out[#out + 1] = bytes
    end
    if italic then out[#out + 1] = ITALIC_OFF end
    if underline then out[#out + 1] = UNDERLINE_OFF end
    out[#out + 1] = END_BOX
    return table.concat(out)
end

local function u16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function block(number, extension, tci, tco, vp, jc, field)
    return "\0" .. u16(number) .. string.char(extension, 0) .. string.char(tci[1], tci[2], tci[3], tci[4]) ..
        string.char(tco[1], tco[2], tco[3], tco[4]) .. string.char(vp, jc, 0) .. field ..
        string.rep("\143", TEXT_BYTES - #field)
end

local function stylesByName(doc)
    local out = {}
    for _, style in ipairs(doc.styles or {}) do
        if type(style) == "table" and style.name then out[style.name] = style end
    end
    return out
end

local function field(width, value)
    local s = tostring(value)
    return string.rep("0", width - #s) .. s
end

-- The .stl file for a hikari.document.read snapshot, and the rows of the Lines cut to fit or holding
-- characters EBU STL lacks. options: {frameRate, date = "YYMMDD"}.
function M.build(doc, options)
    options = options or {}
    local fps = M.timebase(options.frameRate)
    local styles = stylesByName(doc)
    local lines = {}
    for _, line in ipairs(doc.lines or {}) do
        if not line.comment and (line["end"] or 0) > (line.start or 0) then lines[#lines + 1] = line end
    end
    table.sort(lines, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return (a.row or 0) < (b.row or 0)
    end)

    local blocks, cut, unsupportedRows = {}, {}, {}
    local subtitles, first = 0, nil
    for _, line in ipairs(lines) do
        local parsed, align = text.parse(line.text or "", styles[line.style])
        local rows = text.wrap(parsed)
        if #rows > 0 then
            if #rows > text.ROWS then
                cut[#cut + 1] = line.row
                while #rows > text.ROWS do table.remove(rows) end
            end
            local unsupported = {}
            local encoded = {}
            for k, row in ipairs(rows) do encoded[k] = encodeRow(row, unsupported) end
            if unsupported[1] then unsupportedRows[#unsupportedRows + 1] = line.row end
            local bytes = table.concat(encoded, NEW_ROW)
            local vp = align >= 7 and 1 or LAST_ROW - BOTTOM_MARGIN - (#rows - 1) * ROWS_PER_ROW
            local column = (align - 1) % 3
            local jc = column == 0 and 1 or column == 1 and 2 or 3
            local tci = {timecode(line.start, fps)}
            local tco = {timecode(line["end"], fps)}
            first = first or tci
            local chunks = math.max(1, math.ceil(#bytes / TEXT_BYTES))
            for k = 1, chunks do
                local part = bytes:sub((k - 1) * TEXT_BYTES + 1, k * TEXT_BYTES)
                blocks[#blocks + 1] = block(subtitles, k == chunks and 0xFF or k - 1, tci, tco, vp, jc, part)
            end
            subtitles = subtitles + 1
        end
    end

    local language = M.language(info(doc, "Language"))
    local date = options.date or "000000"
    local tcf = first and string.format("%02d%02d%02d%02d", first[1], first[2], first[3], first[4]) or "00000000"
    local gsi = table.concat({
        "850", fps == 30 and "STL30.01" or "STL25.01", "1", "00", string.format("%02X", language),
        text.cp850(info(doc, "Title") or doc.title, 32), text.cp850("", 32), text.cp850("", 32), text.cp850("", 32),
        text.cp850(info(doc, "Translation") or "", 32), text.cp850("", 32), text.cp850("", 16),
        date, date, "00", field(5, #blocks), field(5, subtitles), "001", "40", "23", "1", "00000000", tcf,
        "1", "1", "   ", text.cp850("", 32), text.cp850(info(doc, "Original Editing") or "", 32), text.cp850("", 32),
        string.rep(" ", 75), string.rep(" ", 576),
    })
    assert(#gsi == 1024, "GSI block is " .. #gsi .. " bytes")
    return gsi .. table.concat(blocks), {cut = cut, unsupported = unsupportedRows}
end

return M
