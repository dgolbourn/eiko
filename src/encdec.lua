local cjson = require "cjson"
bit32 = require "bit32"
local dmp = require "diff_match_patch"
local snappy = require "resty.snappy"
local sodium = require "sodium"

local function encode(payload, previous, key)
    local text1 = cjson.encode(payload)
    local diffs = dmp.diff_main(previous, text1)
    local patches = dmp.patch_make(previous, diffs)
    local text = dmp.patch_toText(patches)
    local compressed = snappy.compress(text)
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    local secret = sodium.crypto_secretbox_easy(compressed, nonce, key)
    return nonce, secret
end

local function decode(nonce, secret, previous, key)
    local compressed = sodium.crypto_secretbox_open_easy(secret, nonce, key)
    local text = snappy.uncompress(compressed)
    local patches = dmp.patch_fromText(text)
    local text1 = dmp.patch_apply(patches, previous)
    local payload = cjson.decode(text1)
    return payload
end

return {
    encode = encode, 
    decode = decode
}
