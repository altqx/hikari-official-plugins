local json = require "chains.json"
local model = require "chains.model"
local replay = require "chains.replay"

local M = {}

M.SLOTS = 5

function M.row_id(i)
    return "c" .. i
end

function M.row_index(id)
    return tonumber(tostring(id or ""):match("^c(%d+)$"))
end

local function arr(t)
    return json.array(t or {})
end

local function asks(step)
    local n = 0
    for _, dialog in ipairs(step.dialogs or {}) do
        for _, field in ipairs(dialog.fields) do
            if field.mode == "ask" then
                n = n + 1
            end
        end
    end
    return n
end

function M.missing(chain, loaded)
    for _, step in ipairs(chain.steps) do
        if step.kind == "macro" and not loaded[step.macro] then
            return step.macro
        end
    end
end

local function chain_row(i, chain, loaded, t)
    local parts, n, learns = { t("steps", #chain.steps) }, 0, false
    for _, step in ipairs(chain.steps) do
        n = n + asks(step)
        learns = learns or step.learn == true
    end
    if n > 0 then
        parts[#parts + 1] = t("asks", n)
    end
    if chain.slot then
        parts[#parts + 1] = t("slot", chain.slot)
    end
    local gone = M.missing(chain, loaded)
    if gone then
        parts[#parts + 1] = t("not_loaded", gone)
    elseif learns then
        parts[#parts + 1] = t("learns")
    end
    return { id = M.row_id(i), text = chain.name, detail = table.concat(parts, " · "), muted = gone and true or nil }
end

local function notice(state, chains, t)
    local n = state.notice
    local chain
    for _, c in ipairs(chains) do
        if c.name == n.chain then
            chain = c
        end
    end
    local step = chain and chain.steps[n.step]
    local text = t("stopped", n.chain, n.step, step and model.title(step) or "?", n.message or "")
    if (n.steps or 0) > 0 then
        text = text .. " " .. t("undo_hint", n.steps)
    end
    local buttons = arr()
    if (n.steps or 0) > 0 then
        buttons[#buttons + 1] = { kind = "button", id = "undo_chain", text = t("undo_chain") }
    end
    buttons[#buttons + 1] = { kind = "button", id = "show_log", text = t("show_log") }
    return { kind = "group", title = t("stopped_title"), children = arr({
        { kind = "label", id = "notice", text = text, wrap = true },
        { kind = "row", children = buttons } }) }
end

function M.needs_newer(t)
    return { kind = "column", children = arr({ { kind = "empty", text = t("needs_hikarisub") } }) }
end

function M.library(chains, state, loaded, t)
    local none = state.selected == nil
    local children = arr({ { kind = "row", children = arr({
        { kind = "button", id = "record", text = t("record") },
        { kind = "icon_button", id = "run", icon = "run-script", name = t("run"), disabled = none or nil },
        { kind = "icon_button", id = "edit", icon = "edit", name = t("edit"), disabled = none or nil },
        { kind = "icon_button", id = "import", icon = "import", name = t("import") },
        { kind = "icon_button", id = "delete", icon = "delete", name = t("delete"), disabled = none or nil },
    }) } })
    if #chains == 0 then
        children[#children + 1] = { kind = "empty", text = t("empty") }
    else
        local rows, selected = arr(), nil
        for i, chain in ipairs(chains) do
            rows[i] = chain_row(i, chain, loaded, t)
            if chain.name == state.selected then
                selected = rows[i].id
            end
        end
        children[#children + 1] = { kind = "list", id = "chains", rows = rows, selected = selected, grow = true }
    end
    if state.notice then
        children[#children + 1] = notice(state, chains, t)
    end
    children[#children + 1] = { kind = "row", children = arr({
        { kind = "button", id = "run_selected", text = t("run"), style = "primary", disabled = none or nil },
        { kind = "button", id = "edit_selected", text = t("edit"), disabled = none or nil } }) }
    return { kind = "column", children = children }
end

local function step_rows(steps, t, detail)
    local rows = arr()
    for i, step in ipairs(steps) do
        rows[i] = { id = tostring(i), text = string.format("%d. %s", i, model.title(step)), detail = detail(step),
            icon = step.kind == "macro" and "automation" or "hotkeys" }
    end
    return rows
end

function M.recording(name, steps, t)
    return { kind = "column", children = arr({
        { kind = "label", text = t("recording"), style = "heading" },
        { kind = "label", text = t("recording_hint"), style = "muted", wrap = true },
        { kind = "text", id = "rec_name", label = t("name"), value = name },
        { kind = "list", id = "rec_steps", grow = true, rows = step_rows(steps, t, function(step)
            if step.kind ~= "macro" then
                return t("command")
            end
            local n = #(step.dialogs or {})
            return n == 0 and t("no_dialog") or t("dialogs", n)
        end) },
        { kind = "row", children = arr({
            { kind = "button", id = "stop", text = t("stop_save"), style = "primary" },
            { kind = "button", id = "discard", text = t("discard"), style = "danger" } }) },
    }) }
end

local function options(values, prefix, t)
    local out = arr()
    for i, v in ipairs(values) do
        out[i] = { value = v, text = t(prefix .. v) }
    end
    return out
end

local function dialog_group(d, dialog, t)
    local cells = arr()
    for f, field in ipairs(dialog.fields) do
        local id = string.format("%d:%d", d, f)
        local value = replay.field_widget("value:" .. id, field)
        value.label, value.text, value.name = nil, nil, field.title or field.name
        value.disabled = field.mode == "exclude" or nil
        cells[#cells + 1] = { kind = "label", text = field.title or field.name }
        cells[#cells + 1] = { kind = "choice", id = "mode:" .. id, name = field.title or field.name,
            options = options({ "constant", "ask", "exclude" }, "mode_", t), value = field.mode }
        cells[#cells + 1] = value
    end
    local body = #cells > 0 and { kind = "grid", columns = 3, children = cells }
        or { kind = "label", text = t("no_fields"), style = "muted" }
    return { kind = "group", title = t("dialog_title", d, dialog.button ~= "" and dialog.button or "?"),
        children = arr({ body }) }
end

function M.editor(draft, at, t)
    local step = draft.steps[at]
    local function detail(s)
        local text = t("select_" .. s.select)
        local n = asks(s)
        return n > 0 and text .. " · " .. t("asks", n) or text
    end
    local children = arr({
        { kind = "text", id = "name", label = t("name"), value = draft.name },
        { kind = "list", id = "steps", rows = step_rows(draft.steps, t, detail), selected = step and tostring(at) or nil },
        { kind = "row", children = arr({
            { kind = "icon_button", id = "move_up", icon = "move-up", name = t("move_up"), disabled = (not step or at == 1) or nil },
            { kind = "icon_button", id = "move_down", icon = "move-down", name = t("move_down"),
                disabled = (not step or at == #draft.steps) or nil },
            { kind = "icon_button", id = "remove_step", icon = "delete", name = t("remove_step"), disabled = (not step) or nil },
        }) },
    })
    if step then
        local inner = arr({ { kind = "dropdown", id = "select", label = t("select_after"),
            options = options({ "macro", "keep", "changed" }, "select_", t), value = step.select } })
        if step.kind == "macro" then
            inner[#inner + 1] = { kind = "check", id = "show", text = t("show_dialogs"), value = step.show == true }
            for d, dialog in ipairs(step.dialogs or {}) do
                inner[#inner + 1] = dialog_group(d, dialog, t)
            end
        end
        children[#children + 1] = { kind = "group", title = t("step_title", at, model.title(step)), children = inner }
    end
    local slots = arr({ { value = "none", text = t("slot_none") } })
    for i = 1, M.SLOTS do
        slots[#slots + 1] = { value = tostring(i), text = t("slot_option", i) }
    end
    children[#children + 1] = { kind = "dropdown", id = "slot", label = t("shortcut_slot"), options = slots,
        value = draft.slot and tostring(draft.slot) or "none" }
    children[#children + 1] = { kind = "row", children = arr({
        { kind = "button", id = "save", text = t("save"), style = "primary" },
        { kind = "button", id = "cancel", text = t("cancel") } }) }
    return { kind = "column", children = children }
end

return M
