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

conn:send('[{"_kind":"command1", "foo":"foo"}]\n')

data = conn:receive('*l')

conn:send(data)

conn:close()
