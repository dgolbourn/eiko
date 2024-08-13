local ev = require "ev"
local signal = require "signal"
local config = require "eiko.config"


local server_config = config.load("res/server.yaml")
local server = require "eiko.server".new(server_config)
server.start(ev.Loop.default)

local authenticator_config = config.load("res/authenticator.yaml")
local authenticator = require "eiko.authenticator".new(authenticator_config)
authenticator.start(ev.Loop.default)

local client1_config = config.load("res/client1.yaml")
local client1 = require "eiko.client".new(client1_config)
client1.start(ev.Loop.default)

local client2_config = config.load("res/client2.yaml")
local client2 = require "eiko.client".new(client2_config)
client2.start(ev.Loop.default)

local client3_config = config.load("res/client3.yaml")
local client3 = require "eiko.client".new(client3_config)
client3.start(ev.Loop.default)

local function on_sigint_event(loop, sig, revents)
    server.stop(loop)
    authenticator.stop(loop)
    client1.stop(loop)
    client2.stop(loop)
    client3.stop(loop)
    loop:unloop()
end
local signal_watcher = ev.Signal.new(on_sigint_event, signal.SIGINT)
signal_watcher:start(ev.Loop.default)

local zmq = require "lzmq"
local data_model = require "eiko.data_model"
local config = require "eiko.config"

local context = zmq.context{io_threads = 1}
local user1 = context:socket{zmq.PAIR, connect = client1_config.ipc}
local user2 = context:socket{zmq.PAIR, connect = client2_config.ipc}
local user3 = context:socket{zmq.PAIR, connect = client3_config.ipc}
local game = context:socket{zmq.PAIR, connect = server_config.ipc}

local counter = 0

local function on_timer_event(loop, timer, revents)
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
    counter = counter + 1
    --print(counter)    
end

local timer_watcher = ev.Timer.new(on_timer_event, 2, 0.05)
timer_watcher:start(ev.Loop.default)

local function on_idle_event(loop, idle, revents)
end

local idle_watcher1 = ev.Idle.new(on_idle_event)
idle_watcher1:start(ev.Loop.default)

local function client1_stream_request(loop, idle, revents)
    if user1:has_event(zmq.POLLIN) then
        local incoming_event, err = user1:recv(zmq.NOBLOCK)
        if incoming_event then
            --print("user 1", incoming_event)
        end
    end
end

local function user1_connection_request(loop, idle, revents)
    local event = data_model.user_connection_request.encode{
        host = server_config.host,
        port = server_config.port
    }
    user1:send(event)
    idle_watcher1:callback(client1_stream_request)
end

local function user1_login_response(loop, idle, revents)
    if user1:has_event(zmq.POLLIN) then
        local incoming_event, err = user1:recv(zmq.NOBLOCK)
        if incoming_event then
            data_model.user_login_request.decode(incoming_event)
            idle_watcher1:callback(user1_connection_request)
        end
    end
end

local function user1_login_request(loop, idle, revents)
    local event = data_model.user_login_request.encode{
        login="jane@bloggs.co.uk",
        password="password"
    }
    user1:send(event)
    idle_watcher1:callback(user1_login_response)
end

idle_watcher1:callback(user1_login_request)

local idle_watcher2 = ev.Idle.new(on_idle_event)
idle_watcher2:start(ev.Loop.default)

local function client2_stream_request(loop, idle, revents)
    if user2:has_event(zmq.POLLIN) then
        local incoming_event, err = user2:recv(zmq.NOBLOCK)
        if incoming_event then
            --print("user 2", incoming_event)
        end
    end
end

local function user2_connection_request(loop, idle, revents)
    local event = data_model.user_connection_request.encode{
        host = server_config.host,
        port = server_config.port
    }
    user2:send(event)
    idle_watcher2:callback(client2_stream_request)
end

local function user2_login_response(loop, idle, revents)
    if user2:has_event(zmq.POLLIN) then
        local incoming_event, err = user2:recv(zmq.NOBLOCK)
        if incoming_event then
            data_model.user_login_request.decode(incoming_event)
            idle_watcher2:callback(user2_connection_request)
        end
    end
end

local function user2_login_request(loop, idle, revents)
    local event = data_model.user_login_request.encode{
        login="dave@person.com",
        password="password"
    }
    user2:send(event)
    idle_watcher2:callback(user2_login_response)
end

idle_watcher2:callback(user2_login_request)


local idle_watcher3 = ev.Idle.new(on_idle_event)
idle_watcher3:start(ev.Loop.default)

local function client3_stream_request(loop, idle, revents)
    if user3:has_event(zmq.POLLIN) then
        local incoming_event, err = user3:recv(zmq.NOBLOCK)
        if incoming_event then
            --print("user 3", incoming_event)
        end
    end
end

local function user3_connection_request(loop, idle, revents)
    local event = data_model.user_connection_request.encode{
        host = server_config.host,
        port = server_config.port
    }
    user3:send(event)
    idle_watcher3:callback(client3_stream_request)
end

local function user3_login_response(loop, idle, revents)
    if user3:has_event(zmq.POLLIN) then
        local incoming_event, err = user3:recv(zmq.NOBLOCK)
        if incoming_event then
            data_model.user_login_request.decode(incoming_event)
            idle_watcher3:callback(user3_connection_request)
        end
    end
end

local function user3_login_request(loop, idle, revents)
    local event = data_model.user_login_request.encode{
        login="pam1234@example.co.uk",
        password="password"
    }
    user3:send(event)
    idle_watcher3:callback(user3_login_response)
end

idle_watcher3:callback(user3_login_request)

ev.Loop.default:loop()
