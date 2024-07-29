local context = require "context"
local lanes = require "lanes"
local config = require "config"

local verification_request = lanes.gen('*',
    function()
        local ltn12 = require 'ltn12'
        local https = require 'ssl.https'
        local signal = require "signals"
        local log = require "eiko.logs".defaultLogger()
        local data_model = require "eiko.data_model"
        local _, incoming_event = context:receive(nil, config.authenticator.itc_channel)
        local incoming_event, err = data_model.authenticator_verify_request.decode(incoming_event)
        if err then
            log:error("\"" .. err .. "\" when decoding data from " .. config.authenticator.itc_channel)
        else
            local event = {
                _kind = data_model.remote_verify_request.kind,
                server_authentication_token = incoming_event.server_authentication_token,
                client_authentication_token = incoming_event.client_authentication_token
            }
            local body = data_model.remote_verify_request.encode(event)
            local parts = {}
            local status, code, headers = https.request {
                url = url,
                method = "POST",
                headers = {
                        ["Content-Type"] = "application/json",
                        ["Content-Length"] = #body
                },
                source = ltn12.source.string(body),
                sink = ltn12.sink.table(parts)
            }
            if code == 200 then
                local response_event = table.concat(parts)
                local response_event, err = data_model.remote_verify_response.decode(response_event)
                if response_event then
                    log:info("remote server verified authentication token as " .. response_event.id .. " at " .. peername)
                    local event = {
                        _kind = data_model.authenticator_verify_response.kind,
                        peername = incoming_event.peername,
                        id = id
                    }
                    event = data_model.authenticator_verify_response.encode(event)
                    context:send(nil, config.command.itc_channel, event)
                    signal.raise(signal.realtime(config.command.itc_channel))
                else
                    log:warn("\"" .. err .. "\" when decoding data from remote server for " .. peername)
                end
            elseif status == 401 then
                log:warn("remote server did not verify authentication token for " .. peername)
            else
                log:warn("remote server responded with status " .. status .. " for " .. peername)
            end
        end
    end
)

local signal = require "signals"
local log = require "eiko.logs".defaultLogger()
local ev = require "ev"

local state = nil

local function on_signal_event(loop, sig, revents)
    verification_request()
end

local function start()
    log:info("starting remote authenticator")
    state = {}
    local signal_watcher = ev.Signal.new(on_signal_event, signal.realtime(config.authenticator.itc_channel))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)
end

local function stop()
    log:info("stopping remote authenticator")
    if state.signal_watcher then
        state.signal_watcher:stop(ev.Loop.default)
    end
    state = nil
end

return {
    start = start,
    stop = stop,
}
