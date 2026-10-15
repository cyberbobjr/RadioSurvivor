-- Living Knox : journal à niveaux. Messages en anglais ASCII, préfixés "[LivingKnox] LEVEL".
-- debug n'écrit que si l'option LivingKnox.Debug est vraie ; setEnabled(false) coupe tout le journal.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"

local Log = LivingKnox.Log or {}
LivingKnox.Log = Log

Log.state = Log.state or { enabled = true }

function Log.setEnabled(enabled)
    Log.state.enabled = enabled and true or false
end

function Log.isEnabled()
    return Log.state.enabled == true
end

-- Texte du message : format string.format si des arguments suivent, sinon tostring.
function Log.format(msg, ...)
    if select("#", ...) > 0 then
        return string.format(tostring(msg), ...)
    end
    return tostring(msg)
end

function Log.write(level, msg, ...)
    if not Log.isEnabled() then return false end
    print(LivingKnox.TAG .. " " .. level .. " " .. Log.format(msg, ...))
    return true
end

function Log.debug(msg, ...)
    if not LivingKnox.Config.isDebug() then return false end
    return Log.write("DEBUG", msg, ...)
end

function Log.info(msg, ...)
    return Log.write("INFO", msg, ...)
end

function Log.warn(msg, ...)
    return Log.write("WARN", msg, ...)
end

function Log.error(msg, ...)
    return Log.write("ERROR", msg, ...)
end

return Log
