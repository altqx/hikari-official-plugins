local json = require "chains.json"

local M = {}

M.FORMAT = 1
M.FIELD_MODES = { constant = true, ask = true, exclude = true }
M.SELECT_MODES = { macro = true, keep = true, changed = true }
M.VALUE_KINDS = { edit = "string", textbox = "string", dropdown = "string", color = "string", coloralpha = "string",
    alpha = "string", intedit = "number", floatedit = "number", checkbox = "boolean" }

local function copy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = json.is_array(t) and json.array() or {}
    for k, v in pairs(t) do
        out[k] = copy(v)
    end
    return out
end
M.copy = copy

function M.new_chain(name)
    return { format = M.FORMAT, name = name, steps = json.array() }
end

function M.dialog(ran)
    local fields = json.array()
    for _, control in ipairs(ran.controls or {}) do
        local value = ran.values[control.name]
        if value ~= nil and control.name ~= "" then
            fields[#fields + 1] = { name = control.name, kind = control.kind, mode = "constant", value = value,
                title = control.label ~= "" and control.label or control.hint ~= "" and control.hint or control.name,
                control = copy(control) }
        end
    end
    return { key = ran.key, button = ran.button or "", controls = copy(ran.controls or json.array()), fields = fields }
end

function M.macro_step(ran)
    local dialogs = json.array()
    for _, d in ipairs(ran.dialogs or {}) do
        dialogs[#dialogs + 1] = M.dialog(d)
    end
    return { kind = "macro", file = ran.file, macro = ran.macro, select = "macro", show = false, dialogs = dialogs }
end

function M.command_step(command, name)
    return { kind = "command", command = command, name = name or command, select = "macro" }
end

function M.title(step)
    return step.kind == "macro" and step.macro or step.name
end

function M.asked(chain)
    local out = {}
    for s, step in ipairs(chain.steps) do
        for d, dialog in ipairs(step.dialogs or {}) do
            for _, field in ipairs(dialog.fields) do
                if field.mode == "ask" then
                    out[#out + 1] = { id = string.format("s%d-d%d-%s", s, d, field.name), step = s, dialog = d, field = field }
                end
            end
        end
    end
    return out
end

function M.answer(dialog, asked)
    local values = {}
    for _, field in ipairs(dialog.fields) do
        if field.mode == "constant" then
            values[field.name] = field.value
        elseif field.mode == "ask" then
            local v = asked and asked[field.name]
            if v == nil then
                v = field.value
            end
            values[field.name] = v
        end
    end
    local answer = { values = values, button = dialog.button }
    if dialog.controls and #dialog.controls > 0 and not dialog.partial then
        local controls = json.array()
        for _, c in ipairs(dialog.controls) do
            controls[#controls + 1] = { kind = c.kind, name = c.name }
        end
        answer.controls = controls
    elseif dialog.key then
        answer.key = dialog.key
    else
        local controls = json.array()
        for _, field in ipairs(dialog.fields) do
            controls[#controls + 1] = { kind = field.kind or "edit", name = field.name }
        end
        answer.controls = controls
    end
    return answer
end

function M.learn(step, ran_dialogs)
    for i, ran in ipairs(ran_dialogs) do
        local old = step.dialogs[i]
        local fresh = M.dialog(ran)
        if old then
            local by_name = {}
            for _, f in ipairs(old.fields) do
                by_name[f.name] = f
            end
            for _, f in ipairs(fresh.fields) do
                local was = by_name[f.name]
                if was then
                    f.mode, f.value, f.title = was.mode, was.value, was.title or f.title
                elseif old.partial then
                    f.mode = "exclude"
                end
            end
            fresh.button = old.button ~= "" and old.button or fresh.button
        end
        step.dialogs[i] = fresh
    end
    step.learn = nil
end

local function check(cond, message)
    if not cond then
        error(message, 0)
    end
end

function M.validate(chain)
    return pcall(function()
        check(type(chain) == "table", "a chain is an object")
        check(type(chain.name) == "string" and chain.name ~= "", "a chain needs a name")
        check(type(chain.steps) == "table", "a chain needs steps")
        for i, step in ipairs(chain.steps) do
            local at = string.format("step %d: ", i)
            check(M.SELECT_MODES[step.select], at .. "unknown selection mode")
            if step.kind == "macro" then
                check(type(step.macro) == "string" and step.macro ~= "", at .. "no macro")
                for _, dialog in ipairs(step.dialogs or {}) do
                    for _, field in ipairs(dialog.fields or {}) do
                        check(M.FIELD_MODES[field.mode], at .. "unknown mode for " .. tostring(field.name))
                    end
                end
            else
                check(step.kind == "command" and type(step.command) == "string", at .. "unknown kind of step")
            end
        end
    end)
end

return M
