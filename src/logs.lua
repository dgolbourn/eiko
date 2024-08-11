local ansicolors = require "ansicolors"
local logging = require "logging"
require "logging.console"

logging.defaultLogger(logging.console {
  logLevel = logging.DEBUG,
  destination = "stderr",
  timestampPattern = "%y-%m-%d %H:%M:%S",
  logPatterns = {
    [logging.DEBUG] = ansicolors("%{dim white}%date%{reset}%{cyan} %level %message %{dim white}(%source)\n"),
    [logging.INFO] = ansicolors("%{dim white}%date%{reset} %level %message %{dim white}(%source)\n"),
    [logging.WARN] = ansicolors("%{dim white}%date%{reset}%{yellow} %level %message %{dim white}(%source)\n"),
    [logging.ERROR] = ansicolors("%{dim white}%date%{reset}%{red bright} %level %message %{dim white}(%source)\n"),
    [logging.FATAL] = ansicolors("%{dim white}%date%{reset}%{magenta bright} %level %message %{dim white}(%source)\n"),
  }
})

return logging
