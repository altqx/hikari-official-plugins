package.path = "lua/?.lua;" .. package.path
assert(require("sample").greeting() == "hello")
print("1 test passed")
