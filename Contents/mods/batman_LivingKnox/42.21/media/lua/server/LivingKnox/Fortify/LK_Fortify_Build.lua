-- Living Knox : fortification du foyer, pose des barricades (LK14-T03 : Fortify.nailPlank) et des murs et
-- palissades du pourtour (LK14-T04 : Fortify.buildStep, placeStructure)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

-- ================================================================ pose des barricades (LK14-T03)
-- Fiche docs/annexes/conception/fortification.md §7. Autorité seulement (module absent d'un client MP).

local function ofType(t)
    return function(it) return it:getFullType() == t end
end

-- Ouverture barricadable du chantier site (même case, même face), et sa case ; nil si elle n'y est plus.
function Fortify.openingOf(site)
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(site.x, site.y, site.z) or nil
    if sq == nil then return nil, nil end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o ~= nil and Fortify.openingKind(o) ~= nil and (o:getNorth() == true) == (site.north == true)
            and o:isBarricadeAllowed() then
            return o, sq
        end
    end
    return nil, sq
end

-- Côté où clouer la planche : celui de la barricade déjà commencée (la plus garnie), sinon le côté visé par le plan
-- (site.opp : dehors, comme IsoWindow.addRandomBarricades, fortification.md §5.3) s'il a une case, sinon l'autre.
-- Rend addOpposite et les planches déjà posées, ou nil et une raison.
local function sideFor(o, site)
    local ps, ms = P.planksOf(o:getBarricadeOnSameSquare())
    local po, mo = P.planksOf(o:getBarricadeOnOppositeSquare())
    if ms or mo then return nil, "metal barricade" end
    local have = math.max(ps, po)
    if ps > 0 and ps >= po then return false, have end
    if po > 0 then return true, have end
    local opp = site.opp == true
    local target = opp and o:getOppositeSquare() or o:getSquare()
    if target == nil then opp = not opp end
    return opp, have
end

-- Ouvre une boîte de clous du foyer comme la recette vanilla OpenBox100 (M/recipes/recipes_packing.txt:220-241) : la
-- boîte retirée par Stock.takeItem, BOX_NAILS Base.Nails ajoutés au même conteneur (envoyés aux clients proches sur un
-- serveur), puis relecture du stock (objets ajoutés acceptés : référence à jour). Rend vrai, ou faux et une raison.
local function openBox(gid, box, ctr, who, use)
    local id = box:getID()
    local got, why = P.Stock().takeItem(gid, function(it) return it:getID() == id end, who, use)
    if got == nil then return false, why end
    local list = ctr:AddItems(Fortify.NAILS, P.cfg().BOX_NAILS)
    if isServer() and list ~= nil then sendAddItemsToContainer(ctr, list) end
    Fortify.stats.boxes = Fortify.stats.boxes + 1
    LivingKnox.Log.info("fortify: group %s: %s opened a box of nails (%d nail(s))", gid, tostring(who or "member"),
        list ~= nil and list:size() or 0)
    P.Stock().check(gid, { force = true })
    return true
end

-- Pose des planches sur l'ouverture o, côté addOpp, comme BuildRecipeCode.barricade.OnCreate (M/lua/server/
-- BuildRecipeCode/buildRecipeCode.lua:91-161) : barricade ajoutée ou reprise (IsoBarricade.AddBarricadeToObject,
-- J/iso/objects/IsoBarricade.java:739-764), planches ajoutées (addPlank, :90-108 ; planks = liste d'objets Base.Plank
-- réels, état repris, ou nombre de planches neuves), UNE transmission sur un serveur (barricade neuve :
-- transmitCompleteItemToClients ; planches ajoutées : sendObjectChange(STATE), J/iso/IsoObject.java:4265-4272,
-- 4314-4322), drapeau de construction de la case. Matériaux déjà retirés par l'appelant. Rend la barricade, ou nil.
function Fortify.addPlanks(o, addOpp, planks)
    local b = IsoBarricade.AddBarricadeToObject(o, addOpp)
    if b == nil then return nil end
    local isNew = b:getNumPlanks() == 0 and not b:isMetal() and not b:isMetalBar()
    if type(planks) == "number" then
        for _ = 1, planks do b:addPlank(nil, nil) end   -- planche neuve (1000 PV)
    else
        for _, plank in ipairs(planks) do b:addPlank(nil, plank) end
    end
    if isServer() then
        if isNew then b:transmitCompleteItemToClients() else b:sendObjectChange(IsoObjectChange.STATE) end
    end
    if type(buildUtil) == "table" and buildUtil.setHaveConstruction ~= nil then
        buildUtil.setHaveConstruction(b:getSquare(), true)   -- drapeau de zone de toutes les constructions vanilla
    end
    return b
end

-- Cloue UNE planche sur l'ouverture du chantier site du groupe gid (who : texte du journal), comme
-- BuildRecipeCode.barricade.OnCreate (M/lua/server/BuildRecipeCode/buildRecipeCode.lua:91-161) sans personnage :
-- tout est relu maintenant (ouverture présente, pas l'entrée du foyer, porte fermée, pas de métal, planches sous la
-- visée, marteau, planche et clou au foyer) AVANT toute prise ; puis une planche et un clou retirés du stock (une
-- seule fois, référence à jour), barricade ajoutée (IsoBarricade.AddBarricadeToObject, J/iso/objects/IsoBarricade.java
-- :739-764), planche réelle passée à addPlank (état repris, :90-108), transmission sur un serveur (barricade neuve :
-- transmitCompleteItemToClients ; planche ajoutée : sendObjectChange(STATE)). Rend un texte et le nombre de planches
-- posées, ou nil et une raison (rien fait).
function Fortify.nailPlank(site, gid, who)
    local St = P.Stock()
    if St == nil or St.findItem == nil or St.takeItem == nil then return nil, "no stock module" end
    local o, sq = Fortify.openingOf(site)
    if o == nil then return nil, sq == nil and "square not loaded" or "opening gone" end
    local plan = Fortify.plan(gid)
    local e = plan ~= nil and plan.entry or nil
    if e ~= nil and e.x == site.x and e.y == site.y and e.z == site.z and e.north == site.north then
        return nil, "home entry"   -- l'entrée reste praticable (une barricade bloque la porte pour tous)
    end
    if Fortify.openingKind(o) == "door" and o:IsOpen() then return nil, "door open" end
    local addOpp, have = sideFor(o, site)
    if addOpp == nil then return nil, have end
    if have >= site.steps then return nil, "already done" end
    if not Fortify.hasTool(gid, "HAMMER") then return nil, "no hammer" end
    local pf, plank, pctr = St.findItem(gid, ofType(Fortify.PLANK))
    if pf == nil then return nil, "no plank" end
    local boxF, box, bctr
    if St.findItem(gid, ofType(Fortify.NAILS)) == nil then
        boxF, box, bctr = St.findItem(gid, ofType(Fortify.NAILS_BOX))
        if boxF == nil then return nil, "no nails" end
    end
    local use = "barricade " .. site.id
    if boxF ~= nil then
        local ok, why = openBox(gid, box, bctr, who, use)
        if not ok then return nil, "box of nails not opened: " .. tostring(why) end
    end
    local plankId = plank:getID()
    local gotPlank, w1 = St.takeItem(gid, function(it) return it:getID() == plankId end, who, use)
    if gotPlank == nil then return nil, "plank not taken: " .. tostring(w1) end
    local gotNail, w2 = St.takeItem(gid, ofType(Fortify.NAILS), who, use)
    if gotNail == nil then
        pctr:AddItem(plank)   -- planche remise (relue comme ajoutée) : rien n'est perdu
        if isServer() then sendAddItemToContainer(pctr, plank) end
        return nil, "nail not taken: " .. tostring(w2)
    end
    local b = Fortify.addPlanks(o, addOpp, { plank })
    if b == nil then return nil, "barricade not added" end
    Fortify.invalidate(gid)
    Fortify.stats.planks = Fortify.stats.planks + 1
    local n = b:getNumPlanks()
    return string.format("plank %d/%d nailed on %s %s (%s side)", n, site.steps, tostring(site.opening), site.id,
        addOpp and "opposite" or "same"), n
end

-- ================================================================ murs et palissade du pourtour (LK14-T04)
-- Fiche docs/annexes/conception/fortification.md §8. Une étape par appel (cadre, mur sur le cadre, palissade), posée par
-- l'autorité comme ISBuildIsoEntity:setInfo (M/lua/server/BuildingObjects/ISBuildIsoEntity.lua:595-763) sans
-- personnage : IsoThumpable aux drapeaux tirés du sprite, buildUtil.setInfo, santé du script, composants de l'entité,
-- étape précédente retirée (transmitRemoveItemFromSquare), AddSpecialObject, poteau d'angle, setExplored,
-- RecalcAllWithNeighbours, transmitCompleteItemToClients.

-- Sprites des ouvrages (Fortify.STRUCTURES : entité -> faces W, N) et étapes de chaque sorte du pourtour
-- (Fortify.STAGES) : dérivés des sortes inscrites (LK16-T02, fichiers Fortify/LK_Fortify_Wall.lua, _Palisade.lua).
-- Multiplicateur de la santé bonus selon l'option sandbox ConstructionBonusPoints (ISBuildIsoEntity.lua:655-660).
local BONUS_MULT = { [1] = 0.5, [2] = 0.7, [4] = 1.3, [5] = 1.5 }

-- Fiche de l'entité vanilla posée par le sprite de la face voulue (comme le menu de construction) : info, sprite ;
-- ou nil et une raison. Le nom de l'entité doit être celui attendu (sprite repris par un autre mod : refus).
function Fortify.entityInfo(entity, north)
    local sprites = Fortify.STRUCTURES[entity]
    if sprites == nil then return nil, "unknown structure " .. tostring(entity) end
    local sprite = north and sprites.N or sprites.W
    if SpriteConfigManager == nil then return nil, "no SpriteConfigManager" end
    local info = SpriteConfigManager.getObjectInfoFromSprite(sprite)
    if info == nil or info:getScript() == nil then return nil, "no entity for sprite " .. sprite end
    if info:getName() ~= entity then return nil, "sprite " .. sprite .. " is " .. tostring(info:getName()) end
    return info, sprite
end

-- Santé d'un ouvrage posé sans personnage (ISBuildIsoEntity.lua:637-668) : santé du script + bonus × multiplicateur
-- sandbox + niveau × skillBaseHealth, le niveau étant le plus haut niveau requis par la recette (Menuiserie 2 pour
-- un mur, 0 pour la palissade : les PNJ n'ont pas de compétences ; même plancher que le mode triche vanilla).
function Fortify.healthOf(info)
    local script = info:getScript()
    local level = 0
    local recipe = info:getRecipe() ~= nil and info:getRecipe():getCraftRecipe() or nil
    if recipe ~= nil then
        for i = 0, recipe:getRequiredSkillCount() - 1 do
            local rs = recipe:getRequiredSkill(i)
            if rs ~= nil and rs:getPerk() ~= nil and rs:getLevel() > level then level = rs:getLevel() end
        end
    end
    local bonus = script:getBonusHealth() or 0
    local opt = getSandboxOptions ~= nil and getSandboxOptions():getOptionByName("ConstructionBonusPoints") or nil
    local mult = opt ~= nil and BONUS_MULT[opt:getValue()] or 1
    return math.max(script:getHealth(), 0) + bonus * mult + level * script:getSkillBaseHealth()
end

-- Drapeaux de l'objet tirés des propriétés de son sprite, comme ISBuildIsoEntity:setInfo (:614-631) ; murs, cadres et
-- palissade ne sont ni portes ni fenêtres (canBarricade, isDoor, isDoorFrame faux).
local function propsInfo(t, info)
    local p = t:getProperties()
    local function has(f) return p ~= nil and f ~= nil and p:has(f) end
    local F = IsoFlagType
    local script = info:getScript()
    return {
        canPassThrough = p ~= nil and not (has(F.solid) or has(F.solidtrans) or has(F.doorN) or has(F.doorW)
            or has(F.WallN) or has(F.WallNTrans) or has(F.WallW) or has(F.WallWTrans) or has(F.WallNW)),
        hoppable = has(F.HoppableN) or has(F.HoppableW) or has(F.TallHoppableN) or has(F.TallHoppableW),
        blockAllTheSquare = IsoPropertyType ~= nil and has(IsoPropertyType.BLOCKS_PLACEMENT),
        isFloor = has(F.solidfloor),
        canBarricade = false, thumpDmg = 8, isContainer = false, isDoor = false, isDoorFrame = false, crossSpeed = 1.0,
        name = info:getName(), dismantable = true, canBePlastered = false, modData = {}, isStairs = false,
        isThumpable = script:getIsThumpable() or false, corner = script:getCornerSprite(),
    }
end

-- Ouvrage du pourtour nommé name sur le bord (sq, north), ou nil.
local function structureOn(sq, north, name)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) == north and o:getName() == name then return o end
    end
    return nil
end

-- Poteau d'angle comme buildUtil.checkCorner (M/lua/server/BuildingObjects/ISBuildUtil.lua:57-99) : mur
-- perpendiculaire sur la case diagonale et aucun mur sur la case du coin ; poteau déjà là (étape suivante du même
-- bord) : aucun second poteau (vanilla en ajoute un à chaque étape). Rend vrai si un poteau est posé.
local function cornerPost(sq, north, t, sprite)
    if sprite == nil or type(buildUtil) ~= "table" or buildUtil.addCorner == nil then return false end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local nx, ny, cx, cy = x + 1, y - 1, x + 1, y
    if not north then nx, ny, cx, cy = x - 1, y + 1, x, y + 1 end
    local cell = getCell()
    local sq2 = cell:getGridSquare(nx, ny, z)
    if sq2 == nil then return false end
    local found = false
    local sp = sq2:getSpecialObjects()
    for i = 0, sp:size() - 1 do
        local o = sp:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) ~= north then found = true end
    end
    if not found then return false end
    local csq = cell:getGridSquare(cx, cy, z)
    if csq == nil or csq:getWallFull() then return false end
    local sp2 = csq:getSpecialObjects()
    for i = 0, sp2:size() - 1 do
        local o = sp2:get(i)
        if instanceof(o, "IsoThumpable") and o:isCorner() then return false end
    end
    buildUtil.addCorner(cx, cy, z, t, { corner = sprite })   -- pose, recalcul et envoi aux clients (vanilla)
    Fortify.stats.corners = Fortify.stats.corners + 1
    return true
end

-- Pose l'ouvrage de fiche info (sprite) sur le bord (sq, north) à la place de prev (étape précédente, ou nil), comme
-- ISBuildIsoEntity:setInfo sans personnage. Autorité seulement ; matériaux déjà retirés par l'appelant. Rend l'objet.
function Fortify.placeStructure(sq, north, info, sprite, prev)
    local t = IsoThumpable.new(getCell(), sq, sprite, north, {})   -- table sauvegardée avec l'objet : vide
    local item = propsInfo(t, info)
    buildUtil.setInfo(t, item)
    local health = Fortify.healthOf(info)
    t:setMaxHealth(health)
    t:setHealth(t:getMaxHealth())   -- avant la pose : setHealth enverrait sync() d'un objet posé
    local breakSound = info:getScript():getBreakSound()
    if breakSound ~= nil then t:setBreakSound(breakSound) end
    local entity = info:getScript():getParent()
    if entity ~= nil then GameEntityFactory.CreateIsoObjectEntity(t, entity, true) end
    local index = -1
    if prev ~= nil and prev:getSquare() == sq then index = sq:transmitRemoveItemFromSquare(prev) end
    sq:AddSpecialObject(t, index)
    cornerPost(sq, north, t, item.corner)
    t:setExplored(true)
    sq:RecalcAllWithNeighbours(true)
    if isServer() then t:transmitCompleteItemToClients() end
    if buildUtil.setHaveConstruction ~= nil then buildUtil.setHaveConstruction(sq, true) end
    return t
end

local function typeIn(types)
    return function(it)
        local t = it:getFullType()
        for _, w in ipairs(types) do
            if t == w then return true end
        end
        return false
    end
end

-- Objets du foyer pour les besoins reqs ({ types, n }), sans rien prendre (objets distincts) : liste { it, ctr }, ou
-- nil et le type manquant.
local function gather(gid, reqs, picked)
    local out = {}
    picked = picked or {}
    for _, r in ipairs(reqs) do
        local match = typeIn(r.types)
        for _ = 1, r.n do
            local f, it, ctr = P.Stock().findItem(gid, function(i) return not picked[i:getID()] and match(i) end)
            if f == nil then return nil, r.types[1] end
            picked[it:getID()] = true
            out[#out + 1] = { it = it, ctr = ctr }
        end
    end
    return out
end

-- Objets pris un à un dans le stock (items : { it, ctr }) ; une prise qui échoue remet les objets déjà pris. Rend vrai,
-- ou faux et une raison.
local function takeAll(gid, items, who, use)
    local St = P.Stock()
    local taken = {}
    for _, e in ipairs(items) do
        local id = e.it:getID()
        local got, w = St.takeItem(gid, function(it) return it:getID() == id end, who, use)
        if got == nil then
            for _, b in ipairs(taken) do   -- objets remis (relus comme ajoutés) : rien n'est perdu
                b.ctr:AddItem(b.it)
                if isServer() then sendAddItemToContainer(b.ctr, b.it) end
            end
            return false, e.it:getFullType() .. " not taken: " .. tostring(w)
        end
        taken[#taken + 1] = e
    end
    return true
end

-- Clous libres pour n clous, en ouvrant une boîte au besoin (étape du pourtour, réparation) : liste { it, ctr }, ou nil
-- et une raison. picked : objets déjà retenus, complété.
local function nailsFor(gid, n, picked, who, use)
    local trial = {}
    for k, v in pairs(picked) do trial[k] = v end
    local loose = gather(gid, { Fortify.req({ Fortify.NAILS }, n) }, trial)
    if loose ~= nil then
        for k, v in pairs(trial) do picked[k] = v end
        return loose
    end
    local boxF, box, bctr = P.Stock().findItem(gid, ofType(Fortify.NAILS_BOX))
    if boxF == nil then return nil, "no nails" end
    local ok, w = openBox(gid, box, bctr, who, use)
    if not ok then return nil, "box of nails not opened: " .. tostring(w) end
    loose = gather(gid, { Fortify.req({ Fortify.NAILS }, n) }, picked)
    if loose == nil then return nil, "no nails" end
    return loose
end

-- Chantier du pourtour du plan courant (même identifiant), ou nil et une raison (brèche, hors du plan).
local function ringSiteNow(gid, site)
    local plan = Fortify.plan(gid)
    if plan == nil then return nil, "no plan" end
    for _, g in ipairs(plan.gaps) do
        if g.x == site.x and g.y == site.y and g.z == site.z and g.north == site.north then return nil, "gap" end
    end
    local b = plan.bounds
    if b == nil or site.x < b.x1 or site.x > b.x2 or site.y < b.y1 or site.y > b.y2 then return nil, "outside the home" end
    for _, s in ipairs(plan.sites) do
        if s.id == site.id then return s end
    end
    return nil, "not in the plan"
end

-- Pose UNE étape (cadre, mur, palissade) du chantier de pourtour site du groupe gid (who : texte du journal) : tout est
-- relu AVANT toute prise (chantier encore au plan et hors brèche, bord chargé, étape suivante d'après les ouvrages du
-- bord, sol praticable et bord libre pour une première étape, fiche de l'entité, marteau, tous les matériaux) ; boîte
-- de clous ouverte au besoin ; matériaux retirés une seule fois par Stock.takeItem (remis si une prise échoue) ;
-- ouvrage posé par Fortify.placeStructure. Rend un texte et le nombre d'étapes faites, ou nil et une raison.
function Fortify.buildStep(site, gid, who)
    local St = P.Stock()
    if St == nil or St.findItem == nil or St.takeItem == nil then return nil, "no stock module" end
    local stages = Fortify.STAGES[site.kind]
    if stages == nil then return nil, "not a ring site" end
    if type(buildUtil) ~= "table" or buildUtil.setInfo == nil or IsoThumpable == nil or GameEntityFactory == nil then
        return nil, "no vanilla build helpers"
    end
    local cur, why = ringSiteNow(gid, site)
    if cur == nil then return nil, why end
    local cell = getCell()
    local north = site.north == true
    local sq = cell ~= nil and cell:getGridSquare(site.x, site.y, site.z) or nil
    local ox, oy = site.x, site.y - 1
    if not north then ox, oy = site.x - 1, site.y end
    local other = sq ~= nil and cell:getGridSquare(ox, oy, site.z) or nil
    if sq == nil or other == nil then return nil, "square not loaded" end
    local kind, done = P.builtOn(sq, north)
    done = done or 0
    if kind ~= nil and kind ~= site.kind then return nil, "other structure (" .. kind .. ")" end
    if done >= #stages then return nil, "already done" end
    local stage = stages[done + 1]
    local prev
    if stage.prev ~= nil then
        prev = structureOn(sq, north, stage.prev)
        if prev == nil then return nil, "no " .. stage.prev end
    elseif not P.groundOk(sq) or other:getBuildingDef() ~= nil or other:isWaterSquare() then
        return nil, "ground"
    elseif sq:isBlockedTo(other) then
        return nil, "edge closed"
    end
    local info, sprite = Fortify.entityInfo(stage.entity, north)
    if info == nil then return nil, sprite end
    if stage.tool ~= nil and not Fortify.hasTool(gid, stage.tool) then return nil, "no " .. string.lower(stage.tool) end
    local nails, others = 0, {}
    for _, r in ipairs(stage.materials) do
        if #r.types == 1 and r.types[1] == Fortify.NAILS then nails = r.n else others[#others + 1] = r end
    end
    local picked = {}
    local items, miss = gather(gid, others, picked)
    if items == nil then return nil, "no " .. tostring(miss) end
    local use = site.kind .. " " .. site.id
    if nails > 0 then
        local loose, w = nailsFor(gid, nails, picked, who, use)
        if loose == nil then return nil, w end
        for _, e in ipairs(loose) do items[#items + 1] = e end
    end
    local ok, w = takeAll(gid, items, who, use)
    if not ok then return nil, w end
    Fortify.placeStructure(sq, north, info, sprite, prev)
    Fortify.invalidate(gid)
    Fortify.stats.stages = Fortify.stats.stages + 1
    return string.format("%s %d/%d built on %s (%d item(s) used)", stage.entity, done + 1, #stages, site.id, #items),
        done + 1
end

-- LK20-T07 : fonctions privées partagées avec les autres fichiers de Fortify/ (table Fortify._).
P.gather, P.takeAll, P.nailsFor, P.sideFor, P.structureOn = gather, takeAll, nailsFor, sideFor, structureOn
