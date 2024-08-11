local mongo = require "mongo"
local config = require "eiko.config"
local socket = require "socket"
local ssl = require "ssl"
local data_model = require "eiko.data_model"
local codec = require "eiko.codec"
local sodium = require "sodium"
local log = require "eiko.logs".defaultLogger()
local ev = require "ev"
local uri = require "eiko.uri"


local state = nil

local function client_state_close(client_state, loop)
    log:debug("closing connection with " .. client_state.peername)
    if client_state.client then
        client_state.client:close()
    end
    if client_state.client_io_watcher then
        client_state.client_io_watcher:stop(loop)
    end
    if client_state.timer_watcher then
        client_state.timer_watcher:stop(loop)
    end
    if client_state.peername then
        state.clients[client_state.peername] = nil
    end
end

local function authorise(client_state, incoming_event)
    local collection = state.mongo:getCollection("eiko", "user")
    local query = mongo.BSON{user_authentication_token = incoming_event.user_authentication_token}
    local user = collection:findOne(query)
    if user then
        user = user:value()
        if os.clock() - user.user_authentication_now < config.authenticator.user_authentication_period then
            local query = mongo.BSON{_id = user._id}
            local client_authentication_token = codec.authentication_token()
            local now = mongo.DateTime(os.clock())
            collection:updateOne(query, {
                server_authentication_token = user.server_authentication_token,
                client_authentication_token = client_authentication_token,
                client_authentication_now = now
            })
            local event = data_model.authenticator_authorise_response.encode{
                authentication_token = client_authentication_token
            }
            local _, err = client_state.client:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting to send to " .. client_state.peername)
            else
                log:info("user " .. user.uuid .. " authorised " .. client_state.peername)
            end
        else
            log:warn("authentication token expired for " .. client_state.peername)
        end
    else
        log:warn("no authentication token from " .. client_state.peername)
    end
end

local function login(client_state, incoming_event)
    local collection = state.mongo:getCollection("eiko", "user")
    local query = mongo.BSON{login = incoming_event.login}
    local user = collection:findOne(query)
    if user then
        user = user:value()
        if sodium.crypto_pwhash_str_verify(user.hash, incoming_event.password) then
            local user_authentication_token = codec.authentication_token()
            local now = mongo.DateTime(os.clock())
            local success, err = collection:update({_id = user._id},
                {
                    set = {
                        user_authentication_token = user_authentication_token,
                        user_authentication_now = now
                    }
                },
                {
                    upsert=true
                }
            )
            if err then
                log:warn("\"" .. err .. "\" while attempting to update database")
            else
                local event = data_model.authenticator_login_response.encode{
                    uuid = user.uuid,
                    display_name = user.display_name,
                    authentication_token = user_authentication_token
                }
                local _, err = client_state.client:send(event)
                if err then
                    log:warn("\"" .. err .. "\" while attempting to send to " .. client_state.peername)
                else
                    log:info("user login by " .. user.uuid .. " from " .. client_state.peername)
                end
            end
        else
            log:warn("incorrect login or password from " .. client_state.peername)
        end
    else
        log:warn("incorrect login or password from " .. client_state.peername)
    end
end

local function verify(client_state, incoming_event)
    local collection = state.mongo:getCollection("eiko", "user")
    local query = mongo.BSON{
        server_authentication_token = incoming_event.server_authentication_token,
        client_authentication_token = incoming_event.client_authentication_token
    }
    local user = collection:findOne(query)
    if user then
        user = user:value()
        if os.clock() - user.client_authentication_now < config.authenticator.client_authentication_period then
            local event = data_model.authenticator_verify_response.encode{
                uuid = user.uuid,
                display_name = user.display_name
            }
            local _, err = client_state.client:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting to send to " .. client_state.peername)
            else
                log:info("verified user as " .. user.uuid .. " to " .. client_state.peername)
            end
        else
            log:warn("authentication token expired for " .. user.uuid)
        end
    else
        log:warn("no authentication token from " .. client_state.peername)
    end
end

local function on_client_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        local data, err, partial = client_state.client:receive('*l', client_state.buffer)
        client_state.buffer = partial
        if data then
            local incoming_event, err = data_model.authenticator_request.decode(data)
            if incoming_event then
                if data_model.authenticator_authorise_request.kindof(incoming_event) then
                    authorise(client_state, incoming_event)
                elseif data_model.authenticator_login_request.kindof(incoming_event) then
                    login(client_state, incoming_event)
                elseif data_model.authenticator_verify_request.kindof(incoming_event) then
                    verify(client_state, incoming_event)
                else
                    log:error("unimplemented request " .. incoming_event._kind .. " from " ..peername)
                end
            else
                log:warn("\"" .. err .. "\" when decoding data from " .. peername)
            end
            client_state_close(client_state, loop)
        elseif err == "timeout" then
        else
            log:warn("\"" .. err .. "\" while receiving from " .. peername)
            client_state_close(client_state, loop)
        end
    else
        log:warn("no connection with " .. peername)
    end
end

local function on_client_timeout_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        log:warn("timeout period has elapsed for " .. peername)
        client_state_close(client_state, loop)
    else
        log:warn("no connection with " .. peername)
    end
end

local function on_handshake_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        local success, err = client_state.client:dohandshake()
        if success then
            log:info("successful tls handshake with " .. peername)
            local io_event = function(loop, io, revents)
                on_client_io_event(peername, loop, io, revents)
            end
            client_state.client_io_watcher:callback(io_event)
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
            client_state_close(client_state, loop)
        end
    else
        log:warn("no pending connection with " .. peername)
    end
end

local function on_new_client_io_event(loop, io, revents)
    local client_state = {}
    local client = state.tcp:accept()
    local peername = uri("tcp", unpack{client:getpeername()})
    log:info("connection from unverified " .. peername)
    local client, err = ssl.wrap(client, config.authenticator.ssl_params)
    if err then
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
    else
        client:settimeout(0)
        local io_event = function(loop, io, revents)
            on_handshake_io_event(peername, loop, io, revents)
        end
        client_state.client = client
        client_state.peername = peername
        client_state.client_io_watcher = ev.IO.new(io_event, client:getfd(), ev.READ)
        client_state.client_io_watcher:start(loop)
        local timer_event = function(loop, io, revents)
            on_client_timeout_event(peername, loop, io, revents)
        end
        client_state.timer_watcher = ev.Timer.new(timer_event, config.authenticator.timeout_period, 0)
        client_state.timer_watcher:start(loop)
        state.clients[peername] = client_state
    end
end

local function start(loop)
    log:info("starting authenticator")
    loop = loop or ev.Loop.default
    state = {}
    state.tcp = socket.tcp()
    state.tcp:bind(config.authenticator.host, config.authenticator.port)
    state.tcp:listen(config.authenticator.max_clients)
    state.tcp:settimeout(0)
    state.new_client_io_watcher = ev.IO.new(on_new_client_io_event, state.tcp:getfd(), ev.READ)
    state.new_client_io_watcher:start(loop)
    state.clients = {}
    state.mongo = mongo.Client(config.authenticator.db)
end

local function stop(loop)
    log:info("stopping authenticator")
    loop = loop or ev.Loop.default
    for _, client_state in pairs(state.clients) do
        client_state_close(client_state, loop)
    end
    if state.new_client_io_watcher then
        state.new_client_io_watcher:stop(loop)
    end
    if state.tcp then
        state.tcp:close()
    end
    state = nil
end

return {
    start = start,
    stop = stop
}
