local json = require "chains.json"

local M = {}

local function marked(hikari, value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = marked(hikari, v)
    end
    return json.is_array(value) and hikari.array(out) or out
end
M.marked = marked

function M.render(hikari, panel, tree)
    return hikari.panels.render(panel, marked(hikari, tree))
end

function M.ask(hikari, dialog, spec)
    return hikari.dialogs.ask(dialog, marked(hikari, spec))
end

function M.new(hikari)
    local host = {}
    function host.lines()
        local doc = hikari.document.read()
        return doc and doc.lines or {}
    end
    function host.selection()
        return hikari.selection.get()
    end
    function host.select(selected, active)
        return hikari.selection.set(marked(hikari, selected), active)
    end
    function host.ask(spec)
        return M.ask(hikari, "replay", spec)
    end
    function host.group(name, fn)
        return hikari.document.group(name, fn)
    end
    function host.run_macro(params)
        return hikari.call("automation.run_macro", marked(hikari, params))
    end
    function host.run_command(command)
        return hikari.call("commands.run", { command = command })
    end
    function host.job(title)
        hikari.job.begin({ title = title })
    end
    function host.progress(fraction, text)
        hikari.job.progress(fraction, text)
    end
    function host.cancelled()
        return hikari.job.cancelled() == true
    end
    return host
end

function M.data_files(hikari)
    local files = {}
    function files.read(path)
        local file = hikari.files.open("data", path)
        if not file then
            return nil
        end
        return hikari.files.read(file)
    end
    function files.write(path, text)
        local file, err = hikari.files.open("data", path)
        if not file then
            return nil, err
        end
        return hikari.files.write(file, text)
    end
    return files
end

return M
