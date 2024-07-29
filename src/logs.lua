local ansicolors = require "ansicolors"
local logging = require "logging"
require "logging.console"

logging.defaultLogger(logging.console {
  logLevel = logging.DEBUG,
  destination = "stderr",
  timestampPattern = "%y-%m-%d %H:%M:%S",
  logPatterns = {
    [logging.DEBUG] = ansicolors("%date%{cyan} %level %message\n"),
    [logging.INFO] = ansicolors("%date %level %message\n"),
    [logging.WARN] = ansicolors("%date%{yellow} %level %message\n"),
    [logging.ERROR] = ansicolors("%date%{red bright} %level %message %{reset}(%source)\n"),
    [logging.FATAL] = ansicolors("%date%{magenta bright} %level %message %{reset}(%source)\n"),
  }
})

return logging
