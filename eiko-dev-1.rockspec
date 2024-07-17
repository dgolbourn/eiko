rockspec_format = "3.0"
package = "eiko"
version = "dev-1"
source = {
   url=""
}
dependencies = {
   "lua==5.1",
   "luaunit",
   "luasocket",
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
   command = "test/run_tests.sh test --output junit --name reports"
}
