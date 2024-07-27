local signal = require "signal"
local config = require "config".remote_authenticator
local client_command_config = require "config".client_command
local itc_events = require "config".itc_events
local https = require("ssl.https")

local state = {}

local function on_signal_event(loop, sig, revents)
    local key, incoming_event = context:receive(nil, config.itc_channel)
    if incoming_event.kind == itc_events.remote_authenticator_verify_request then
        -- forward message to remote
        local res, code, response_headers = https.request{
            url = "https://golbourn.co.uk/v01/Authenticatie.svc"
        }
        -- forward response to client_command
        local event = {
            kind = itc_events.remote_authenticator_verify_response,
            message = {
                --
            }
        }
        context:send(nil, client_command_config.itc_channel, event)
        signal.raise(signal.realtime(client_command_config.itc_channel))
    else
        log:error("unknown event kind \"" .. incoming_event.kind .. "\" received on " .. config.itc_channel)
    end
end

local function start()
    state = {}
    local signal_watcher = ev.Signal.new(on_signal_event, signal.realtime(config.itc_channel))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)
    state.clients = {}
end

local function stop()
    state.signal_watcher:stop(ev.Loop.default)
    state = nil
end

return = {
    start = start,
    stop = stop,
}
