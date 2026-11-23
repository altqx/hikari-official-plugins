local check = require "glossary.check"

local t = hikari.i18n.t
local SEVERITY = {Error = "error", Warning = "warning", Information = "info", Hint = "hint"}
local MOST = 20000
local PAGE = 5000

local checked = {}

local function settings()
    return check.rules(hikari.settings.get("terms")), hikari.settings.get("match-case"),
        SEVERITY[hikari.settings.get("severity")] or "warning"
end

local function read_lines(document)
    local lines, offset, revision = {}, 0, nil
    while true do
        local page = hikari.call("lines.list", {document = document, offset = offset, limit = PAGE, fields = {"text", "comment"}})
        if not page then
            return nil
        end
        if revision and page.revision ~= revision then
            return nil
        end
        revision = page.revision
        for _, line in ipairs(page.lines) do
            lines[#lines + 1] = line
        end
        if #page.lines < PAGE then
            return lines, revision
        end
        offset = offset + PAGE
    end
end

local function check_document(document)
    local rules, matchCase, severity = settings()
    if #rules == 0 then
        pcall(hikari.problems.clear, {document = document})
        checked[document] = nil
        return
    end
    local lines, revision = read_lines(document)
    if not lines or checked[document] == revision then
        return
    end
    local ok = pcall(hikari.problems.set, check.problems(lines, rules, matchCase, severity, t, MOST),
        {revision = revision, document = document})
    checked[document] = ok and revision or nil
end

local function check_all()
    checked = {}
    local listed = hikari.call("documents.list", {})
    for _, d in ipairs(listed and listed.documents or {}) do
        check_document(d.document)
    end
end

hikari.commands.register("check", check_all)

hikari.events.on("document.changed", function(e)
    check_document(e.document)
end)

hikari.events.on("documents.changed", function(e)
    local open = {}
    for _, id in ipairs(e.documents) do
        open[id] = true
        if checked[id] == nil then
            check_document(id)
        end
    end
    for id in pairs(checked) do
        if not open[id] then
            checked[id] = nil
        end
    end
end)

pcall(hikari.events.on, "plugin_settings.changed", check_all)

check_all()
