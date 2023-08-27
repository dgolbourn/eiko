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
