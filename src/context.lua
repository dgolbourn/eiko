local lanes = require "lanes".configure{with_timers=false, verbose_errors=true}
local linda = lanes.linda()

return linda
