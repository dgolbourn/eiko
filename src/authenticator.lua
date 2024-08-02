local lanes = require "lanes".configure{with_timers=false, verbose_errors=true}
local config = require "config"
local log = require "eiko.logs".defaultLogger()
local ev = require "ev"
local data_model = require "eiko.data_model"
local zmq = require "lzmq"


local state = nil

local function https_response(peername, loop, async, revents)
    local pending_state = state.pending[peername]
    state.pending[peername] = nil
    pending_state.timer_watcher:stop(loop)
    local response_event, err = pending_state.request:join(0)
    if response_event then
        if response_event.code == 200 then
            local response_event, err = data_model.remote_verify_response.decode(response_event.body)
            if response_event then
                log:info("remote server verified authentication token as " .. response_event.id .. " at " .. peername)
                local event = data_model.authenticator_verify_response.encode{
                    peername = peername,
                    id = id
                }
                state.command_pusher(event)
            else
                log:warn("\"" .. err .. "\" when decoding data from remote server for " .. peername)
            end
        elseif response_event.code == 401 then
            log:warn("remote server did not verify authentication token for " .. peername)
        else
            log:warn("remote server responded with \"" .. code .. "\" for " .. peername)
        end
    else
        log:error("remote server request failed with \"" .. err .. "\" for " .. peername)
    end
end

local function https_request(url, event)
    local ltn12 = require 'ltn12'
    local https = require 'ssl.https'
    local parts = {}
    local status, code, headers = https.request{
        url = url,
        method = "POST",
        headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = #event
        },
        source = ltn12.source.string(event),
        sink = ltn12.sink.table(parts)
    }
    return {
        status=status, 
        code=code, 
        headers=headers, 
        body=table.concat(parts)
    }
end

local function on_authentication_timeout_event(peername, loop, io, revents)
    log:warn("authentication period has elapsed for " .. peername)
    local pending_state = state.pending[peername]
    if pending_state.timer_watcher then
        pending_state.timer_watcher:stop(loop)
    end
    if pending_state.async_watcher then
        pending_state.async_watcher:stop(loop)
    end
    if pending_state.request then
        pending_state.request:cancel()
    end
end

local function on_command_puller_io_event(loop, io, revents)
    state.command_puller_idle_watcher:start(loop)
    state.command_puller_io_watcher:stop(loop)
end

local function on_command_puller_idle_event(loop, idle, revents)
    if state.command_puller:has_event(zmq.POLLIN) then
        local incoming_event, err = state.command_puller:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.authenticator_verify_request.decode(incoming_event)
            if err then
                log:warn("\"" .. err .. "\" when decoding data from " .. config.command.push.allocator)
            else
                local pending = {}
                local peername = incoming_event.peername
                state.pending[peername] = pending
                function on_response_event(loop, async, revents)
                    https_response(peername, loop, async, revents)
                end
                local async_watcher = ev.Async.new(on_response_event)
                local url = config.authenticator.verify_url
                local event = data_model.remote_verify_request.encode{
                    server_authentication_token = incoming_event.server_authentication_token,
                    client_authentication_token = incoming_event.client_authentication_token
                }                
                function on_request_event()
                    local status, response = pcall(https_request(url, event))
                    async_watcher:send(loop)
                    if status then
                        return response
                    else 
                        return nil, response
                    end
                end
                pending.async_watcher = async_watcher
                pending.async_watcher:start(loop)
                pending.request = lanes.gen('*', on_request_event)()
                local timer_event = function(loop, io, revents)
                    on_authentication_timeout_event(peername, loop, io, revents)
                end
                pending.timer_watcher = ev.Timer.new(timer_event, config.authenticator.authentication_period, 0)
                pending.timer_watcher:start(loop)
                log:info("sent verification request to " .. url .. " for " .. peername)
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:warn("\"" .. err:msg() .. "\" when decoding data from " .. config.command.push.allocator)
        end
    else
        state.command_puller_idle_watcher:stop(loop)
        state.command_puller_io_watcher:start(loop)
    end
end

local function start(loop)
    log:info("starting authenticator")
    state = {}
    state.loop = loop or ev.Loop.default
    state.ipc_context = zmq.context{io_threads = 1}
    state.command_puller = state.ipc_context:socket{zmq.PULL,
        connect = config.command.push.authenticator
    }
    state.command_puller_io_watcher = ev.IO.new(on_command_puller_io_event, state.command_puller:get_fd(), ev.READ)
    state.command_puller_idle_watcher = ev.Idle.new(on_command_puller_idle_event)
    state.command_puller_io_watcher:start(loop)
    state.command_pusher = state.ipc_context:socket{zmq.PUSH,
        bind = config.authenticator.push.command
    }
    state.pending = {}
end

local function stop()
    log:info("stopping authenticator")
    local loop = state.loop
    state.loop = nil
    for _, pending_state in pairs(state.pending) do
        if pending_state.timer_watcher then
            pending_state.timer_watcher:stop(loop)
        end
        if pending_state.async_watcher then
            pending_state.async_watcher:stop(loop)
        end
        if pending_state.request then
            pending_state.request:cancel()
        end
    end
    if state.command_puller_io_watcher then
        state.command_puller_io_watcher:stop(loop)
    end
    if state.command_puller_idle_watcher then
        state.command_puller_idle_watcher:stop(loop)
    end
    if state.command_puller then
        state.command_puller:close()
    end
    if state.command_pusher then
        state.command_pusher:close()
    end
    if state.ipc_context then
        state.ipc_context:shutdown()
    end
    state = nil
end

return {
    start = start,
    stop = stop,
}
