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
}
description = {}
build = {
   type = "builtin",
   install = {
      lua = {
         eiko = "src/eiko.lua",
         ["eiko.encdec"] = "src/encdec.lua",
         ["eiko.client_command"] = "src/client_command.lua",
         ["eiko.client_action"] = "src/client_action.lua",
         ["eiko.game_loop"] = "src/game_loop.lua",
         ["eiko.server_event"] = "src/server_event.lua",
         ["eiko.server_action"] = "src/server_action.lua",  
         ["eiko.data_model"] = "src/data_model.lua",         
      }
   },
   copy_directories = {"res"}
}
test = {
   type = "command",
   command = "test/run_tests.sh test --output junit --name reports"
}
