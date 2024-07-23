local cjson = require "cjson"
bit32 = require "bit32"
local dmp = require "diff_match_patch"
local snappy = require "resty.snappy"
local sodium = require "sodium"

local function encode(new, previous, key)
    local diffs = dmp.diff_main(previous, new)
    local patches = dmp.patch_make(previous, diffs)
    local text = dmp.patch_toText(patches)
    local compressed = snappy.compress(text)
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    local secret = sodium.crypto_secretbox_easy(compressed, nonce, key)
    return nonce .. secret
end

local function decode(noncesecret, previous, key)
    local nonce = string.sub(noncesecret, 1, sodium.crypto_secretbox_NONCEBYTES)
    local secret = string.sub(noncesecret, sodium.crypto_secretbox_NONCEBYTES + 1, -1)
    local compressed = sodium.crypto_secretbox_open_easy(secret, nonce, key)
    local text = snappy.uncompress(compressed)
    local patches = dmp.patch_fromText(text)
    local new = dmp.patch_apply(patches, previous)
    return new
end

return {
    encode = encode, 
    decode = decode
}
