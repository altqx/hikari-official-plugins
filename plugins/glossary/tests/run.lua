package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local check = require "glossary.check"

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

local function hits(text, rows, matchCase)
    local out = {}
    for _, h in ipairs(check.find(text, check.rules(rows), matchCase)) do
        out[#out + 1] = {h.from, h.to, h.avoid, h.prefer or false}
    end
    return out
end

test("rules read both arrows, trim, and keep a bare term", function()
    eq(check.rules({"e-mail → email", "  web site->website ", "utilize", "", "→ x", 7}), {
        {avoid = "web site", prefer = "website"},
        {avoid = "utilize"},
        {avoid = "e-mail", prefer = "email"},
    })
end)

test("a whole word matches, a part of one doesn't", function()
    eq(hits("Email the e-mail. Re-e-mails no.", {"e-mail -> email"}), {{10, 16, "e-mail", "email"}})
    eq(hits("okay ok OK", {"ok → fine"}), {{5, 7, "ok", "fine"}, {8, 10, "OK", "FINE"}})
end)

test("case follows the text it replaces unless Match case is on", function()
    eq(hits("Colour colour", {"colour → color"}), {{0, 6, "Colour", "Color"}, {7, 13, "colour", "color"}})
    eq(hits("Colour colour", {"colour → color"}, true), {{7, 13, "colour", "color"}})
end)

test("override blocks and escapes never match and break words", function()
    eq(hits("{\\i1}ok{\\i0}\\Nok\\hok {ok}", {"ok → fine"}),
        {{5, 7, "ok", "fine"}, {14, 16, "ok", "fine"}, {18, 20, "ok", "fine"}})
end)

test("offsets count UTF-16 units", function()
    eq(hits("é 😀 ok", {"ok → fine"}), {{5, 7, "ok", "fine"}})
    eq(hits("caféok café ok", {"ok"}), {{12, 14, "ok", false}})
end)

test("a longer term wins where two overlap", function()
    eq(hits("web site and site", {"site → page", "web site → website"}),
        {{0, 8, "web site", "website"}, {13, 17, "site", "page"}})
end)

test("problems skip comments and carry a fix only with a preferred term", function()
    local lines = {
        {id = 1, text = "Send an e-mail.", comment = false},
        {id = 2, text = "e-mail", comment = true},
        {id = 3, text = "Utilize it.", comment = false},
    }
    eq(check.problems(lines, check.rules({"e-mail → email", "utilize"}), false, "warning", t, 100), {
        {line = 1, from = 8, to = 14, severity = "warning", code = "glossary", message = "Use “email”, not “e-mail”.",
         fixes = {{title = "Change to “email”", edits = {{from = 8, to = 14, insert = "email"}}}}},
        {line = 3, from = 0, to = 7, severity = "warning", code = "glossary",
         message = "“Utilize” is on the glossary's avoid list."},
    })
end)

test("problems stop at the cap", function()
    local lines = {}
    for i = 1, 10 do lines[i] = {id = i, text = "ok ok ok"} end
    eq(#check.problems(lines, check.rules({"ok"}), false, "hint", t, 25), 25)
end)

if #failed > 0 then
    for _, f in ipairs(failed) do io.stderr:write("FAIL ", f, "\n") end
    print(string.format("%d tests passed, %d failed", passed, #failed))
    os.exit(1)
end
print(string.format("%d tests passed", passed))
