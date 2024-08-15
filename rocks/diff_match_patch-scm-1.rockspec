rockspec_format = "3.0"
package = "diff_match_patch"
version = "scm-1"
source = {
   url="git://github.com/google/diff-match-patch"
}
dependencies = {
   "lua==5.1"
}
description = {}
build = {
   type = "builtin",
   modules = {
      diff_match_patch = "lua/diff_match_patch.lua"
   },
   patches = {
      ["lua51-support.diff"] =
            "--- a/lua/diff_match_patch.lua\n" ..
            "+++ b/lua/diff_match_patch.lua\n" ..
            "@@ -27,8 +27,11 @@\n" ..
            "     = bit.band, bit.bor, bit.lshift\n" ..
            " --]]\n" ..
            " \n" ..
            "+-- local band, bor, lshift\n" ..
            "+--     = bit32.band, bit32.bor, bit32.lshift\n" ..
            "+require 'bit'\n" ..
            " local band, bor, lshift\n" ..
            "-    = bit32.band, bit32.bor, bit32.lshift\n" ..
            "+    = bit.band, bit.bor, bit.lshift\n" ..
            " local type, setmetatable, ipairs, select\n" ..
            "     = type, setmetatable, ipairs, select\n" ..
            " local unpack, tonumber, error\n"
   }   
}
