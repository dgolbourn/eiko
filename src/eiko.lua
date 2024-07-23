local ev = require "ev"
local se = require "eiko.server_event"
local cc = require "eiko.client_command"
local gl = require "eiko.game_loop"

cc.start("localhost", 21098)

se.start("localhost", 21098)

local game_loop_period = 1./40
local game_loop_timer = ev.Timer.new(gl.callback, game_loop_period, game_loop_period)
game_loop_timer:start(ev.Loop.default)

ev.Loop.default:loop()
