local json = require "chains.json"
local model = require "chains.model"
local recorder = require "chains.recorder"
local replay = require "chains.replay"
local import = require "chains.import"
local store = require "chains.store"
local view = require "chains.view"

local M = {}
M.__index = M

function M.new(deps)
    local self = setmetatable({ deps = deps, t = deps.t, store = store.open(deps.files),
        recorder = recorder.new(deps.own), mode = "library" }, M)
    self.selected = self.store.chains[1] and self.store.chains[1].name
    return self
end

function M:notify(text, level)
    if self.deps.notify then
        self.deps.notify(text, level)
    end
end

function M:loaded()
    local set = {}
    for _, m in ipairs(self.deps.macros() or {}) do
        if m.enabled ~= false then
            set[m.macro] = true
        end
    end
    return set
end

function M:show()
    local tree
    if self.mode == "recording" then
        tree = view.recording(self.rec_name, self.recorder:steps(), self.t)
    elseif self.mode == "editing" then
        tree = view.editor(self.draft, self.at, self.t)
    else
        local loaded = self:loaded()
        self.stale = false
        for _, chain in ipairs(self.store.chains) do
            self.stale = self.stale or view.missing(chain, loaded) ~= nil
        end
        tree = view.library(self.store.chains, { selected = self.selected, notice = self.notice }, loaded, self.t)
    end
    self.deps.render(tree)
end

function M:save()
    local ok, err = self.store:save()
    if not ok then
        self:notify(self.t("save_failed", err and err.message or "?"), "error")
    end
end

function M:record()
    if self.mode == "recording" then
        return self:stop(self.rec_name)
    end
    self.rec_name = self.store:unique(self.t("new_chain"))
    self.recorder:start(self.rec_name)
    self.mode, self.notice = "recording", nil
    self:show()
end

function M:stop(name)
    local chain = self.recorder:stop()
    self.mode = "library"
    if #chain.steps == 0 then
        self:notify(self.t("nothing_recorded"))
    else
        chain.name = name ~= nil and name ~= "" and name or self.rec_name
        self.selected = self.store:add(chain).name
        self:save()
    end
    self:show()
end

function M:run(chain)
    if self.mode == "recording" then
        return self:notify(self.t("busy_recording"), "warning")
    end
    local report = replay.run(chain, self.deps.host, self.t)
    if report.learned then
        self:save()
    end
    if report.outcome == "failed" then
        self.notice = { chain = chain.name, step = report.step, message = report.message, steps = report.steps }
        self.undo_revision = self.deps.revision()
    else
        self.notice = nil
    end
    self:show()
end

function M:run_slot(n)
    for _, chain in ipairs(self.store.chains) do
        if chain.slot == n then
            return self:run(chain)
        end
    end
    self:notify(self.t("slot_empty", n), "warning")
end

function M:undo_chain()
    if self.deps.revision() == self.undo_revision then
        self.deps.undo()
    else
        self:notify(self.t("undo_moved"), "warning")
    end
    self.notice = nil
    self:show()
end

function M:on_macro_ran(data)
    if self.mode == "recording" then
        self.recorder:macro_ran(data)
        self:show()
    end
end

function M:on_selection_changed()
    if self.mode == "library" and self.stale then
        self:show()
    end
end

function M:on_command_ran(data)
    if self.mode == "recording" then
        local name = self.deps.command_name and self.deps.command_name(data.command)
        self.recorder:command_ran(data, name)
        self:show()
    end
end

function M:import()
    local text, name = self.deps.pick()
    if not text then
        return
    end
    local found, why = import.read(text, self.deps.macros() or {})
    if not found then
        return self:notify(self.t("import_failed", self.t("import_" .. why)), "error")
    end
    local rows, problems = json.array(), {}
    for _, p in ipairs(found.problems) do
        problems[p.chain] = problems[p.chain] or {}
        local list = problems[p.chain]
        list[#list + 1] = p.problem == "missing_macro" and self.t("import_missing", p.macro) or self.t("import_asked_button", p.step)
    end
    for i, chain in ipairs(found.chains) do
        local detail = self.t("steps", #chain.steps)
        if problems[chain.name] then
            detail = detail .. " · " .. table.concat(problems[chain.name], " · ")
        end
        rows[i] = { id = tostring(i), text = chain.name, detail = detail,
            icon = problems[chain.name] and "notice-warning" or nil }
    end
    local n = #found.chains
    local button = self.deps.ask("import", {
        title = self.t("import_title"),
        body = { kind = "column", children = json.array({
            { kind = "label", text = self.t("import_holds", name or "?", n), wrap = true },
            { kind = "list", id = "found", rows = rows },
            { kind = "label", text = self.t("import_hint"), style = "muted", wrap = true },
            { kind = "label", text = self.t("credit"), style = "small" } }) },
        buttons = json.array({ { id = "import", text = self.t("import_n", n), style = "primary", default = true },
            { id = "cancel", text = self.t("cancel"), cancel = true } }),
    })
    if button ~= "import" or n == 0 then
        return
    end
    local first
    for _, chain in ipairs(found.chains) do
        local added = self.store:add(chain)
        first = first or added.name
    end
    self.selected = first
    self:save()
    self:notify(self.t("imported", n))
    self:show()
end

function M:delete()
    local chain = self.selected and self.store:find(self.selected)
    if not chain then
        return
    end
    local button = self.deps.ask("delete", {
        title = self.t("delete_title"),
        body = { kind = "label", text = self.t("delete_body", chain.name), wrap = true },
        buttons = json.array({ { id = "delete", text = self.t("delete"), style = "danger" },
            { id = "cancel", text = self.t("cancel"), cancel = true, default = true } }),
    })
    if button ~= "delete" then
        return
    end
    self.store:remove(chain.name)
    self.selected = self.store.chains[1] and self.store.chains[1].name
    self:save()
    self:show()
end

function M:edit()
    local chain = self.selected and self.store:find(self.selected)
    if not chain then
        return
    end
    self.editing, self.draft, self.at = chain, model.copy(chain), 1
    self.mode, self.notice = "editing", nil
    self:show()
end

function M:keep_edit()
    local draft, chain = self.draft, self.editing
    local name = draft.name ~= "" and draft.name or chain.name
    draft.name = self.store:unique(name, chain)
    local _, i = self.store:find(chain.name)
    self.store.chains[i] = draft
    if draft.slot then
        for _, other in ipairs(self.store.chains) do
            if other ~= draft and other.slot == draft.slot then
                other.slot = nil
            end
        end
    end
    self.selected = draft.name
    self:save()
end

local function field_at(step, id)
    local d, f = id:match("^%a+:(%d+):(%d+)$")
    local dialog = step and step.dialogs and step.dialogs[tonumber(d)]
    return dialog and dialog.fields[tonumber(f)]
end

local function coerce(field, value)
    local kind = model.VALUE_KINDS[field.kind]
    if kind == "number" then
        return tonumber(value) or field.value
    elseif kind == "boolean" then
        return value == true
    end
    return value ~= nil and tostring(value) or field.value
end

function M:on_editor(e)
    local draft, step = self.draft, self.draft.steps[self.at]
    local w = e.widget or ""
    if e.kind == "change" then
        if w == "name" then
            draft.name = tostring(e.value or "")
        elseif w == "select" and step then
            step.select = model.SELECT_MODES[e.value] and e.value or step.select
        elseif w == "show" and step then
            step.show = e.value == true
        elseif w == "slot" then
            draft.slot = tonumber(e.value)
        elseif w:find("^mode:") then
            local field = field_at(step, w)
            if field and model.FIELD_MODES[e.value] then
                field.mode = e.value
                self:show()
            end
        elseif w:find("^value:") then
            local field = field_at(step, w)
            if field then
                field.value = coerce(field, e.value)
            end
        end
    elseif e.kind == "select" and w == "steps" then
        self.at = tonumber(e.value) or self.at
        self:show()
    elseif e.kind == "click" then
        local steps = draft.steps
        if w == "move_up" and self.at > 1 then
            steps[self.at], steps[self.at - 1] = steps[self.at - 1], steps[self.at]
            self.at = self.at - 1
        elseif w == "move_down" and self.at < #steps then
            steps[self.at], steps[self.at + 1] = steps[self.at + 1], steps[self.at]
            self.at = self.at + 1
        elseif w == "remove_step" and step then
            table.remove(steps, self.at)
            self.at = math.max(1, math.min(self.at, #steps))
        elseif w == "save" then
            self:keep_edit()
            self.mode = "library"
        elseif w == "cancel" then
            self.mode = "library"
        end
        self:show()
    end
end

function M:on_library(e)
    local w = e.widget
    local picked = w == "chains" and self.store.chains[view.row_index(e.value)]
    if e.kind == "select" and w == "chains" then
        self.selected = picked and picked.name or self.selected
        return self:show()
    end
    if e.kind == "activate" and w == "chains" then
        self.selected = picked and picked.name or self.selected
        w = "run"
    elseif e.kind ~= "click" and e.kind ~= "menu" then
        return
    end
    local chain = self.selected and self.store:find(self.selected)
    if w == "record" then
        self:record()
    elseif (w == "run" or w == "run_selected") and chain then
        self:run(chain)
    elseif (w == "edit" or w == "edit_selected") and chain then
        self:edit()
    elseif w == "import" then
        self:import()
    elseif w == "delete" then
        self:delete()
    elseif w == "undo_chain" then
        self:undo_chain()
    elseif w == "show_log" then
        self.deps.show_log()
    end
end

function M:on_panel(e)
    if e.kind == "show" then
        return self:show()
    end
    if self.mode == "recording" then
        local values = e.values or {}
        if e.kind == "change" and e.widget == "rec_name" then
            self.rec_name = tostring(e.value or "")
        elseif e.kind == "click" and e.widget == "stop" then
            self:stop(values.rec_name or self.rec_name)
        elseif e.kind == "click" and e.widget == "discard" then
            self.recorder:stop()
            self.mode = "library"
            self:show()
        end
    elseif self.mode == "editing" then
        self:on_editor(e)
    else
        self:on_library(e)
    end
end

return M
