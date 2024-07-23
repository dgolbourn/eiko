local ev = require "ev"
local se = require "eiko.server_event"
local cc = require "eiko.client_command"
local gl = require "eiko.game_loop"

local client_command_period = 1./10
local client_command_timer = ev.Timer.new(cc.callback, client_command_period, client_command_period)
client_command_timer:start(ev.Loop.default)

local server_event_period = 1./20
local server_event_timer = ev.Timer.new(se.callback, server_event_period, server_event_period)
server_event_timer:start(ev.Loop.default)

local game_loop_period = 1./40
local game_loop_timer = ev.Timer.new(gl.callback, game_loop_period, game_loop_period)
game_loop_timer:start(ev.Loop.default)

ev.Loop.default:loop()
