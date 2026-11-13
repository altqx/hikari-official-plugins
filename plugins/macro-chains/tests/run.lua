package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;" .. package.path

local t = require "t"
for _, suite in ipairs({ "json_test", "model_test", "recorder_test", "replay_test", "import_test", "store_test", "view_test", "app_test", "i18n_test", "host_test", "main_test" }) do
    local ok, err = pcall(require, suite)
    if not ok and not tostring(err):find("module '" .. suite .. "' not found", 1, true) then
        error(err, 0)
    end
end
os.exit(t.finish() and 0 or 1)
