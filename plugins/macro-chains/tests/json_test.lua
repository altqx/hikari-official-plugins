local t = require "t"
local json = require "chains.json"

t.test("json round-trips nested values with sorted keys", function()
    local text = json.encode({ b = { 1, 2.5, "x" }, a = true, c = { d = "é\n\"q\"" } })
    t.eq(text, '{"a":true,"b":[1,2.5,"x"],"c":{"d":"é\\n\\"q\\""}}')
    t.eq(json.decode(text), { b = { 1, 2.5, "x" }, a = true, c = { d = "é\n\"q\"" } })
end)

t.test("json keeps an empty array an array", function()
    t.eq(json.encode({ steps = json.array() }), '{"steps":[]}')
    t.eq(json.encode(json.decode('{"steps":[]}')), '{"steps":[]}')
    t.eq(json.encode({}), "{}")
end)

t.test("json reads escapes, surrogate pairs and numbers", function()
    t.eq(json.decode('["\\u00e9\\ud83d\\ude00", -1.5e2, 0]'), { "é😀", -150, 0 })
end)

t.test("json refuses what it can't write and says where bad text breaks", function()
    t.fails(function() json.encode({ 1 / 0 }) end, "finite")
    local loop = {}
    loop.self = loop
    t.fails(function() json.encode(loop) end, "holds itself")
    local value, err = json.decode('{"a": [1, 2,}')
    t.eq(value, nil)
    t.ok(err:find("character 13"), err)
    t.eq(json.decode('{"a": 1} x'), nil)
end)
