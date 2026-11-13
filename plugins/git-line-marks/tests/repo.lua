local M = {}

local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local p = io.popen(command .. " 2>/dev/null; echo \"exit=$?\"", "r")
    local out = p:read("*a")
    p:close()
    local body, code = out:match("^(.*)exit=(%d+)\n?$")
    return body, tonumber(code)
end

function M.available()
    local _, code = capture("git --version")
    return code == 0
end

function M.git(dir, args)
    local out, code = capture("git -C " .. quote(dir) .. " -c user.name=Test -c user.email=test@example.invalid "
        .. "-c init.defaultBranch=master -c commit.gpgsign=false -c tag.gpgsign=false " .. args)
    assert(code == 0, "git " .. args .. " failed")
    return out
end

function M.create()
    local base = os.getenv("TMPDIR") or "/tmp"
    local dir = capture("mktemp -d " .. quote(base .. "/git-line-marks.XXXXXX")):gsub("\n$", "")
    M.git(dir, "init -q")
    return dir
end

function M.remove(dir)
    assert(dir:find("git%-line%-marks%."), "refusing to remove " .. dir)
    os.execute("rm -rf " .. quote(dir))
end

function M.write(dir, path, text)
    local f = assert(io.open(dir .. "/" .. path, "wb"))
    f:write(text)
    f:close()
end

function M.read(dir, path)
    local f = assert(io.open(dir .. "/" .. path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

function M.commit_all(dir, message)
    M.git(dir, "add -A")
    M.git(dir, "commit -q -m " .. quote(message))
end

function M.commit(dir, ref)
    return (M.git(dir, "rev-parse --verify -q " .. quote(ref .. "^{commit}")):gsub("\n$", ""))
end

function M.show(dir, ref, path)
    local _, known = capture("git -C " .. quote(dir) .. " rev-parse --verify -q " .. quote(ref .. "^{commit}"))
    if known ~= 0 then
        return nil, {code = "not_found", message = "no such ref", data = {reason = "no_ref"}}
    end
    local text, code = capture("git -C " .. quote(dir) .. " show " .. quote(ref .. ":" .. path))
    if code ~= 0 then
        return nil, {code = "not_found", message = "not in that ref", data = {reason = "no_file"}}
    end
    return text
end

return M
