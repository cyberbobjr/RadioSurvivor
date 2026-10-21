-- Living Knox : avertissements et sommations à l'approche d'un foyer ou d'un groupe, côté autorité (LK11-T02).
-- Fiche : docs/annexes/conception/sommations.md. Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi
-- media/lua/server, il s'arrête ici. Aucune décision côté client : les clients ne reçoivent que les répliques
-- (LK_Speech), les consignes LK03 (regard, arrêt), les gestes (LK_Anim) et les effets d'un coup de semonce (LK_Combat),
-- tous décidés et diffusés par l'autorité : deux observateurs voient la même séquence.
--
-- 1. Qui est averti (Encounters.contextFor, appelé par LivingKnox.Decisions.context pour chaque membre COMBATTANT
--    évalué) : joueur VU par le membre (Hostility.candidatesOf), pour qui Hostility.chooseTarget rend l'action "warn"
--    (niveau méfiant, ou hostile pour un type qui ne tire pas le premier : cibles.md), et qui est DANS LA ZONE :
--    à HOME_ZONE cases (x et y) de la case du foyer, au plus un étage d'écart, ou à MEMBER_ZONE cases du membre
--    (groupe sans foyer, membre loin du foyer). Aucune interprétation du texte du joueur : seuls les faits (distance,
--    arme et actes enregistrés par LK_Hostility) comptent.
-- 2. Rencontre (une par groupe et par compte, mémoire seulement) menée par UN guetteur : le premier combattant évalué
--    qui voit le joueur ; remplacé par un autre si le guetteur n'est plus évalué depuis WARNER_MS (mort, retiré).
-- 3. Séquence graduée (Encounters.advance, pure, déterministe) :
--      étape 1 « warned »  : sommation (réplique IGUI_LK_Warn_1_*), arrêt, regard vers le joueur, arme en main
--                            (geste "guard") ;
--      étape 2 « aimed »   : dernière sommation (IGUI_LK_Warn_2_*), arme braquée (geste "aim") ;
--      étape 3 « final »   : type qui tire le premier (Hostility.firstStrike), arme à feu chargée, deux sommations
--                            ENTENDUES par le joueur : un coup de semonce (cartouche retirée, bruit et son vanilla de
--                            l'arme par Combat.shotEffects, aucun dégât), puis IGUI_LK_Warn_3_shot ; sinon arme
--                            toujours braquée et IGUI_LK_Warn_3_hold. Un groupe neutre ne tire jamais pendant la
--                            séquence.
--    Passage à l'étape suivante : réplique de l'étape courante entendue par le joueur (Speech.say : le joueur visé
--    parmi les auditeurs ; sinon redite après MIN_STEP_MS) ET délai de tolérance TOLERANCE_MS[niveau] écoulé, ou
--    distance de sécurité franchie (HOME_SAFE du foyer, MEMBER_SAFE du guetteur) après MIN_STEP_MS.
--    Engagement : seulement quand Hostility.targetRule rend "attack" pour ce joueur (provocation, incident) ; la
--    cascade prend alors le comportement « fight » (Combat.apply -> Combat.engage) avant la sommation, et la rencontre
--    est close (« escalated »).
--    Repli : joueur qui recule de BACKOFF cases depuis sa distance la plus courte de l'étape : une étape de moins
--    (arme abaissée) ; joueur sorti de la zone, perdu de vue depuis LOST_MS ou plus averti (attitude remontée) :
--    fin de la sommation (IGUI_LK_Warn_Back), le membre reprend la cascade. Retour dans la zone dans les RESUME_MS :
--    reprise à l'étape la plus haute atteinte (IGUI_LK_Warn_Again, puis la réplique de l'étape) ; au-delà, oubli.
--    Au plus un coup de semonce par rencontre.
-- 4. Exécution (Encounters.apply, appelée par Decisions.apply pour le comportement « warn ») : arrêt de la marche du
--    cadre, consigne "face" vers le joueur (renouvelée s'il tourne de FACE_DELTA degrés), puis geste (après "face",
--    qui remet le repos), puis réplique ou coup de semonce. Gestes par Decisions.setAlertGesture : retirés quand le
--    membre quitte « warn ».
-- Mémoire seulement : un redémarrage oublie les rencontres (la cascade les refait au premier passage).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Decisions"

local Encounters = LivingKnox.Encounters or {}
LivingKnox.Encounters = Encounters

Encounters.STAGES = { "warned", "aimed", "final" }
Encounters.KEY_PREFIX = "IGUI_LK_Warn_"
-- Répliques par étape (clés IGUI_LK_Warn_<suffixe>, Translate/EN|FR/IG_UI.json) ; choix déterministe par rencontre.
Encounters.LINES = { [1] = { "1_1", "1_2" }, [2] = { "2_1", "2_2" }, hold = { "3_hold" }, shot = { "3_shot" },
    back = { "Back" }, again = { "Again" } }
Encounters.GESTURES = { [1] = "guard", [2] = "aim", [3] = "aim" }

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche ; à recalibrer en jeu).
Encounters.CFG = Encounters.CFG or {
    HOME_ZONE = 14,          -- cases (x et y) autour de la case du foyer, un étage d'écart au plus : approche du foyer
    HOME_SAFE = 7,           -- cases : distance de sécurité du foyer ; la franchir presse l'escalade
    MEMBER_ZONE = 10,        -- cases du guetteur : approche du groupe (sans foyer, ou membre loin du foyer)
    MEMBER_SAFE = 5,         -- cases : distance de sécurité du guetteur
    TOLERANCE_MS = { hostile = 6000, wary = 10000 },   -- délai de tolérance entre deux étapes, selon l'attitude
    MIN_STEP_MS = 2500,      -- au moins ce délai entre deux répliques (le temps de lire la sommation)
    BACKOFF = 2,             -- cases de recul depuis la distance la plus courte de l'étape : une étape de moins
    LOST_MS = 4000,          -- joueur perdu de vue par le guetteur depuis ce délai : traité comme parti
    RESUME_MS = 120000,      -- après le départ du joueur, reprise à l'étape atteinte pendant ce délai ; puis oubli
    WARNER_MS = 10000,       -- guetteur non évalué depuis ce délai : un autre combattant le remplace
    SHOT_MS = 1000,          -- geste de tir du coup de semonce : une boucle du clip (Combat.CFG.SHOT_MS)
    RANGE = 25,              -- cases : portée des répliques (Speech.RANGE, lecture complète à 15 cases dehors)
    FACE_DELTA = 30,         -- degrés : nouvelle consigne « face » si le joueur a tourné d'au moins autant
    MAX = 64,                -- rencontres gardées au plus (la plus ancienne oubliée)
}

Encounters.state = Encounters.state or { list = {}, n = 0 }
Encounters.stats = Encounters.stats or { started = 0, resumed = 0, advanced = 0, eased = 0, stoodDown = 0,
    escalated = 0, forgotten = 0, said = 0, unheard = 0, shots = 0, noShot = 0 }

local function log() return LivingKnox.Log end
local function cfg() return Encounters.CFG end
local function now() return getTimestampMs() end

local function count(name)
    Encounters.stats[name] = (Encounters.stats[name] or 0) + 1
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function angleGap(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then d = 360 - d end
    return d
end

local function hashText(s)
    local h = 7
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 2147483647 end
    return h
end

-- ================================================================ pur

-- Nouvelle rencontre (pure) du groupe gid avec le compte u.
function Encounters.new(gid, u)
    return { gid = gid, u = u, stage = 0, peak = 0, since = nil, near = nil, out = nil, heard = nil, told = {},
        pending = nil, saidMs = nil, shot = false, n = 0 }
end

-- Pas de la séquence (pur). enc : rencontre ; obs = { t (ms), inZone, inSafe, d (distance au guetteur), level
-- ("hostile" | "wary") }. Rend l'événement ("start", "resume", "advance", "ease", "standdown", "forget") ou nil.
-- Pose enc.pending = "stage" | "again" quand une réplique est due (dite par Encounters.apply).
function Encounters.advance(enc, obs)
    local c = cfg()
    local t = obs.t
    if not obs.inZone then
        if enc.stage > 0 then
            if enc.stage > enc.peak then enc.peak = enc.stage end
            enc.stage, enc.out, enc.since, enc.pending, enc.heard = 0, t, t, nil, nil
            return "standdown"
        end
        if enc.out ~= nil and t - enc.out > c.RESUME_MS then return "forget" end
        return nil
    end
    if enc.stage == 0 then
        local resume = enc.peak > 0 and enc.out ~= nil and t - enc.out <= c.RESUME_MS
        enc.stage = resume and enc.peak or 1
        if not resume then enc.peak, enc.told, enc.shot = 0, {}, false end
        enc.since, enc.near, enc.out, enc.heard = t, obs.d, nil, nil
        enc.pending = resume and "again" or "stage"
        if enc.stage > enc.peak then enc.peak = enc.stage end
        return resume and "resume" or "start"
    end
    if obs.d < enc.near then enc.near = obs.d end
    if enc.stage > 1 and obs.d >= enc.near + c.BACKOFF then
        enc.stage = enc.stage - 1
        enc.since, enc.near = t, obs.d
        enc.heard = enc.stage   -- étape déjà dite et entendue : pas de redite en reculant
        enc.pending = nil
        return "ease"
    end
    if enc.stage >= #Encounters.STAGES or enc.heard ~= enc.stage then return nil end
    local wait = t - enc.since
    local tol = c.TOLERANCE_MS[obs.level] or c.TOLERANCE_MS.wary
    if wait >= tol or (obs.inSafe and wait >= c.MIN_STEP_MS) then
        enc.stage = enc.stage + 1
        enc.since, enc.near, enc.heard, enc.pending = t, obs.d, nil, "stage"
        if enc.stage > enc.peak then enc.peak = enc.stage end
        return "advance"
    end
    return nil
end

-- Coup de semonce permis (pur) : étape finale, type qui tire le premier, arme à feu chargée, les deux sommations
-- entendues par le joueur, aucun coup de semonce déjà tiré dans la rencontre.
function Encounters.mayShoot(enc, firstStrike, loaded)
    return enc.stage == #Encounters.STAGES and firstStrike == true and loaded == true and enc.told[1] == true
        and enc.told[2] == true and not enc.shot
end

-- Rayons des zones (LK05-T14) : foyer (option WarnHomeRadius) et guetteur (WarnGroupRadius) ; distance de sécurité =
-- la moitié (arrondie en dessous) quand l'option est lue. Repli : HOME_ZONE / HOME_SAFE, MEMBER_ZONE / MEMBER_SAFE.
-- Rend homeZone, homeSafe, memberZone, memberSafe.
function Encounters.radii()
    local c, C = cfg(), LivingKnox.Config
    local hz, mz = C.danger("WarnHomeRadius", nil), C.danger("WarnGroupRadius", nil)
    local hs, ms = c.HOME_SAFE, c.MEMBER_SAFE
    if hz ~= nil then hs = math.floor(hz / 2) else hz = c.HOME_ZONE end
    if mz ~= nil then ms = math.floor(mz / 2) else mz = c.MEMBER_ZONE end
    return hz, hs, mz, ms
end

-- Zones (pur) : joueur en (px, py, pz) à d cases du guetteur ; home = { x, y, z } ou nil. Rend inZone, inSafe.
function Encounters.zones(px, py, pz, d, home)
    local homeZone, homeSafe, memberZone, memberSafe = Encounters.radii()
    local inZone, inSafe = d <= memberZone, d <= memberSafe
    if home ~= nil and math.abs(math.floor(pz) - home.z) <= 1 then
        local hd = cheb(math.floor(px), math.floor(py), home.x, home.y)
        if hd <= homeZone then inZone = true end
        if hd <= homeSafe then inSafe = true end
    end
    return inZone, inSafe
end

-- Clé de réplique (pure, déterministe par rencontre) : kind = 1 | 2 | "hold" | "shot" | "back" | "again".
function Encounters.lineKey(gid, u, kind, n)
    local list = Encounters.LINES[kind]
    local i = 1 + hashText(tostring(gid) .. "|" .. tostring(u) .. "|" .. tostring(kind) .. "|" .. tostring(n or 0))
        % #list
    return Encounters.KEY_PREFIX .. list[i]
end

-- ================================================================ autorité

local function keyOf(gid, u) return tostring(gid) .. "|" .. tostring(u) end

local function remember(key, enc)
    local list = Encounters.state.list
    if list[key] == nil then
        local n, oldest, oldestKey = 0, nil, nil
        for k, e in pairs(list) do
            n = n + 1
            local seen = e.seenMs or 0
            if oldest == nil or seen < oldest or (seen == oldest and k < oldestKey) then oldest, oldestKey = seen, k end
        end
        if n >= cfg().MAX and oldestKey ~= nil then list[oldestKey] = nil end
        Encounters.state.n = Encounters.state.n + 1
        enc.n = Encounters.state.n
    end
    list[key] = enc
end

local function playerName(p)
    if p == nil or p.getUsername == nil then return nil end
    return tostring(p:getUsername())
end

-- Réplique kind du guetteur npc à destination du joueur de la rencontre. Rend vrai si ce joueur l'a entendue.
function Encounters.say(enc, npc, kind, band)
    local S = LivingKnox.Speech
    if S == nil or S.say == nil then return false end
    local key = Encounters.lineKey(enc.gid, enc.u, kind, enc.n)
    local out, why = S.say(npc, { key = key }, { range = cfg().RANGE, band = band or "hostile", chat = true })
    count("said")
    if out == nil then
        log().debug("npc %s: warning %s to %s not said: %s", npc, key, enc.u, tostring(why))
        return false
    end
    for _, p in ipairs(out.heard or {}) do
        if playerName(p) == enc.u then return true end
    end
    return false
end

local function bandOf(level)
    local S = LivingKnox.Speech
    if S ~= nil and S.bandOf ~= nil then return S.bandOf(level) end
    return "hostile"
end

-- Fin de la rencontre (attitude remontée, engagement) : rien n'est dit.
local function close(key, enc, why, stat)
    Encounters.state.list[key] = nil
    count(stat)
    log().info("group %s: warning of %s over at stage %d: %s", enc.gid, enc.u, enc.stage, why)
end

-- Rencontres d'un groupe gid fermées par un engagement : la cascade prend « fight » (targetRule rend "attack").
local function escalate(gid, u, reason)
    local key = keyOf(gid, u)
    local enc = Encounters.state.list[key]
    if enc ~= nil then close(key, enc, "escalated (" .. tostring(reason) .. ")", "escalated") end
end

-- Pas d'une rencontre menée par le guetteur npc. obs nil : joueur non vu cette fois.
local function stepEncounter(key, enc, npc, obs, t)
    if obs == nil then
        if enc.seenMs ~= nil and t - enc.seenMs <= cfg().LOST_MS then return nil end
        obs = { t = t, inZone = false, inSafe = false, d = 1e9, level = enc.level }
    else
        enc.seenMs = t
        enc.level = obs.level
    end
    local ev = Encounters.advance(enc, obs)
    if ev == nil then return nil end
    if ev == "forget" then
        Encounters.state.list[key] = nil
        count("forgotten")
        return ev
    end
    local stat = { start = "started", resume = "resumed", advance = "advanced", ease = "eased", standdown = "stoodDown" }
    count(stat[ev])
    log().info("npc %s: warning of %s (%s): %s, stage %d %s (%.1f squares%s)", npc, enc.u, tostring(enc.gid), ev,
        enc.stage, enc.stage > 0 and Encounters.STAGES[enc.stage] or "none", obs.d < 1e9 and obs.d or -1,
        obs.inSafe and ", inside the safety distance" or "")
    if ev == "standdown" then Encounters.say(enc, npc, "back", bandOf(enc.level)) end
    -- LK12-T02 : fait "encounterStarted" (nouvelle rencontre, pas une reprise) ; LK_API en tire l'événement public.
    if ev == "start" then
        LivingKnox.publish("encounterStarted", { group = enc.gid, npc = npc, player = enc.u, level = enc.level,
            n = enc.n })
    end
    return ev
end

-- Entrée de la cascade (LivingKnox.Decisions.context) : sommation que mène le membre m (combattant), ou nil. Rend
-- { u, stage, key = "p<compte>", why, x, y, z, d, level, ekey }.
function Encounters.contextFor(gid, g, mid, m, body, ctx, per, players, minute)
    if not ctx.combatant or m == nil or m.npc == nil then return nil end
    local Ho = LivingKnox.Hostility
    if Ho == nil or Ho.chooseTarget == nil or Ho.candidatesOf == nil then return nil end
    local npc = m.npc
    local t = now()
    local cands = Ho.candidatesOf(per, players)
    local res = #cands > 0 and Ho.chooseTarget(gid, npc, cands) or nil
    local spots = {}
    for _, e in ipairs(per and not per.stale and per.p or {}) do
        if e.s and spots[e.u] == nil then spots[e.u] = e end
    end
    local warned = {}
    for _, dcs in ipairs(res and res.list or {}) do
        if dcs.action == "attack" then
            escalate(gid, dcs.u, dcs.reason)
        elseif dcs.action == "warn" and spots[dcs.u] ~= nil and warned[dcs.u] == nil then
            local e = spots[dcs.u]
            local inZone, inSafe = Encounters.zones(e.x, e.y, e.z or 0, dcs.d, g.home)
            warned[dcs.u] = { t = t, inZone = inZone, inSafe = inSafe, d = dcs.d,
                level = dcs.level == "hostile" and "hostile" or "wary", x = e.x, y = e.y, z = e.z or 0 }
        end
    end
    -- Rencontres du groupe : celles de ce guetteur avancent ; un guetteur absent depuis WARNER_MS est remplacé.
    local list = Encounters.state.list
    local keys = {}
    for k, enc in pairs(list) do
        if enc.gid == gid then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local mine = {}
    for _, k in ipairs(keys) do
        local enc = list[k]
        local lead = cfg().WARNER_MS
        if enc.stage == 0 and warned[enc.u] == nil and enc.out ~= nil and t - enc.out > cfg().RESUME_MS then
            list[k] = nil   -- joueur parti depuis RESUME_MS : rencontre oubliée, quel que soit son guetteur
            count("forgotten")
        else
            if enc.npc ~= npc and warned[enc.u] ~= nil and (enc.npcMs == nil or t - enc.npcMs > lead) then
                log().info("npc %s takes over the warning of %s from npc %s", npc, enc.u, tostring(enc.npc))
                enc.npc = npc
            end
            if enc.npc == npc then
                enc.npcMs = t
                local ob = warned[enc.u]
                if ob == nil and enc.stage > 0 and spots[enc.u] ~= nil then
                    -- Vu mais plus averti (attitude remontée, trêve) : fin de la sommation sans réplique.
                    close(k, enc, "no longer warned", "stoodDown")
                else
                    stepEncounter(k, enc, npc, ob, t)
                    if list[k] ~= nil and enc.stage > 0 then mine[#mine + 1] = enc end
                end
            end
            warned[enc.u] = nil   -- menée par ce guetteur ou par un autre
        end
    end
    -- Joueur averti sans rencontre : ce membre la commence s'il est dans la zone.
    local fresh = {}
    for u in pairs(warned) do fresh[#fresh + 1] = u end
    table.sort(fresh)
    for _, u in ipairs(fresh) do
        local ob = warned[u]
        if ob.inZone then
            local enc = Encounters.new(gid, u)
            enc.npc, enc.npcMs = npc, t
            remember(keyOf(gid, u), enc)
            stepEncounter(keyOf(gid, u), enc, npc, ob, t)
            mine[#mine + 1] = enc
        end
    end
    if #mine == 0 then return nil end
    table.sort(mine, function(a, b)
        if a.stage ~= b.stage then return a.stage > b.stage end
        return a.u < b.u
    end)
    local enc = mine[1]
    local e = spots[enc.u]
    local x, y, z = e and e.x or enc.x, e and e.y or enc.y, e and e.z or enc.z
    enc.x, enc.y, enc.z = x, y, z
    local d = e and e.d or nil
    return { u = enc.u, stage = enc.stage, key = "p" .. enc.u, ekey = keyOf(gid, enc.u), level = enc.level, x = x,
        y = y, z = z, d = d, firstStrike = Ho.firstStrike ~= nil and Ho.firstStrike(g.type) or false,
        why = string.format("warning %s: stage %d %s (%s)", enc.u, enc.stage, Encounters.STAGES[enc.stage],
            tostring(enc.level)) }
end

-- ---------------------------------------------------------------- exécution

-- Arme à feu chargée du PNJ id (corps z) : { t, w } si une cartouche au moins est dans l'arme, sinon nil.
local function loadedGun(id, z)
    local C, Am = LivingKnox.Combat, LivingKnox.Ammo
    if C == nil or C.weaponOf == nil or Am == nil then return nil end
    local w = C.weaponOf(id)
    if w == nil or not w.ranged then return nil end
    local spec = Am.spec(w.t)
    if spec == nil or Am.loaded(z, w.t) < spec.per then return nil end
    return w
end

-- Coup de semonce : une cartouche retirée de l'arme avant tout effet, bruit et son vanilla (Combat.shotEffects),
-- aucun dégât. Rend vrai s'il est tiré.
local function warningShot(id, enc, z, gun, t)
    local Am, C = LivingKnox.Ammo, LivingKnox.Combat
    if not Am.consume(z, gun.t) then return false end
    enc.shot = true
    enc.shotUntil = t + cfg().SHOT_MS
    C.shotEffects(id, { t = gun.t }, z, gun.w)
    count("shots")
    log().info("npc %s fired a warning shot with %s at %s (%d round(s) left)", id, gun.t, enc.u, Am.loaded(z, gun.t))
    return true
end

local function issue(id, v)
    local De = LivingKnox.Decisions
    if v ~= nil and De.noteIssued ~= nil then return De.noteIssued(id, v) end
    return false
end

-- Comportement « warn » (appelé par Decisions.apply à chaque passage du guetteur).
function Encounters.apply(id, st, ctx, fresh)
    local w = ctx.warn
    if w == nil then return end
    local enc = Encounters.state.list[w.ekey]
    if enc == nil or enc.stage == 0 then return end
    local D = LivingKnox.Directives
    local De = LivingKnox.Decisions
    local B = LivingKnox.Bodies
    local z = B and B.find(id) or nil
    if z == nil then return end
    local t = now()
    local open = De.ownOpen ~= nil and De.ownOpen(id) or nil
    if open ~= nil and open.op == D.OP_MOVE then issue(id, D.stop(id)) end
    local a = De.angleTo(w.x + 0.5 - ctx.x, w.y + 0.5 - ctx.y)
    if a ~= nil and (fresh or enc.faced == nil or angleGap(a, enc.faced) >= cfg().FACE_DELTA) then
        if issue(id, D.face(id, a)) then enc.faced = a end
    end
    if enc.pending ~= nil and (enc.saidMs == nil or t - enc.saidMs >= cfg().MIN_STEP_MS) then
        local band = bandOf(enc.level)
        if enc.pending == "again" then
            Encounters.say(enc, id, "again", band)
            enc.pending = "stage"
            enc.saidMs = t
        else
            local kind = enc.stage
            if enc.stage == #Encounters.STAGES then
                local gun = w.firstStrike and loadedGun(id, z) or nil
                if Encounters.mayShoot(enc, w.firstStrike, gun ~= nil) and warningShot(id, enc, z, gun, t) then
                    kind = "shot"
                else
                    if w.firstStrike and not enc.shot then count("noShot") end
                    kind = "hold"
                end
            end
            local heard = Encounters.say(enc, id, kind, band)
            enc.saidMs = t
            if heard then
                enc.heard = enc.stage
                enc.told[enc.stage] = true
                enc.pending = nil
            else
                count("unheard")
                if enc.stage == #Encounters.STAGES then enc.pending = nil end   -- rien de plus à redire
            end
        end
    end
    local g = Encounters.GESTURES[enc.stage] or "guard"
    if enc.shotUntil ~= nil and t < enc.shotUntil then g = "shoot" end
    De.setAlertGesture(id, g)   -- après « face », qui remet le repos ; reposé à chaque passage
end

-- ---------------------------------------------------------------- lecture, mémoire

-- Rencontre du groupe gid avec le compte u (copie), ou nil : { stage, peak, npc, level, shot, told1, told2, out }.
function Encounters.get(gid, u)
    local enc = Encounters.state.list[keyOf(gid, u)]
    if enc == nil then return nil end
    return { stage = enc.stage, peak = enc.peak, npc = enc.npc, level = enc.level, shot = enc.shot,
        told1 = enc.told[1] == true, told2 = enc.told[2] == true, out = enc.out, heard = enc.heard }
end

-- PNJ oublié : ses rencontres attendent un autre guetteur (WARNER_MS).
function Encounters.forget(id)
    for _, enc in pairs(Encounters.state.list) do
        if enc.npc == id then enc.npcMs = nil end
    end
end

function Encounters.forgetGroup(gid)
    local gone = {}
    for k, enc in pairs(Encounters.state.list) do
        if enc.gid == gid then gone[#gone + 1] = k end
    end
    for _, k in ipairs(gone) do Encounters.state.list[k] = nil end
end

function Encounters.reset()
    Encounters.state = { list = {}, n = 0 }
end

return Encounters
