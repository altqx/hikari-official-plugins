local compare = require "gitmarks.compare"
local marks = require "gitmarks.marks"
local panel = require "gitmarks.panel"

local t = hikari.i18n.t
local host = {vcs = hikari.vcs, document = hikari.document, marks = hikari.marks}

local remembered = hikari.settings.get("last-ref")
local state = {
    search = "",
    picked = remembered ~= "" and remembered or nil,
    onSave = hikari.settings.get("refresh-on-save"),
}

local function render()
    pcall(hikari.panels.render, panel.ID, panel.tree(state, t))
end

local function present(value)
    return value ~= nil and value ~= hikari.null
end

local function folder_of(path)
    return present(path) and (path:match("^(.*)[/\\][^/\\]*$") or path) or ""
end

local function quoted(path)
    if path:find("[%s'\"]") then
        return '"' .. path:gsub('"', '\\"') .. '"'
    end
    return path
end

local function problem(err, document)
    local p = {state = compare.problem(err), message = type(err) == "table" and err.message or nil}
    if p.state == "unsafe_repository" then
        p.folder = p.message and p.message:match("'([^']+)'") or folder_of(document and document.path)
        p.command = "git config --global --add safe.directory " .. quoted(p.folder)
    end
    return p
end

local function load_refs()
    state.refs, state.problem = nil, nil
    local document = hikari.call("documents.get", {})
    state.title = document and document.title or nil
    if not document then
        return
    end
    if document.format ~= "ass" then
        state.problem = {state = "not_ass"}
        return
    end
    if not present(document.path) then
        state.problem = {state = "no_path"}
        return
    end
    local refs, err = hikari.vcs.refs({limit = 50})
    if not refs then
        state.problem = problem(err, document)
        return
    end
    state.refs = refs
end

local function run()
    if not state.picked or not state.refs then
        render()
        return
    end
    state.busy, state.problem = true, nil
    render()
    local done, failure = compare.run(host, state.picked, nil, t)
    state.busy = false
    if done then
        state.done, state.compared = done, marks.label(state.picked)
        hikari.settings.set("last-ref", state.picked)
    else
        state.done = nil
        local document = hikari.call("documents.get", {})
        state.problem = failure.error and problem(failure.error, document) or failure
        state.problem.state = failure.state
        hikari.marks.clear()
    end
    render()
end

local function refresh()
    load_refs()
    if state.done or state.picked then
        run()
    else
        render()
    end
end

local function clear()
    hikari.marks.clear()
    state.done = nil
    render()
end

local function choose(value)
    if type(value) == "string" and value:sub(1, 4) == "ref:" then
        state.picked = value:sub(5)
        return true
    end
    return false
end

hikari.panels.on(panel.ID, function(e)
    if e.kind == "show" then
        if not state.refs and not state.problem then load_refs() end
        render()
    elseif e.widget == "search" and e.kind == "change" then
        state.search = e.value or ""
        render()
    elseif e.widget == "search" and e.kind == "submit" then
        local typed = (e.value or ""):match("^%s*(.-)%s*$")
        if typed ~= "" then
            state.picked = typed
            run()
        end
    elseif e.widget == "refs" and e.kind == "select" then
        if choose(e.value) then render() end
    elseif e.widget == "refs" and e.kind == "activate" then
        if choose(e.value) then run() end
    elseif e.kind == "click" and e.widget == "compare" then
        run()
    elseif e.kind == "click" and (e.widget == "refresh" or e.widget == "reload") then
        refresh()
    elseif e.kind == "click" and e.widget == "clear" then
        clear()
    elseif e.kind == "click" and e.widget == "save" then
        hikari.commands.run("GLOBAL_SAVE_SUBS")
    elseif e.kind == "change" and e.widget == "on-save" then
        state.onSave = e.value and true or false
        hikari.settings.set("refresh-on-save", state.onSave)
    elseif e.widget == "changes" and (e.kind == "select" or e.kind == "activate") then
        local line = tonumber(e.value)
        if line then hikari.selection.set({line}, line) end
    end
end)

hikari.commands.register("refresh", function()
    hikari.panels.show(panel.ID)
    refresh()
end)

hikari.commands.register("clear", clear)

hikari.events.on("document.saved", function()
    if state.problem and state.problem.state == "no_path" then
        refresh()
    elseif state.onSave and state.done then
        run()
    end
end)

hikari.events.on("documents.changed", function()
    state.done, state.compared, state.search = nil, nil, ""
    load_refs()
    render()
end)
