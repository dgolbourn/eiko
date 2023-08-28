rockspec_format = "3.0"
package = "eiko"
version = "dev-1"
source = {
   url=""
}
dependencies = {
   "lua==5.1",
   "luaunit"
}
description = {}
build = {   
   type = "builtin",
   modules = {
      eiko = "src/eiko.lua"
   }
}
test = {
   type = "command",
   command = "eval '$(luarocks path)' && chmod +x ./test/test.sh && ./test/test.sh test --output junit --name reports"
}
