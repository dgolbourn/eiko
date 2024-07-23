local ev = require "ev"

local client_command_period = 1./10
local function client_command_callback(loop, timer_event)
    print("client")
end
local client_command_timer = ev.Timer.new(client_command_callback, client_command_period, client_command_period)

local server_event_period = 1./20
local function server_event_callback(loop, timer_event)
    print("server")
end
local server_event_timer = ev.Timer.new(server_event_callback, server_event_period, server_event_period)

local game_period = 1./40
local function game_callback(loop, timer_event)
    print("game")
end
local game_timer = ev.Timer.new(game_callback, game_period, game_period)

client_command_timer:start(ev.Loop.default)
game_timer:start(ev.Loop.default)
server_event_timer:start(ev.Loop.default)

ev.Loop.default:loop()
