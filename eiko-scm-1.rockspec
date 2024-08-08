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
   "jsonschema",
   "lualogging",
   "ansicolors",
   "lyaml",
   "lua_signal",
   "luafilesystem",
   "lzmq",
   "lua-mongo",
   "lua_uuid"
}
description = {}
build = {
   type = "builtin",
   modules = {
      eiko = "src/eiko.lua",
      ["eiko.codec"] = "src/codec.lua",
      ["eiko.command"] = "src/command.lua",
      ["eiko.event"] = "src/event.lua",
      ["eiko.data_model"] = "src/data_model.lua",
      ["eiko.logs"] = "src/logs.lua",
      ["eiko.config"] = "src/config.lua",
   },
   copy_directories = {"res"}
}
test = {
   type = "command",
   command = "test/run_tests.sh test --output junit --name reports"
}
