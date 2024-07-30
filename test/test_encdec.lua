local lu = require "luaunit"

Test = {}

function Test:test_enc_dec()
    local encdec = require "eiko.encdec"
    local cjson = require "cjson"
    local sodium = require "sodium"
    local payload = {a={"blah"}}
    local key = sodium.crypto_secretbox_keygen()
    local new = cjson.encode(payload)
    local counter = 1
    local epoch = 2
    local noncesecret = encdec.encode(new, counter, epoch, key)
    local decoded_new, decoded_counter, decoded_epoch = encdec.decode(noncesecret, key)
    local decoded_payload = cjson.decode(decoded_new)
    lu.assertEquals(payload, decoded_payload)
    lu.assertEquals(counter, decoded_counter)
    lu.assertEquals(epoch, decoded_epoch)
end

function Test:test_delta_compress_enc_dec()
    local encdec = require "eiko.encdec"
    local sodium = require "sodium"
    local new = "asdsfsdfsdfsdfsdgdgsdgsdgsdgasgsd the quick brown fox jumped over the lazy dog"
    local previous = "asdsfsdfsdfsdfsdgdgsdgsdgsdgasgsd the lazy dog did not jump over the quick brown fox"
    local key = sodium.crypto_secretbox_keygen()
    local new_counter = 1
    local previous_counter = 0
    local noncesecret = encdec.delta_compress_encode(new, new_counter, previous, previous_counter, key)
    local previous_map = {}
    previous_map[previous_counter] = previous
    local decoded_new, decoded_new_counter = encdec.delta_compress_decode(noncesecret, previous_map, key)
    lu.assertEquals(new_counter, decoded_new_counter)
    lu.assertEquals(new, decoded_new)
end

function Test:test_auth_verify()
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

function Test:test_authentication_token()
    local encdec = require "eiko.encdec"
    print(encdec.authentication_token())
end

os.exit(lu.LuaUnit.run())
