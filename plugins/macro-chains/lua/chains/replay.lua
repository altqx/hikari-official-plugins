local json = require "chains.json"
local model = require "chains.model"

local M = {}

function M.field_widget(id, f)
    local c = f.control or {}
    local w = { id = id, label = f.title or f.name, tooltip = c.hint ~= "" and c.hint or nil }
    if f.kind == "intedit" or f.kind == "floatedit" then
        w.kind = "number"
        w.value = tonumber(f.value) or 0
        w.minimum, w.maximum = c.min, c.max
        w.decimals = f.kind == "intedit" and 0 or 3
        w.step = f.kind == "floatedit" and c.step and c.step > 0 and c.step or nil
    elseif f.kind == "checkbox" then
        w.kind, w.text, w.label, w.value = "check", f.title or f.name, nil, f.value == true
    elseif f.kind == "dropdown" and c.items and #c.items > 0 then
        w.kind, w.options, w.value = "dropdown", json.array(model.copy(c.items)), tostring(f.value)
    elseif f.kind == "textbox" then
        w.kind, w.value, w.rows = "text_area", tostring(f.value or ""), 3
    else
        w.kind, w.value = "text", tostring(f.value or "")
    end
    return w
end

function M.dialog_spec(chain, t)
    local asked = model.asked(chain)
    if #asked == 0 then
        return nil, asked
    end
    local groups, by_step = json.array(), {}
    for _, entry in ipairs(asked) do
        local group = by_step[entry.step]
        if not group then
            group = { kind = "group", title = t("step_title", entry.step, model.title(chain.steps[entry.step])),
                children = json.array() }
            by_step[entry.step] = group
            groups[#groups + 1] = group
        end
        group.children[#group.children + 1] = M.field_widget(entry.id, entry.field)
    end
    return {
        title = chain.name,
        body = { kind = "column", children = groups },
        buttons = json.array({ { id = "run", text = t("run"), style = "primary", default = true },
            { id = "cancel", text = t("cancel"), cancel = true } }),
    }, asked
end

local function line_text(line)
    local keys = {}
    for k in pairs(line) do
        if k ~= "row" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. "=" .. tostring(line[k])
    end
    return table.concat(parts, "\1")
end

local function snapshot(host)
    local out = {}
    for _, line in ipairs(host.lines() or {}) do
        out[line.id] = line_text(line)
    end
    return out
end

local function changed_since(before, host)
    local selected = json.array()
    for _, line in ipairs(host.lines() or {}) do
        if before[line.id] ~= line_text(line) then
            selected[#selected + 1] = line.id
        end
    end
    return selected
end

local function still_there(ids, host)
    local present = {}
    for _, line in ipairs(host.lines() or {}) do
        present[line.id] = true
    end
    local out = json.array()
    for _, id in ipairs(ids or {}) do
        if present[id] then
            out[#out + 1] = id
        end
    end
    return out
end

local function run_step(step, values, host)
    local learned = false
    if step.kind == "command" then
        local ok, err = host.run_command(step.command)
        return ok and true or false, err and err.message
    end
    local answers = json.array()
    for d, dialog in ipairs(step.dialogs or {}) do
        answers[d] = model.answer(dialog, values[d])
    end
    local result, err = host.run_macro({ file = step.file, macro = step.macro, answers = answers,
        show = step.show and "prefilled" or "never" })
    if not result then
        return false, err and err.message
    end
    local applied = result.outcome == "applied"
    if applied and step.learn and result.dialogs then
        model.learn(step, result.dialogs)
        learned = true
    end
    local message = (result.message or ""):gsub("%s+$", "")
    return applied, message ~= "" and message or result.outcome, learned
end

local function select_after(step, before, host)
    if step.select == "keep" then
        host.select(still_there(before.selected, host), before.active)
    elseif step.select == "changed" then
        local ids = changed_since(before.lines, host)
        if #ids > 0 then
            host.select(ids, ids[1])
        end
    end
end

function M.run(chain, host, t)
    local spec, asked = M.dialog_spec(chain, t)
    local values = {}
    if spec then
        local button, answered = host.ask(spec)
        if button ~= "run" then
            return { outcome = "cancelled" }
        end
        for _, entry in ipairs(asked) do
            values[entry.step] = values[entry.step] or {}
            values[entry.step][entry.dialog] = values[entry.step][entry.dialog] or {}
            local v = answered[entry.id]
            if v ~= nil then
                values[entry.step][entry.dialog][entry.field.name] = v
            end
        end
    end
    local report = { outcome = "applied", learned = false }
    local count = #chain.steps
    host.job(t("job_title", chain.name))
    local ended = host.group(chain.name, function()
        for i, step in ipairs(chain.steps) do
            if host.cancelled() then
                report.outcome, report.step = "cancelled", i
                return
            end
            host.progress((i - 1) / count, t("job_step", i, count, model.title(step)))
            local selection = host.selection() or {}
            local before = { selected = selection.selected, active = selection.active,
                lines = step.select == "changed" and snapshot(host) or nil }
            local ok, message, learned = run_step(step, values[i] or {}, host)
            report.learned = report.learned or learned
            if not ok then
                report.outcome, report.step, report.message = "failed", i, message
                return
            end
            select_after(step, before, host)
        end
    end)
    report.steps = ended and ended.steps or 0
    return report
end

return M
