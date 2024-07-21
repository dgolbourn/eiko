local lu = require "luaunit"

Test = {}

function Test:test_sodium()
    local luasodium = require "luasodium"
    local message = 'my message to encrypt'
    local nonce = string.rep('\0', luasodium.crypto_secretbox_NONCEBYTES)
    local key = string.rep('\0', luasodium.crypto_secretbox_KEYBYTES)
    assert(
      luasodium.crypto_secretbox_open_easy(
        luasodium.crypto_secretbox_easy(message,nonce,key),
        nonce,
        key
      ) == message
    )
end

os.exit(lu.LuaUnit.run())
