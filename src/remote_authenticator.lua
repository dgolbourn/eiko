local verification_request
repeat
    local lanes = require "lanes"
    local context = require "context"
    local remote_authenticator_verify_response = require "config".itc_events.remote_authenticator_verify_response
    local client_command_itc_channel = require "config".client_command.itc_channel
    verification_request = lanes.gen('*', {required={"ssl.https", "signal", "ltn12", "cjson"}},
        function(url, authentication_token, peername)
            local ltn12 = require 'ltn12'
            local https = require 'ssl.https'
            local signal = require "signal"
            local json = require "cjson"
            local parts = {}
            local body = json.encode({authentication_token = authentication_token})
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
            if status == 200 then
                local response = json.decode(table.concat(parts))
                local event = {
                    kind = remote_authenticator_verify_response,
                    message = {
                        peername = peername,
                        id = response.id
                    }
                }
                context:send(nil, client_command_itc_channel, event)
                signal.raise(signal.realtime(client_command_itc_channel))
            end
            -- if status == 200 then
            --     log_event = "verification server verified authentication token for " .. peername
            -- elseif status == 401 then
            --     log_event = "verification server declined to verify authentication token for " .. peername
            -- else
            --    log_event = "verification server responded with status " .. status .. " for " .. peername
            -- end
            -- context:send(nil, log_config.itc_channel, log_event)
            -- signal.raise(signal.realtime(log_config.itc_channel))
        end
    )
until true

local signal = require "signals"
local remote_authenticator_config = require "config".remote_authenticator
local itc_events = require "config".itc_events
local log = require "eiko.logs".defaultLogger()
local ev = require "ev"

local state = nil

local function on_signal_event(loop, sig, revents)
    local key, incoming_event = context:receive(nil, remote_authenticator_config.itc_channel)
    if incoming_event.kind == itc_events.remote_authenticator_verify_request then
        local incoming_message = incoming_event.message
        verification_request(remote_authenticator_config.verify_url, incoming_message.authentication_token, incoming_message.peername)
    end
end

local function start()
    log:info("starting remote authenticator")
    state = {}
    local signal_watcher = ev.Signal.new(on_signal_event, signal.realtime(remote_authenticator_config.itc_channel))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)
end

local function stop()
    log:info("stopping remote authenticator")
    state.signal_watcher:stop(ev.Loop.default)
    state = nil
end

return {
    start = start,
    stop = stop,
}
