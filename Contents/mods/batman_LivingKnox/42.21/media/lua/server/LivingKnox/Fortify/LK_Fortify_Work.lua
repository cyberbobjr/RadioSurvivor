-- Living Knox : fortification du foyer, réparations (LK14-T06 : Fortify.repair) et travail de l'ouvrier
-- (réservation des chantiers, étapes, Fortify.run appelé par l'activité « chore » de la façade)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

-- ================================================================ réparations (LK14-T06)
-- Fiche docs/annexes/conception/fortification.md §9. Autorité seulement ; une réparation par appel ; tout est relu AVANT toute
-- prise ; matériaux retirés une seule fois par Stock.takeItem (remis si une prise échoue).

-- Planche saine : état relatif au moins REPAIR_BELOW (une planche plus abîmée serait aussitôt à réparer).
local function soundPlank(it)
    if it:getFullType() ~= Fortify.PLANK then return false end
    local mx = it:getConditionMax()
    return mx ~= nil and mx > 0 and it:getCondition() / mx >= P.cfg().REPAIR_BELOW
end

-- Barricade de bois la plus garnie de l'ouverture o (celle dont la planche extérieure reçoit les coups) : barricade,
-- addOpposite ; ou nil et une raison.
local function plankedSide(o)
    local same, opp = o:getBarricadeOnSameSquare(), o:getBarricadeOnOppositeSquare()
    local ps, ms = P.planksOf(same)
    local po, mo = P.planksOf(opp)
    if ms or mo then return nil, "metal barricade" end
    if ps > 0 and ps >= po then return same, false end
    if po > 0 then return opp, true end
    return nil, "no barricade"
end

-- Répare la barricade du chantier site (target "barricade") : planche extérieure abîmée retirée (removePlank,
-- IsoBarricade.java:110-136 : planche d'état proportionnel rendue au conteneur de la planche neuve, comme
-- ISUnbarricadeAction:complete la rend au joueur, M/lua/shared/TimedActions/ISUnbarricadeAction.lua:97-152), planche
-- saine clouée à sa place (addPlank, :90-108), transmission : état de la barricade (sendObjectChange(STATE)) ; si la
-- planche retirée était la dernière, barricade effacée par le Java (transmitRemoveItemFromSquare sur un serveur) puis
-- recréée et envoyée complète. Rend un texte et 1, ou nil et une raison.
local function repairPlank(site, gid, who)
    local St = P.Stock()
    local o, sq = Fortify.openingOf(site)
    if o == nil then return nil, sq == nil and "square not loaded" or "opening gone" end
    local b, addOpp = plankedSide(o)
    if b == nil then return nil, addOpp end
    local cond = b:getThumpCondition()
    if not P.needsRepair(cond) then return nil, "already repaired" end
    if not Fortify.hasTool(gid, "HAMMER") then return nil, "no hammer" end
    local pf, plank, pctr = St.findItem(gid, soundPlank)
    if pf == nil then return nil, "no sound plank" end
    local use = "repair " .. site.id
    local items = { { it = plank, ctr = pctr } }
    local nails, why = P.nailsFor(gid, 1, { [plank:getID()] = true }, who, use)
    if nails == nil then return nil, why end
    items[#items + 1] = nails[1]
    local ok, w = P.takeAll(gid, items, who, use)
    if not ok then return nil, w end
    local before = b:getNumPlanks()
    local old = b:removePlank(nil)
    local isNew = false
    if before <= 1 then   -- dernière planche : la barricade a été retirée de sa case
        b = IsoBarricade.AddBarricadeToObject(o, addOpp)
        if b == nil then return nil, "barricade not re-added" end
        isNew = true
    end
    b:addPlank(nil, plank)
    if isServer() then
        if isNew then b:transmitCompleteItemToClients() else b:sendObjectChange(IsoObjectChange.STATE) end
    end
    if old ~= nil then   -- planche abîmée rendue (vanilla : à l'inventaire de celui qui la retire)
        pctr:AddItem(old)
        if isServer() then sendAddItemToContainer(pctr, old) end
    end
    if type(buildUtil) == "table" and buildUtil.setHaveConstruction ~= nil then
        buildUtil.setHaveConstruction(b:getSquare(), true)
    end
    Fortify.invalidate(gid)
    Fortify.stats.repairs = Fortify.stats.repairs + 1
    return string.format("outer plank of %s %s replaced (%d%% -> %d%%, %d plank(s))", tostring(site.opening), site.id,
        math.floor(cond * 100 + 0.5), math.floor(b:getThumpCondition() * 100 + 0.5), b:getNumPlanks()), 1
end

-- Ouvrage achevé du pourtour (mur sur son cadre, palissade) sur le bord (sq, north), ou nil.
local function finishedStructure(sq, north, target)
    local kind, steps, o = P.builtOn(sq, north)
    if kind ~= target then return nil end
    if steps < #(Fortify.STAGES[kind] or {}) then return nil end   -- cadre seul : pas encore un mur
    return o
end

-- Répare un mur ou une palissade du chantier site (target "wall" ou "palisade") comme la réparation vanilla
-- (ISMoveableSpriteProps:repairObject, M/lua/shared/Moveables/ISMoveableSpriteProps.lua:3538-3599) sans hasard ni
-- compétence : marteau et scie, pièce requise et une pièce facultative selon les dégâts (Fortify.repairParts),
-- matériaux retirés, santé remise au maximum (IsoThumpable.setHealth envoie sync() sur un serveur,
-- J/iso/objects/IsoThumpable.java:288-297). Rend un texte et 1, ou nil et une raison.
local function repairStructure(site, gid, who)
    local plan = Fortify.plan(gid)
    local bd = plan ~= nil and plan.bounds or nil
    if bd == nil or site.x < bd.x1 or site.x > bd.x2 or site.y < bd.y1 or site.y > bd.y2 then
        return nil, "outside the home"
    end
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(site.x, site.y, site.z) or nil
    if sq == nil then return nil, "square not loaded" end
    local o = finishedStructure(sq, site.north == true, site.target)
    if o == nil then return nil, "no " .. tostring(site.target) end
    local health = Fortify.healthRatio(o)
    if not P.needsRepair(health) then return nil, "already repaired" end
    local r = Fortify.REPAIRS[site.target]
    for _, name in ipairs(r.tools) do
        if not Fortify.hasTool(gid, name) then return nil, "no " .. string.lower(name) end
    end
    local required, options = Fortify.repairParts(site.target, health)
    local picked = {}
    local items, miss = P.gather(gid, required, picked)
    if items == nil then return nil, "no " .. tostring(miss) end
    local use = "repair " .. site.id
    local extra
    for _, opt in ipairs(options) do   -- première pièce facultative présente en quantité
        if extra == nil then
            local trial = {}
            for k, v in pairs(picked) do trial[k] = v end
            extra = P.gather(gid, { opt }, trial)
            if extra ~= nil then picked = trial end
        end
    end
    if extra == nil and options[1] ~= nil and options[1].types[1] == Fortify.NAILS then   -- clous en boîte
        local w
        extra, w = P.nailsFor(gid, options[1].n, picked, who, use)
        if extra == nil then return nil, w end
    end
    if extra == nil then return nil, "no " .. tostring(options[1] and options[1].types[1]) end
    for _, e in ipairs(extra) do items[#items + 1] = e end
    local ok, w = P.takeAll(gid, items, who, use)
    if not ok then return nil, w end
    local h0 = o:getHealth()
    o:setHealth(o:getMaxHealth())
    Fortify.invalidate(gid)
    Fortify.stats.repairs = Fortify.stats.repairs + 1
    return string.format("%s %s repaired (%d -> %d / %d, %d item(s) used)", tostring(o:getName()), site.id, h0,
        o:getHealth(), o:getMaxHealth(), #items), 1
end

Fortify.repairPlank = repairPlank           -- LK16-T02 : réparation de la sorte barricade (spec.repair.run)
Fortify.repairStructure = repairStructure   -- LK16-T02 : réparation des sortes du pourtour (spec.repair.run)

-- Répare l'ouvrage du chantier site (kind "repair") du groupe gid par la réparation de la sorte site.target.
function Fortify.repair(site, gid, who)
    local St = P.Stock()
    if St == nil or St.findItem == nil or St.takeItem == nil then return nil, "no stock module" end
    local spec = Fortify.kinds.byId[site.target]
    if spec == nil or spec.repair == nil then return nil, "unknown repair target " .. tostring(site.target) end
    return spec.repair.run(site, gid, who)
end

local function claimKey(gid, sid) return tostring(gid) .. "|" .. sid end

-- Chantier du membre libéré (fin, abandon, interruption : Routines.leave et forget).
function Fortify.release(id, m)
    if type(m) ~= "table" or type(m.site) ~= "table" then return end
    local k = claimKey(m.gid, m.site.id)
    if Fortify.state.claims[k] == id then Fortify.state.claims[k] = nil end
end

-- Libération portée par la mémoire de routine (LK16-T04 : Routines.leave et forget l'appellent sans nommer ce module).
local function releaseMemory(id, m) Fortify.release(id, m) end

local function finishSite(id, m, minute, why)
    m.phase = "done"
    Fortify.release(id, m)
    Fortify.state.rest[id] = minute + P.cfg().REST_MINUTES
    local spec = Fortify.kinds.byId[m.site.kind]
    local unit = spec ~= nil and spec.unit or "stage(s)"
    if why == nil then
        Fortify.stats.finished = Fortify.stats.finished + 1
        LivingKnox.Log.info("npc %s (%s %s): %s %s done, %d %s", tostring(id), tostring(m.gid), tostring(m.mid), m.site.kind,
            m.site.id, m.placed, unit)
    else
        Fortify.stats.skipped = Fortify.stats.skipped + 1
        LivingKnox.Log.info("npc %s (%s %s): %s %s stopped after %d %s: %s", tostring(id), tostring(m.gid), tostring(m.mid),
            m.site.kind, m.site.id, m.placed, unit, tostring(why))
    end
end

-- Geste, minutes de travail avant chaque pose et effet (une planche, une étape) : travail de la sorte inscrite.
local function workOf(site)
    return Fortify.kinds.byId[site.kind].work(site, P.cfg())
end

-- LK16-T02 : travail d'une sorte du pourtour (spec.work des fichiers de sorte à étapes) : geste de la sorte
-- (CFG.RING_GESTURES), STAGE_MINUTES minutes avant chaque étape posée par Fortify.buildStep.
function Fortify.stageWork(site, c)
    return c.RING_GESTURES[site.kind] or c.GESTURE, c.STAGE_MINUTES, Fortify.buildStep
end

-- Place de travail : la case intérieure de l'ouverture, tournée vers l'extérieur ; sinon une case libre voisine du
-- même bâtiment (règle des corvées, Routines.exec.placeBeside).
local function placeFor(site)
    local cell = getCell()
    if cell == nil then return nil end
    local X = LivingKnox.Routines.exec
    local sq = cell:getGridSquare(site.inside.x, site.inside.y, site.z)
    if X.standable(sq) then
        return { x = site.inside.x, y = site.inside.y, z = site.z,
            a = Fortify.ports.angleTo(site.outside.x - site.inside.x, site.outside.y - site.inside.y) }
    end
    local bid = sq ~= nil and X.buildingId(sq) or nil
    return X.placeBeside(cell, site.inside.x, site.inside.y, site.z, bid, {})
end

local function step(id, ctx, m)
    local X = LivingKnox.Routines.exec
    local e = X.entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) and (m.phase == "go" or m.phase == "face") then
        -- Une autre consigne est passée (suite de test, autre module) : retour à la place.
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
        m.phase = "go"
    end
    if m.phase == "place" then
        local p = placeFor(m.site)
        if p == nil then return finishSite(id, m, ctx.minute, "no place inside " .. m.site.id) end
        m.place, m.phase = p, "go"
    end
    if m.phase == "go" then
        local res = X.goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
        if res == "moving" then return end
        if res == "failed" then return finishSite(id, m, ctx.minute, "cannot reach " .. m.site.id) end
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
        X.sitDown(id, m, (workOf(m.site)))
        m.since, m.phase = ctx.minute, "work"
        return
    end
    if m.phase == "work" then
        local gesture, minutes, effect = workOf(m.site)
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) ~= gesture then X.sitDown(id, m, gesture) end
        if ctx.minute - m.since < minutes then return end
        m.phase = "nail"   -- avant l'effet : jamais deux fois la même pose, même si le Java lève une erreur
        local ok, text, n = pcall(effect, m.site, m.gid, m.mid)
        if not ok then
            LivingKnox.Log.error("npc %s: %s %s failed: %s", tostring(id), m.site.kind, m.site.id, tostring(text))
            return finishSite(id, m, ctx.minute, "error")
        end
        if text == nil then return finishSite(id, m, ctx.minute, n) end
        m.placed = m.placed + 1
        LivingKnox.Log.info("npc %s (%s %s): %s", tostring(id), tostring(m.gid), tostring(m.mid), text)
        if n >= m.site.steps then return finishSite(id, m, ctx.minute, nil) end
        m.since, m.phase = ctx.minute, "work"
    end
end

-- Membre de poste « builder » en corvée (comportement « chore », LK_Routines.apply) : poursuit son chantier de
-- fortification (barricade, mur, palissade) ou en prend un (Fortify.siteFor, chantier qu'aucun autre membre ne
-- tient). Rend vrai si le membre est occupé par la fortification (corvée et entretien attendent), faux sinon.
function Fortify.run(id, st, ctx, g)
    if ctx.gid == nil or ctx.duty ~= "builder" or type(g) ~= "table" or type(g.home) ~= "table" then return false end
    local mem = LivingKnox.Routines.state.npcs
    local m = mem[id]
    if m ~= nil and m.kind == "fortify" then
        if m.phase == "done" then return false end
        step(id, ctx, m)
        return true
    end
    local wait = Fortify.state.rest[id]
    if wait ~= nil and ctx.minute < wait then return false end
    local site, why = Fortify.siteFor(ctx.gid, ctx.mid)
    local k = site ~= nil and claimKey(ctx.gid, site.id) or nil
    if site == nil or not Fortify.KINDS[site.kind] or site.inside == nil
        or (Fortify.state.claims[k] ~= nil and Fortify.state.claims[k] ~= id) then
        Fortify.state.rest[id] = ctx.minute + P.cfg().IDLE_MINUTES
        LivingKnox.Log.debug("npc %s: no fortification site: %s", tostring(id), tostring(site ~= nil and site.id or why))
        return false
    end
    -- Place du chantier évitée par ce PNJ (échec "stuck" récent, LivingKnox.Movement.avoided) : il le reprend après
    -- l'évitement au lieu d'enchaîner les arrêts "cannot reach" (campagne MP du 2026-10-15, réparation urgente).
    local Mv = LivingKnox.Movement
    if Mv ~= nil and Mv.avoided ~= nil and Mv.avoided(id, site.inside.x, site.inside.y, site.z) ~= nil then
        Fortify.state.rest[id] = ctx.minute + P.cfg().REST_MINUTES
        LivingKnox.Log.debug("npc %s: site %s avoided for now (recent stuck move)", tostring(id), site.id)
        return false
    end
    if m ~= nil then LivingKnox.Routines.leave(id) end   -- corvée visible en cours : debout d'abord
    Fortify.state.claims[k] = id
    m = { key = "fortify " .. site.id, kind = "fortify", site = site, gid = ctx.gid, mid = ctx.mid, phase = "place",
        fails = 0, placed = 0, release = releaseMemory }
    mem[id] = m
    Fortify.stats.started = Fortify.stats.started + 1
    LivingKnox.Log.info("npc %s (%s %s): %s %s (%s, %d/%d step(s), %s)", tostring(id), tostring(ctx.gid), tostring(ctx.mid),
        site.kind, site.id, tostring(site.opening or site.side), site.have, site.steps, tostring(st.why or st.b))
    step(id, ctx, m)
    return true
end
