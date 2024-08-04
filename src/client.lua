local socket = require "socket"
local ssl = require "ssl"
local encdec = require "eiko.encdec"
local data_model = require "eiko.data_model"
local config = require "eiko.config"
 
local tcp = socket.tcp()
tcp:connect(config.command.host, config.command.port)
tcp = ssl.wrap(tcp, config.client.ssl_params)

-- on_handshake_io_event

succ, err = tcp:dohandshake()

-- on_client_authentication_io_event

client_authentication_request = tcp:receive('*l')

client_authentication_request = data_model.client_authentication_request.decode(client_authentication_request)

authenticator_authorise_request = data_model.authenticator_authorise_request.encode{
    user_authentication_token = authentication_token,
    server_authentication_token = client_authentication_request.authentication_token
}

authenticator:send(authenticator_authorise_request)

-- on_server_authorisation_io_event

authenticator_authorise_response = authenticator:receive()

authenticator_authorise_response = data_model.authenticator_authorise_response.decode(authenticator_authorise_response)

client_authentication_response = data_model.client_authentication_response.encode{
    authentication_token = authenticator_authorise_response.authentication_token
}

tcp:send(client_authentication_reponse)

-- on_event_authentication_io_event

event_authentication_request = tcp:receive('*l')

event_authentication_request = data_model.event_authentication_request.decode(event_authentication_request)

udp = socket.udp()
udp:setpeername(config.event.host, config.event.port)

event_authentication_response = data_model.event_authentication_response.encode{
    authentication_token = event_authentication_request.authentication_token
}

event_authentication_response = encdec.encode(event_authentication_response, 0, 0, event_authentication_request.traffic_key)

print(event_authentication_response)

print(udp:send(event_authentication_response))

-- complete

while true do
    data = udp:receive()
    print(data)
end
