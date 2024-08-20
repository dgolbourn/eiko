local lu = require "luaunit"

Test = {}

function Test:test_ffi()
    local ffi = require("ffi")
    ffi.cdef[[int printf(const char *fmt, ...);]]
    ffi.C.printf("Hello %s!\n", "world")
end

os.exit(lu.LuaUnit.run())
