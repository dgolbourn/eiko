local lu = require "luaunit"

Test = {}

function Test:test_encdec()
    local encdec = require "eiko.encdec"
    local cjson = require "cjson"
    local sodium = require "sodium"
    local payload = {a={"blah"}}
    local previous = [[{"a":["foo"]}]]
    local key = sodium.crypto_secretbox_keygen()
    local new = cjson.encode(payload)
    local noncesecret = encdec.delta_compress_encode(new, previous, key)
    local decoded_new = encdec.delta_compress_decode(noncesecret, previous, key)
    local decoded_payload = cjson.decode(decoded_new)
    lu.assertEquals(payload, decoded_payload)
end

function Test:test_authverify()
    local encdec = require "eiko.encdec"
    local cjson = require "cjson"
    local sodium = require "sodium"
    local payload = {a={"blah"}}
    local key = sodium.crypto_auth_keygen()
    local message = cjson.encode(payload)
    local messagetag = encdec.authenticate(message, key)
    local is_verified = encdec.verify(messagetag, key)
    lu.assertEquals(is_verified, true)
end

os.exit(lu.LuaUnit.run())
