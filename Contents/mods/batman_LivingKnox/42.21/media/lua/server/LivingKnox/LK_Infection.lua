-- Living Knox : virus de Knox d'un PNJ incarné, adaptateur de l'autorité (LK21-T04, ADR docs/architecture/decisions/
-- adr-blessures-soins.md, D04). Règles pures : shared/LivingKnox/LK_Virus.lua (transmission, délai, relevé, forme).
-- Autorité seulement (un client MP charge aussi media/lua/server, il s'arrête ici).
--
-- Responsabilité : ce qui arrive à un corps infecté, du jour de la contamination au relevé de son cadavre.
--   1. Contamination : le virus est posé par la source de blessure « zombie » (Virus.fromWounds) dans la liste de
--      plaies du corps (LK_Health), qui le sauvegarde. Au fait "npcWounded" d'une infection nouvelle, le PNJ le sait
--      (Health.get(id).virus) et son groupe le note au journal (entrée « infected », LK_Journal).
--   2. Échéance : chaque minute de jeu (EveryOneMinute), un corps relié dans le monde dont l'échéance est atteinte
--      meurt par le chemin unique Health.kill, cause « infection » (BodyDamage.Update : ReduceGeneralHealth(110),
--      J/characters/BodyDamage/BodyDamage.java:2018-2025). Sa mort suit le chemin ordinaire (LK_Bodies.onZombieDead :
--      faits memberDied, observation group_death, npcDied ; groupe : membre mort, journal).
--   3. Relevé : à la mort de tout corps (fait "bodyDying", avant LK_Health qui efface les plaies), si le corps doit se
--      relever (Virus.rises : option de transmission, corps infecté ; IsoGameCharacter.shouldBecomeZombieAfterDeath,
--      J/characters/IsoGameCharacter.java:10523-10540), le PNJ est marqué (npc.rises) et son cadavre, dès que le
--      moteur l'a créé (LivingKnox.Death.findCorpse), reçoit le relevé du vanilla : IsoDeadBody.reanimateLater
--      (J/iso/objects/IsoDeadBody.java:1756-1758, délai de l'option ZombieLore.Reanimate, comme un joueur mort
--      infecté, J/characters/IsoPlayer.java:7791-7794 ; heure gardée avec le cadavre, :923). Le moteur le relève
--      (IsoDeadBody.update, :1764-1775 ; reanimate copie les ModData, :1867). Le balayage des corps (LK_Bodies.examine)
--      voit ce zombie étiqueté d'un PNJ mort et le confie à Bodies.onRisen (Infection.release) : étiquette retirée
--      (zombie ordinaire, jamais remis à terre), PNJ retiré du registre (Identity.forget), fait "npcRisen".
-- Membre hors écran : même règle d'échéance (Virus.isDue) dans la simulation (LK_MemberHealth.pass) ; aucun corps,
-- aucun relevé.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Virus"
require "LivingKnox/LK_WoundContext"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Health"

local Virus = LivingKnox.Virus

local Infection = LivingKnox.Infection or {}
LivingKnox.Infection = Infection

Infection.pending = Infection.pending or {}   -- npcId -> { x, y, z, ms } : cadavre attendu (mémoire seulement)
Infection.state0 = Infection.state0 or { ticks = 0 }
Infection.stats = Infection.stats or { infected = 0, deaths = 0, rising = 0, risen = 0, lost = 0 }

local function cfg() return LivingKnox.Config.INFECTION end
local function H() return LivingKnox.Health end
local function B() return LivingKnox.Bodies end

-- Infection du PNJ id (copie { since, due }, heures d'âge du monde), ou nil.
function Infection.state(id)
    local list = H().wounds(id)
    local v = list ~= nil and list.virus or nil
    if v == nil then return nil end
    return { since = v.since, due = v.due }
end

-- ---------------------------------------------------------------- 1. contamination

-- Groupe du PNJ id : entrée « infected » au journal technique (et de récit par LK_Journal).
local function noteGroup(id)
    local G = LivingKnox.Groups
    if G == nil or G.findNpc == nil then return end
    local gid, mid = G.findNpc(id)
    if gid == nil then return end
    G.update(function(data)
        local g = data.groups[gid]
        if g == nil or g.members[mid] == nil then return false end
        G.appendLog(g, "infected", mid, G.today())
        return true, true
    end)
end

-- Vrai si l'infection du PNJ id vient du coup dont les plaies sont added : commencée à cette heure, et aucune plaie
-- plus ancienne ne porte le virus.
local function freshInfection(id, added)
    local list = H().wounds(id)
    local v = list ~= nil and list.virus or nil
    if v == nil or v.since ~= LivingKnox.WoundContext.worldHours() then return false end
    local mine = {}
    for _, w in ipairs(added) do mine[w] = true end
    for _, w in ipairs(list) do
        if w.virus and not mine[w] then return false end
    end
    return true
end

-- Fait "npcWounded" (LK_Health) : infection nouvelle si une plaie du coup porte le virus (freshInfection). Rend vrai si
-- notée.
function Infection.onWounded(info)
    if not Virus.carried(info.wounds) or not freshInfection(info.npc, info.wounds) then return false end
    local v = Infection.state(info.npc)
    Infection.stats.infected = Infection.stats.infected + 1
    LivingKnox.Log.info("npc %s infected by the Knox virus at hour %.3f: death due at hour %.3f", info.npc, v.since,
        v.due)
    noteGroup(info.npc)
    return true
end

-- ---------------------------------------------------------------- 2. échéance

-- Corps reliés dans le monde dont l'infection arrive à échéance à l'heure hours (défaut : horloge du jeu) : mort par
-- Health.kill, cause « infection ». Rend le nombre de morts décidées.
function Infection.duePass(hours)
    if not LivingKnox.isAuthority() or not LivingKnox.Store.isReady() then return 0 end
    hours = hours or LivingKnox.WoundContext.worldHours()
    if hours == nil then return 0 end
    local bodies, health = B(), H()
    local ids = {}
    for id in pairs(bodies.bound) do ids[#ids + 1] = id end
    table.sort(ids)
    local n = 0
    for _, id in ipairs(ids) do
        local z = bodies.bound[id]
        local list = not health.decided[id] and health.wounds(id) or nil
        if z ~= nil and list ~= nil and Virus.isDue(list.virus, hours) and bodies.inWorld(z) then
            local v = list.virus
            if health.kill(id, z, nil, nil, "infection") then
                n = n + 1
                Infection.stats.deaths = Infection.stats.deaths + 1
                LivingKnox.Log.info("npc %s died of the Knox virus (infected at hour %.3f, due at hour %.3f)", id,
                    v.since, v.due)
            end
        end
    end
    return n
end

-- ---------------------------------------------------------------- 3. relevé

-- Fait "bodyDying" (LK_Bodies.onZombieDead, avant LK_Health qui efface les plaies) : corps qui doit se relever noté
-- (npc.rises) et son cadavre attendu. Rend vrai si le corps se relèvera.
function Infection.onBodyDying(info)
    local id, z = info.npc, info.body
    local list = H().wounds(id) or {}
    if not Virus.rises(list.virus ~= nil, LivingKnox.WoundContext.current()) then return false end
    local npc = LivingKnox.Identity.get(LivingKnox.Store.data(), id)
    if npc == nil or z == nil then return false end
    npc.rises = true
    LivingKnox.Store.markDirty()
    Infection.pending[id] = { x = math.floor(z:getX()), y = math.floor(z:getY()), z = math.floor(z:getZ()),
        ms = getTimestampMs() }
    Infection.stats.rising = Infection.stats.rising + 1
    LivingKnox.Log.info("npc %s died %s: its corpse will rise", id, list.virus ~= nil and "infected" or
        "(everyone is infected)")
    return true
end

-- Cadavres attendus : relevé du vanilla programmé (reanimateLater) dès que le moteur a créé le cadavre ; abandon
-- signalé après CORPSE_WAIT_MS. Rend le nombre de cadavres programmés.
function Infection.corpsePass()
    local D = LivingKnox.Death
    if D == nil or D.findCorpse == nil then return 0 end
    local ids = {}
    for id in pairs(Infection.pending) do ids[#ids + 1] = id end
    table.sort(ids)
    local n, t = 0, getTimestampMs()
    for _, id in ipairs(ids) do
        local e = Infection.pending[id]
        local body = D.findCorpse(id, e.x, e.y, e.z)
        if body ~= nil then
            Infection.pending[id] = nil
            body:reanimateLater()
            n = n + 1
            LivingKnox.Log.info("npc %s: corpse at %s,%s,%s will rise at hour %.3f", id, tostring(e.x), tostring(e.y),
                tostring(e.z), body:getReanimateTime())
        elseif t - e.ms > cfg().CORPSE_WAIT_MS then
            Infection.pending[id] = nil
            Infection.stats.lost = Infection.stats.lost + 1
            LivingKnox.Log.warn("npc %s: corpse not found near %s,%s,%s, it will not rise", id, tostring(e.x),
                tostring(e.y), tostring(e.z))
        end
    end
    return n
end

-- Bodies.onRisen : zombie z relevé du cadavre du PNJ mort id. Relevé voulu (npc.rises) : étiquette retirée (zombie
-- ordinaire), PNJ retiré du registre, fait "npcRisen". Rend vrai si pris.
function Infection.release(z, id, npc)
    if npc == nil or npc.rises ~= true then return false end
    LivingKnox.Identity.clearTag(z:getModData())
    LivingKnox.Identity.forget(LivingKnox.Store.data(), id)
    LivingKnox.Store.markChanged()
    Infection.stats.risen = Infection.stats.risen + 1
    local x, y, zz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    LivingKnox.Log.info("npc %s rose as an ordinary zombie at %s,%s,%s: removed from the registry", id, tostring(x),
        tostring(y), tostring(zz))
    LivingKnox.publish("npcRisen", { npc = id, x = x, y = y, z = zz })
    return true
end

-- ---------------------------------------------------------------- événements

local function onEveryOneMinute()
    if LivingKnox.isAuthority() then LivingKnox.Infection.duePass() end
end

local function onTick()
    local st = Infection.state0
    st.ticks = st.ticks + 1
    if st.ticks < cfg().CORPSE_EVERY then return end
    st.ticks = 0
    if LivingKnox.isAuthority() then LivingKnox.Infection.corpsePass() end
end

LivingKnox.subscribe("EveryOneMinute", "Infection.duePass", onEveryOneMinute)
LivingKnox.subscribe("OnTick", "Infection.corpsePass", onTick)
LivingKnox.listen("npcWounded", "Infection.onWounded", function(info) LivingKnox.Infection.onWounded(info) end)
-- Avant LK_Health (order 10), qui efface les plaies du corps mort.
LivingKnox.listen("bodyDying", "Infection.onBodyDying", function(info) LivingKnox.Infection.onBodyDying(info) end, 5)
LivingKnox.Bodies.onRisen = function(z, id, npc) return LivingKnox.Infection.release(z, id, npc) end

return Infection
