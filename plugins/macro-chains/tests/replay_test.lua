local t = require "t"
local fake = require "fake_host"
local model = require "chains.model"
local replay = require "chains.replay"

local function step(macro, fields, select)
    local s = model.macro_step({ file = "f.lua", macro = macro, dialogs = { {
        key = "0123456789abcdef", button = "OK", values = {}, controls = {} } } })
    s.select = select or "macro"
    s.dialogs[1].fields = fields or {}
    s.dialogs[1].controls = {}
    for _, f in ipairs(fields or {}) do
        s.dialogs[1].controls[#s.dialogs[1].controls + 1] = { name = f.name, kind = f.kind }
    end
    return s
end

local function field(name, kind, mode, value, extra)
    local f = { name = name, kind = kind, mode = mode, value = value, title = name, control = extra or {} }
    return f
end

local function suffix(host, answers)
    for _, l in ipairs(host.lines_) do
        if host.sel.selected[1] == nil or l.id == host.sel.selected[1] then
            l.text = l.text .. (answers[1].values.tag or "")
        end
    end
end

t.test("a chain without Ask fields runs without a dialog, as one group, each step answered by controls", function()
    local host = fake.new({ "a", "b" })
    host.macros.Tag = suffix
    host.commands.EDIT_LINE_DUPLICATE = function(h) h.add("dup") end
    local chain = model.new_chain("Signs")
    chain.steps = { step("Tag", { field("tag", "edit", "constant", "!") }),
        model.command_step("EDIT_LINE_DUPLICATE", "Duplicate"),
        step("Tag", { field("tag", "edit", "exclude", "?") }) }
    local report = replay.run(chain, host, fake.t)
    t.eq(report.outcome, "applied")
    t.eq(report.steps, 3)
    t.eq(host.asked, nil)
    t.eq(host.groups, { "Signs" })
    t.eq(host.requests[1].answers[1], { values = { tag = "!" }, button = "OK", controls = { { kind = "edit", name = "tag" } } })
    t.eq(host.requests[1].show, "never")
    t.eq(host.requests[2].answers[1].values, {})
    t.eq(host.lines_[1].text, "a!")
    t.eq(host.job_title, "job_title(Signs)")
    t.eq(host.log[1], "progress job_step(1,3,Tag)")
end)

t.test("Ask fields share one dialog, grouped by step, and their answers go to their own steps", function()
    local host = fake.new({ "a" })
    host.macros.Tag = suffix
    host.macros.Count = function() end
    local chain = model.new_chain("Signs")
    chain.steps = { step("Tag", { field("tag", "edit", "ask", "!"), field("on", "checkbox", "ask", true) }),
        step("Count", { field("n", "intedit", "ask", 2, { min = 0, max = 9, hint = "How many" }),
            field("mode", "dropdown", "ask", "fast", { items = { "fast", "slow" } }) }) }
    host.answer = { "run", { ["s1-d1-tag"] = "?", ["s2-d1-n"] = 7 } }
    t.eq(replay.run(chain, host, fake.t).outcome, "applied")
    local body = host.asked.body.children
    t.eq(#body, 2)
    t.eq(body[1].title, "step_title(1,Tag)")
    t.eq(body[1].children[1], { id = "s1-d1-tag", kind = "text", label = "tag", value = "!" })
    t.eq(body[1].children[2], { id = "s1-d1-on", kind = "check", text = "on", value = true })
    t.eq(body[2].children[1], { id = "s2-d1-n", kind = "number", label = "n", value = 2, minimum = 0, maximum = 9,
        decimals = 0, tooltip = "How many" })
    t.eq(body[2].children[2].options, { "fast", "slow" })
    t.eq(host.requests[1].answers[1].values, { tag = "?", on = true })
    t.eq(host.requests[2].answers[1].values, { n = 7, mode = "fast" })
    t.eq(host.asked.buttons[1].id, "run")
end)

t.test("cancelling the merged dialog runs nothing", function()
    local host = fake.new({ "a" })
    host.macros.Tag = suffix
    local chain = model.new_chain("Signs")
    chain.steps = { step("Tag", { field("tag", "edit", "ask", "!") }) }
    host.answer = { "cancel", {} }
    t.eq(replay.run(chain, host, fake.t), { outcome = "cancelled" })
    t.eq(host.requests, nil)
    t.eq(#host.groups, 0)
end)

t.test("a failing step stops the chain and says which", function()
    local host = fake.new({ "a" })
    host.macros.Tag = suffix
    host.macros.Break = function() return "failed" end
    local chain = model.new_chain("Signs")
    chain.steps = { step("Tag"), step("Break"), step("Tag") }
    local report = replay.run(chain, host, fake.t)
    t.eq({ report.outcome, report.step, report.message, report.steps }, { "failed", 2, "it broke", 1 })
    t.eq(#host.requests, 2)
    chain.steps = { step("Missing") }
    t.eq(replay.run(chain, host, fake.t).message, "No loaded macro")
end)

t.test("each step's selection mode sets what the next step works on", function()
    local host = fake.new({ "a", "b", "c" })
    host.sel = { selected = { 2 }, active = 2 }
    host.macros.Grow = function(h) h.add("new"); h.lines_[1].text = "A"; h.sel = { selected = { 3 }, active = 3 } end
    local chain = model.new_chain("Sel")
    chain.steps = { step("Grow", {}, "keep"), step("Grow", {}, "changed"), step("Grow", {}, "macro") }
    replay.run(chain, host, fake.t)
    t.eq(host.log, { "progress job_step(1,3,Grow)", "ran Grow", "select 2", "progress job_step(2,3,Grow)", "ran Grow",
        "select 5", "progress job_step(3,3,Grow)", "ran Grow" })
    t.eq(host.sel.selected, { 3 })
end)

t.test("a failed macro's message is reported without the blank lines that end it", function()
    local host = fake.new({ "a" })
    host.macros.Fail = function() return "failed" end
    host.failure = "boom\n\n"
    local chain = model.new_chain("Signs")
    chain.steps = { step("Fail") }
    t.eq(replay.run(chain, host, fake.t).message, "boom")
end)

t.test("a chain can be stopped between steps from its job card", function()
    local host = fake.new({ "a" })
    host.macros.Tag = suffix
    host.cancel_at = 1
    local chain = model.new_chain("Signs")
    chain.steps = { step("Tag"), step("Tag") }
    local report = replay.run(chain, host, fake.t)
    t.eq({ report.outcome, report.step }, { "cancelled", 2 })
end)

local function ran_dialog(key, name, value)
    return { { key = key, button = "OK", values = { [name] = value }, controls = { { name = name, kind = "intedit" } } } }
end

t.test("each learning step learns its dialogs from its own run, and a run that gives none leaves it learning", function()
    local host = fake.new({ "a" })
    host.macros.Fade, host.macros.Glow, host.macros.Blur = function() end, function() end, function() end
    host.dialogs = { Fade = ran_dialog("fedcba9876543210", "ms", 250), Glow = ran_dialog("0123456789abcdef", "blur", 3) }
    local chain = model.new_chain("Signs")
    chain.steps = { step("Fade"), step("Glow"), step("Blur") }
    for _, s in ipairs(chain.steps) do
        s.learn = true
    end
    local report = replay.run(chain, host, fake.t)
    t.eq({ report.outcome, report.learned }, { "applied", true })
    t.eq({ chain.steps[1].learn, chain.steps[1].dialogs[1].key }, { nil, "fedcba9876543210" })
    t.eq({ chain.steps[2].learn, chain.steps[2].dialogs[1].fields[1].value }, { nil, 3 })
    t.eq(chain.steps[3].learn, true)
end)

t.test("a step that is not learning keeps its dialogs whatever its run gives", function()
    local host = fake.new({ "a" })
    host.macros.Fade = function() end
    host.dialogs = { Fade = ran_dialog("fedcba9876543210", "ms", 250) }
    local chain = model.new_chain("Signs")
    chain.steps = { step("Fade") }
    local report = replay.run(chain, host, fake.t)
    t.eq({ report.learned, chain.steps[1].dialogs[1].key }, { false, "0123456789abcdef" })
end)
