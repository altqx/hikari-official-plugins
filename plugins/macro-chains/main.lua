local app = require "chains.app"
local host = require "chains.host"
local view = require "chains.view"

local PANEL = "chains"

local function t(key, ...)
    local args = { ... }
    if args[#args] == 1 then
        local one = key .. "_one"
        local text = hikari.i18n.t(one, ...)
        if text ~= one then
            return text
        end
    end
    return hikari.i18n.t(key, ...)
end

if not (hikari.document and hikari.document.group) then
    hikari.panels.on(PANEL, function(e)
        if e.kind == "show" then
            host.render(hikari, PANEL, view.needs_newer(t))
        end
    end)
    local function explain()
        hikari.notify(t("needs_hikarisub"), "warning")
    end
    hikari.commands.register("record", explain)
    for slot = 1, view.SLOTS do
        hikari.commands.register("run-slot-" .. slot, explain)
    end
    return
end

local names = {}
local function command_name(id)
    if names[id] == nil then
        local listed = hikari.call("commands.list", {})
        for _, c in ipairs(listed and listed.commands or {}) do
            names[c.command] = c.name
        end
        names[id] = names[id] or false
    end
    return names[id] or nil
end

local chains = app.new({
    t = t,
    own = "plugin." .. hikari.plugin.id .. ".",
    host = host.new(hikari),
    files = host.data_files(hikari),
    macros = function()
        local listed = hikari.call("automation.macros", {})
        return listed and listed.macros or {}
    end,
    command_name = command_name,
    render = function(tree)
        host.render(hikari, PANEL, tree)
    end,
    ask = function(dialog, spec)
        return host.ask(hikari, dialog, spec)
    end,
    pick = function()
        local picked = hikari.files.pick({ title = t("import_title"),
            filters = hikari.array({ { name = t("json_files"), patterns = hikari.array({ "*.json" }) } }) })
        if not picked then
            return nil
        end
        return hikari.files.read(picked), picked.name
    end,
    notify = function(text, level)
        hikari.notify(text, level)
    end,
    revision = function()
        local doc = hikari.document.read()
        return doc and doc.revision
    end,
    undo = function()
        return hikari.commands.run("GLOBAL_UNDO")
    end,
    show_log = function()
        hikari.call("panels.open", { panel = "Log" })
    end,
})

if chains.store.problem then
    hikari.notify(t("unreadable"), "warning")
end

hikari.panels.on(PANEL, function(e)
    chains:on_panel(e)
end)
hikari.events.on("macro.ran", function(data)
    chains:on_macro_ran(data)
end)
hikari.events.on("selection.changed", function()
    chains:on_selection_changed()
end)
hikari.events.on("command.ran", function(data)
    chains:on_command_ran(data)
end)
hikari.commands.register("record", function()
    hikari.panels.show(PANEL)
    chains:record()
end)
for slot = 1, view.SLOTS do
    hikari.commands.register("run-slot-" .. slot, function()
        chains:run_slot(slot)
    end)
end
