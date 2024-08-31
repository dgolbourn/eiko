rockspec_format = "3.0"
package = "eiko-engine"
version = "scm-1"
source = {
   url=""
}
dependencies = {
   "lua==5.1",
   "luasocket",
   "lua-cjson",
   "lua-tinyyaml",
   "luafilesystem",
   "argparse",
}
description = {}
build = {
   type = "builtin",
   modules = {
      ["eiko-engine.geo"] = "src/geo.lua"
   }
}
test_dependencies = {
   "luaunit",
   "luacheck"
}
test = {
   type = "command",
   command = "test/run_tests.sh test --output junit --name reports"
}
