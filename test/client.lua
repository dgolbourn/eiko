local socket = require("socket")
local ssl = require("ssl")

local params = {
    mode = "client",
    protocol = "any",
    verify = "none",
    options = {"all"}
}
 
local conn = socket.tcp()
conn:connect("localhost", 21098)
conn = ssl.wrap(conn, params)
succ, err = conn:dohandshake()
print(succ)
print(err)

conn:send('{"_kind":"client_authentication_reponse","authentication_token": "fsrfrsgsd"}\n')

data = conn:receive('*l')
print(data)
conn:close()
