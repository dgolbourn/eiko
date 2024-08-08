local function thread(mock_tcp_client, weak_mongo_client)
    local socket = require "socket"
    local mongo = require "lua-mongo-pool"
    local ssl = require "ssl"
    local data_model = require "eiko.data_model"
    local codec = require "eiko.codec"
    local sodium = require "sodium"
    local mongo_client = mongo.PooledClient(weak_mongo_client)
    local tcp_client, err = ssl.wrap(mock_tcp_client, config.authenticator.ssl_params)
    tcp_client:settimeout(config.authenticator.socket_period)
    if err then
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. tcp_client:getpeername())
        return
    end
    local success, err = tcp_client:dohandshake()
    if err then
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. tcp_client:getpeername())
        return
    end
    local data, err = tcp_client:receive('*l')
    if err then
        log:warn("\"" .. err .. "\" while receiving from " .. tcp_client:getpeername())
        tcp_client:close()
        return
    end
    local incoming_event, err = data_model.authenticator_request.decode(data)
    if incoming_event then
        if authenticator_authorise_request.kindof(incoming_event) then
            local collection = mongo_client:getCollection("eiko", "user")
            local query = mongo.BSON{user_authentication_token = incoming_event.user_authentication_token}
            local user = collection:findOne(query)
            if user then
                user = user:value()
                if os.clock() - user.user_authentication_now < config.user_authentication_period then
                    local query = mongo.BSON{_id = user._id}
                    local client_authentication_token = codec.authentication_token()
                    local now = mongo.DateTime(os.clock())
                    collection:updateOne(query, {
                        server_authentication_token = server_authentication_token,
                        client_authentication_token = client_authentication_token,
                        client_authentication_now = now
                    })
                    local event = data_model.authenticator_authorise_response.encode{
                        authentication_token = client_authentication_token
                    }
                    tcp_client:send(event)                
                else
                    log:warn("authentication token expired for " .. tcp_client:getpeername())
                end
            else
                log:warn("no authentication token from " .. tcp_client:getpeername())
            end
        elseif authenticator_login_request.kindof(incoming_event) then
            local collection = mongo_client:getCollection("eiko", "user")
            local query = mongo.BSON{login = incoming_event.login}
            local user = collection:findOne(query)
            if user then
                user = user:value()
                if sodium.crypto_pwhash_str_verify(user.hash, incoming_event.password) then
                    local query = mongo.BSON{_id = user._id}
                    local user_authentication_token = codec.authentication_token()
                    local now = mongo.DateTime(os.clock())
                    collection:updateOne(query, {
                        user_authentication_token = user_authentication_token,
                        user_authentication_now = now
                    })
                    local event = data_model.authenticator_login_response.encode{
                        uuid = user.uuid,
                        display_name = user.display_name,
                        authentication_token = user_authentication_token
                    }
                    tcp_client:send(event)
                else
                    log:warn("incorrect login or password from " .. tcp_client:getpeername())
                end
            else
                log:warn("incorrect login or password from " .. tcp_client:getpeername())
            end
        elseif authenticator_verify_request.kindof(incoming_event) then
            local collection = mongo_client:getCollection("eiko", "user")
            local query = mongo.BSON{
                server_authentication_token = server_authentication_token,
                client_authentication_token = client_authentication_token
            }
            local user = collection:findOne(query)
            if user then
                user = user:value()
                if os.clock() - user.client_authentication_now < config.client_authentication_period then
                    local event = data_model.authenticator_verify_response.encode{
                        uuid = user.uuid,
                        display_name = user.display_name
                    }
                    tcp_client:send(event)                
                else
                    log:warn("authentication token expired for " .. user.display_name)
                end
            else
                log:warn("no authentication token from " .. tcp_client:getpeername())
            end
        else
            log:error("unimplemented request " .. incoming_event._kind .. " from " .. tcp_client:getpeername())
        end
    else
        log:warn("\"" .. err .. "\" while decoding data from " .. tcp_client:getpeername())
    end
    tcp_client:close()
end

local lanes = require "lanes".configure{with_timers=false, verbose_errors=true}
local mongo = require "lua-mongo-pool"
local sodium = require "sodium"
local uuid = require "lua_uuid"
local config = require "eiko.config"
local socket = require "socket"

local state = {}

local function to_mock_client(client)
    local fd = client:getfd()
    client.setfd(socket._SOCKETINVALID)
    return {
        setfd = function(self, _)
        end,
        getfd = function(self)
            return fd
        end
    }
end

local function io_event(loop, io, revents)
    local client = {}
    local tcp_client = state.tcp:accept()
    log:info("connection from " .. tcp_client:getpeername())
    local tcp_client = to_mock_client(tcp_client)
    local mongo_client = state.pool:pop()
    client.thread = lanes.get('*', thread)(tcp_client, mongo_client)
end

local function start(loop)
    log:info("starting authenticator")
    loop = loop or ev.Loop.default
    state = {}
    state.tcp = socket.tcp()
    state.tcp:bind(config.authenticator.host, config.authenticator.port)
    state.tcp:listen(config.authenticator.max_clients)
    state.tcp:settimeout(0)
    state.io_watcher = ev.IO.new(io_event, state.tcp:getfd(), ev.READ)
    state.io_watcher:start(loop)
    state.pool = mongo.ClientPool(config.authenticator.db)
end

return {
    start = start,
    stop = stop
}
