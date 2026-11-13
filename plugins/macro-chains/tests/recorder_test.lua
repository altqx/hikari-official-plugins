local t = require "t"
local Recorder = require "chains.recorder"

local function ran(macro, ok)
    return { file = "f.lua", macro = macro, ok = ok ~= false, outcome = ok == false and "failed" or "applied",
        dialogs = { { key = "0123456789abcdef", values = { n = 1 }, button = "OK", controls = { { name = "n", kind = "intedit" } } } } }
end

t.test("only what ran while recording becomes a step, in order", function()
    local r = Recorder.new("plugin.hikarisub.macro-chains.")
    r:macro_ran(ran("Before"))
    r:start("Signs")
    t.ok(r:recording())
    r:macro_ran(ran("Fade"))
    r:command_ran({ command = "EDIT_LINE_DUPLICATE", ok = true }, "Duplicate lines")
    r:macro_ran(ran("Shift"))
    local chain = r:stop()
    t.ok(not r:recording())
    r:macro_ran(ran("After"))
    t.eq(chain.name, "Signs")
    t.eq(#chain.steps, 3)
    t.eq({ chain.steps[1].macro, chain.steps[2].command, chain.steps[2].name, chain.steps[3].macro },
        { "Fade", "EDIT_LINE_DUPLICATE", "Duplicate lines", "Shift" })
end)

t.test("failed runs, macro menu commands and the plugin's own commands are left out", function()
    local r = Recorder.new("plugin.hikarisub.macro-chains.")
    r:start("x")
    r:macro_ran(ran("Broke", false))
    r:command_ran({ command = "macro:f.lua:0", ok = true })
    r:command_ran({ command = "plugin.hikarisub.macro-chains.record", ok = true })
    r:command_ran({ command = "EDIT_LINE_DELETE", ok = false })
    t.eq(#r:stop().steps, 0)
end)

t.test("undo while recording takes the last step back and redo returns it", function()
    local r = Recorder.new("plugin.hikarisub.macro-chains.")
    r:start("x")
    r:macro_ran(ran("One"))
    r:macro_ran(ran("Two"))
    r:command_ran({ command = "GLOBAL_UNDO", ok = true })
    t.eq(#r:steps(), 1)
    r:command_ran({ command = "GLOBAL_REDO", ok = true })
    t.eq(r:steps()[2].macro, "Two")
    r:command_ran({ command = "GLOBAL_UNDO", ok = true })
    r:macro_ran(ran("Three"))
    r:command_ran({ command = "GLOBAL_REDO", ok = true })
    local steps = r:stop().steps
    t.eq({ #steps, steps[2].macro }, { 2, "Three" })
end)
