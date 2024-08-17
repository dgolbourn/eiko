rockspec_format = "3.0"
package = "eiko"
version = "win-1"
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
   "luafilesystem"
}
description = {}
build = {
   type = "builtin",
   modules = {
      ["eiko.codec"] = "src/codec.lua",
      ["eiko.server"] = "src/server.lua",
      ["eiko.client"] = "src/client.lua",
      ["eiko.data_model"] = "src/data_model.lua",
      ["eiko.logs"] = "src/logs.lua",
      ["eiko.config"] = "src/config.lua",
      ["eiko.uri"] = "src/uri.lua",
      ["eiko.event"] = "src/event.lua",
      ["eiko.main"] = "src/main.lua"
   }
}
