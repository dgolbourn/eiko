local event = require "eiko.event".event()
local config = require "eiko.config"
local data_model = require "eiko.data_model"
local socket = require "socket"

local server_config = config.load("res/server.yaml")
local server = require "eiko.server".new(server_config)
server.start(event)

-- local authenticator_config = config.load("res/authenticator.yaml")
-- local authenticator = require "eiko.authenticator".new(authenticator_config)
-- authenticator.start(event)

local client1_config = config.load("res/client1.yaml")
local client1 = require "eiko.client".new(client1_config)
client1.start(event)

local client2_config = config.load("res/client2.yaml")
local client2 = require "eiko.client".new(client2_config)
client2.start(event)

local client3_config = config.load("res/client3.yaml")
local client3 = require "eiko.client".new(client3_config)
client3.start(event)

local user1 = socket.udp()
user1:settimeout(0)
user1:setsockname(client1_config.ipc.incoming.host, client1_config.ipc.incoming.port)
user1:setpeername(client1_config.ipc.outgoing.host, client1_config.ipc.outgoing.port)

local user2 = socket.udp()
user2:settimeout(0)
user2:setsockname(client2_config.ipc.incoming.host, client2_config.ipc.incoming.port)
user2:setpeername(client2_config.ipc.outgoing.host, client2_config.ipc.outgoing.port)

local user3 = socket.udp()
user3:settimeout(0)
user3:setsockname(client3_config.ipc.incoming.host, client3_config.ipc.incoming.port)
user3:setpeername(client3_config.ipc.outgoing.host, client3_config.ipc.outgoing.port)

local game = socket.udp()
game:settimeout(0)
game:setsockname(server_config.ipc.incoming.host, server_config.ipc.incoming.port)
game:setpeername(server_config.ipc.outgoing.host, server_config.ipc.outgoing.port)

local counter = 0

local timer_watcher = nil

local function on_timer_event()
    local event = data_model.game_stream_request.encode{
        global = {
            counter = counter
        },
        user = {
            ["0068388e-2c0d-4eaf-a159-8f0bf99a3521"] = {data = "user1", counter = counter},
            ["d28d0ee5-8fb9-4731-acc7-2f7d14baa90f"] = {data = "user2", counter = counter},
            ["75a4892b-db30-415c-9758-b06043e4b3a5"] = {data = "user3", counter = counter}
        }
    }
    counter = counter + 1
    game:send(event)

    local event = data_model.game_state_request.encode{
        global = {
            counter = counter
        },
        user = {
            ["0068388e-2c0d-4eaf-a159-8f0bf99a3521"] = {data = "state1", counter = counter},
            ["d28d0ee5-8fb9-4731-acc7-2f7d14baa90f"] = {data = "state2", counter = counter},
            ["75a4892b-db30-415c-9758-b06043e4b3a5"] = {data = "state3", counter = counter}
        }
    }
    game:send(event)

    timer_watcher.start()
end

timer_watcher = event.timer(1, on_timer_event)
timer_watcher.start()

local user1_watcher = nil
local function client1_stream_request()
    local incoming_event, err = user1:receive()
    if incoming_event then
        print("user 1", incoming_event)
    end
end
local function user1_connection_request()
    local event = data_model.user_connection_request.encode{
        host = server_config.host,
        port = server_config.port
    }
    user1:send(event)
    user1_watcher.callback(client1_stream_request)
end
local function user1_login_response()
    local incoming_event, err = user1:receive()
    if incoming_event then
        data_model.user_login_request.decode(incoming_event)
        user1_connection_request()
    end
end
local function user1_login_request()
    local event = data_model.user_login_request.encode{
        login="jane@bloggs.co.uk",
        password="password"
    }
    user1:send(event)
    user1_watcher.callback(user1_login_response)
end
user1_watcher = event.receiver(user1, nil)
user1_watcher.start()
user1_login_request()

local user2_watcher = nil
local function client2_stream_request()
    local incoming_event, err = user2:receive()
    if incoming_event then
        print("user 2", incoming_event)
    end
end
local function user2_connection_request()
    local event = data_model.user_connection_request.encode{
        host = server_config.host,
        port = server_config.port
    }
    user2:send(event)
    user2_watcher.callback(client2_stream_request)
end
local function user2_login_response()
    local incoming_event, err = user2:receive()
    if incoming_event then
        data_model.user_login_request.decode(incoming_event)
        user2_connection_request()
    end
end
local function user2_login_request()
    local event = data_model.user_login_request.encode{
        login="dave@person.com",
        password="password"
    }
    user2:send(event)
    user2_watcher.callback(user2_login_response)
end
user2_watcher = event.receiver(user2, nil)
user2_watcher.start()
user2_login_request()

local user3_watcher = nil
local function client3_stream_request()
    local incoming_event, err = user3:receive()
    if incoming_event then
        print("user 3", incoming_event)
    end
end
local function user3_connection_request()
    local event = data_model.user_connection_request.encode{
        host = server_config.host,
        port = server_config.port
    }
    user3:send(event)
    user3_watcher.callback(client3_stream_request)
end
local function user3_login_response()
    local incoming_event, err = user3:receive()
    if incoming_event then
        data_model.user_login_request.decode(incoming_event)
        user3_connection_request()
    end
end
local function user3_login_request()
    local event = data_model.user_login_request.encode{
        login="pam1234@example.co.uk",
        password="password"
    }
    user3:send(event)
    user3_watcher.callback(user3_login_response)
end
user3_watcher = event.receiver(user3, nil)
user3_watcher.start()
user3_login_request()

event.loop()
