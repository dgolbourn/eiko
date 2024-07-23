local lu = require "luaunit"

Test = {}

function Test:test_sodium()
    local sodium = require "sodium"
    local message = 'my message to encrypt'
    local nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES)
    local key = sodium.crypto_secretbox_keygen()
    local encoded_message = sodium.crypto_secretbox_easy(message, nonce, key)
    local decoded_message = sodium.crypto_secretbox_open_easy(encoded_message, nonce, key) 
    lu.assertEquals(message, decoded_message)
end

os.exit(lu.LuaUnit.run())
