local signal = require "signal"
local config = require "config".remote_authenticator
local client_command_config = require "config".client_command
local itc_events = require "config".itc_events
local ltn12 = require 'ltn12'
local https = require 'ssl.https'
local json = require "cjson"
local log = require "logs"

local state = {}

local function on_signal_event(loop, sig, revents)
    local key, incoming_event = context:receive(nil, config.itc_channel)
    if incoming_event.kind == itc_events.remote_authenticator_verify_request then
        local incoming_message = incoming_event.message
        local body = json.encode({authentication_token = incoming_message.authentication_token})
        local parts = {}
        log:info("sending verification request for " .. incoming_message.peername)
        local status, code, headers = https.request {
            url = config.verify_url,
            method = "POST",
            headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Length"] = #body
            },
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(parts)
        }
        if status == 200 then
            log:info("verification server verified authentication token for " .. incoming_message.peername)
            local response = json.decode(table.concat(parts))
            local event = {
                kind = itc_events.remote_authenticator_verify_response,
                message = {
                    peername = incoming_message.peername,
                    id = response.id
                }
            }
            context:send(nil, client_command_config.itc_channel, event)
            signal.raise(signal.realtime(client_command_config.itc_channel))
        elseif status == 401 then
            log:warn("verification server declined to verify authentication token for " .. incoming_message.peername)
        else
            log:error("verification server responded with status " .. status)
        end
    else
        log:error("unknown event kind \"" .. incoming_event.kind .. "\" received on " .. config.itc_channel)
    end
end

local function start()
    state = {}
    local signal_watcher = ev.Signal.new(on_signal_event, signal.realtime(config.itc_channel))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)
end

local function stop()
    state.signal_watcher:stop(ev.Loop.default)
    state = nil
end

return = {
    start = start,
    stop = stop,
}
