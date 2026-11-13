local t = require "t"
local model = require "chains.model"

local ran = {
    file = "fade.lua", macro = "Fade", ok = true, outcome = "applied",
    dialogs = { {
        key = "0123456789abcdef", button = "Apply",
        values = { tags = "\\blur2", count = 3, flag = true },
        controls = { { name = "tags", kind = "edit", hint = "Tags to add" }, { name = "count", kind = "intedit", min = 0, max = 9 },
            { name = "flag", kind = "checkbox", label = "Keep" } },
    } },
}

t.test("a recorded macro step keeps every value as a constant, in the dialog's order", function()
    local step = model.macro_step(ran)
    t.eq(step.kind, "macro")
    t.eq(step.select, "macro")
    local fields = step.dialogs[1].fields
    t.eq(#fields, 3)
    t.eq({ fields[1].name, fields[1].mode, fields[1].value, fields[1].title }, { "tags", "constant", "\\blur2", "Tags to add" })
    t.eq(fields[3].title, "Keep")
    t.eq(fields[2].control.max, 9)
end)

t.test("an answer gives constants and asked values, never excluded ones, by controls", function()
    local dialog = model.macro_step(ran).dialogs[1]
    dialog.fields[1].mode = "ask"
    dialog.fields[2].mode = "exclude"
    local answer = model.answer(dialog, { tags = "\\fs20" })
    t.eq(answer.values, { tags = "\\fs20", flag = true })
    t.eq(answer.button, "Apply")
    t.eq(answer.key, nil)
    t.eq(answer.controls, { { kind = "edit", name = "tags" }, { kind = "intedit", name = "count" }, { kind = "checkbox", name = "flag" } })
    t.eq(model.answer(dialog, {}).values.tags, "\\blur2")
end)

t.test("asked fields are listed across steps with ids for the merged dialog", function()
    local chain = model.new_chain("Signs")
    local a, b = model.macro_step(ran), model.macro_step(ran)
    a.dialogs[1].fields[2].mode = "ask"
    b.dialogs[1].fields[1].mode = "ask"
    chain.steps = { a, model.command_step("EDIT_LINE_DUPLICATE", "Duplicate"), b }
    local asked = model.asked(chain)
    t.eq(#asked, 2)
    t.eq({ asked[1].id, asked[2].id }, { "s1-d1-count", "s3-d1-tags" })
end)

t.test("learning a run keeps modes and values and excludes fields an import didn't name", function()
    local step = { kind = "macro", macro = "Fade", select = "macro", learn = true, dialogs = { {
        partial = true, button = "Apply", controls = {},
        fields = { { name = "count", kind = "intedit", mode = "ask", value = 5, title = "How many" } },
    } } }
    model.learn(step, ran.dialogs)
    local d = step.dialogs[1]
    t.eq(d.key, "0123456789abcdef")
    t.eq(d.partial, nil)
    t.eq(step.learn, nil)
    t.eq({ d.fields[1].name, d.fields[1].mode }, { "tags", "exclude" })
    t.eq({ d.fields[2].mode, d.fields[2].value, d.fields[2].title }, { "ask", 5, "How many" })
    t.eq(#model.answer(d, {}).controls, 3)
end)

t.test("validate names what's wrong with a stored chain", function()
    t.ok(model.validate({ name = "x", steps = { model.macro_step(ran) } }))
    local ok, err = model.validate({ name = "x", steps = { { kind = "macro", macro = "m", select = "sideways" } } })
    t.eq(ok, false)
    t.eq(err, "step 1: unknown selection mode")
    t.eq(select(2, model.validate({ steps = {} })), "a chain needs a name")
end)
