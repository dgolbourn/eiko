rockspec_format = "3.0"
package = "eiko"
version = "scm-1"
source = {
   url=""
}
dependencies = {
   "lua==5.1",
   "luaunit",
   "luasocket",
   "luasec",
   "luasodium",
   "lua-resty-snappy",
   "diff_match_patch",
   "lua-cjson",
   "lua-ev",
}
description = {}
build = {
   type = "builtin",
   install = {
      lua = {
         eiko = "src/eiko.lua",
         ["eiko.encdec"] = "src/encdec.lua"
      }
   }
}
test = {
   type = "command",
   command = "test/run_tests.sh test --output junit --name reports"
}
