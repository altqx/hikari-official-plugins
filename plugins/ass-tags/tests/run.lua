package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local tags = require "ass_tags.tags"

local passed, failed = 0, {}

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failed[#failed + 1] = name .. ": " .. tostring(err)
    end
end

local function show(v)
    if type(v) == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return type(v) == "string" and string.format("%q", v) or tostring(v)
end

local function eq(actual, expected, what)
    if show(actual) ~= show(expected) then
        error((what or "value") .. "\n  expected " .. show(expected) .. "\n  actual   " .. show(actual), 2)
    end
end

local strings = {}
do
    local f = assert(io.open("i18n/en.json", "rb"))
    for k, v in f:read("*a"):gmatch('"([^"]+)":%s*"([^"]*)"') do strings[k] = v end
    f:close()
end

local function t(key, ...)
    local args = {...}
    local text = strings[key] or key
    return (text:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end


local function fonts()
    return {"Arial", "Noto Sans", "Arial Black"}
end

local function labels(items)
    local out = {}
    for _, item in ipairs(items or {}) do out[#out + 1] = item.label end
    return out
end

test("offsets count UTF-16 units both ways", function()
    local text = "é😀{\\b1}"
    eq(tags.units_of(text, #"é😀"), 3)
    eq(tags.bytes_of(text, 3), #"é😀")
end)

test("fade arguments offer a snippet and presets after \\fad(", function()
    local items = tags.complete("{\\fad(}", 6, t, fonts)
    eq(items[1], {label = "Fade in and out", insert = "${1:200},${2:200})", snippet = true, from = 6, to = 6})
    eq(items[2], {label = "200,200", insert = "200,200)", detail = "200 ms in, 200 ms out", from = 6, to = 6})
    eq(#items, 6)
end)

test("typed fade digits narrow the presets and widen the range", function()
    eq(labels(tags.complete("{\\fad(5}", 7, t, fonts)), {"500,500", "500,0"})
    eq(tags.complete("{\\fad(5}", 7, t, fonts)[1].from, 6)
end)

test("\\fn offers the Styles' fonts that start with what was typed", function()
    eq(labels(tags.complete("{\\fn}", 4, t, fonts)), {"Arial", "Noto Sans", "Arial Black"})
    local items = tags.complete("x😀{\\fnar}", 9, t, fonts)
    eq(labels(items), {"Arial", "Arial Black"})
    eq({items[1].from, items[1].to, items[1].detail}, {7, 9, "A Style's font"})
end)

test("nothing is offered outside an override block", function()
    eq(tags.complete("\\fad(", 5, t, fonts), nil)
    eq(tags.complete("{\\b1}\\fn", 8, t, fonts), nil)
    eq(tags.complete("{\\b1}", 4, t, fonts), nil)
end)

test("a hover explains the tag under the pointer with its range", function()
    local text = "{\\b1\\fad(200,300)\\fnNoto Sans}Hi"
    eq(tags.hover(text, 6, t), {text = "Fade: 200 ms in, 300 ms out", from = 4, to = 17})
    eq(tags.hover(text, 2, t), {text = "Bold: on", from = 1, to = 4})
    eq(tags.hover(text, 20, t), {text = "Font: Noto Sans", from = 17, to = 29})
end)

test("hovers read numbers, karaoke and aliases", function()
    eq(tags.hover("{\\fscx120}", 2, t).text, "Width: 120%")
    eq(tags.hover("{\\fs40}", 2, t).text, "Font size: 40")
    eq(tags.hover("{\\fr45}", 2, t).text, "Rotation: 45°")
    eq(tags.hover("{\\kf35}", 2, t).text, "Karaoke: 350 ms")
    eq(tags.hover("{\\i0}", 2, t).text, "Italic: off")
    eq(tags.hover("{\\move(1,2,3,4)}", 2, t).text, "Move from 1, 2 to 3, 4")
    eq(tags.hover("{\\an7}", 2, t).text, "Alignment: numpad 7")
end)

test("no hover off a tag, on an unknown tag or on bad arguments", function()
    eq(tags.hover("{\\b1}Hi", 6, t), nil)
    eq(tags.hover("{\\b1}", 4, t), nil)
    eq(tags.hover("{\\frx10}", 2, t), nil)
    eq(tags.hover("{\\iclip(1,2,3,4)}", 2, t), nil)
    eq(tags.hover("{\\an12}", 2, t), nil)
    eq(tags.hover("{\\pos(1)}", 2, t), nil)
    eq(tags.hover("{\\xyz}", 2, t), nil)
    eq(tags.hover("", 0, t), nil)
end)

if #failed > 0 then
    for _, f in ipairs(failed) do io.stderr:write("FAIL ", f, "\n") end
    print(string.format("%d tests passed, %d failed", passed, #failed))
    os.exit(1)
end
print(string.format("%d tests passed", passed))
