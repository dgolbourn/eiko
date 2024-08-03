local socket = require("socket")
local ssl = require("ssl")
local encdec = require("eiko.encdec")
local data_model = require("eiko.data_model")


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

client_authentication_request = conn:receive('*l')

print(client_authentication_request)

client_authentication_request = data_model.client_authentication_request.decode(client_authentication_request)

client_authentication_reponse = data_model.client_authentication_response.encode{
    authentication_token= "mock-token"
}

conn:send(client_authentication_reponse)

event_authentication_request = conn:receive('*l')

print(event_authentication_request)

event_authentication_request = data_model.event_authentication_request.decode(event_authentication_request)

udp = socket.udp()
udp:setpeername("localhost", 21098)

event_authentication_response = data_model.event_authentication_response.encode{
    authentication_token = event_authentication_request.authentication_token
}

event_authentication_response = encdec.encode(event_authentication_response, 0, 0, event_authentication_request.traffic_key)

print(event_authentication_response)

print(udp:send(event_authentication_response))

while true do
    data = udp:receive()
    print(data)
end