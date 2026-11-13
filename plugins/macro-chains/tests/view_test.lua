local t = require "t"
local fake = require "fake_host"
local model = require "chains.model"
local view = require "chains.view"

local function find(tree, id)
    if type(tree) ~= "table" then
        return nil
    end
    if tree.id == id then
        return tree
    end
    for _, key in ipairs({ "children", "body" }) do
        local inner = tree[key]
        if type(inner) == "table" then
            if inner.kind then
                local hit = find(inner, id)
                if hit then
                    return hit
                end
            else
                for _, child in ipairs(inner) do
                    local hit = find(child, id)
                    if hit then
                        return hit
                    end
                end
            end
        end
    end
end

local function macro(name, fields)
    local step = model.macro_step({ file = "f.lua", macro = name, dialogs = { {
        key = "0123456789abcdef", button = "Apply", values = {}, controls = {} } } })
    step.dialogs[1].fields = fields or {}
    return step
end

local function field(name, kind, mode, value)
    return { name = name, kind = kind, mode = mode, value = value, title = name, control = {} }
end

local function chain(name, steps, extra)
    local c = model.new_chain(name)
    c.steps = steps
    for k, v in pairs(extra or {}) do
        c[k] = v
    end
    return c
end

local loaded = { Glow = true, Fade = true }

t.test("the library lists each chain with its steps, asks, slot and what keeps it from running", function()
    local imported = macro("Fade")
    imported.learn = true
    local chains = {
        chain("Signs", { macro("Glow", { field("blur", "intedit", "ask", 2) }), model.command_step("X", "Duplicate") }, { slot = 1 }),
        chain("Fade fix", { imported }),
        chain("Old", { macro("Gone/Away") }),
    }
    local tree = view.library(chains, { selected = "Signs" }, loaded, fake.t)
    local list = find(tree, "chains")
    t.eq(list.selected, "c1")
    t.eq(list.rows[1], { id = "c1", text = "Signs", detail = "steps(2) · asks(1) · slot(1)" })
    t.eq(list.rows[2].detail, "steps(1) · learns")
    t.eq(list.rows[3], { id = "c3", text = "Old", detail = "steps(1) · not_loaded(Gone/Away)", muted = true })
    local gone = macro("Gone/Away")
    gone.learn = true
    t.eq(view.library({ chain("Old", { gone }) }, {}, loaded, fake.t).children[2].rows[1].detail,
        "steps(1) · not_loaded(Gone/Away)")
    t.eq(find(tree, "run").disabled, nil)
end)

t.test("without a chain the library shows its empty state, and the chain actions are off", function()
    local tree = view.library({}, {}, loaded, fake.t)
    t.eq(find(tree, "chains"), nil)
    t.eq(tree.children[2], { kind = "empty", text = "empty" })
    t.eq(find(tree, "run").disabled, true)
    t.eq(find(tree, "edit").disabled, true)
    t.eq(find(tree, "delete").disabled, true)
    t.eq(find(tree, "record").disabled, nil)
    t.eq(tree.menu, nil)
end)

t.test("a stopped chain says where it stopped and offers to undo what ran", function()
    local signs = chain("Signs", { macro("Glow"), macro("Fade"), macro("Glow") })
    local tree = view.library({ signs }, { selected = "Signs",
        notice = { chain = "Signs", outcome = "failed", step = 3, message = "boom", steps = 2 } }, loaded, fake.t)
    t.eq(find(tree, "notice").text, "stopped(Signs,3,Glow,boom) undo_hint(2)")
    t.eq(find(tree, "undo_chain").kind, "button")
    t.eq(find(tree, "show_log").kind, "button")
end)

t.test("a stop at the first step has nothing to undo", function()
    local signs = chain("Signs", { macro("Glow") })
    local tree = view.library({ signs }, { selected = "Signs",
        notice = { chain = "Signs", outcome = "failed", step = 1, message = "boom", steps = 0 } }, loaded, fake.t)
    t.eq(find(tree, "notice").text, "stopped(Signs,1,Glow,boom)")
    t.eq(find(tree, "undo_chain"), nil)
end)

t.test("recording shows the steps so far and the name to save them under", function()
    local upper = macro("Upper")
    upper.dialogs = {}
    local tree = view.recording("Signs", { macro("Glow", { field("blur", "intedit", "constant", 2) }),
        model.command_step("X", "Duplicate"), upper }, fake.t)
    t.eq(find(tree, "rec_name").value, "Signs")
    t.eq(find(tree, "rec_steps").rows, { { id = "1", text = "1. Glow", detail = "dialogs(1)", icon = "automation" },
        { id = "2", text = "2. Duplicate", detail = "command", icon = "hotkeys" },
        { id = "3", text = "3. Upper", detail = "no_dialog", icon = "automation" } })
    t.eq(find(tree, "stop").style, "primary")
    t.eq(find(tree, "discard").style, "danger")
end)

t.test("the editor shows the chosen step's selection, dialogs and each field's mode beside its value", function()
    local glow = macro("Glow", { field("blur", "intedit", "ask", 2), field("layers", "intedit", "exclude", 3),
        field("keep", "checkbox", "constant", true) })
    glow.select = "changed"
    local draft = chain("Signs", { macro("Fade"), glow }, { slot = 2 })
    local tree = view.editor(draft, 2, fake.t)
    t.eq(find(tree, "name").value, "Signs")
    t.eq(find(tree, "steps").selected, "2")
    t.eq(find(tree, "steps").rows[2].detail, "select_changed · asks(1)")
    t.eq(find(tree, "select").value, "changed")
    t.eq(find(tree, "show").value, false)
    t.eq(find(tree, "mode:1:1").value, "ask")
    t.eq(find(tree, "mode:1:1").options[1], { value = "constant", text = "mode_constant" })
    t.eq(find(tree, "value:1:1").kind, "number")
    t.eq(find(tree, "value:1:2").disabled, true)
    t.eq(find(tree, "value:1:3").kind, "check")
    t.eq(find(tree, "slot").value, "2")
    t.eq(find(tree, "move_up").disabled, nil)
    t.eq(find(tree, "move_down").disabled, true)
end)

t.test("a command step has no dialogs to edit", function()
    local draft = chain("Signs", { model.command_step("X", "Duplicate") })
    local tree = view.editor(draft, 1, fake.t)
    t.eq(find(tree, "select").value, "macro")
    t.eq(find(tree, "show"), nil)
    t.eq(find(tree, "mode:1:1"), nil)
end)
