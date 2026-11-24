local file = assert(io.open("hikari-plugin.json", "rb"))
local manifest = file:read("*a")
file:close()

local passed, failed = 0, {}

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failed[#failed + 1] = name .. ": " .. tostring(err)
    end
end

local platforms = {"linux-x64", "linux-arm64", "windows-x64", "windows-arm64", "macos-x64", "macos-arm64"}

local function block(platform)
    return manifest:match('"' .. platform:gsub("%-", "%%-") .. '": (%b{})')
end

test("every platform downloads typos-lsp 0.1.58", function()
    for _, platform in ipairs(platforms) do
        local entry = assert(block(platform), platform .. " is missing")
        assert(entry:match('"url": "https://github%.com/tekumara/typos%-lsp/releases/download/v0%.1%.58/typos%-lsp%-v0%.1%.58%-'),
            platform .. " doesn't download 0.1.58")
        assert(entry:match('"sha256": "' .. ("%x"):rep(64) .. '"'), platform .. " has no SHA-256")
        assert(entry:match('"size": %d+'), platform .. " has no size")
        local entryFile = assert(entry:match('"entry": "([^"]+)"'), platform .. " names no entry")
        local windows = platform:match("^windows") ~= nil
        assert(entryFile:match("typos%-lsp%.exe$") or not windows, platform .. " runs no .exe")
    end
end)

test("the program has no network and no plugin protocol", function()
    assert(manifest:match('"network": false'))
    assert(not manifest:match('"api": true'))
end)

test("it is a program package with one language server", function()
    assert(not manifest:match('"main"'), "a program package has no main")
    assert(manifest:match('"languageServers": %[%s*{[^}]*"program": "typos%-lsp"'))
    assert(manifest:match('"tags": "blank"'))
end)

print(("%d passed, %d failed"):format(passed, #failed))
for _, f in ipairs(failed) do
    print(f)
end
os.exit(#failed == 0 and 0 or 1)
