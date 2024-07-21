local lu = require "luaunit"

Test = {}

function Test:test_diff_match_patch()
    bit32 = require "bit32"
    dmp = require "diff_match_patch"
    text1 = "the quick brown fox jumped over the lazy dog"
    text2 = "the lazy dog did not jump over the quick brown fox"
    diffs = dmp.diff_main(text1, text2)
    patches = dmp.patch_make(text1, diffs)
    text = dmp.patch_toText(patches)
    patches = dmp.patch_fromText(text)
    text2, results = dmp.patch_apply(patches, text1)
end

os.exit(lu.LuaUnit.run())
