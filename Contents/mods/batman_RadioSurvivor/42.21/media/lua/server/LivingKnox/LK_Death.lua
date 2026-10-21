-- Living Knox : cadavre d'un PNJ renvoyé aux clients MP qui ne l'ont pas reçu (LK07-T10). Serveur MP seulement ;
-- un client MP charge aussi ce fichier (media/lua/server) et un solo n'en a pas besoin : rien n'y est suivi.
-- Fiche : docs/annexes/conception/sante.md, « Cadavre renvoyé à un client sans copie (LK07-T10) ».
--
-- Cause (Java 42.21.0, J = zombie/..., base zombies-as-npc-bodies.md, « Copie cliente d'un zombie ») : un client crée
-- le cadavre d'un zombie seulement par le paquet de mort (DeadZombiePacket), qu'il IGNORE s'il n'a pas la copie de ce
-- zombie (J/network/packets/character/DeadCharacterPacket.java:90-92, isConsistent) : copie retirée « stale » après
-- 5 s sans paquet, client arrivé juste avant la mort, corps tué avant que sa copie parte. Aucun autre paquet ne
-- l'apporte : ce client n'a pas le cadavre et sa case compte un objet statique de moins que celle du serveur, ce qui
-- bloque aussi les cadavres suivants de la case (J/characters/NetworkCharacterAI.java:201-210, 435-437).
--
-- Renvoi sans doublon : sendCorpse(body) envoie AddCorpseToMap à TOUTES les connexions proches
-- (J/network/GameServer.java:1852-1866), et un client qui a déjà le cadavre en ajoute un second (objet neuf lu du
-- paquet, J/network/packets/actions/AddCorpseToMapPacket.java:89-97 ; IsoGridSquare.addCorpse ne compare que l'objet,
-- J/iso/IsoGridSquare.java:2648). Aucune fonction Lua n'envoie un cadavre à une seule connexion. D'où :
--   1. à la mort (Death.track, appelé par Bodies.onZombieDead et Bodies.layDown), le corps est noté ;
--   2. CHECK_DELAY_MS plus tard (le cadavre d'un client qui avait la copie arrive au plus 5 s après le paquet de mort :
--      relance de NetworkCharacterAI, PostponedPacket DEAD_BODY_DELAY_MS), le serveur demande aux joueurs proches
--      (commande "corpseCheck" : identifiant d'objet du cadavre, case, nombre d'objets statiques de la case) ;
--   3. un client qui ne trouve pas ce cadavre répond "corpseMissing" (client/LivingKnox/LK_DeathClient.lua) ;
--   4. le serveur retire alors le cadavre (removeCorpse(body, false) : RemoveCorpseFromMap aux connexions proches,
--      J/iso/IsoGridSquare.java:2600-2620 ; un client qui l'a le retire par son identifiant d'objet, un client qui ne
--      l'a pas ignore le paquet), puis RESEND_GAP_MS plus tard le remet sur sa case (addCorpse(body, true), sans
--      paquet sur le serveur) et l'envoie à tous (sendCorpse). Chaque client finit avec un seul cadavre, contenu
--      compris (IsoDeadBody.writeToRemoteBuffer -> save). L'écart évite qu'un retrait (paquet RELIABLE non ordonné)
--      arrive après l'ajout (RELIABLE_ORDERED) du même identifiant d'objet, que le serveur garde
--      (J/network/id/ObjectIDManager.java:96-121) ;
--   5. une nouvelle demande suit le renvoi (vérification) ; au plus MAX_RESENDS renvois par cadavre.
-- Le retrait part avec l'identifiant de personnage du cadavre : IsoDeadBody.setCharacterOnlineID(short) ne peut pas
-- être appelé depuis Lua (Kahlua ne convertit pas un nombre en short : « expected argument of type short, got Double »,
-- campagne MP du 2026-10-15, retrait jamais fait, cadavre jamais renvoyé). Limite restante : un client sans le cadavre
-- mais qui a un zombie vivant de même onlineId (identifiants recyclés) garde le retrait en attente sur ce zombie
-- (RemoveCorpseFromMapPacket.java:75-80, 105-112) ; la vérification qui suit le renvoi redemande alors un renvoi
-- (au plus MAX_RESENDS).
-- Identifiant d'objet lu par tostring(body:getObjectID()) : ObjectID n'est pas exposé, Kahlua rend alors toString()
-- (se/krka/kahlua/vm/KahluaUtil.java:268-319), "DeadBody-<n>" (J/network/id/ObjectID.java:77-79) ; le client pose le
-- même identifiant sur son cadavre (DeadCharacterPacket.java:146-150, AddCorpseToMapPacket.java:62-63). Texte d'une
-- autre forme : le client compare alors le nombre d'objets statiques de la case.
-- Limites : un joueur qui fouille ce cadavre chez lui à l'instant du renvoi voit sa fenêtre se fermer ; un arrêt du
-- serveur pendant RESEND_GAP_MS perd le cadavre (hors de sa case). Le renvoi n'a lieu que si un client le demande.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"

local Death = LivingKnox.Death or {}
LivingKnox.Death = Death

Death.MODULE = "LivingKnox"
Death.CMD_CHECK = "corpseCheck"
Death.CMD_MISSING = "corpseMissing"
Death.CHECK_DELAY_MS = 7000    -- cadavre d'un client qui avait la copie : au plus 5 s après le paquet de mort
Death.RECHECK_MS = 3000        -- vérification après un renvoi (AddCorpseToMap traité à réception)
Death.REPLY_MS = 5000          -- réponses acceptées après une demande
Death.RESEND_GAP_MS = 1000     -- retrait, puis remise et envoi du cadavre
Death.MAX_RESENDS = 2
Death.NEAR = 100               -- joueurs interrogés (portée réseau d'une connexion : 64 à 96 cases)
Death.EVERY = 5                -- images entre deux passages (serveur dédié : 10 images par seconde)
Death.ID_PATTERN = "^DeadBody%-%d+$"

Death.pending = Death.pending or {}   -- npcId -> { id, z = zombie, x, y, z, at, phase, ... } (mémoire seulement)
Death.state = Death.state or { ticks = 0 }
Death.stats = Death.stats or { tracked = 0, asked = 0, missing = 0, resent = 0, clean = 0, gone = 0, nobody = 0,
    refused = 0, failed = 0, stillMissing = 0 }

local function log() return LivingKnox.Log end

-- Vrai sur un serveur MP (dédié ou hébergé) : seul endroit où un client peut manquer un cadavre.
function Death.active()
    return isServer() and not isClient()
end

-- Identifiant d'objet d'un cadavre ("DeadBody-<n>"), ou nil s'il n'a pas cette forme.
function Death.objectKey(body)
    local ok, key = pcall(function() return tostring(body:getObjectID()) end)
    if ok and type(key) == "string" and string.find(key, Death.ID_PATTERN) then return key end
    return nil
end

-- Note le corps z du PNJ id qui vient de mourir (OnZombieDead : le cadavre n'existe pas encore). Serveur MP seulement.
function Death.track(id, z, why)
    if not Death.active() or type(id) ~= "string" or z == nil then return false end
    Death.pending[id] = { id = id, zb = z, x = math.floor(z:getX()), y = math.floor(z:getY()),
        z = math.floor(z:getZ()), at = getTimestampMs(), wait = Death.CHECK_DELAY_MS, phase = "wait", resends = 0,
        why = why }
    Death.stats.tracked = Death.stats.tracked + 1
    return true
end

-- Cadavre étiqueté du PNJ id sur la case (x, y, z) ou une voisine, ou nil.
function Death.findCorpse(id, x, y, z)
    local I = LivingKnox.Identity
    local cell = getCell()
    if cell == nil then return nil end
    for dy = -1, 1 do
        for dx = -1, 1 do
            local sq = cell:getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            for i = 0, (list and list:size() or 0) - 1 do
                local o = list:get(i)
                if instanceof(o, "IsoDeadBody") and o:hasModData() and I.readTag(o:getModData()) == id then
                    return o, sq
                end
            end
        end
    end
    return nil
end

-- Joueurs connectés à NEAR cases au plus de (x, y).
local function playersNear(x, y)
    local out = {}
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        if p ~= nil and math.abs(p:getX() - x) <= Death.NEAR and math.abs(p:getY() - y) <= Death.NEAR then
            out[#out + 1] = p
        end
    end
    return out
end

-- Vrai si le cadavre est encore sur sa case (ni traîné, ni retiré, ni brûlé).
local function onSquare(e)
    local sq = e.body and e.body:getSquare()
    local list = sq and sq:getStaticMovingObjects()
    return list ~= nil and list:contains(e.body)
end

local function drop(e, stat)
    Death.pending[e.id] = nil
    if stat ~= nil then Death.stats[stat] = Death.stats[stat] + 1 end
end

-- Demande aux joueurs proches s'ils ont le cadavre.
local function ask(e, t)
    if e.body == nil or not onSquare(e) then
        local body, sq = Death.findCorpse(e.id, e.x, e.y, e.z)
        if body == nil then return drop(e, "gone") end
        e.body, e.x, e.y, e.z = body, sq:getX(), sq:getY(), sq:getZ()
    end
    local players = playersNear(e.x, e.y)
    if #players == 0 then return drop(e, "nobody") end
    local sq = e.body:getSquare()
    local args = { id = e.id, o = Death.objectKey(e.body), n = sq:getStaticMovingObjects():size(), x = sq:getX(),
        y = sq:getY(), z = sq:getZ() }
    for _, p in ipairs(players) do sendServerCommand(p, Death.MODULE, Death.CMD_CHECK, args) end
    e.phase, e.at, e.reported = "asked", t, nil
    Death.stats.asked = Death.stats.asked + 1
end

-- Étape 4 : retrait du cadavre chez tous (ceux qui l'ont), avant sa remise.
local function removeNow(e, t)
    local body = e.body
    local sq = body:getSquare()
    local ok, err = pcall(function() sq:removeCorpse(body, false) end)
    if not ok then
        log().error("npc %s: corpse not removed for its resend: %s", e.id, tostring(err))
        -- Cadavre resté sur sa case : rien à remettre.
        if sq ~= nil and sq:getStaticMovingObjects():contains(body) then return drop(e, "failed") end
    end
    e.sq, e.phase, e.at = sq, "removed", t
end

-- Étape 4 (suite) : cadavre remis sur sa case et envoyé à toutes les connexions proches.
local function addBack(e, t)
    local body, sq = e.body, e.sq
    local ok, err = pcall(function()
        if body:getSquare() == nil then body:setSquare(sq) end
        sq:addCorpse(body, true)
        sendCorpse(body)
    end)
    if not ok then
        log().error("npc %s: corpse not resent: %s", e.id, tostring(err))
        return drop(e, "failed")
    end
    e.resends = e.resends + 1
    Death.stats.resent = Death.stats.resent + 1
    log().info("npc %s: corpse resent to the clients near %s,%s,%s (missing on %s, resend %d)", e.id,
        tostring(sq:getX()), tostring(sq:getY()), tostring(sq:getZ()), tostring(e.reported), e.resends)
    e.phase, e.at, e.wait, e.reported = "wait", t, Death.RECHECK_MS, nil
end

-- Passage : demandes dues, réponses closes, remises dues. Rend le nombre d'entrées en cours.
function Death.pass(t)
    if not Death.active() then return 0 end
    t = t or getTimestampMs()
    local list = {}
    for _, e in pairs(Death.pending) do list[#list + 1] = e end
    for _, e in ipairs(list) do
        if e.phase == "wait" and t - e.at >= e.wait then
            ask(e, t)
        elseif e.phase == "asked" and t - e.at >= Death.REPLY_MS then
            drop(e, "clean")
        elseif e.phase == "missing" then
            if e.body ~= nil and onSquare(e) then removeNow(e, t) else drop(e, "gone") end
        elseif e.phase == "removed" and t - e.at >= Death.RESEND_GAP_MS then
            addBack(e, t)
        end
    end
    local n = 0
    for _ in pairs(Death.pending) do n = n + 1 end
    return n
end

-- Réponse d'un client : il n'a pas le cadavre du PNJ args.id. Acceptée pendant REPLY_MS après la demande, d'un joueur
-- proche, une fois par demande ; au-delà de MAX_RESENDS, notée seulement.
function Death.onMissing(player, args)
    if not Death.active() or player == nil or type(args) ~= "table" or type(args.id) ~= "string" then return false end
    local e = Death.pending[args.id]
    local who = tostring(player:getUsername())
    if e == nil or e.phase ~= "asked" or e.body == nil or math.abs(player:getX() - e.x) > Death.NEAR
        or math.abs(player:getY() - e.y) > Death.NEAR then
        Death.stats.refused = Death.stats.refused + 1
        return false
    end
    Death.stats.missing = Death.stats.missing + 1
    if e.resends >= Death.MAX_RESENDS then
        log().warn("npc %s: corpse still missing on %s after %d resend(s)", e.id, who, e.resends)
        drop(e, "stillMissing")
        return false
    end
    e.reported, e.phase = who, "missing"
    return true
end

function Death.tick()
    if not Death.active() then return end
    local st = Death.state
    st.ticks = st.ticks + 1
    if st.ticks < Death.EVERY then return end
    st.ticks = 0
    Death.pass()
end

if Events ~= nil and Death.active() then
    local function onTick()
        LivingKnox.Death.tick()
    end
    local function onClientCommand(module, command, player, args)
        if module == Death.MODULE and command == Death.CMD_MISSING then LivingKnox.Death.onMissing(player, args) end
    end
    LivingKnox.subscribe("OnTick", "Death.tick", onTick)
    LivingKnox.subscribe("OnClientCommand", "Death.onClientCommand", onClientCommand)
end

return Death
