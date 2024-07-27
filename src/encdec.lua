local cjson = require "cjson"
bit32 = require "bit32"
local dmp = require "diff_match_patch"
local snappy = require "resty.snappy"
local sodium = require "sodium"
local mime = require "mime"

local function delta_compress_encode(new, new_counter, previous, previous_counter, key)
    local diffs = dmp.diff_main(previous, new)
    local patches = dmp.patch_make(previous, diffs)
    local text = dmp.patch_toText(patches)
    local counters = string.format("%016X", new_counter) .. string.format("%016X", previous_counter)
    local counterstext = counters .. text
    local compressed = snappy.compress(counters .. text)
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    local secret = sodium.crypto_secretbox_easy(compressed, nonce, key)
    return nonce .. secret
end

local function delta_compress_decode(noncesecret, previous_map, key)
    local nonce = string.sub(noncesecret, 1, sodium.crypto_secretbox_NONCEBYTES)
    local secret = string.sub(noncesecret, sodium.crypto_secretbox_NONCEBYTES + 1, -1)
    local compressed = sodium.crypto_secretbox_open_easy(secret, nonce, key)
    local counterstext = snappy.uncompress(compressed)
    local new_counter = tonumber(string.sub(counterstext, 1, 16), 16)
    local previous_counter = tonumber(string.sub(counterstext, 17, 32), 16)
    local previous = previous_map[previous_counter]
    local text = string.sub(counterstext, 33, -1)
    local patches = dmp.patch_fromText(text)
    local new = dmp.patch_apply(patches, previous)
    return new, new_counter
end

local function encode(message, key)
    local compressed = snappy.compress(message)
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    local secret = sodium.crypto_secretbox_easy(compressed, nonce, key)
    return nonce .. secret
end

local function decode(noncesecret, key)
    local nonce = string.sub(noncesecret, 1, sodium.crypto_secretbox_NONCEBYTES)
    local secret = string.sub(noncesecret, sodium.crypto_secretbox_NONCEBYTES + 1, -1)
    local compressed = sodium.crypto_secretbox_open_easy(secret, nonce, key)
    local message = snappy.uncompress(compressed)
    return message
end

local authentication_key = sodium.crypto_auth_keygen()

local function authentication_token()
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    return (mime.b64(nonce .. sodium.crypto_auth(nonce, authentication_key)))
end

local function authenticate(message, key)
    return message .. sodium.crypto_auth(message, key)
end

local function verify(messagetag, key)
    local message = string.sub(messagetag, 1, -(sodium.crypto_auth_BYTES + 1))
    local tag = string.sub(messagetag, -sodium.crypto_auth_BYTES, -1)
    return sodium.crypto_auth_verify(tag, message, key)
end

return {
    encode = encode,
    decode = decode,
    delta_compress_encode = delta_compress_encode,
    delta_compress_decode = delta_compress_decode,
    authenticate = authenticate,
    verify = verify,
    authentication_token = authentication_token
}
