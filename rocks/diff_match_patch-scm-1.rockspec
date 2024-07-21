rockspec_format = "3.0"
package = "diff_match_patch"
version = "scm-1"
source = {
   url="git://github.com/google/diff-match-patch"
}
dependencies = {
   "lua==5.1",
   "bit32",
}
description = {}
build = {
   type = "builtin",
   modules = {
      diff_match_patch = "lua/diff_match_patch.lua"
   }
}
