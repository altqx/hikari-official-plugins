local t = require "t"

local function older_hikarisub()
    local h = { handlers = {}, commands = {}, notes = {}, rendered = {} }
    h.plugin = { id = "hikarisub.macro-chains" }
    h.i18n = { t = function(key) return key end }
    h.array = function(list) return list end
    h.document = { read = function() return { revision = 1 } end }
    h.panels = {
        on = function(id, fn) h.handlers[id] = fn end,
        render = function(id, tree) h.rendered[#h.rendered + 1] = { id, tree } end,
    }
    h.commands = { register = function(id, fn) h.commands[id] = fn end }
    h.events = { on = function() error("an older HikariSub gets no chain events") end }
    h.notify = function(text, level) h.notes[#h.notes + 1] = { text, level } end
    h.call = function() error("an older HikariSub gets no calls") end
    return h
end

t.test("without undo groups the plugin loads, says it needs a newer HikariSub, and touches no chain", function()
    local h = older_hikarisub()
    _G.hikari = h
    dofile("main.lua")
    h.handlers.chains({ kind = "show" })
    t.eq(h.rendered[1][2].children[1], { kind = "empty", text = "needs_hikarisub" })
    h.commands.record()
    h.commands["run-slot-3"]()
    _G.hikari = nil
    t.eq(h.notes, { { "needs_hikarisub", "warning" }, { "needs_hikarisub", "warning" } })
end)
