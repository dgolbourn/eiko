local lu = require "luaunit"

Test = {}

function Test:test_encdec()
    local encdec = require "eiko.encdec"
    local cjson = require "cjson"
    local sodium = require "sodium"
    payload = {a={"blah"}}
    previous = [[{"a":["foo"]}]]
    key = sodium.crypto_secretbox_keygen()
    noncesecret = encdec.encode(payload, previous, key)
    decoded_payload = encdec.decode(noncesecret, previous, key)
    lu.assertEquals(payload, decoded_payload)
end

os.exit(lu.LuaUnit.run())
