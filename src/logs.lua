local ansicolors = require "ansicolors"
local logging = require "logging"
require "logging.console"

logging.defaultLogger(logging.console {
  logLevel = logging.DEBUG,
  destination = "stderr",
  timestampPattern = "%y-%m-%d %H:%M:%S",
  logPatterns = {
    [logging.DEBUG] = ansicolors("%{dim white}%date%{reset} %{white}* %{dim cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.INFO] = ansicolors("%{dim white}%date%{reset} %{white}* %{bright cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.WARN] = ansicolors("%{dim white}%date%{reset} %{white}* %{yellow}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.ERROR] = ansicolors("%{dim white}%date%{reset} %{white}* %{red}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.FATAL] = ansicolors("%{dim white}%date%{reset} %{white}* %{magenta}%level %{reset}%message %{dim white}(%file:%line)\n"),
  }
})

local client = logging.console {
  logLevel = logging.DEBUG,
  destination = "stderr",
  timestampPattern = "%y-%m-%d %H:%M:%S",
  logPatterns = {
    [logging.DEBUG] = ansicolors("%{dim white}%date%{reset} %{green}* %{dim cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.INFO] = ansicolors("%{dim white}%date%{reset} %{green}* %{bright cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.WARN] = ansicolors("%{dim white}%date%{reset} %{green}* %{yellow}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.ERROR] = ansicolors("%{dim white}%date%{reset} %{green}* %{red bright}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.FATAL] = ansicolors("%{dim white}%date%{reset} %{green}* %{magenta bright}%level %{reset}%message %{dim white}(%file:%line)\n"),
  }
}

local server = logging.console {
  logLevel = logging.DEBUG,
  destination = "stderr",
  timestampPattern = "%y-%m-%d %H:%M:%S",
  logPatterns = {
    [logging.DEBUG] = ansicolors("%{dim white}%date%{reset} %{red}* %{dim cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.INFO] = ansicolors("%{dim white}%date%{reset} %{red}* %{bright cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.WARN] = ansicolors("%{dim white}%date%{reset} %{red}* %{yellow}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.ERROR] = ansicolors("%{dim white}%date%{reset} %{red}* %{red bright}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.FATAL] = ansicolors("%{dim white}%date%{reset} %{red}* %{magenta bright}%level %{reset}%message %{dim white}(%file:%line)\n"),
  }
}

local authenticator = logging.console {
  logLevel = logging.DEBUG,
  destination = "stderr",
  timestampPattern = "%y-%m-%d %H:%M:%S",
  logPatterns = {
    [logging.DEBUG] = ansicolors("%{dim white}%date%{reset} %{blue}* %{dim cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.INFO] = ansicolors("%{dim white}%date%{reset} %{blue}* %{bright cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.WARN] = ansicolors("%{dim white}%date%{reset} %{blue}* %{yellow}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.ERROR] = ansicolors("%{dim white}%date%{reset} %{blue}* %{red bright}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.FATAL] = ansicolors("%{dim white}%date%{reset} %{blue}* %{magenta bright}%level %{reset}%message %{dim white}(%file:%line)\n"),
  }
}

return {
  client = client,
  server = server,
  authenticator = authenticator
}
