-- Living Knox : moteur des tâches d'entretien du foyer par ses membres (LK05-T10, refondu en LK15-T01).
-- Fiche : docs/annexes/conception/entretien.md ; décisions : docs/architecture/decisions/adr-registre-routines.md (D01, D03).
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Ce fichier ne nomme AUCUNE tâche. Chaque tâche s'inscrit par LivingKnox.Upkeep.registerJob(spec) depuis son fichier
-- media/lua/server/LivingKnox/Jobs/LK_Job_<Nom>.lua (chargé par le jeu, sous-dossiers compris). spec :
--   kind     : nom unique de la tâche (clé « <kind> x,y,z »)
--   order    : priorité, plus petit d'abord ; à égalité, par kind (ordre stable, sans next : Kahlua)
--   prefer   : facultatif, comportement de rôle qui la prend avant les autres (« garden » : le jardinier)
--   gesture  : geste pendant le travail (LivingKnox.Anim)
--   minutes  : minutes de jeu de travail avant l'effet
--   survey(gid, g, area) : cases ouvertes { x, y, bid } ou nil ; area = zone du foyer (Upkeep.area)
--   place(job)   : facultatif, case où se tenir ; par défaut une case libre voisine de l'objet
--   standOnSelf  : facultatif, si pas de case voisine, la case de l'objet elle-même quand elle est praticable
--   apply(job, gid, who, sq) : effet, une seule fois, état et matériaux relus au moment de l'effet ; rend un texte
--                  (fait) ou nil et une raison (rien fait)
--   groupLog : facultatif, le texte de l'effet va au journal du groupe (kind « upkeep »)
-- Relevé : au plus une fois toutes les SCAN_MINUTES minutes de jeu par groupe, zone du foyer entièrement chargée
-- (LK_Homes : Homes.ready). Réservation : un membre prend la première tâche ouverte qu'aucun autre ne tient (le
-- comportement « garden » d'abord pour une tâche préférée). Exécution : aller à la case, regarder, geste, durée, effet
-- une fois ; tâche faite ou abandonnée : plus proposée pendant DONE_MINUTES ; interrompue avant l'effet : libérée.
-- Lumières : à chaque minute de jeu, de LIGHT_FROM à LIGHT_TO, un membre qui entre dans une pièce du bâtiment de son
-- foyer allume les interrupteurs éteints que le courant permet d'allumer (IsoLightSwitch.canSwitchLight ;
-- J/iso/objects/IsoLightSwitch.java:392-447 ; setActive(true) : J/iso/objects/IsoLightSwitch.java:449-476). Aucune
-- extinction. Mémoire (tâches relevées, prises, faites, pièces vues) : non sauvegardée, recalculée.
-- Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"
require "LivingKnox/LK_Stock"
require "LivingKnox/LK_Routines"

local Upkeep = LivingKnox.Upkeep or {}
LivingKnox.Upkeep = Upkeep

-- Registre (LK15-T01) : tâches inscrites, par kind ; liste triée par order puis kind ; vues GESTURE et JOBS (kinds).
Upkeep.registry = Upkeep.registry or {}
Upkeep.specs = Upkeep.specs or {}
Upkeep.GESTURE = Upkeep.GESTURE or {}
Upkeep.JOBS = Upkeep.JOBS or {}

-- Réglages du moteur (les réglages propres à une tâche sont dans son fichier).
Upkeep.CFG = Upkeep.CFG or {
    SCAN_MINUTES = 10,         -- relevé des tâches d'un groupe au plus toutes les 10 minutes de jeu
    DONE_MINUTES = 10,         -- tâche faite ou abandonnée : plus proposée pendant 10 minutes de jeu
    MAX_JOBS = 8,              -- tâches retenues par relevé
    LIGHT_FROM = 19,           -- heure du jour à partir de laquelle une pièce est éclairée en y entrant
    LIGHT_TO = 7,              -- heure du jour à laquelle cela cesse
}

Upkeep.state = Upkeep.state or { scans = {}, claims = {}, done = {}, rooms = {} }
Upkeep.stats = Upkeep.stats or { scans = 0, started = 0, applied = 0, skipped = 0, lights = 0 }

local function log() return LivingKnox.Log end
local function cfg() return Upkeep.CFG end
local function Groups() return LivingKnox.Groups end
local function Homes() return LivingKnox.Homes end
local function R() return LivingKnox.Routines end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

-- ================================================================ registre

local function validSpec(spec)
    return type(spec) == "table" and type(spec.kind) == "string" and type(spec.order) == "number"
        and type(spec.gesture) == "string" and type(spec.minutes) == "number" and type(spec.survey) == "function"
        and type(spec.apply) == "function"
end

-- Inscrit une tâche (spec, voir l'en-tête). Une tâche déjà inscrite sous le même kind est remplacée (rechargement).
function Upkeep.registerJob(spec)
    if not validSpec(spec) then
        error("LivingKnox.Upkeep.registerJob: spec needs kind, order, gesture, minutes, survey and apply", 2)
    end
    local reg = Upkeep.registry
    local old = Upkeep.specs[spec.kind]
    if old ~= nil then
        for i, s in ipairs(reg) do
            if s == old then
                table.remove(reg, i)
                break
            end
        end
    end
    Upkeep.specs[spec.kind] = spec
    reg[#reg + 1] = spec
    table.sort(reg, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.kind < b.kind
    end)
    local kinds = {}
    for i, s in ipairs(reg) do kinds[i] = s.kind end
    Upkeep.JOBS = kinds
    Upkeep.GESTURE[spec.kind] = spec.gesture
    return spec
end

-- ================================================================ zone et relevé

-- Zone du foyer du groupe g : { home, z, style, bid, rd, squares = { { x, y, dx, dy, sq, inside } ... } }, dans l'ordre
-- (dy, dx) ; inside = case du bâtiment du foyer. Rend la zone, ou nil et une raison (pas de foyer, zone non chargée).
function Upkeep.area(gid, g)
    if type(g) ~= "table" or type(g.home) ~= "table" then return nil, "no home" end
    local home = g.home
    local style, def = Homes().ready(home)
    if style == nil then return nil, def end
    local bid = def ~= nil and def:getIDString() or nil
    local cell = getCell()
    local rd = Homes().CFG.RADIUS
    local squares = {}
    for dy = -rd, rd do
        for dx = -rd, rd do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, home.z)
            if sq ~= nil then
                squares[#squares + 1] = { x = x, y = y, dx = dx, dy = dy, sq = sq,
                    inside = style == "building" and Homes().buildingId(sq) == bid }
            end
        end
    end
    return { gid = gid, home = home, z = home.z, style = style, bid = bid, rd = rd, squares = squares }, nil
end

-- Générateur du groupe gid sur la case sq (LK05-T19 : marque LK_Homes.GEN_TAG), ou nil.
function Upkeep.groupGeneratorOn(sq, gid)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if Homes().groupGenerator(o, gid) then return o end
    end
    return nil
end

-- Générateurs du groupe dans la zone, une case de marge pour que la place à côté reste dans la zone : { x, y, gen }.
function Upkeep.groupGenerators(area, gid)
    local out = {}
    for _, e in ipairs(area.squares) do
        if math.max(math.abs(e.dx), math.abs(e.dy)) < area.rd then
            local gen = Upkeep.groupGeneratorOn(e.sq, gid)
            if gen ~= nil then out[#out + 1] = { x = e.x, y = e.y, gen = gen } end
        end
    end
    return out
end

-- Au plus max tâches, dans l'ordre donné, la première de chaque sorte toujours gardée : une maison tachée de sang
-- partout (combats précédents) remplissait les MAX_JOBS places de « clean » et le verre n'était jamais proposé
-- (campagne MP du 2026-10-14, lk.upkeep : trois taches lavées en 5 min, verre jamais ramassé).
function Upkeep.capJobs(list, max)
    if #list <= max then return list end
    local keep, kinds, n = {}, {}, 0
    for i, j in ipairs(list) do
        if not kinds[j.kind] then
            kinds[j.kind] = true
            keep[i] = true
            n = n + 1
        end
    end
    for i = 1, #list do
        if n >= max then break end
        if not keep[i] then
            keep[i] = true
            n = n + 1
        end
    end
    local out = {}
    for i, j in ipairs(list) do
        if keep[i] then out[#out + 1] = j end
    end
    return out
end

-- Tâches ouvertes du foyer du groupe g : liste { kind, key, x, y, z, bid } dans l'ordre du registre puis des relevés,
-- MAX_JOBS au plus (Upkeep.capJobs) ; ou nil et une raison (zone non chargée, pas de foyer).
function Upkeep.jobs(gid, g)
    local area, why = Upkeep.area(gid, g)
    if area == nil then return nil, why end
    local out = {}
    for _, spec in ipairs(Upkeep.registry) do
        for _, e in ipairs(spec.survey(gid, g, area) or {}) do
            out[#out + 1] = { kind = spec.kind, key = string.format("%s %d,%d,%d", spec.kind, e.x, e.y, area.z),
                x = e.x, y = e.y, z = area.z, bid = e.bid }
        end
    end
    return Upkeep.capJobs(out, cfg().MAX_JOBS)
end

local function claimKey(gid, key) return tostring(gid) .. "|" .. key end

-- Tâches du groupe (relevé gardé SCAN_MINUTES minutes de jeu), ou liste vide.
local function cached(gid, g, minute)
    local st = Upkeep.state
    local s = st.scans[gid]
    if s ~= nil and minute >= s.minute and minute - s.minute < cfg().SCAN_MINUTES then return s.jobs end
    local jobs, why = Upkeep.jobs(gid, g)
    st.scans[gid] = { minute = minute, jobs = jobs or {} }
    Upkeep.stats.scans = Upkeep.stats.scans + 1
    if jobs == nil then
        log().debug("group %s: upkeep survey postponed: %s", tostring(gid), tostring(why))
    elseif #jobs > 0 then
        log().debug("group %s: %d upkeep job(s) open", tostring(gid), #jobs)
    end
    return jobs or {}
end

-- Première tâche ouverte du groupe que personne d'autre ne tient (et pas faite récemment), prise par id. allowed :
-- comportements du rôle du membre (ctx.allowed) ; une tâche dont prefer figure dans allowed passe avant les autres
-- (ordre gardé dans chaque groupe). Rend la tâche (copie), ou nil.
function Upkeep.claim(gid, g, id, minute, allowed)
    local st = Upkeep.state
    local jobs = cached(gid, g, minute)
    local function take(job)
        local k = claimKey(gid, job.key)
        local holder = st.claims[k]
        local doneUntil = st.done[k]
        if (holder == nil or holder == id) and (doneUntil == nil or minute >= doneUntil) then
            st.claims[k] = id
            return { kind = job.kind, key = job.key, x = job.x, y = job.y, z = job.z, bid = job.bid }
        end
        return nil
    end
    if type(allowed) == "table" then
        for _, job in ipairs(jobs) do
            local spec = Upkeep.specs[job.kind]
            if spec ~= nil and spec.prefer ~= nil and allowed[spec.prefer] then
                local got = take(job)
                if got ~= nil then return got end
            end
        end
    end
    for _, job in ipairs(jobs) do
        local got = take(job)
        if got ~= nil then return got end
    end
    return nil
end

-- Tâche du membre libérée (fin, abandon, interruption).
function Upkeep.release(id, m)
    if type(m) ~= "table" or type(m.job) ~= "table" then return end
    local k = claimKey(m.gid, m.job.key)
    if Upkeep.state.claims[k] == id then Upkeep.state.claims[k] = nil end
end

-- ================================================================ effet (autorité, une fois)

-- Applique la tâche job pour le groupe gid (who : texte du journal) par le spec de son kind. Rend un texte (fait), ou
-- nil et une raison (rien fait).
function Upkeep.apply(job, gid, who)
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(job.x, job.y, job.z) or nil
    if sq == nil then return nil, "square not loaded" end
    local spec = Upkeep.specs[job.kind]
    if spec == nil then return nil, "unknown job " .. tostring(job.kind) end
    return spec.apply(job, gid, who, sq)
end

-- ================================================================ exécution (membre en corvée)

local function specOf(job) return Upkeep.specs[job.kind] end

local function finish(id, m, minute, text, why)
    m.phase = "done"
    local st = Upkeep.state
    st.done[claimKey(m.gid, m.job.key)] = minute + cfg().DONE_MINUTES
    Upkeep.release(id, m)
    if text ~= nil then
        Upkeep.stats.applied = Upkeep.stats.applied + 1
        log().info("npc %s (%s %s): upkeep %s", tostring(id), tostring(m.gid), tostring(m.mid), text)
        local spec = specOf(m.job)
        if spec ~= nil and spec.groupLog then
            local G = Groups()
            G.update(function(data)
                local g = data.groups[m.gid]
                if g == nil then return false, false end
                G.appendLog(g, "upkeep", string.sub(text, 1, G.TEXT_MAX), G.today())
                return true, true
            end)
        end
    else
        Upkeep.stats.skipped = Upkeep.stats.skipped + 1
        log().debug("npc %s: upkeep %s not done: %s", tostring(id), m.job.key, tostring(why))
    end
end

-- Place du membre pour la tâche : place de la tâche (spec.place), sinon case libre voisine de l'objet (règle des
-- corvées), sinon la case de l'objet si spec.standOnSelf et praticable (tache de sang, verre), sans regard.
local function placeFor(job, spec)
    local cell = getCell()
    if cell == nil then return nil end
    if spec.place ~= nil then return spec.place(job) end
    local X = R().exec
    local p = X.placeBeside(cell, job.x, job.y, job.z, job.bid, {})
    if p ~= nil then return p end
    if spec.standOnSelf then
        local sq = cell:getGridSquare(job.x, job.y, job.z)
        if X.standable(sq) then return { x = job.x, y = job.y, z = job.z } end
    end
    return nil
end

local function step(id, ctx, m)
    local X = R().exec
    local spec = specOf(m.job)
    if spec == nil then return finish(id, m, ctx.minute, nil, "unknown job " .. tostring(m.job.kind)) end
    local e = X.entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) and (m.phase == "go" or m.phase == "face") then
        -- Une autre consigne est passée (suite de test, autre module) : retour à la place.
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
        m.phase = "go"
    end
    if m.phase == "place" then
        local p = placeFor(m.job, spec)
        if p == nil then return finish(id, m, ctx.minute, nil, "no free square beside " .. m.job.key) end
        m.place, m.phase = p, "go"
    end
    if m.phase == "go" then
        local res = X.goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
        if res == "moving" then return end
        if res == "failed" then return finish(id, m, ctx.minute, nil, "cannot reach " .. m.job.key) end
        m.phase = "face"
    end
    if m.phase == "face" then
        if m.place.a ~= nil then
            if m.faceV == nil then
                X.faceTo(id, m, m.place.a)
                return
            end
            e = X.entryOf(id)
            if e == nil or e.v ~= m.faceV or not e.done then return end
        end
        X.sitDown(id, m, spec.gesture)
        m.since, m.phase = ctx.minute, "work"
        return
    end
    if m.phase == "work" then
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) ~= spec.gesture then X.sitDown(id, m, spec.gesture) end
        if ctx.minute - m.since < spec.minutes then return end
        m.phase = "done"   -- avant l'effet : jamais deux fois, même si le Java lève une erreur
        local ok, text, why = pcall(Upkeep.apply, m.job, m.gid, m.mid)
        if not ok then
            log().error("npc %s: upkeep %s failed: %s", tostring(id), m.job.key, tostring(text))
            text, why = nil, "error"
        end
        finish(id, m, ctx.minute, text, why)
    end
end

-- Membre en corvée (comportement « chore ») : poursuit sa tâche d'entretien ou en prend une. Rend vrai si le membre
-- est occupé par l'entretien (la corvée visible attend), faux sinon.
function Upkeep.run(id, st, ctx, g)
    if ctx.gid == nil or type(g) ~= "table" or type(g.home) ~= "table" then return false end
    local mem = R().state.npcs
    local m = mem[id]
    if m ~= nil and m.kind == "upkeep" then
        if m.phase == "done" then return false end
        step(id, ctx, m)
        return true
    end
    local job = Upkeep.claim(ctx.gid, g, id, ctx.minute, ctx.allowed)
    if job == nil then return false end
    if m ~= nil then R().leave(id) end   -- corvée visible en cours : debout d'abord
    m = { key = "upkeep " .. job.key, kind = "upkeep", job = job, gid = ctx.gid, mid = ctx.mid, phase = "place",
        fails = 0 }
    mem[id] = m
    Upkeep.stats.started = Upkeep.stats.started + 1
    log().debug("npc %s: upkeep %s (%s)", tostring(id), job.key, tostring(st.why or st.b))
    step(id, ctx, m)
    return true
end

-- ================================================================ lumières

local function hourOfDay()
    local gt = getGameTime()
    local h = gt ~= nil and gt:getWorldAgeHours() or 0
    return (math.floor(h) + 7) % 24
end

-- Vrai si l'heure du jour hod est dans la plage éclairée (LIGHT_FROM .. LIGHT_TO, à cheval sur minuit).
function Upkeep.dark(hod)
    local from, to = cfg().LIGHT_FROM, cfg().LIGHT_TO
    if from > to then return hod >= from or hod < to end
    return hod >= from and hod < to
end

-- Allume les interrupteurs éteints de la pièce room que le courant permet d'allumer (lampes sur pile écartées). Rend
-- le nombre d'interrupteurs allumés.
function Upkeep.lightRoom(room)
    local list = room ~= nil and room:getLightSwitches() or nil
    if list == nil then return 0 end
    local n = 0
    for i = 0, list:size() - 1 do
        local ls = list:get(i)
        if ls ~= nil and not ls:isActivated() and not (ls:getCanBeModified() and ls:getUseBattery())
            and ls:canSwitchLight() then
            if ls:setActive(true) then n = n + 1 end
        end
    end
    return n
end

local function lightGroup(gid, g, cell)
    local home = g.home
    local style, def = Homes().ready(home)
    if style ~= "building" or def == nil then return 0 end
    local bid = def:getIDString()
    local rooms = Upkeep.state.rooms
    local B = LivingKnox.Bodies
    local n = 0
    local mids = {}
    for mid in pairs(g.members) do mids[#mids + 1] = mid end
    table.sort(mids)
    for _, mid in ipairs(mids) do
        local m = g.members[mid]
        local z = m.alive and m.npc ~= nil and B ~= nil and B.find(m.npc) or nil
        local room
        if z ~= nil and math.floor(z:getZ()) == home.z
            and cheb(z:getX(), z:getY(), home.x + 0.5, home.y + 0.5) <= Homes().CFG.RADIUS then
            local sq = cell:getGridSquare(math.floor(z:getX()), math.floor(z:getY()), home.z)
            if sq ~= nil and Homes().buildingId(sq) == bid then room = sq:getRoom() end
        end
        if m.npc ~= nil then
            if room ~= nil and rooms[m.npc] ~= room then
                local lit = Upkeep.lightRoom(room)
                if lit > 0 then
                    n = n + lit
                    log().info("npc %s (%s %s): %d light switch(es) turned on entering a room of the home", m.npc,
                        tostring(gid), mid, lit)
                end
            end
            rooms[m.npc] = room
        end
    end
    return n
end

-- Passage des lumières (chaque minute de jeu). Rend le nombre d'interrupteurs allumés.
function Upkeep.lights()
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    if not Upkeep.dark(hourOfDay()) then
        Upkeep.state.rooms = {}   -- au jour : la prochaine soirée compte comme une entrée
        return 0
    end
    local cell = getCell()
    if cell == nil then return 0 end
    local G = Groups()
    local n = 0
    for _, gid in ipairs(G.list()) do
        local g = G.get(gid)
        if g ~= nil and type(g.home) == "table" and cell:getGridSquare(g.home.x, g.home.y, g.home.z) ~= nil then
            local ok, lit = pcall(lightGroup, gid, g, cell)
            if not ok then
                log().error("group %s: lights failed: %s", tostring(gid), tostring(lit))
            else
                n = n + lit
            end
        end
    end
    Upkeep.stats.lights = Upkeep.stats.lights + n
    return n
end

function Upkeep.reset()
    Upkeep.state = { scans = {}, claims = {}, done = {}, rooms = {} }
end

LivingKnox.subscribe("EveryOneMinute", "Upkeep.onEveryOneMinute", function() Upkeep.lights() end)

-- Activité « chore » (ADR D04, ordre 20) : entretien du foyer avant les corvées visibles (LK05-T10 ; inscrite en LK15-T02).
LivingKnox.Routines.registerActivity({ id = "chore.upkeep", behaviour = "chore", order = 20,
    run = function(id, st, ctx, g) return Upkeep.run(id, st, ctx, g) end })

return Upkeep
