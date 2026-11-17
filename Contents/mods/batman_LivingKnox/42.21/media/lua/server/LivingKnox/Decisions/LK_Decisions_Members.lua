-- Living Knox : cadre de décision des PNJ, menaces perçues d'un membre (attitudes du groupe envers les
-- joueurs).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- ================================================================ membres (autorité)

-- Attitude du groupe gid envers les joueurs vivants connus : { [compte] = niveau } (LK_Hostility ; sans identité de
-- personnage : niveau de départ du type).
local function attitudesFor(gid, g, players)
    local out = {}
    local Ho = LivingKnox.Hostility
    if Ho == nil then return out end
    for _, p in ipairs(players) do
        local name = p:getUsername()
        local key = Ho.keyOf and Ho.keyOf(p) or nil
        local level
        if key ~= nil then
            local view = Ho.get(gid, key)
            level = view and view.level or nil
        end
        if level == nil then level = Ho.levelOf(Ho.startFor(g.type)) end
        out[name] = level
    end
    return out
end

-- Menaces perçues (liste triée par distance puis clé) : zombies vus ou entendus ; joueurs vus ou entendus envers qui
-- le groupe est hostile (fuite permise) ou méfiant (regard seulement). Perception absente ou périmée : aucune.
-- LK05-T14 : un zombie perçu au-delà de Config.zombieAlertDistance() (option ZombieAlertDistance) est ignoré.
function Decisions.threatsOf(per, attitudes)
    local out = {}
    if per == nil or per.stale then return out end
    local zmax = LivingKnox.Config.zombieAlertDistance()
    for _, e in ipairs(per.z or {}) do
        if (e.s or e.h) and (zmax == nil or (e.d or 0) <= zmax) then
            out[#out + 1] = { kind = "zombie", key = "z" .. tostring(e.o), label = tostring(e.o), x = e.x, y = e.y,
                z = e.z, d = e.d or 0, seen = e.s, flee = true }
        end
    end
    for _, e in ipairs(per.p or {}) do
        local level = attitudes[e.u]
        if (e.s or e.h) and (level == "hostile" or level == "wary") then
            out[#out + 1] = { kind = "player", key = "p" .. e.u, label = e.u, x = e.x, y = e.y, z = e.z, d = e.d or 0,
                seen = e.s, flee = level == "hostile" }
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    return out
end

P.attitudesFor = attitudesFor
