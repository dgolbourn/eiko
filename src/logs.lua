local ansicolors = require "ansicolors"
local logging = require "logging"
local envconfig = require "logging.envconfig"

envconfig.set_default_settings("EIKO")
local logger_name, logger_opts = envconfig.get_default_settings()
local env_logger = require("logging."..logger_name)
local function log_patterns(colour)
  return {
    [logging.DEBUG] = ansicolors("%{dim white}%date%{reset} %{" .. colour .. "}* %{reset}%{dim cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.INFO] = ansicolors("%{dim white}%date%{reset} %{" .. colour .. "}* %{reset}%{bright cyan}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.WARN] = ansicolors("%{dim white}%date%{reset} %{" .. colour .. "}* %{reset}%{yellow}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.ERROR] = ansicolors("%{dim white}%date%{reset} %{" .. colour .. "}* %{reset}%{red}%level %{reset}%message %{dim white}(%file:%line)\n"),
    [logging.FATAL] = ansicolors("%{dim white}%date%{reset} %{" .. colour .. "}* %{reset}%{magenta}%level %{reset}%message %{dim white}(%file:%line)\n"),
  }
end

logger_opts.logPatterns = log_patterns("white")
logging.defaultLogger(env_logger(logger_opts))

logger_opts.logPatterns = log_patterns("green")
local client = env_logger(logger_opts)

logger_opts.logPatterns = log_patterns("red")
local server = env_logger(logger_opts)

logger_opts.logPatterns = log_patterns("blue")
local authenticator = env_logger(logger_opts)

return {
  client = client,
  server = server,
  authenticator = authenticator
}
