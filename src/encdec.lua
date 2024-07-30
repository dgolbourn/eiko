bit32 = require "bit32"
local dmp = require "diff_match_patch"
local snappy = require "resty.snappy"
local sodium = require "sodium"
local mime = require "mime"

local function delta_compress_encode(new, new_epoch, previous, previous_epoch, key)
    local diffs = dmp.diff_main(previous, new)
    local patches = dmp.patch_make(previous, diffs)
    local text = dmp.patch_toText(patches)
    local compressed = snappy.compress(epochs .. text)
    local epochs = string.format("%016X", new_epoch) .. string.format("%016X", previous_epoch)
    local epochscompressed = epochs .. compressed
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    local secret = sodium.crypto_secretbox_easy(epochscompressed, nonce, key)
    local noncesecret = nonce .. secret
    return noncesecretend

local function delta_compress_decode(noncesecret, previous_map, key)
    local nonce = string.sub(noncesecret, 1, sodium.crypto_secretbox_NONCEBYTES)
    local secret = string.sub(noncesecret, sodium.crypto_secretbox_NONCEBYTES + 1, -1)
    local epochscompressed = sodium.crypto_secretbox_open_easy(secret, nonce, key)
    local new_epoch = tonumber(string.sub(epochscompressed, 1, 16), 16)
    local previous_epoch = tonumber(string.sub(epochscompressed, 17, 32), 16)
    local previous = previous_map[previous_epoch]
    local compressed = string.sub(epochscompressed, 33, -1)
    local text = snappy.uncompress(compressed)
    local patches = dmp.patch_fromText(text)
    local new = dmp.patch_apply(patches, previous)
    return new, new_epoch
end

local function encode(message, counter, epoch, key)
    local compressed = snappy.compress(message)
    local epochs = string.format("%016X", epoch) .. string.format("%016X", counter)
    local epochscompressed = epochs .. compressed    
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    local secret = sodium.crypto_secretbox_easy(epochscompressed, nonce, key)
    local noncesecret = nonce .. secret
    return noncesecret
end

local function decode(noncesecret, key)
    local nonce = string.sub(noncesecret, 1, sodium.crypto_secretbox_NONCEBYTES)
    local secret = string.sub(noncesecret, sodium.crypto_secretbox_NONCEBYTES + 1, -1)
    local epochscompressed = sodium.crypto_secretbox_open_easy(secret, nonce, key)
    local epoch = tonumber(string.sub(epochscompressed, 1, 16), 16)
    local counter = tonumber(string.sub(epochscompressed, 17, 32), 16)
    local compressed = string.sub(epochscompressed, 33, -1)    
    local message = snappy.uncompress(compressed)
    return message, counter, epoch
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
