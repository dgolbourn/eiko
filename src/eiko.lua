print("hello")

local region = {}      
region[1] = nil
region[2] = nil
region[3] = nil

local ffi = require("ffi")
ffi.cdef[[
int printf(const char *fmt, ...);
]]
ffi.C.printf("Hello %s!\n", "world")