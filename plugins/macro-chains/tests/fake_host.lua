local M = {}

function M.new(texts)
    local host = { log = {}, lines_ = {}, sel = { selected = {}, active = nil }, macros = {}, commands = {},
        answer = { "run", {} }, groups = {}, next_id = 1 }
    for _, text in ipairs(texts or {}) do
        host.lines_[#host.lines_ + 1] = { id = host.next_id, text = text }
        host.next_id = host.next_id + 1
    end

    function host.lines()
        local out = {}
        for i, l in ipairs(host.lines_) do
            out[i] = { id = l.id, text = l.text, row = i }
        end
        return out
    end
    function host.selection()
        return { selected = host.sel.selected, active = host.sel.active }
    end
    function host.select(selected, active)
        host.log[#host.log + 1] = "select " .. table.concat(selected, ",")
        host.sel = { selected = selected, active = active }
    end
    function host.ask(spec)
        host.asked = spec
        return host.answer[1], host.answer[2]
    end
    function host.group(name, fn)
        local before = #host.log
        fn()
        host.groups[#host.groups + 1] = name
        local steps = 0
        for i = before + 1, #host.log do
            if host.log[i]:find("^ran ") then
                steps = steps + 1
            end
        end
        return { steps = steps }
    end
    function host.run_macro(params)
        local macro = host.macros[params.macro]
        host.requests = host.requests or {}
        host.requests[#host.requests + 1] = params
        if not macro then
            return nil, { code = "not_found", message = "No loaded macro" }
        end
        local outcome = macro(host, params.answers) or "applied"
        if outcome == "applied" then
            host.log[#host.log + 1] = "ran " .. params.macro
        end
        return { outcome = outcome, message = outcome == "applied" and "" or host.failure or "it broke", log = "",
            dialogs = host.dialogs and host.dialogs[params.macro] }
    end
    function host.run_command(id)
        local command = host.commands[id]
        if not command then
            return nil, { code = "refused", message = "Not now" }
        end
        command(host)
        host.log[#host.log + 1] = "ran " .. id
        return true
    end
    function host.job(title)
        host.job_title = title
    end
    function host.progress(_, text)
        host.log[#host.log + 1] = "progress " .. text
    end
    function host.cancelled()
        return host.cancel_at ~= nil and #host.groups == 0 and host.ran_count() >= host.cancel_at
    end
    function host.ran_count()
        local n = 0
        for _, e in ipairs(host.log) do
            if e:find("^ran ") then
                n = n + 1
            end
        end
        return n
    end
    function host.add(text)
        local line = { id = host.next_id, text = text }
        host.next_id = host.next_id + 1
        host.lines_[#host.lines_ + 1] = line
        return line
    end
    return host
end

function M.t(key, ...)
    local args = { ... }
    return key .. (#args > 0 and "(" .. table.concat((function()
        local out = {}
        for i, a in ipairs(args) do
            out[i] = tostring(a)
        end
        return out
    end)(), ",") .. ")" or "")
end

return M
