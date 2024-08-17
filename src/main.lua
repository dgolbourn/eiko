local argparse = require "argparse"
local parser = argparse("eiko", "eiko netcode")
parser:argument("mode", "client or server"):choices{"client", "server", "authenticator"}
parser:argument("config", "configuration file")
local args = parser:parse()

local event = require "eiko.event".event()
local config = require "eiko.config".load(args.config)
local eiko = require("eiko." .. args.mode).new(config)
eiko.start(event)
event.loop()
