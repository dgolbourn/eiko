local lu = require "luaunit"

Test = {}

function Test:test_diff_match_patch()
    bit32 = require "bit32"
    local dmp = require "diff_match_patch"
    local text1 = "asdsfsdfsdfsdfsdgdgsdgsdgsdgasgsd the quick brown fox jumped over the lazy dog"
    local text2 = "asdsfsdfsdfsdfsdgdgsdgsdgsdgasgsd the lazy dog did not jump over the quick brown fox"
    local diffs = dmp.diff_main(text1, text2)   
    dmp.diff_cleanupEfficiency(diffs) 
    local patches = dmp.patch_make(text1, diffs)
    local text = dmp.patch_toText(patches)
    print(text, string.len(text))
    patches = dmp.patch_fromText(text)
    local text2_new, results = dmp.patch_apply(patches, text1)
    lu.assertEquals(text2_new, text2)
end

os.exit(lu.LuaUnit.run())
