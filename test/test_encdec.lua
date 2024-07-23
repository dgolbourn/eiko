local lu = require "luaunit"

Test = {}

function Test:test_encdec()
    local encdec = require "eiko.encdec"
    local cjson = require "cjson"
    local sodium = require "sodium"
    payload = {a={"blah"}}
    previous = [[{"a":["foo"]}]]
    key = sodium.crypto_secretbox_keygen()
    new = cjson.encode(payload)
    noncesecret = encdec.encode(new, previous, key)
    decoded_new = encdec.decode(noncesecret, previous, key)
    decoded_payload = cjson.decode(decoded_new)
    lu.assertEquals(payload, decoded_payload)
end

os.exit(lu.LuaUnit.run())
