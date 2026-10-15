-- Living Knox : matérialisation des groupes à l'approche d'un joueur et mise à jour de l'état simulé au retrait
-- (LK09-T03). Fiche : docs/conception/corps-registre.md, section « Matérialisation » ; docs/conception/simulation.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Passage (LivingKnox.Bodies.tick, une fois par tranche de balayage) : pour chaque groupe dont le foyer (home) est
-- connu et chargé, avec un joueur vivant à Config.MATERIALIZE.RADIUS cases ou moins, les membres PRÉSENTS au foyer
-- (vivants, hors équipe d'une expédition en route) qui n'ont pas de corps en reçoivent un, PER_PASS au plus par
-- passage, MAX_PER_GROUP par groupe et MAX_TOTAL en tout (corps de membres comptés au registre des corps) :
--   - lien npc vers un PNJ virtuel : nouvelle incarnation de ce PNJ (Bodies.embody : même identifiant lk-<n>, même
--     apparence, même arme, génération suivante) ;
--   - aucun lien (membre de la population initiale, recrue) ou lien vers un PNJ oublié : nouveau PNJ (Bodies.spawn)
--     dont l'apparence vient du profil du type (looks et outfits du profil, sexe du membre) et l'arme d'une des armes
--     du profil (Equipment.setWeapon), puis lien npc posé (Groups.setNpc) ;
--   - lien vers un PNJ incarné : rien (son corps existe, chargé ou mis de côté) ;
--   - lien vers un PNJ mort alors que le membre est vivant (mort d'un corps avant cette tâche) : le membre est marqué
--     mort (Materialize.onBodyDied), jamais recréé.
-- Santé : celle de naissance du corps (npc.hpMax, robustesse du moteur) réduite selon la blessure abstraite du membre
-- (wound 0..99 -> santé x (100 - wound) / 100), posée sur la copie de l'autorité dans le même appel Lua que la
-- création : un client MP la reçoit avec sa copie (J/popman/NetworkZombieSimulator.java:200).
-- Place : cases du foyer au même niveau, à PLACE_RADIUS cases au plus, la plus proche d'abord : même bâtiment que la
-- case du foyer (IsoGridSquare.getBuildingDef, par la pièce, J/iso/IsoGridSquare.java:7805-7816) ou, foyer hors de
-- tout bâtiment (camp), cases hors bâtiment ; jamais un escalier (isFree(false) y est vrai, J/iso/IsoGridSquare.java:
-- 2173-2175 HasStairs) ; chaque case doit satisfaire Bodies.freeSquare (case libre de LK02-T11).
-- Retrait (Bodies.release, LK03-T04) : Materialize.onReleased convertit la santé gardée en blessure du membre (le
-- membre est de nouveau traité par la simulation horaire, présent au foyer). Mort d'un corps de membre
-- (Bodies.onZombieDead) : Materialize.onBodyDied marque le membre mort une seule fois, sans second fait memberDied
-- (Groups.applyDeath quiet), succession immédiate et moral comme une mort hors écran.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Groups"

local Materialize = LivingKnox.Materialize or {}
LivingKnox.Materialize = Materialize

Materialize.state = Materialize.state or { warned = {}, near = {} }
Materialize.stats = Materialize.stats or { passes = 0, created = 0, embodied = 0, refused = 0, reconciled = 0,
    released = 0, died = 0 }

local M = 2147483647
local SALT_LOOK, SALT_OUTFIT, SALT_WEAPON = 1, 2, 3

local function log() return LivingKnox.Log end
local function Identity() return LivingKnox.Identity end
local function Store() return LivingKnox.Store end
local function Bodies() return LivingKnox.Bodies end
local function Groups() return LivingKnox.Groups end

-- Réglages --------------------------------------------------------------------------------------------------------

local function num(v, lo, hi, default)
    if type(v) ~= "number" or v ~= v then v = default end
    if v < lo then v = lo end
    if v > hi then v = hi end
    return v
end

-- Réglages lus et bornés (à chaque passage). RADIUS est plafonné pour garder l'hystérésis avec le retrait :
-- RADIUS + PLACE_RADIUS < BODIES.RELEASE_RADIUS.
function Materialize.settings()
    local raw = LivingKnox.Config.MATERIALIZE
    if type(raw) ~= "table" then raw = {} end
    local release = num(LivingKnox.Config.BODIES and LivingKnox.Config.BODIES.RELEASE_RADIUS, 2, 100000, 120)
    local s = {
        placeRadius = math.floor(num(raw.PLACE_RADIUS, 0, 16, 8)),
        maxPerGroup = math.floor(num(raw.MAX_PER_GROUP, 0, Groups().MAX_MEMBERS, 8)),
        maxTotal = math.floor(num(raw.MAX_TOTAL, 0, Bodies().MAX_EMBODIED, 24)),
        perPass = math.floor(num(raw.PER_PASS, 1, 8, 2)),
        fullHealth = num(raw.FULL_HEALTH, 0.001, Identity().HP_MAX, 1.8),
    }
    s.radius = math.floor(num(raw.RADIUS, 1, math.max(1, release - s.placeRadius - 1), 80))
    return s
end

-- Santé <-> blessure abstraite (logique pure) ------------------------------------------------------------------------

local function woundMax()
    local c = LivingKnox.Config.SIMULATION
    local death = c and c.WOUND_DEATH or 100
    return math.max(0, death - 1)
end

-- Santé d'un corps neuf pour une blessure wound (0..99) et une santé de naissance full : full x (100 - wound) / 100.
-- Une blessure abstraite ne tue jamais à la matérialisation (au plus WOUND_DEATH - 1).
function Materialize.healthOf(wound, full)
    local w = math.floor(num(wound, 0, woundMax(), 0))
    return full * (100 - w) / 100
end

-- Blessure abstraite (0..WOUND_DEATH - 1, entier) d'une santé hp rapportée à la santé de naissance full ; nil si hp
-- est inconnue. Un corps vivant n'est jamais rendu mort par la conversion ; une santé au-dessus de full = indemne.
function Materialize.woundOf(hp, full)
    if type(hp) ~= "number" or hp ~= hp then return nil end
    if type(full) ~= "number" or full ~= full or full <= 0 then return nil end
    local w = math.floor(100 * (1 - hp / full) + 0.5)
    if w < 0 then w = 0 end
    if w > woundMax() then w = woundMax() end
    return w
end

-- Membres -----------------------------------------------------------------------------------------------------------

-- Membres présents au foyer d'un groupe (registre vivant ou copie) : vivants, hors équipe d'une expédition en route ;
-- chef d'abord, puis par ancienneté.
function Materialize.presentMembers(g)
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local G = Groups()
    local out = {}
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then out[#out + 1] = mid end
    end
    table.sort(out, function(a, b)
        if a == g.leader then return b ~= g.leader end
        if b == g.leader then return false end
        return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0)
    end)
    return out
end

-- État du PNJ d'un membre au registre des corps : "embodied", "virtual", "dead", ou "none" (aucun lien, ou PNJ absent
-- du registre).
function Materialize.npcState(m, registry)
    local npc = m.npc and Identity().get(registry, m.npc)
    if npc == nil then return "none", nil end
    return npc.state, npc
end

-- Corps de membres de groupe au registre des corps (PNJ incarnés liés à un membre), total et par groupe.
local function embodiedMembers(data, registry)
    local total, byGroup = 0, {}
    for gid, g in pairs(data.groups) do
        local n = 0
        for _, m in pairs(g.members) do
            local npc = m.npc and Identity().get(registry, m.npc)
            if npc ~= nil and npc.state == Identity().STATE_EMBODIED then n = n + 1 end
        end
        byGroup[gid] = n
        total = total + n
    end
    return total, byGroup
end

-- Apparence et arme d'après le type -------------------------------------------------------------------------------

local function hashText(s, h)
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % M end
    return h
end

-- Élément de list choisi de façon stable pour (groupe, membre, salt), ou nil si la liste est vide.
local function stablePick(list, gid, mid, salt)
    if type(list) ~= "table" or #list == 0 then return nil end
    local h = hashText(tostring(gid) .. "/" .. tostring(mid) .. "/" .. tostring(salt), 17)
    return list[1 + (h % #list)]
end

local function typeProfile(g, m)
    local def = LivingKnox.GroupTypes.get(g.type)
    if def == nil or m.profile == nil then return nil end
    for _, p in ipairs(def.profiles) do
        if p.id == m.profile then return p end
    end
    return nil
end

-- Entrée d'apparence (LK_Appearance.normalize) d'un membre : sexe du membre, profil d'apparence parmi les looks de son
-- profil de type compatibles avec ce sexe, tenue parmi les outfits du profil ; champ absent : tiré avec le numéro du
-- PNJ (Identity.create).
function Materialize.appearanceOf(gid, g, mid, m)
    local out = {}
    local female = m.female
    local p = typeProfile(g, m)
    if p ~= nil and female == nil then female = p.female end
    if type(female) == "boolean" then out.female = female end
    if p ~= nil and p.looks ~= nil then
        local looks = {}
        for _, name in ipairs(p.looks) do
            local look = LivingKnox.Appearance.look(name)
            if look ~= nil and (female == nil or look.female == female) then looks[#looks + 1] = name end
        end
        out.look = stablePick(looks, gid, mid, SALT_LOOK)
    end
    if p ~= nil and p.outfits ~= nil then out.outfit = stablePick(p.outfits, gid, mid, SALT_OUTFIT) end
    return out
end

-- Arme d'un membre : une des armes de son profil de type (choix stable), ou nil.
function Materialize.weaponOf(gid, g, mid, m)
    local p = typeProfile(g, m)
    return p and stablePick(p.weapons, gid, mid, SALT_WEAPON) or nil
end

-- Place -------------------------------------------------------------------------------------------------------------

local function buildingId(sq)
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()   -- long au-delà de 2^53 : texte exact (base world-placement.md)
end

-- Case du foyer chargée et identifiant de son bâtiment (nil : camp), ou nil si la case n'est pas chargée.
function Materialize.homeSquare(home)
    local sq = getCell():getGridSquare(home.x, home.y, home.z)
    if sq == nil then return nil end
    return sq, buildingId(sq)
end

-- Case libre la plus proche du foyer, à radius cases au plus, au niveau du foyer : même bâtiment (bid) ou, camp
-- (bid nil), hors bâtiment ; aucun escalier ; Bodies.freeSquare. Rend la case, ou nil.
function Materialize.placeFor(home, bid, radius)
    local cell = getCell()
    for r = 0, radius do
        for _, d in ipairs(Bodies().ring(r)) do
            local sq = cell:getGridSquare(home.x + d[1], home.y + d[2], home.z)
            if sq ~= nil and buildingId(sq) == bid and not sq:HasStairs() and Bodies().freeSquare(sq) then
                return sq
            end
        end
    end
    return nil
end

-- Avertissement unique par (groupe, raison) tant qu'un joueur reste près du foyer.
local function warnOnce(gid, key, fmt, ...)
    local w = Materialize.state.warned
    w[gid] = w[gid] or {}
    if w[gid][key] then return end
    w[gid][key] = true
    log().warn(fmt, ...)
end

-- Mort et retrait (appelés par LK_Bodies) -----------------------------------------------------------------------------

-- Membre mid du groupe gid mort (corps du PNJ npcId mort, ou PNJ trouvé mort) : alive = faux une seule fois (rien si
-- déjà mort ou retiré), sans fait memberDied (déjà publié par Bodies.onZombieDead), succession immédiate si c'était
-- le chef, moral MORALE_DEATH. Une sauvegarde. Rend vrai si le membre vient d'être marqué mort.
function Materialize.onBodyDied(npcId, gid, mid)
    local G = Groups()
    local marked = G.update(function(data)
        local g = data.groups[gid]
        local m = g and g.members[mid]
        if m == nil or not m.alive or m.npc ~= npcId then return false, false end
        local day = G.today()
        local wasLeader = G.applyDeath(g, mid, day, true)
        if wasLeader then
            local successor = G.pickSuccessor(g)
            if successor then G.applyLeader(g, successor, day) end
        end
        local c = LivingKnox.Config.SIMULATION
        local morale = g.morale + (c and c.MORALE_DEATH or 0)
        if morale < 0 then morale = 0 end
        if morale > G.LEVEL_MAX then morale = G.LEVEL_MAX end
        g.morale = math.floor(morale + 0.5)
        return true, true
    end)
    if marked == true then
        Materialize.stats.died = Materialize.stats.died + 1
        log().info("group %s member %s (npc %s) marked dead: its body died", gid, mid, npcId)
        return true
    end
    return false
end

-- PNJ npcId rendu à la simulation abstraite (Bodies.release) avec la santé gardée hp (ou nil) : blessure du membre
-- lié = Materialize.woundOf(hp, npc.hpMax ou FULL_HEALTH) ; membre de nouveau présent au foyer pour la simulation
-- horaire. Santé inconnue : blessure inchangée. Rend la blessure retenue, ou nil.
function Materialize.onReleased(npcId, hp, npc)
    local G = Groups()
    local gid, mid = G.findNpc(npcId)
    if gid == nil then return nil end
    local full = npc and npc.hpMax or Materialize.settings().fullHealth
    local wound = Materialize.woundOf(hp, full)
    local kept = G.update(function(data)
        local m = data.groups[gid] and data.groups[gid].members[mid]
        if m == nil or not m.alive or wound == nil then return false, false end
        local before = m.wound or 0
        if wound > 0 then m.wound = wound else m.wound = nil end
        return before ~= wound, true
    end)
    Materialize.stats.released = Materialize.stats.released + 1
    local Ex = LivingKnox.Expeditions   -- LK05-T05 : membre d'une expédition physique : équipe ou bascule hors écran
    if Ex ~= nil and Ex.onReleased ~= nil then Ex.onReleased(gid, mid) end
    log().info("group %s member %s back to the offscreen simulation at home (npc %s): health %s of %s, wound %s",
        gid, mid, npcId, hp and string.format("%.3f", hp) or "unknown", string.format("%.3f", full),
        wound and tostring(wound) or "unchanged")
    if kept == true then return wound end
    return nil
end

-- Création ------------------------------------------------------------------------------------------------------------

-- Pose la santé d'un corps neuf selon la blessure du membre. Rend la santé posée, ou nil (indemne).
local function applyWound(z, npc, m, s)
    local w = m.wound or 0
    if w <= 0 then return nil end
    local full = npc.hpMax or s.fullHealth
    local hp = Materialize.healthOf(w, full)
    z:setHealth(hp)
    return hp
end

-- Corps pour le membre mid du groupe gid sur la case sq. Rend le PNJ et le zombie, ou nil et une raison.
function Materialize.embodyMember(gid, g, mid, m, sq, s)
    local B, I = Bodies(), Identity()
    local registry = Store().data()
    local state, npc = Materialize.npcState(m, registry)
    local x, y, zz = sq:getX(), sq:getY(), sq:getZ()
    local z, why, npcId
    if state == I.STATE_VIRTUAL then
        npcId = npc.id
        z, why = B.embody(npcId, x, y, zz)
        if z == nil then return nil, why end
        Materialize.stats.embodied = Materialize.stats.embodied + 1
    elseif state == "none" then
        local id, body = B.spawn(Materialize.appearanceOf(gid, g, mid, m), x, y, zz)
        if id == nil then return nil, body end
        local linked, err = Groups().setNpc(gid, mid, id)
        if not linked then
            B.despawn(id, true)
            return nil, "npc link refused: " .. tostring(err)
        end
        npcId, z = id, body
        npc = I.get(Store().data(), id)
        local weapon = Materialize.weaponOf(gid, g, mid, m)
        if weapon ~= nil and LivingKnox.Equipment ~= nil then
            local armed, werr = LivingKnox.Equipment.setWeapon(id, weapon)
            if not armed then
                log().warn("npc %s (group %s member %s): weapon %s refused: %s", id, gid, mid, weapon, tostring(werr))
            end
        end
        Materialize.stats.created = Materialize.stats.created + 1
    else
        return nil, "npc " .. tostring(m.npc) .. " is " .. tostring(state)
    end
    local hp = applyWound(z, npc, m, s)
    -- Santé de référence (LK07-T02) : celle que la simulation donne au membre (blessure abstraite), décidée ici.
    local H = LivingKnox.Health
    if H ~= nil and H.setBirth ~= nil then H.setBirth(npcId, hp or z:getHealth()) end
    log().info("group %s member %s materialized as npc %s at %s,%s,%s (wound %s, health %s)", gid, mid, npcId,
        tostring(x), tostring(y), tostring(zz), tostring(m.wound or 0),
        string.format("%.3f", hp or z:getHealth()))
    return npcId, z
end

-- Passage -------------------------------------------------------------------------------------------------------------

-- Membre vivant dont le PNJ est mort au registre des corps : marqué mort (jamais recréé).
local function reconcile(gid, mid, m)
    if Materialize.onBodyDied(m.npc, gid, mid) then
        Materialize.stats.reconciled = Materialize.stats.reconciled + 1
        log().warn("group %s member %s was alive but its npc %s is dead: marked dead, not materialized", gid, mid,
            tostring(m.npc))
    end
end

-- Un groupe proche d'un joueur : membres présents sans corps matérialisés, dans les bornes. Rend le nombre de corps
-- créés ; budget = corps encore permis dans ce passage ; counts = { total, byGroup }.
local function materializeGroup(gid, g, s, budget, counts)
    local home = g.home
    local sq, bid = Materialize.homeSquare(home)
    if sq == nil then return 0 end                                     -- foyer non chargé : attente
    local registry = Store().data()
    local created = 0
    for _, mid in ipairs(Materialize.presentMembers(g)) do
        local m = g.members[mid]
        local state = Materialize.npcState(m, registry)
        if state == Identity().STATE_DEAD then
            reconcile(gid, mid, m)
        elseif state ~= Identity().STATE_EMBODIED then
            if created >= budget then return created end
            if (counts.byGroup[gid] or 0) >= s.maxPerGroup then
                warnOnce(gid, "group", "group %s: %s body(ies) already, MAX_PER_GROUP reached: other members stay "
                    .. "offscreen", gid, tostring(counts.byGroup[gid] or 0))
                return created
            end
            if counts.total >= s.maxTotal then
                warnOnce(gid, "total", "group %s: %s group member bodies in the world, MAX_TOTAL reached", gid,
                    tostring(counts.total))
                return created
            end
            local place = Materialize.placeFor(home, bid, s.placeRadius)
            if place == nil then
                warnOnce(gid, "place", "group %s: no free square within %s of its home %s,%s,%s (%s): waiting", gid,
                    tostring(s.placeRadius), tostring(home.x), tostring(home.y), tostring(home.z),
                    bid and "building" or "camp")
                return created
            end
            local npcId, why = Materialize.embodyMember(gid, g, mid, m, place, s)
            if npcId == nil then
                Materialize.stats.refused = Materialize.stats.refused + 1
                warnOnce(gid, "refused:" .. mid, "group %s member %s not materialized: %s", gid, mid, tostring(why))
                return created
            end
            created = created + 1
            counts.total = counts.total + 1
            counts.byGroup[gid] = (counts.byGroup[gid] or 0) + 1
        end
    end
    return created
end

-- Passage (autorité, appelé par Bodies.tick après ses contrôles) : groupes dans l'ordre de leur numéro ; PER_PASS
-- corps au plus. Rend le nombre de corps créés.
function Materialize.pass()
    local G = Groups()
    if G == nil or not G.ensure() then return 0 end
    if not Bodies().canAct(true) then return 0 end
    Materialize.stats.passes = Materialize.stats.passes + 1
    local s = Materialize.settings()
    local players = Bodies().livingPlayers()
    local data = G.state.data
    local st = Materialize.state
    local near, anyNear = {}, false
    local ids = G.list()
    for _, gid in ipairs(ids) do
        local g = data.groups[gid]
        if g ~= nil and g.home ~= nil
            and Bodies().playerNear(players, g.home.x + 0.5, g.home.y + 0.5, s.radius) then
            near[gid], anyNear = true, true
        end
    end
    for gid in pairs(st.near) do
        if not near[gid] then st.warned[gid] = nil end              -- avertissements de nouveau permis à l'approche
    end
    st.near = near
    if not anyNear then return 0 end                                 -- coût : groupes x joueurs seulement
    local total, byGroup = embodiedMembers(data, Store().data())
    local counts = { total = total, byGroup = byGroup }
    local created = 0
    for _, gid in ipairs(ids) do
        if near[gid] and created < s.perPass then
            local g = data.groups[gid]
            if g ~= nil then created = created + materializeGroup(gid, g, s, s.perPass - created, counts) end
        end
    end
    return created
end

return Materialize
