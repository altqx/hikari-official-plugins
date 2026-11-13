local t = require "t"
local json = require "chains.json"
local host = require "chains.host"

local marked = setmetatable({}, { __mode = "k" })

local function fake_hikari()
    local sent = {}
    local hikari = { sent = sent }
    function hikari.array(list)
        marked[list] = true
        return list
    end
    hikari.selection = { set = function(selected, active) sent.select = { selected, active } end }
    hikari.dialogs = { ask = function(id, spec) sent.ask = { id, spec } return "run", {} end }
    hikari.panels = { render = function(panel, tree) sent.render = { panel, tree } end }
    function hikari.call(op, params)
        sent.call = { op, params }
        return {}
    end
    return hikari
end

t.test("what goes to HikariSub marks every list as a JSON array, empty ones too, and leaves objects alone", function()
    local hikari = fake_hikari()
    local tree = { kind = "column", children = json.array({ { kind = "list", id = "x", rows = json.array() },
        { kind = "row", children = { { kind = "label", text = "a" } } } }) }
    host.render(hikari, "chains", tree)
    local sent = hikari.sent.render[2]
    t.eq(marked[sent], nil)
    t.eq(marked[sent.children], true)
    t.eq(marked[sent.children[1].rows], true)
    t.eq(marked[sent.children[2].children], true)
    t.eq(marked[sent.children[1]], nil)
end)

t.test("the replay's calls mark their lists too", function()
    local hikari = fake_hikari()
    local h = host.new(hikari)
    h.select(json.array(), nil)
    t.eq(marked[hikari.sent.select[1]], true)
    h.run_macro({ file = "f.lua", macro = "Glow", answers = json.array(), show = "never" })
    t.eq(marked[hikari.sent.call[2].answers], true)
    h.ask({ title = "x", buttons = json.array({ { id = "run" } }), body = { kind = "column", children = json.array() } })
    t.eq(marked[hikari.sent.ask[2].buttons], true)
    t.eq(marked[hikari.sent.ask[2].body.children], true)
end)
