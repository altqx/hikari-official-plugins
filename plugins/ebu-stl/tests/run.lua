package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local base64 = require "ebustl.base64"
local notice = require "ebustl.notice"
local stl = require "ebustl.stl"
local text = require "ebustl.text"

local passed, failed = 0, {}

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failed[#failed + 1] = name .. ": " .. tostring(err)
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error((what or "value") .. "\n  expected " .. string.format("%q", tostring(expected)) ..
            "\n  actual   " .. string.format("%q", tostring(actual)), 2)
    end
end

local strings = {}
do
    local f = assert(io.open("i18n/en.json", "rb"))
    local json = f:read("*a")
    f:close()
    for key, value in json:gmatch('"([^"]+)":%s*"([^"]*)"') do strings[key] = value end
end

local function t(key, ...)
    local s = strings[key] or key
    local args = {...}
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end

local function line(row, start, finish, body, extra)
    local l = {id = row, row = row, start = start, ["end"] = finish, style = "Default", text = body, comment = false}
    for k, v in pairs(extra or {}) do l[k] = v end
    return l
end

local function doc(lines, info, styles)
    return {title = "episode.ass", lines = lines, info = info or {},
            styles = styles or {{name = "Default", alignment = "2", italic = "0", underline = "0"}}}
end

local function tti(file, n)
    local at = 1024 + (n - 1) * 128
    return file:sub(at + 1, at + 128)
end

local function textField(block)
    return (block:sub(17):gsub("\143+$", ""))
end

local function bytes(...)
    return string.char(...)
end

test("the GSI block is 1024 bytes with the header fields in place", function()
    local file = stl.build(doc({line(1, 61000, 63500, "Hello")},
        {{key = "Title", value = "Pilot"}, {key = "Language", value = "en_GB"}}), {frameRate = 25, date = "261117"})
    eq(#file, 1024 + 128, "size")
    eq(file:sub(1, 3), "850", "CPN")
    eq(file:sub(4, 11), "STL25.01", "DFC")
    eq(file:sub(12, 12), "1", "DSC")
    eq(file:sub(13, 14), "00", "CCT")
    eq(file:sub(15, 16), "09", "LC")
    eq(file:sub(17, 48), "Pilot" .. string.rep(" ", 27), "OPT")
    eq(file:sub(225, 230), "261117", "CD")
    eq(file:sub(231, 236), "261117", "RD")
    eq(file:sub(239, 243), "00001", "TNB")
    eq(file:sub(244, 248), "00001", "TNS")
    eq(file:sub(249, 251), "001", "TNG")
    eq(file:sub(252, 253), "40", "MNC")
    eq(file:sub(254, 255), "23", "MNR")
    eq(file:sub(256, 256), "1", "TCS")
    eq(file:sub(257, 264), "00000000", "TCP")
    eq(file:sub(265, 272), "00010100", "TCF")
    eq(file:sub(273, 274), "11", "TND DSN")
end)

test("a TTI block holds the number, timecodes, position and boxed double-height text", function()
    local file = stl.build(doc({line(1, 1000, 2040, "Hi"), line(2, 3000, 4000, "One\\NTwo")}), {frameRate = 25})
    local first, second = tti(file, 1), tti(file, 2)
    eq(#first, 128, "block size")
    eq(first:sub(1, 1), "\0", "SGN")
    eq(first:sub(2, 3), bytes(0, 0), "SN")
    eq(second:sub(2, 3), bytes(1, 0), "second SN")
    eq(first:sub(4, 4), "\255", "EBN")
    eq(first:sub(5, 5), "\0", "CS")
    eq(first:sub(6, 9), bytes(0, 0, 1, 0), "TCI")
    eq(first:sub(10, 13), bytes(0, 0, 2, 1), "TCO")
    eq(first:byte(14), 21, "VP of one row")
    eq(second:byte(14), 19, "VP of two rows")
    eq(first:byte(15), 2, "JC centred")
    eq(first:byte(16), 0, "CF")
    eq(textField(first), "\13\11\11Hi\10\10", "TF")
    eq(textField(second), "\13\11\11One\10\10\138\138\13\11\11Two\10\10", "two rows")
    eq(first:sub(-1), "\143", "padding")
end)

test("\\an and the Style place the subtitle at the top or bottom and justify it", function()
    local file = stl.build(doc({line(1, 0, 1000, "{\\an8}Top"), line(2, 1000, 2000, "{\\an1}Left"),
        line(3, 2000, 3000, "Right", {style = "Side"})}, {},
        {{name = "Default", alignment = "2"}, {name = "Side", alignment = "9"}}), {})
    eq(tti(file, 1):byte(14), 1, "top VP")
    eq(tti(file, 1):byte(15), 2, "centred")
    eq(tti(file, 2):byte(14), 21, "bottom VP")
    eq(tti(file, 2):byte(15), 1, "left")
    eq(tti(file, 3):byte(14), 1, "Style top")
    eq(tti(file, 3):byte(15), 3, "right")
end)

test("italic and underline become teletext codes and close at each row's end", function()
    local file = stl.build(doc({line(1, 0, 1000, "{\\i1}It{\\i0} and {\\u1}un\\Nder{\\r}x"),
        line(2, 1000, 2000, "Whole", {style = "Lean"})}, {},
        {{name = "Default", alignment = "2"}, {name = "Lean", alignment = "2", italic = "-1"}}), {})
    eq(textField(tti(file, 1)),
        "\13\11\11\128It\129 and \130un\131\10\10\138\138\13\11\11\130der\131x\10\10", "codes")
    eq(textField(tti(file, 2)), "\13\11\11\128Whole\129\10\10", "Style italic")
end)

test("rows wrap at 40 characters and a third row is cut and named by its row number", function()
    local long = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen"
    local file, report = stl.build(doc({line(4, 0, 1000, "short"), line(7, 1000, 2000, long),
        line(9, 2000, 3000, "a\\Nb")}), {})
    local field = textField(tti(file, 2))
    eq(field, "\13\11\11one two three four five six seven eight\10\10\138\138" ..
        "\13\11\11nine ten eleven twelve thirteen fourteen\10\10", "two rows of 40")
    eq(#report.cut, 1, "cut count")
    eq(report.cut[1], 7, "cut row")
    eq(notice.text(report, t), "EBU STL holds 2 rows of 40 characters, so Line 7 was cut.", "notice")
    local _, many = stl.build(doc({line(2, 0, 1000, "a\\Nb\\Nc"), line(5, 1000, 2000, "d\\Ne\\Nf")}), {})
    eq(notice.text(many, t), "EBU STL holds 2 rows of 40 characters, so Lines 2, 5 were cut.", "many")
    eq(notice.text({cut = {}, unsupported = {}}, t), nil, "nothing lost")
end)

test("a word longer than a row is split", function()
    local rows = text.wrap({(text.parse(string.rep("x", 45)))[1]})
    eq(#rows, 2, "rows")
    eq(#rows[1], 40, "first row")
    eq(#rows[2], 5, "second row")
end)

test("characters go into the Latin table, with diacritics before their letter", function()
    eq(text.encode("é"), "\194e", "e acute")
    eq(text.encode("Ü"), "\200U", "U diaeresis")
    eq(text.encode("ç"), "\203c", "c cedilla")
    eq(text.encode("č"), "\207c", "c caron")
    eq(text.encode("ß"), "\251", "sharp s")
    eq(text.encode("œ"), "\250", "oe")
    eq(text.encode("$"), "\164", "dollar")
    eq(text.encode("#"), "#", "hash")
    eq(text.encode("’"), "\185", "right quote")
    eq(text.encode("♪"), "\213", "note")
    eq(text.encode("漢"), nil, "no table entry")
    local file, report = stl.build(doc({line(3, 0, 1000, "Café 漢")}), {})
    eq(textField(tti(file, 1)), "\13\11\11Caf\194e ?\10\10", "encoded")
    eq(report.unsupported[1], 3, "named")
    eq(notice.text(report, t), "Line 3 has characters EBU STL can’t hold; they became “?”.", "notice")
end)

test("text past 112 bytes goes on in extension blocks", function()
    local accented = string.rep("é", 40) .. "\\N" .. string.rep("é", 40)
    local file = stl.build(doc({line(1, 0, 1000, accented), line(2, 1000, 2000, "next")}), {})
    eq(#file, 1024 + 3 * 128, "blocks")
    eq(tti(file, 1):byte(4), 0, "first extension")
    eq(tti(file, 2):byte(4), 0xFF, "last block")
    eq(tti(file, 1):sub(2, 3), tti(file, 2):sub(2, 3), "same subtitle")
    eq(tti(file, 3):sub(2, 3), bytes(1, 0), "next subtitle")
    eq(file:sub(239, 243), "00003", "TNB")
    eq(file:sub(244, 248), "00002", "TNS")
    eq(#textField(tti(file, 1)) + #textField(tti(file, 2)), 85 + 2 + 85, "every byte kept")
end)

test("comments, drawings, empty and zero-length Lines are left out, and Lines go in time order", function()
    local file = stl.build(doc({line(1, 5000, 6000, "late"), line(2, 0, 1000, "note", {comment = true}),
        line(3, 1000, 2000, "{\\p1}m 0 0 l 10 10{\\p0}"), line(4, 2000, 2000, "flash"), line(5, 3000, 4000, "  "),
        line(6, 1000, 2000, "early")}), {})
    eq(#file, 1024 + 2 * 128, "two subtitles")
    eq(textField(tti(file, 1)), "\13\11\11early\10\10", "first")
    eq(textField(tti(file, 2)), "\13\11\11late\10\10", "second")
end)

test("the timebase is 30 near 30 frames a second and 25 otherwise", function()
    eq(stl.timebase(29.97), 30, "29.97")
    eq(stl.timebase(59.94), 30, "59.94")
    eq(stl.timebase(23.976), 25, "23.976")
    eq(stl.timebase(nil), 25, "none")
    local file = stl.build(doc({line(1, 3723500, 3724000, "x")}), {frameRate = 29.97})
    eq(file:sub(4, 11), "STL30.01", "DFC")
    eq(tti(file, 1):sub(6, 9), bytes(1, 2, 3, 15), "TCI at 30")
end)

test("the language comes from Script Info Language", function()
    eq(stl.language("de"), 0x08, "code")
    eq(stl.language("pt_BR"), 0x21, "region")
    eq(stl.language("French"), 0x0F, "name")
    eq(stl.language("ja"), 0, "not in the table")
    eq(stl.language(nil), 0, "none")
end)

test("GSI text is code page 850, cut and padded", function()
    eq(text.cp850("Ça", 4), "\128a  ", "C cedilla")
    eq(text.cp850(string.rep("a", 40), 32), string.rep("a", 32), "cut")
    eq(text.cp850("漢", 2), "? ", "unknown")
end)

test("base64 pads the last group", function()
    eq(base64.encode("Man"), "TWFu")
    eq(base64.encode("Ma"), "TWE=")
    eq(base64.encode("M"), "TQ==")
    eq(base64.encode("\0\255\128"), "AP+A")
end)

test("the exporter returns the file as base64 and warns about what it lost", function()
    local exporter, notified
    _G.hikari = {
        null = setmetatable({}, {}),
        formats = {exporter = function(id, fn) eq(id, "ebu-stl", "format id"); exporter = fn end},
        notify = function(message, level) notified = {message, level} end,
        i18n = {t = t},
    }
    dofile("main.lua")
    local data, encoding = exporter(doc({line(2, 0, 1000, "a\\Nb\\Nc")}), {frameRate = hikari.null})
    eq(encoding, "base64", "encoding")
    eq(#data, (1024 + 128) / 3 * 4, "size")
    eq(notified[2], "warning", "level")
    eq(notified[1], "EBU STL holds 2 rows of 40 characters, so Line 2 was cut.", "text")
    _G.hikari = nil
end)

for _, f in ipairs(failed) do io.stderr:write(f, "\n") end
print(string.format("%d passed, %d failed", passed, #failed))
os.exit(#failed == 0 and 0 or 1)
