local t = require "t"
local fake = require "fake_host"
local json = require "chains.json"
local model = require "chains.model"
local app = require "chains.app"

local OWN = "plugin.hikarisub.macro-chains."

local function make(lines)
    local host = fake.new(lines or { "a", "b" })
    local files = { data = {} }
    function files.read(path)
        return files.data[path]
    end
    function files.write(path, text)
        files.data[path] = text
        return true
    end
    local ui = { trees = {}, asks = {}, notes = {}, answers = {}, undone = 0, revision = 1,
        macros = { { file = "f.lua", macro = "Glow", enabled = true }, { file = "f.lua", macro = "Fade", enabled = true } } }
    local deps = {
        t = fake.t, own = OWN, host = host, files = files,
        macros = function() return ui.macros end,
        command_name = function(id) return ui.names and ui.names[id] end,
        render = function(tree) ui.trees[#ui.trees + 1] = tree end,
        ask = function(id, spec)
            ui.asks[#ui.asks + 1] = { id = id, spec = spec }
            local a = table.remove(ui.answers, 1) or { "cancel" }
            return a[1], a[2]
        end,
        pick = function() return ui.picked, "arch.AegisubChain.json" end,
        notify = function(text, level) ui.notes[#ui.notes + 1] = text .. (level and " [" .. level .. "]" or "") end,
        revision = function() return ui.revision end,
        undo = function() ui.undone = ui.undone + 1 return true end,
        show_log = function() ui.log_shown = true end,
    }
    return app.new(deps), ui, host, files
end

local function saved(files)
    return json.decode(files.data["chains.json"]).chains
end

local function glow_ran(blur)
    return { ok = true, file = "f.lua", macro = "Glow", dialogs = { { key = "0123456789abcdef", button = "Apply",
        values = { blur = blur }, controls = { { name = "blur", kind = "intedit", label = "Blur", hint = "" } } } } }
end

local function click(a, widget, values)
    a:on_panel({ kind = "click", widget = widget, values = values or {} })
end

local function record_signs(a, ui)
    a:record()
    a:on_macro_ran(glow_ran(2))
    ui.names = { EDIT_LINE_DUPLICATE = "Duplicate lines" }
    a:on_command_ran({ command = "EDIT_LINE_DUPLICATE", ok = true })
    click(a, "stop", { rec_name = "Signs" })
end

t.test("recording turns each macro and command that ran into a step and saves the chain under its name", function()
    local a, ui, _, files = make()
    a:show()
    t.eq(ui.trees[1].children[2].kind, "empty")
    a:record()
    t.eq(a.mode, "recording")
    a:on_macro_ran(glow_ran(2))
    a:on_command_ran({ command = OWN .. "record", ok = true })
    ui.names = { EDIT_LINE_DUPLICATE = "Duplicate lines" }
    a:on_command_ran({ command = "EDIT_LINE_DUPLICATE", ok = true })
    t.eq(#a.recorder:steps(), 2)
    click(a, "stop", { rec_name = "Signs" })
    t.eq(a.mode, "library")
    t.eq(a.selected, "Signs")
    local chains = saved(files)
    t.eq(chains[1].name, "Signs")
    t.eq(chains[1].steps[2], { kind = "command", command = "EDIT_LINE_DUPLICATE", name = "Duplicate lines", select = "macro" })
end)

t.test("Record a chain while recording stops and saves, and nothing recorded saves nothing", function()
    local a, ui, _, files = make()
    a:record()
    a:record()
    t.eq(a.mode, "library")
    t.eq(files.data["chains.json"], nil)
    t.eq(ui.notes[1], "nothing_recorded")
end)

t.test("Discard throws the recording away", function()
    local a, _, _, files = make()
    a:record()
    a:on_macro_ran(glow_ran(2))
    click(a, "discard")
    t.eq(a.mode, "library")
    t.eq(files.data["chains.json"], nil)
end)

t.test("a chain runs from the panel as one group and remembers nothing to undo when it applied", function()
    local a, ui, host = make()
    host.macros.Glow = function(h) h.add("glow") end
    record_signs(a, ui)
    host.commands.EDIT_LINE_DUPLICATE = function(h) h.add("dup") end
    click(a, "run_selected")
    t.eq(host.groups, { "Signs" })
    t.eq(host.requests[1].answers[1].values, { blur = 2 })
    t.eq(a.notice, nil)
end)

t.test("a failed step stops the chain, and Undo the chain undoes it only while nothing changed after it", function()
    local a, ui, host = make()
    host.macros.Glow = function(h) h.add("glow") end
    record_signs(a, ui)
    host.commands.EDIT_LINE_DUPLICATE = nil
    click(a, "run_selected")
    t.eq(a.notice, { chain = "Signs", step = 2, message = "Not now", steps = 1 })
    click(a, "undo_chain")
    t.eq(ui.undone, 1)
    t.eq(a.notice, nil)
    click(a, "run_selected")
    ui.revision = 2
    click(a, "undo_chain")
    t.eq(ui.undone, 1)
    t.eq(ui.notes[#ui.notes], "undo_moved [warning]")
end)

t.test("Show the log opens the Log panel", function()
    local a, ui = make()
    click(a, "show_log")
    t.eq(ui.log_shown, true)
end)

t.test("a chain doesn't run while recording", function()
    local a, ui, host = make()
    record_signs(a, ui)
    a:record()
    a:run_slot(1)
    a.selected = "Signs"
    a:run(a.store:find("Signs"))
    t.eq(host.groups, {})
    t.eq(ui.notes[#ui.notes], "busy_recording [warning]")
end)

t.test("a slot command runs the chain in that slot, and an empty slot says so", function()
    local a, ui, host = make()
    host.macros.Glow = function() end
    host.commands.EDIT_LINE_DUPLICATE = function() end
    record_signs(a, ui)
    a:run_slot(1)
    t.eq(ui.notes[#ui.notes], "slot_empty(1) [warning]")
    a.store:find("Signs").slot = 1
    a:run_slot(1)
    t.eq(host.groups, { "Signs" })
end)

t.test("editing changes a copy, and Save keeps it, moving the slot off the chain that had it", function()
    local a, ui, _, files = make()
    record_signs(a, ui)
    a.store:add(model.new_chain("Other")).slot = 3
    a.selected = "Signs"
    click(a, "edit_selected")
    t.eq(a.mode, "editing")
    a:on_panel({ kind = "change", widget = "mode:1:1", value = "ask" })
    a:on_panel({ kind = "change", widget = "value:1:1", value = 7 })
    a:on_panel({ kind = "change", widget = "slot", value = "3" })
    a:on_panel({ kind = "select", widget = "steps", value = "2" })
    a:on_panel({ kind = "change", widget = "select", value = "keep" })
    t.eq(a.store:find("Signs").steps[1].dialogs[1].fields[1].mode, "constant")
    a:on_panel({ kind = "change", widget = "name", value = "Signs 2" })
    click(a, "save")
    t.eq(a.mode, "library")
    t.eq(a.selected, "Signs 2")
    local chain = a.store:find("Signs 2")
    t.eq(chain.steps[1].dialogs[1].fields[1].mode, "ask")
    t.eq(chain.steps[1].dialogs[1].fields[1].value, 7)
    t.eq(chain.steps[2].select, "keep")
    t.eq(chain.slot, 3)
    t.eq(a.store:find("Other").slot, nil)
    t.eq(saved(files)[1].name, "Signs 2")
end)

t.test("Cancel leaves the chain as it was, and steps move and go in the copy", function()
    local a, ui = make()
    record_signs(a, ui)
    click(a, "edit_selected")
    a:on_panel({ kind = "select", widget = "steps", value = "2" })
    click(a, "move_up")
    t.eq(a.draft.steps[1].kind, "command")
    t.eq(a.at, 1)
    click(a, "remove_step")
    t.eq(#a.draft.steps, 1)
    click(a, "cancel")
    t.eq(#a.store:find("Signs").steps, 2)
end)

t.test("Delete asks first", function()
    local a, ui, _, files = make()
    record_signs(a, ui)
    click(a, "delete")
    t.eq(a.store:find("Signs") ~= nil, true)
    ui.answers = { { "delete" } }
    click(a, "delete")
    t.eq(a.store:find("Signs"), nil)
    t.eq(a.selected, nil)
    t.eq(saved(files), {})
end)

local EXPORT = [[{"config":{"chains":{"Fade fix":[{"macro":"Fade","select":"keep","dialogs":[
  {"values":{"ms":{"value":200,"mode":"user"}},"button":{"value":"OK","mode":"const"}}]}]}}}]]

t.test("Import reads AegisubChain's chains, shows what it found and adds them once the user agrees", function()
    local a, ui, _, files = make()
    ui.picked = EXPORT
    a:import()
    t.eq(ui.asks[1].id, "import")
    t.eq(a.store.chains, {})
    ui.answers = { { "import" } }
    a:import()
    t.eq(a.store:find("Fade fix").steps[1].learn, true)
    t.eq(a.selected, "Fade fix")
    t.eq(saved(files)[1].name, "Fade fix")
    t.eq(ui.notes[#ui.notes], "imported(1)")
end)

t.test("a file Import can't read says why", function()
    local a, ui = make()
    ui.picked = "{"
    a:import()
    t.eq(#ui.asks, 0)
    t.eq(ui.notes[1]:find("^import_failed") ~= nil, true)
end)

t.test("an imported chain learns its dialogs from the run's answer and saves them", function()
    local a, ui, host, files = make()
    host.macros.Fade = function() end
    host.dialogs = { Fade = { { key = "fedcba9876543210", button = "OK", values = { ms = 250, curve = "linear" },
        controls = { { name = "ms", kind = "intedit", label = "ms", hint = "" },
            { name = "curve", kind = "dropdown", label = "Curve", hint = "" } } } } }
    ui.picked = EXPORT
    ui.answers = { { "import" } }
    host.answer = { "run", { ["s1-d1-ms"] = 250 } }
    a:import()
    click(a, "run_selected")
    t.eq(host.requests[1].answers[1].values, { ms = 250 })
    local step = saved(files)[1].steps[1]
    t.eq(step.learn, nil)
    t.eq(step.dialogs[1].key, "fedcba9876543210")
    t.eq(step.dialogs[1].fields[2].mode, "exclude")
    t.eq(a.mode, "library")
end)

t.test("the list names chains by place, so any name works, and choosing a row chooses its chain", function()
    local a, ui = make()
    record_signs(a, ui)
    a.store:add(model.new_chain("Fade fix: 2 / final"))
    a:show()
    local list = ui.trees[#ui.trees].children[2]
    t.eq(list.rows[2].id, "c2")
    t.eq(list.rows[2].text, "Fade fix: 2 / final")
    a:on_panel({ kind = "select", widget = "chains", value = "c2" })
    t.eq(a.selected, "Fade fix: 2 / final")
    t.eq(ui.trees[#ui.trees].children[2].selected, "c2")
    a:on_panel({ kind = "select", widget = "chains", value = "c9" })
    t.eq(a.selected, "Fade fix: 2 / final")
end)

t.test("Import's list names chains by place too", function()
    local a, ui = make()
    ui.picked = [[{"config":{"chains":{"Fade fix":[{"macro":"Fade","dialogs":[]}]}}}]]
    a:import()
    t.eq(ui.asks[1].spec.body.children[2].rows[1].id, "1")
    t.eq(ui.asks[1].spec.body.children[2].rows[1].text, "Fade fix")
end)

t.test("while a macro shows as not loaded, a selection change looks again, since scripts load after the plugin", function()
    local a, ui = make()
    record_signs(a, ui)
    ui.macros = {}
    a:show()
    local before = #ui.trees
    t.eq(ui.trees[before].children[2].rows[1].muted, true)
    ui.macros = { { file = "f.lua", macro = "Glow", enabled = true } }
    a:on_selection_changed()
    t.eq(#ui.trees, before + 1)
    t.eq(ui.trees[#ui.trees].children[2].rows[1].muted, nil)
    a:on_selection_changed()
    t.eq(#ui.trees, before + 1)
end)

t.test("a stored chain comes back on the next start, the first one chosen", function()
    local a, ui, _, files = make()
    record_signs(a, ui)
    local again = app.new({ t = fake.t, own = OWN, host = fake.new({}), files = files, macros = function() return {} end,
        render = function() end })
    t.eq(again.selected, "Signs")
end)
