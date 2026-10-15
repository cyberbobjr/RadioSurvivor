"""Doublure du module public du mod requis Signal Smoke (batman_SignalSmoke) pour les bancs lupa de RadioSurvivor.

Signal Smoke est un mod requis (mod.info require=, 2026-10-15) : le Lua serveur fait require 'SignalSmoke/SignalSmoke'
sans repli. Les bancs qui chargent ce Lua installent cette doublure (package.preload) avant le chargement :

    from signalsmoke_double import SIGNAL_SMOKE
    rt.execute(SIGNAL_SMOKE)

Doublure de l'API documentée dans Workshop/SignalSmoke (SignalSmoke.lua : COLORS, onSignal, removeSignalListener,
notify, start, stop ; événement « started » avec entry { id, kind, x, y, z, color { r, g, b }, owner, source } et
player / username, abonnés appelés sous pcall au moment de start). Mêmes couleurs que SignalSmoke.COLORS.
Globales de test : SS_FAKE (module), SS_LISTENERS (abonnés), SS_STARTED (entrées posées). Différence voulue :
une erreur d'abonné est relevée (error) au lieu d'être seulement journalisée, pour qu'un banc la voie.
"""

SIGNAL_SMOKE = r"""
SS_LISTENERS, SS_STARTED = {}, {}
SS_FAKE = {COLORS = {
    green = {r = 0.3, g = 1.0, b = 0.3}, red = {r = 1.0, g = 0.25, b = 0.2}, yellow = {r = 1.0, g = 0.95, b = 0.25},
    purple = {r = 0.75, g = 0.3, b = 1.0}, orange = {r = 1.0, g = 0.6, b = 0.15}, blue = {r = 0.3, g = 0.55, b = 1.0},
    white = {r = 1.0, g = 1.0, b = 1.0}}}
function SS_FAKE.onSignal(fn)
    for _, f in ipairs(SS_LISTENERS) do if f == fn then return false end end
    SS_LISTENERS[#SS_LISTENERS + 1] = fn
    return true
end
function SS_FAKE.removeSignalListener(fn)
    for i, f in ipairs(SS_LISTENERS) do if f == fn then table.remove(SS_LISTENERS, i); return true end end
    return false
end
function SS_FAKE.notify(event)
    for _, fn in ipairs(SS_LISTENERS) do
        local ok, err = pcall(fn, event)
        if not ok then error('signal listener failed: ' .. tostring(err)) end
    end
end
function SS_FAKE.start(o)
    local c = SS_FAKE.COLORS[o.color]
    local entry = {id = o.id or ('ss' .. (#SS_STARTED + 1)), kind = o.kind or 'smoke', x = o.x, y = o.y, z = o.z or 0,
        color = {r = c.r, g = c.g, b = c.b}, owner = o.owner, source = o.source or 'script'}
    SS_STARTED[#SS_STARTED + 1] = entry
    local username = o.username or (o.player and o.player:getUsername())
    SS_FAKE.notify({type = o.eventType or 'started', id = entry.id, entry = entry, source = entry.source,
        player = o.player, username = username})
    return entry.id
end
function SS_FAKE.stop(id) return true end
function SS_FAKE.isActive(id)
    for _, e in ipairs(SS_STARTED) do if e.id == id then return true end end
    return false
end
package.loaded['SignalSmoke/SignalSmoke'] = nil
package.preload['SignalSmoke/SignalSmoke'] = function() return SS_FAKE end
"""
