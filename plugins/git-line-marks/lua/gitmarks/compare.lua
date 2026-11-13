local ass = require "gitmarks.ass"
local diff = require "gitmarks.diff"
local marks = require "gitmarks.marks"

local M = {}

M.MARK_LIMIT = 20000

local KNOWN = {
    no_git = true, no_repository = true, unsafe_repository = true, no_path = true, no_file = true,
    no_ref = true, timed_out = true, too_large = true, not_text = true,
}

function M.problem(err)
    local reason = type(err) == "table" and type(err.data) == "table" and err.data.reason
    if KNOWN[reason] then return reason end
    if type(err) == "table" and err.code == "not_granted" then return "not_granted" end
    return "failed"
end

function M.run(host, ref, document, t)
    local snapshot, err = host.document.read(document)
    if not snapshot then
        return nil, {state = "failed", error = err}
    end
    if snapshot.format ~= "ass" then
        return nil, {state = "not_ass", format = snapshot.format}
    end
    local text, shown = host.vcs.show(ref, snapshot.document)
    if not text then
        return nil, {state = M.problem(shown), error = shown}
    end
    local old = ass.lines(text)
    if not old then
        return nil, {state = "not_ass_at_ref"}
    end
    local result = diff.compare(old, snapshot.lines)
    local list = marks.build(result, snapshot.lines, ref, t)
    local shownCount = #list
    if shownCount > M.MARK_LIMIT then
        for n = #list, M.MARK_LIMIT + 1, -1 do list[n] = nil end
    end
    host.marks.clear(nil, snapshot.document)
    if #list > 0 then
        local ok, setErr = host.marks.set(list, snapshot.document)
        if not ok then
            return nil, {state = "failed", error = setErr}
        end
    end
    return {
        result = result,
        marks = list,
        found = shownCount,
        entries = marks.entries(result, snapshot.lines, t),
        commit = shown.commit,
        document = snapshot.document,
        revision = snapshot.revision,
    }
end

return M
