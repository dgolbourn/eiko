rockspec_format = "3.0"
package = "eiko"
version = "scm-1"
source = {
   url=""
}
dependencies = {
   "lua==5.1",
   "luasocket",
   "luasec",
   "luasodium",
   "lua-resty-snappy",
   "diff_match_patch",
   "lua-cjson",
   "jsonschema",
   "lualogging",
   "ansicolors",
   "lua-tinyyaml",
   "luafilesystem",
   "lua-mongo"
}
description = {}
build = {
   type = "builtin",
   modules = {
      ["eiko.codec"] = "src/codec.lua",
      ["eiko.server"] = "src/server.lua",
      ["eiko.client"] = "src/client.lua",
      ["eiko.authenticator"] = "src/authenticator.lua",
      ["eiko.data_model"] = "src/data_model.lua",
      ["eiko.logs"] = "src/logs.lua",
      ["eiko.config"] = "src/config.lua",
      ["eiko.uri"] = "src/uri.lua",
      ["eiko.event"] = "src/event.lua",
   },
   copy_directories = {"res"}
}
test_dependencies = {
   "luaunit",
   "luacheck",
   "uuid"
}
test = {
   type = "command",
   command = "test/run_tests.sh test --output junit --name reports"
}
