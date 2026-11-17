-- Living Knox : santé de référence des PNJ, tenue par l'autorité (LK07-T02). Fiche : docs/annexes/conception/sante.md,
-- section « Santé de référence (LK07-T02) ». Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- La santé vanilla d'un corps (zombie) est rendue inerte : setInvulnerable(true) sur la copie de l'autorité (ici) et
-- sur chaque copie client (client/LivingKnox/LK_HealthClient.lua), santé vanilla laissée fixe (<= 32,767, jamais
-- relevée). Effets (J/CombatManager.java:1097-1110, J/characters/IsoGameCharacter.java:2903-2908, 6036-6039,
-- 11714) : aucun dégât vanilla (coup, explosion, chute, véhicule, feu éteint), setHealth(0) ignoré, pas de corps
-- rendu rampant ; le coup reste visible (événements, réaction, son).
-- La santé de référence est le champ hp du registre des corps (npc.hp, LK_Identity ; même échelle que la santé du
-- moteur, npc.hpMax = santé de naissance), tenu par l'autorité et sauvegardé avec le registre. Seules écritures :
--   - Health.bodyBound (corps relié : création, retour de chunk, redémarrage ; appelé par Bodies.guardNow) : hp gardé
--     s'il est connu (au plus hpMax), sinon santé du corps ;
--   - Health.setBirth (matérialisation d'un membre de groupe, LK09-T03, LK21-T03 : santé et plaies du membre hors
--     écran, état décidé par la simulation de l'autorité) ;
--   - Health.applyHit (coup contrôlé, en baisse seulement) ;
--   - Health.bleedPass (plaies, LK21-T02, en baisse seulement) ;
--   - Health.noteHeal (soin connu de l'autorité, LK07-T03, LK_Care) et la régénération de Health.bleedPass
--     (LK21-T02, règle du vanilla) : SEULES hausses possibles.
-- Plaies (LK21-T02, ADR docs/architecture/decisions/adr-blessures-soins.md D01 et D03 ; remplace le saignement unique
-- npc.bleed de LK07-T03, non repris : mod non publié) : liste de plaies localisées du modèle pur
-- shared/LivingKnox/LK_Wounds.lua, gardée dans le registre des corps sous sa forme compacte (npc.wounds, texte de
-- Wounds.pack, LK_WoundsForm.lua ; absent = aucune plaie ; validé à la relecture par Identity.validate) et relue une
-- fois (cache Health.woundCache tant que le texte ne change pas). Ce module en est le seul écrivain, comme de npc.hp.
--   - Un coup non mortel (Health.applyHit) fait ses plaies par la source de blessure que choisit le registre des
--     sources (Wounds.fromHit, server/LivingKnox/LK_WoundSources.lua : attaquant, arme, issue ; ou source nommée) ;
--     aucune source : dégâts seulement. Hasard et options du jeu : LivingKnox.WoundContext (LK_WoundContext.lua).
--   - Chaque minute de jeu (EveryOneMinute, minutes manquées rattrapées d'après l'âge du monde, au plus STEP_MAX), les
--     plaies d'un corps relié dans le monde évoluent (Wounds.advance : saignement, dégâts de partie, guérison,
--     bandage, infection) et la santé baisse de hpLoss x hpMax ; les plaies guéries sont retirées. À 0 : mort par le
--     chemin de Health.kill, cause « bleeding » (sans arme ni attaquant).
--   - Saignement lu : Health.bleeding = Wounds.bleeding (fraction de hpMax perdue par heure de jeu).
--   - Soins : Health.stopBleeding (adaptateur provisoire de LK_Care jusqu'à LK21-T05 : bande les plaies qui
--     saignent) ; les soins de LK21-T05 changeront les plaies par Health.wounds puis Health.woundsChanged.
--   - PNJ virtuel (corps retiré) : plaies suspendues, reprises à la prochaine incarnation. Mort : plaies effacées.
--   - Membre de groupe (LK21-T03, LK_Materialize) : ses plaies passent telles quelles au corps à la naissance
--     (Health.setBirth) et lui reviennent au retrait (Health.handOver) ; la simulation hors écran les fait évoluer
--     par la même formule (Wounds.healthStep, shared/LivingKnox/LK_WoundsHealth.lua).
-- Régénération (LK21-T02, Wounds.regeneration) : chaque minute de jeu, un corps relié qui n'a pas toute sa santé en
-- regagne comme un joueur éveillé et nourri du vanilla (BodyDamage.java:1887-1928), sans dépasser ce que ses plaies
-- tiennent encore (Wounds.healthCap) ; soin connu (noteHeal) en plus.
-- Coups (abonné OnWeaponHitCharacter, autorité ; J/characters/IsoGameCharacter.java:5704-5743) : l'événement part
-- AVANT les dégâts vanilla. Valeur reçue : serveur MP = dégâts calculés par le client attaquant (après
-- processHitDamage, avant la réduction de mêlée x 0,15 ; PlayerHitZombie, J/network/fields/hit/WeaponHit.java:79) ;
-- solo = dégâts avant processHitDamage (estimés ici : x NON_PLAYER, niveau d'arme, critique, coup au sol). Contrôles
-- sur un serveur MP, pour un attaquant joueur (Health.judge) : vivant ; mêlée hors véhicule ; à portée de l'arme
-- (getMaxRange + marge, niveaux) ; cadence (seau à jetons par attaquant et par PNJ) ; explosif absent de son
-- inventaire (une bombe lancée l'a quitté). Aucun plafond tiré de l'arme (décision du 2026-10-11, LK07-T06) :
-- la valeur est crue telle quelle (un coup de grâce au couteau, x 1000 chez l'attaquant, doit tuer), refusée
-- seulement si elle n'est pas un nombre fini positif ou nul, et bornée par la santé restante (Health.applyHit).
-- Poussée sans visée au sol : aucun dégât (J/characters/IsoGameCharacter.java:5716-5719). Les drapeaux de
-- l'attaquant (visée au sol, poussée, critique) sont posés par le paquet avant Hit
-- (J/network/packets/hit/PlayerHit.java:88-90, J/network/fields/hit/Player.java:113-125).
-- Mort (LK07-T04 : chemin unique Health.kill, cause "bleeding" ou "zombie" décidée avec elle, corps dans le monde
-- exigé) : décidée ici une seule fois (Health.decided) quand hp atteint 0 : invulnérabilité retirée, faux mort levé,
-- puis le chemin vanilla de l'autorité : serveur setAttackedBy + die() (J/characters/IsoGameCharacter.java:
-- 5836-5846, 13478-13496), solo Kill(arme, attaquant). OnZombieDead -> Bodies.onZombieDead (registre "dead",
-- Materialize.onBodyDied) -> Health.onBodyDied. Une mort vanilla non décidée ici (Kill par un autre mod, santé
-- négative forgée par un client propriétaire) est journalisée (WARN) puis menée à son terme (santé posée à 0 pour
-- que le moteur crée le cadavre) ; le registre ne la compte qu'une fois (Bodies.onZombieDead).
-- Retransmission (serveur MP) : commande "npcHealth" { d = { [npcId] = { r, hp, mx, w = nombre de plaies } } } aux
-- destinataires des
-- consignes (Directives.targets : joueurs à NEAR_RADIUS cases du corps et propriétaire), un message par client et
-- par passage (SEND_MS), seulement aux clients qui n'ont pas la révision courante : aucune diffusion à tous.
-- r : révision croissante (livraison RELIABLE non ordonnée : le client garde la plus grande).
-- Autres sources (véhicule, feu, chute) : neutralisées par l'invulnérabilité, aucun dégât de référence (voir la
-- fiche). Explosion par piège ou bombe : chemin Hit, couverte (arme isExplosive).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local Health = LivingKnox.Health or {}
LivingKnox.Health = Health

-- Constantes lues aussi par un client MP (qui charge media/lua/server mais s'arrête à la garde).
Health.MODULE = "LivingKnox"
Health.CMD = "npcHealth"   -- serveur -> clients proches : { d = { [npcId] = { r, hp, mx, w } } }

-- Réglages (lus à chaque appel ; bornes de docs/annexes/conception/sante.md, « Santé de référence (LK07-T02) »).
LivingKnox.Config.HEALTH = LivingKnox.Config.HEALTH or {
    APPLY_EVERY = 3,          -- images entre deux passages d'invulnérabilité sur les corps connus
    SEND_MS = 500,            -- serveur : envoi de la santé aux destinataires au plus toutes les SEND_MS
    MELEE_SLACK = 2,          -- cases ajoutées à la portée d'une arme de mêlée (gigue des positions du serveur)
    RANGED_SLACK = 5,         -- cases ajoutées à la portée d'une arme à feu
    MELEE_LEVELS = 1,         -- niveaux d'écart au plus (mêlée)
    RANGED_LEVELS = 2,        -- niveaux d'écart au plus (arme à feu)
    RATE = 10,                -- coups acceptés par seconde, par attaquant et par PNJ (seau à jetons)
    BURST = 5,                -- coups d'avance (paquets regroupés par le réseau)
    WARN_EVERY_MS = 60000,    -- une ligne par (attaquant, raison) au plus par minute
}
-- Plaies : réglages LivingKnox.Config.BLEEDING (LK_Config.lua, lus aussi par la simulation hors écran, LK21-T03).

if isClient() then return Health end

require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Directives"
require "LivingKnox/LK_WoundsForm"
require "LivingKnox/LK_WoundsHealth"
require "LivingKnox/LK_WoundSources"
require "LivingKnox/LK_WoundContext"

local Wounds = LivingKnox.Wounds

Health.decided = Health.decided or {}   -- npcId -> vrai : mort décidée par l'autorité (une seule fois)
Health.parts = Health.parts or {}       -- npcId -> partie du corps du dernier OnHitZombie (consommée par le coup)
Health.buckets = Health.buckets or {}   -- "<attaquant>|<npcId>" -> { tokens, ms }
Health.rev = Health.rev or {}           -- npcId -> révision de la santé
Health.sent = Health.sent or {}         -- compte -> { [npcId] = révision remise }
Health.warned = Health.warned or {}
Health.woundCache = Health.woundCache or {}   -- npcId -> { text = npc.wounds lu, list = plaies vivantes }
Health.state = Health.state or { r = 0, ticks = 0, sendMs = nil }
Health.stats = Health.stats or { hits = 0, applied = 0, refused = 0, shoves = 0, ignored = 0,
    deaths = 0, engineDeaths = 0, protected = 0, heals = 0, messages = 0, why = {} }
Health.stats.bleeds = Health.stats.bleeds or 0              -- plaies qui saignent à la blessure (LK21-T02)
Health.stats.bleedDeaths = Health.stats.bleedDeaths or 0    -- morts par les plaies (cause « bleeding »)
Health.stats.bleedStops = Health.stats.bleedStops or 0      -- saignements arrêtés (soin ou seuls)
Health.stats.wounds = Health.stats.wounds or 0              -- plaies faites (LK21-T02)
Health.stats.healed = Health.stats.healed or 0              -- plaies guéries et retirées (LK21-T02)

local function cfg() return LivingKnox.Config.HEALTH end
local function bcfg() return LivingKnox.Config.BLEEDING end
local function wctx() return LivingKnox.WoundContext.current() end

local function now() return getTimestampMs() end
local function round3(v) return math.floor(v * 1000 + 0.5) / 1000 end

local function isPlayer(o)
    return instanceof(o, "IsoPlayer") and not instanceof(o, "IsoAnimal")
end

local function nameOf(o)
    if isPlayer(o) then return o:getUsername() end
    if o == nil then return "nobody" end
    return "non-player"
end

-- Raisons suspectes (WARN) ; les autres sont des courses attendues (INFO).
Health.SUSPECT = { ["attacker is dead"] = true, ["melee from a vehicle"] = true, ["out of reach"] = true,
    ["other level"] = true, ["too many hits"] = true, ["explosive still in the attacker's inventory"] = true,
    ["bad damage"] = true }

local function note(name, id, reason, detail)
    local key = tostring(name) .. "|" .. reason
    local last = Health.warned[key]
    if last ~= nil and now() - last < cfg().WARN_EVERY_MS then return end
    Health.warned[key] = now()
    local say = Health.SUSPECT[reason] and LivingKnox.Log.warn or LivingKnox.Log.info
    say("hit on npc %s by %s refused: %s%s", tostring(id), tostring(name), reason,
        detail and (" (" .. detail .. ")") or "")
end

local function refuse(name, id, reason, detail)
    local st = Health.stats
    st.refused = st.refused + 1
    st.why[reason] = (st.why[reason] or 0) + 1
    note(name, id, reason, detail)
    return nil, reason
end

-- PNJ du registre (table vivante) ou nil.
local function npcOf(id)
    if not LivingKnox.Store.isReady() then return nil end
    return LivingKnox.Identity.get(LivingKnox.Store.data(), id)
end

-- Identifiant du PNJ dont z est le corps courant relié (Bodies.bound), ou nil.
function Health.currentId(z)
    if z == nil or not instanceof(z, "IsoZombie") or z:isDead() or not z:hasModData() then return nil end
    if not LivingKnox.Store.isReady() then return nil end
    local id = LivingKnox.Identity.readTag(z:getModData())
    if not id then return nil end
    local B = LivingKnox.Bodies
    if B == nil or not rawequal(B.bound[id], z) then return nil end
    return id
end

-- ---------------------------------------------------------------- invulnérabilité

-- Rend la santé vanilla du corps inerte. Rend vrai si le drapeau vient d'être posé.
function Health.protect(z)
    if z == nil or z:isDead() or z:isInvulnerable() then return false end
    z:setInvulnerable(true)
    Health.stats.protected = Health.stats.protected + 1
    return true
end

-- Retire l'invulnérabilité (mort voulue, retrait du corps : setHealth(0) serait sinon ignoré). Rend vrai si retirée.
function Health.makeMortal(z)
    if z == nil or not z:isInvulnerable() then return false end
    z:setInvulnerable(false)
    return true
end

-- ---------------------------------------------------------------- référence

local function touch(id)
    local st = Health.state
    st.r = st.r + 1
    Health.rev[id] = st.r
end

local function fullOf(npc, z)
    if LivingKnox.Identity.validHealth(npc.hpMax) and npc.hpMax > 0 then return npc.hpMax end
    if z ~= nil then
        local h = z:getHealth()
        if LivingKnox.Identity.validHealth(h) and h > 0 then return h end
    end
    return nil
end

-- Corps relié (Bodies.guardNow) : invulnérable, référence initialisée si elle manque. Rend la référence.
function Health.bodyBound(id, z)
    if not LivingKnox.isAuthority() or z == nil then return nil end
    Health.protect(z)
    local npc = npcOf(id)
    if npc == nil then return nil end
    Health.decided[id] = nil
    local full = fullOf(npc, z)
    local hp = npc.hp
    if not LivingKnox.Identity.validHealth(hp) or hp <= 0 then
        hp = z:getHealth()
        if not LivingKnox.Identity.validHealth(hp) or hp <= 0 then hp = full end
    end
    if hp == nil then return nil end
    if full ~= nil and hp > full then hp = full end
    if npc.hp ~= hp then
        npc.hp = hp
        LivingKnox.Store.markDirty()
    end
    touch(id)
    return hp
end

-- Santé de référence du PNJ incarné id, ou nil (inconnue, PNJ virtuel ou mort).
function Health.reference(id)
    local npc = npcOf(id)
    if npc == nil or npc.state ~= LivingKnox.Identity.STATE_EMBODIED
        or not LivingKnox.Identity.validHealth(npc.hp) then return nil end
    return npc.hp
end

-- ---------------------------------------------------------------- plaies (LK21-T02)

-- Plaies vivantes du PNJ npc (liste du modèle) : relues de la forme sauvegardée npc.wounds, gardées en cache tant que
-- ce texte ne change pas. Forme absente : aucune plaie ; forme refusée (refusée aussi par Identity.validate à la
-- relecture du registre, donc seulement après une écriture d'un autre module) : signalée, lue comme aucune plaie.
local function woundsOf(npc)
    local text = npc.wounds
    local c = Health.woundCache[npc.id]
    if c ~= nil and c.text == text then return c.list end
    local list, why = nil, nil
    if text ~= nil then list, why = Wounds.unpack(text) end
    if list == nil then
        if text ~= nil then LivingKnox.Log.warn("npc %s: wounds not readable (%s), ignored", npc.id, tostring(why)) end
        list = {}
    end
    Health.woundCache[npc.id] = { text = text, list = list }
    return list
end

-- Forme sauvegardée des plaies list du PNJ npc (absente sans plaie) et cache à jour.
local function saveWounds(npc, list)
    local text = nil
    if #list > 0 then text = Wounds.pack(list) end
    npc.wounds = text
    Health.woundCache[npc.id] = { text = text, list = list }
end

local function clearWounds(npc)
    npc.wounds = nil
    Health.woundCache[npc.id] = nil
end

-- Plaies vivantes du PNJ id (liste du modèle, à changer par les transitions de Wounds puis Health.woundsChanged), ou
-- nil (PNJ inconnu).
function Health.wounds(id)
    local npc = npcOf(id)
    if npc == nil then return nil end
    return woundsOf(npc)
end

-- Plaies du PNJ id changées par un soin (LK21-T05) : forme sauvegardée, registre à écrire, révision. Rend vrai, ou
-- faux (PNJ inconnu).
function Health.woundsChanged(id)
    local npc = npcOf(id)
    if npc == nil then return false end
    saveWounds(npc, woundsOf(npc))
    LivingKnox.Store.markDirty()
    touch(id)
    return true
end

-- Plaies du PNJ virtuel id rendues à la simulation hors écran (retrait d'un membre de groupe, LK21-T03) : forme
-- sauvegardée (texte de Wounds.pack, ou nil sans plaie), retirée du registre des corps (un seul détenteur). PNJ
-- inconnu ou incarné : nil, rien n'est retiré.
function Health.handOver(id)
    local npc = npcOf(id)
    if npc == nil or npc.state ~= LivingKnox.Identity.STATE_VIRTUAL then return nil end
    local text = npc.wounds
    if text ~= nil then
        clearWounds(npc)
        LivingKnox.Store.markDirty()
    end
    return text
end

-- Santé de naissance décidée par l'autorité (matérialisation d'un membre, LK09-T03) et plaies du membre (LK21-T03 :
-- forme sauvegardée de Wounds.pack, ou nil = aucune plaie ; forme refusée : signalée, aucune plaie). Rend vrai si
-- posée.
function Health.setBirth(id, hp, wounds)
    if not LivingKnox.isAuthority() or not LivingKnox.Identity.validHealth(hp) or hp <= 0 then return false end
    local npc = npcOf(id)
    if npc == nil or npc.state ~= LivingKnox.Identity.STATE_EMBODIED then return false end
    npc.hp = hp
    local list, why = {}, nil
    if wounds ~= nil then list, why = Wounds.unpack(wounds) end
    if list == nil then
        LivingKnox.Log.warn("npc %s: birth wounds not readable (%s), ignored", id, tostring(why))
        list = {}
    end
    saveWounds(npc, list)
    LivingKnox.Store.markDirty()
    touch(id)
    return true
end

-- Saignement du PNJ id (fraction de hpMax perdue par heure de jeu, somme des plaies), 0 s'il ne saigne pas.
function Health.bleeding(id)
    local npc = npcOf(id)
    if npc == nil then return 0 end
    local b = Wounds.bleeding(woundsOf(npc), wctx())
    if not LivingKnox.Num.finite(b) or b <= 0 then return 0 end
    return b
end

-- État de santé du PNJ id (copie) : { hp, max, dead, wounds = { { p = partie, kind, bleed (fraction par heure),
-- bandaged, infected, foreign }, ... }, bleed (0 : aucun saignement) }, ou nil.
function Health.get(id)
    local npc = npcOf(id)
    if npc == nil or not LivingKnox.Identity.validHealth(npc.hp) then return nil end
    local wounds, ctx = {}, wctx()
    for i, w in ipairs(woundsOf(npc)) do
        wounds[i] = { p = w.part, kind = w.kind, bleed = Wounds.woundBleeding(w, ctx), bandaged = w.bandage ~= nil,
            infected = w.infected == true, foreign = w.foreign == true }
    end
    return { hp = npc.hp, max = npc.hpMax, dead = npc.state == LivingKnox.Identity.STATE_DEAD, wounds = wounds,
        bleed = Health.bleeding(id) }
end

-- Plaies du coup hit (Wounds.fromHit) sur le PNJ npc, coup non mortel. Rend les plaies ajoutées.
local function woundFrom(id, npc, hit)
    local list = woundsOf(npc)
    local added, source = Wounds.fromHit(list, hit, wctx())
    if #added == 0 then return added end
    saveWounds(npc, list)
    for _, w in ipairs(added) do
        Health.stats.wounds = Health.stats.wounds + 1
        if w.bleed > 0 then Health.stats.bleeds = Health.stats.bleeds + 1 end
        LivingKnox.Log.info("npc %s wounded (%s): %s on %s%s", id, tostring(source), w.kind, w.part,
            w.bleed > 0 and ", bleeding" or "")
    end
    return added
end

-- Arrête le saignement du PNJ id. ADAPTATEUR PROVISOIRE de LK_Care (LK07-T03) jusqu'à LK21-T05 (registre des soins) :
-- chaque plaie qui saigne reçoit un bandage (Wounds.bandageBleeding) de vie tirée dans BANDAGE_LIFE plus power
-- (BandagePower de l'objet, 0 par défaut), sans alcool. Rend le saignement arrêté (fraction par heure ; 0 : aucun).
function Health.stopBleeding(id, why, power)
    local npc = npcOf(id)
    if npc == nil then return 0 end
    local list = woundsOf(npc)
    local stopped = Wounds.bandageBleeding(list, wctx(), bcfg().BANDAGE_LIFE, power)
    if stopped <= 0 then return 0 end
    saveWounds(npc, list)
    LivingKnox.Store.markDirty()
    touch(id)
    Health.stats.bleedStops = Health.stats.bleedStops + 1
    LivingKnox.Log.info("npc %s stopped bleeding (%s)", id, tostring(why or "care"))
    return stopped
end

-- Minute de jeu courante (âge du monde), ou nil.
local function gameMinute()
    local gt = getGameTime and getGameTime()
    if gt == nil then return nil end
    local h = gt:getWorldAgeHours()
    if not LivingKnox.Num.finite(h) or h < 0 then return nil end
    return math.floor(h * 60 + 0.5)
end

-- Évolution des plaies et régénération des corps reliés depuis le dernier passage (minutes manquées rattrapées, au plus
-- STEP_MAX) : formule commune au corps et à la simulation hors écran (Wounds.healthStep, LK_WoundsHealth.lua), santé
-- rapportée à hpMax. Santé gardée au millionième
-- (une minute de régénération ou de petit saignement vaut moins que le millième envoyé aux clients). Mort décidée par
-- Health.kill (cause « bleeding ») quand la référence atteint 0. Rend le nombre de PNJ qui ont encore des plaies.
local function round6(v) return math.floor(v * 1e6 + 0.5) / 1e6 end

local function woundPass(id, z, npc, steps)
    local list, ctx = woundsOf(npc), wctx()
    local full = fullOf(npc, z) or npc.hp
    local bleeding = Wounds.bleeding(list, ctx)
    local health, out = Wounds.healthStep(list, npc.hp / full, steps, ctx)
    Health.stats.healed = Health.stats.healed + #out.healed
    local hp = health * full
    saveWounds(npc, list)
    if hp < 0 then hp = 0 end
    local before = npc.hp
    npc.hp = round6(hp)
    if npc.hp <= 0 and hp > 0 then npc.hp = 0.000001 end
    LivingKnox.Store.markDirty()
    if round3(npc.hp) ~= round3(before) or #out.healed > 0 then touch(id) end   -- envoi seulement si visible
    if hp <= 0 then
        Health.stats.bleedDeaths = Health.stats.bleedDeaths + 1
        LivingKnox.Log.info("npc %s bled to death (%d wound(s), bleeding %.4f per hour)", id, #list, bleeding)
        Health.kill(id, z, nil, nil, "bleeding")
    elseif bleeding > 0 and Wounds.bleeding(list, ctx) <= 0 then
        Health.stats.bleedStops = Health.stats.bleedStops + 1
        LivingKnox.Log.info("npc %s stopped bleeding on its own, health %.3f", id, npc.hp)
    end
    return hp
end

function Health.bleedPass(minute)
    if not LivingKnox.isAuthority() or not LivingKnox.Store.isReady() then return 0 end
    minute = minute or gameMinute()
    if minute == nil then return 0 end
    local st = Health.state
    local last = st.bleedMinute
    st.bleedMinute = minute
    if last == nil or minute <= last then return 0 end
    local steps = math.min(minute - last, bcfg().STEP_MAX)
    local B = LivingKnox.Bodies
    if B == nil then return 0 end
    local ids = {}
    for id in pairs(B.bound) do ids[#ids + 1] = id end
    table.sort(ids)
    local left = 0
    for _, id in ipairs(ids) do
        local z = B.bound[id]
        local npc = npcOf(id)
        -- Corps mis de côté (chunk déchargé, encore dans Bodies.bound) : plaies suspendues (LK07-T04). Santé pleine
        -- sans plaie : rien à faire.
        if z ~= nil and B.inWorld(z) and npc ~= nil and npc.state == LivingKnox.Identity.STATE_EMBODIED
            and not Health.decided[id] and LivingKnox.Identity.validHealth(npc.hp)
            and (#woundsOf(npc) > 0 or npc.hp < (fullOf(npc, z) or npc.hp)) then
            if woundPass(id, z, npc, steps) > 0 and #woundsOf(npc) > 0 then left = left + 1 end
        end
    end
    return left
end

-- Soin connu de l'autorité (LK07-T03) : seule hausse de la référence, jusqu'à hpMax. Rend la nouvelle santé, ou nil.
function Health.noteHeal(id, amount)
    if not LivingKnox.isAuthority() or not LivingKnox.Num.finite(amount) or amount <= 0 then return nil end
    local npc = npcOf(id)
    if npc == nil or npc.state ~= LivingKnox.Identity.STATE_EMBODIED or Health.decided[id] then return nil end
    if not LivingKnox.Identity.validHealth(npc.hp) then return nil end
    local hp = npc.hp + amount
    local full = fullOf(npc, nil)
    if full ~= nil and hp > full then hp = full end
    if hp > LivingKnox.Identity.HP_MAX then hp = LivingKnox.Identity.HP_MAX end
    npc.hp = hp
    Health.stats.heals = Health.stats.heals + 1
    LivingKnox.Store.markDirty()
    touch(id)
    LivingKnox.Log.info("npc %s healed by %.3f: health %.3f", id, amount, hp)
    return hp
end

-- Saignement total réglé à target (fraction de hpMax par heure) sur les plaies de list (LK21-T02) : 0 arrête le
-- saignement de chaque plaie ; sinon les plaies qui saignent sont mises à l'échelle (chacune bornée à BLEED_LIMIT,
-- borne de la forme sauvegardée), ou une plaie ADMIN_KIND est posée sur ADMIN_PART si aucune ne saigne. Rend vrai, ou
-- nil et la raison.
local function adminBleeding(list, target, ctx)
    if target <= 0 then
        for _, w in ipairs(list) do w.bleed = 0 end
        return true
    end
    local current = Wounds.bleeding(list, ctx)
    if current > 0 then
        local k = target / current
        for _, w in ipairs(list) do
            if Wounds.woundBleeding(w, ctx) > 0 then w.bleed = math.min(Wounds.BLEED_LIMIT, w.bleed * k) end
        end
        return true
    end
    local w, why = Wounds.add(list, bcfg().ADMIN_PART, bcfg().ADMIN_KIND, ctx, { bleed = true })
    if w == nil then return nil, why end
    w.bleed = 1
    w.bleed = math.min(Wounds.BLEED_LIMIT, target / Wounds.woundBleeding(w, ctx))
    return true
end

-- Réglage d'un administrateur (LK13-T13, LK_Admin : bornes et droit contrôlés par l'appelant) : santé hp (]0,
-- HP_MAX], jamais une mort, qui ne passe que par Health.kill) ou saignement bleed (>= 0 ; 0 = arrêté ; réglé sur les
-- plaies, adminBleeding), PNJ incarné vivant seulement. Écrit à la fin de l'image (Store.markChanged), révision
-- envoyée aux clients proches. Rend vrai, ou nil et la raison.
function Health.setByAdmin(id, hp, bleed)
    if not LivingKnox.isAuthority() then return nil, "not the authority" end
    local npc = npcOf(id)
    if npc == nil or npc.state ~= LivingKnox.Identity.STATE_EMBODIED or Health.decided[id] then return nil, "npc not embodied" end
    if hp ~= nil then
        if not LivingKnox.Num.finite(hp) or hp <= 0 or hp > LivingKnox.Identity.HP_MAX then return nil, "bad health" end
        npc.hp = round3(hp)
        if npc.hp <= 0 then npc.hp = 0.001 end
    end
    if bleed ~= nil then
        if not LivingKnox.Num.finite(bleed) or bleed < 0 then return nil, "bad bleeding" end
        local list = woundsOf(npc)
        local ok, why = adminBleeding(list, bleed, wctx())
        if not ok then return nil, why end
        saveWounds(npc, list)
    end
    LivingKnox.Store.markChanged()
    touch(id)
    return true
end

-- ---------------------------------------------------------------- contrôle d'un coup

local function combat(key, default)
    local ok, v = pcall(function() return getCombatConfig():get(CombatConfigKey[key]) end)
    if ok and LivingKnox.Num.finite(v) then return v end
    return default
end

local function levelMult(level)
    level = math.max(0, math.min(10, level or 10))
    return combat("BASE_WEAPON_DAMAGE_MULTIPLIER", 0.3) + level * combat("WEAPON_LEVEL_DAMAGE_MULTIPLIER_INCREMENT", 0.1)
end

local function shoving(wielder)
    return isPlayer(wielder) and wielder:isDoShove() and not wielder:isAimAtFloor()
end

-- Solo : valeur de l'événement (avant processHitDamage) portée à l'échelle du serveur MP, coup de face supposé.
function Health.soloValue(wielder, weapon, damage)
    if weapon:isExplosive() then return damage end
    local v = damage * combat("NON_PLAYER_RECEIVED_DAMAGE_MULTIPLIER", 1.5) * levelMult(wielder:getWeaponLevel())
    local crit = weapon:getCriticalDamageMultiplier()
    if not LivingKnox.Num.finite(crit) then crit = 0 end
    if not weapon:isRanged() and wielder:isAimAtFloor() and not (isPlayer(wielder) and wielder:isDoShove()) then
        v = v * math.max(5, crit)
    end
    if wielder:isCriticalHit() then v = v * math.max(2, crit) end
    return v
end

-- Seau à jetons de l'attaquant name sur le PNJ id : vrai si un coup peut encore être pris.
local function take(name, id)
    local c = cfg()
    local key = tostring(name) .. "|" .. id
    local t = now()
    local b = Health.buckets[key]
    if b == nil then
        b = { tokens = c.BURST, ms = t }
        Health.buckets[key] = b
    end
    b.tokens = math.min(c.BURST, b.tokens + (t - b.ms) * c.RATE / 1000)
    b.ms = t
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

-- Contrôles réservés au serveur MP (attaquant joueur d'une connexion). Rend nil, ou la raison et un détail.
local function implausible(id, z, wielder, weapon)
    local c = cfg()
    if wielder:isDead() then return "attacker is dead" end
    if weapon:isExplosive() then
        local inv = wielder:getInventory()
        if inv ~= nil and inv:contains(weapon, true) then return "explosive still in the attacker's inventory" end
        return nil
    end
    local ranged = weapon:isRanged()
    if not ranged and wielder:getVehicle() ~= nil then return "melee from a vehicle" end
    local dx, dy = wielder:getX() - z:getX(), wielder:getY() - z:getY()
    local dist = math.sqrt(dx * dx + dy * dy)
    local reach = weapon:getMaxRange(wielder)
    if not LivingKnox.Num.finite(reach) or reach < 0 then reach = 0 end
    reach = reach + (ranged and c.RANGED_SLACK or c.MELEE_SLACK)
    if dist > reach then return "out of reach", string.format("%.1f squares, reach %.1f", dist, reach) end
    local dz = math.abs(wielder:getZ() - z:getZ())
    if dz > (ranged and c.RANGED_LEVELS or c.MELEE_LEVELS) then
        return "other level", string.format("%.2f levels", dz)
    end
    if not take(nameOf(wielder), id) then return "too many hits" end
    return nil
end

-- Dégâts de référence d'un coup sur le corps z du PNJ id. Rend le montant à retirer (0 : coup sans dégâts), ou nil et
-- la raison du refus. Valeur crue sans plafond tiré de l'arme (LK07-T06) ; refusée si elle n'est pas un nombre fini
-- (NaN, infini, chaîne) ou si elle est négative.
function Health.judge(id, z, wielder, weapon, damage)
    local name = nameOf(wielder)
    if weapon == nil or wielder == nil then return refuse(name, id, "bad damage", "no weapon or attacker") end
    if not LivingKnox.Num.finite(damage) or damage < 0 then return refuse(name, id, "bad damage", tostring(damage)) end
    if shoving(wielder) then
        Health.stats.shoves = Health.stats.shoves + 1
        return 0
    end
    if isServer() and isPlayer(wielder) then
        local bad, detail = implausible(id, z, wielder, weapon)
        if bad then return refuse(name, id, bad, detail) end
    end
    local v = isServer() and damage or Health.soloValue(wielder, weapon, damage)
    if weapon:isMelee() then v = v * combat("GLOBAL_MELEE_DAMAGE_REDUCTION_MULTIPLIER", 0.15) end
    return v
end

-- ---------------------------------------------------------------- dégâts et mort

-- Retire amount de la référence du PNJ id (corps z) ; coup non mortel : plaies faites par la source du coup (LK21-T02,
-- Wounds.fromHit). part : partie donnée par le moteur (OnHitZombie) ou texte libre ; opts (facultatif) : { source =
-- source nommée (verre brisé...), issue = issue déjà décidée (attaque de zombie, LK_Zombies), risk }. Mort décidée à
-- 0. Rend la santé restante.
function Health.applyHit(id, z, amount, part, wielder, weapon, opts)
    local npc = npcOf(id)
    if npc == nil or Health.decided[id] then return nil end
    if not LivingKnox.Identity.validHealth(npc.hp) then Health.bodyBound(id, z) end
    if not LivingKnox.Identity.validHealth(npc.hp) then return nil end
    if amount <= 0 then return npc.hp end
    if amount > npc.hp then amount = npc.hp end   -- borne : la santé restante (blessure notée à sa vraie valeur)
    local hp = npc.hp - amount
    if hp < 0 then hp = 0 end
    npc.hp = round3(hp)
    if npc.hp <= 0 and hp > 0 then npc.hp = 0.001 end   -- arrondi : jamais une mort que le calcul n'a pas faite
    if hp > 0 then
        woundFrom(id, npc, { attacker = wielder, weapon = weapon, damage = amount, part = part,
            source = opts and opts.source, issue = opts and opts.issue, risk = opts and opts.risk })
    end
    Health.stats.applied = Health.stats.applied + 1
    LivingKnox.Store.markDirty()
    touch(id)
    LivingKnox.Log.debug("npc %s hit by %s with %s: %.3f, health %.3f", id, nameOf(wielder),
        weapon and tostring(weapon:getFullType()) or "nothing", amount, npc.hp)
    if hp <= 0 then Health.kill(id, z, wielder, weapon) end
    local De = LivingKnox.Decisions   -- LK06-T05 : coup reçu (danger, reddition rompue, appel à l'aide)
    if De ~= nil and De.noteHit ~= nil then De.noteHit(id, z, wielder) end
    return npc.hp
end

-- Cause décidée par l'autorité avec la mort (LK07-T04) : "bleeding" (perte de sang), "zombie" (attaquant zombie
-- vanilla), ou nil (Bodies.deathCause applique alors sa règle). Lue par Bodies.deathCause, effacée à la mort du corps.
Health.causes = Health.causes or {}

local function isZombieAttacker(o)
    return o ~= nil and instanceof(o, "IsoZombie") and not isPlayer(o)
end

-- Cause décidée pour le PNJ id (mort en cours), ou nil.
function Health.causeOf(id)
    return Health.causes[id]
end

-- Mort décidée par l'autorité, une seule fois, quel que soit le chemin (coup de joueur, zombie, saignement, appel
-- direct : seul point d'entrée d'une mort voulue, LK07-T04). z : corps courant (nil : Bodies.bound). cause :
-- facultative ("bleeding"...), "zombie" déduit d'un attaquant zombie. Le corps doit être dans le monde : un corps mis
-- de côté (chunk déchargé) ne ferait aucun cadavre utile (case absente) et resterait dans reanimated.bin.
-- Rend vrai si elle vient d'être décidée, sinon faux et la raison.
function Health.kill(id, z, wielder, weapon, cause)
    if Health.decided[id] then return false, "death already decided" end
    local npc = npcOf(id)
    if npc == nil or npc.state ~= LivingKnox.Identity.STATE_EMBODIED then return false, "npc not embodied" end
    local B = LivingKnox.Bodies
    if z == nil and B ~= nil then z = B.bound[id] end
    if z == nil or B == nil or not rawequal(B.bound[id], z) or not B.inWorld(z) then
        return false, "body not in the world"
    end
    if cause == nil and isZombieAttacker(wielder) then cause = "zombie" end
    Health.decided[id] = true
    Health.causes[id] = cause
    npc.hp = 0
    clearWounds(npc)
    touch(id)
    Health.stats.deaths = Health.stats.deaths + 1
    if isServer() then Health.flush(id, z) end   -- santé nulle aux destinataires avant le paquet de mort
    LivingKnox.Log.info("npc %s: reference health 0, death decided by the authority (%s, %s%s)", id, nameOf(wielder),
        weapon and tostring(weapon:getFullType()) or "no weapon", cause and (", " .. cause) or "")
    Health.makeMortal(z)
    if z:isFakeDead() then z:setFakeDead(false) end   -- un cadavre faux mort se relèverait (sante.md, section 5)
    if isServer() or weapon == nil or wielder == nil then
        -- Sans attaquant (saignement, appel direct) : l'attaquant d'un ancien coup n'est pas le tueur.
        z:setAttackedBy(wielder)
        z:die()
    else
        z:Kill(weapon, wielder)
    end
    return true
end

-- Mort du corps courant du PNJ id (appelé par Bodies.onZombieDead, une fois par corps). Mort non décidée ici :
-- signalée, puis menée à son terme (santé vanilla à 0).
function Health.onBodyDied(id, z)
    local decided = Health.decided[id]
    Health.decided[id] = nil
    Health.causes[id] = nil
    Health.parts[id] = nil
    local npc = npcOf(id)
    local before = npc and npc.hp
    if npc ~= nil then
        npc.hp = 0
        clearWounds(npc)
    end
    touch(id)
    if decided then return true end
    Health.stats.engineDeaths = Health.stats.engineDeaths + 1
    LivingKnox.Log.warn("npc %s died without a decision of the authority (engine death, reference health was %s)", id,
        LivingKnox.Num.finite(before) and string.format("%.3f", before) or "unknown")
    if z ~= nil then
        Health.makeMortal(z)
        if z:getHealth() > 0 then z:setHealth(0) end
    end
    return false
end

-- ---------------------------------------------------------------- événements

-- OnHitZombie (autorité) : partie du corps tirée par cette machine, gardée pour le coup qui suit.
function Health.onHitZombie(z, _, part)
    if not LivingKnox.isAuthority() then return end
    local id = Health.currentId(z)
    if id then Health.parts[id] = part ~= nil and tostring(part) or nil end
end

-- OnWeaponHitCharacter (autorité). Rend la santé restante, ou nil.
function Health.onWeaponHit(wielder, target, weapon, damage)
    if not LivingKnox.isAuthority() then return nil end
    local id = Health.currentId(target)
    if id == nil then return nil end
    Health.stats.hits = Health.stats.hits + 1
    local part = Health.parts[id]
    Health.parts[id] = nil
    if Health.decided[id] then
        Health.stats.ignored = Health.stats.ignored + 1
        return nil
    end
    local amount = Health.judge(id, target, wielder, weapon, damage)
    if amount == nil then return nil end
    return Health.applyHit(id, target, amount, part, wielder, weapon)
end

-- ---------------------------------------------------------------- retransmission (serveur MP)

local function wire(id)
    local npc = npcOf(id)
    if npc == nil or not LivingKnox.Identity.validHealth(npc.hp) then return nil end
    return { r = Health.rev[id], hp = round3(npc.hp), mx = npc.hpMax and round3(npc.hpMax) or nil,
        w = #woundsOf(npc) }
end

local function sendBatch(batch)
    for name, b in pairs(batch) do
        sendServerCommand(b.player, Health.MODULE, Health.CMD, { d = b.d })
        Health.stats.messages = Health.stats.messages + 1
        local s = Health.sent[name]
        if s == nil then
            s = {}
            Health.sent[name] = s
        end
        for id, e in pairs(b.d) do s[id] = e.r end
    end
end

local function collect(batch, id, z)
    local Dir = LivingKnox.Directives
    if Dir == nil or Dir.targets == nil or Health.rev[id] == nil then return end
    local targets = Dir.targets(z)
    local e = nil
    for name, p in pairs(targets) do
        local s = Health.sent[name]
        if s == nil or s[id] ~= Health.rev[id] then
            e = e or wire(id)
            if e == nil then return end
            local b = batch[name]
            if b == nil then
                b = { player = p, d = {} }
                batch[name] = b
            end
            b.d[id] = e
        end
    end
end

-- Envoie tout de suite la santé du PNJ id aux destinataires qui ne l'ont pas (mort décidée).
function Health.flush(id, z)
    if not isServer() or z == nil then return end
    local batch = {}
    collect(batch, id, z)
    sendBatch(batch)
end

-- Passage d'envoi : corps reliés dans le monde, destinataires sans la révision courante. Rend le nombre de messages.
function Health.sendPass()
    if not isServer() then return 0 end
    local B = LivingKnox.Bodies
    if B == nil then return 0 end
    local batch = {}
    for id, z in pairs(B.bound) do
        if z ~= nil and B.inWorld(z) then collect(batch, id, z) end
    end
    local before = Health.stats.messages
    sendBatch(batch)
    return Health.stats.messages - before
end

-- Entrée en partie d'un client ("guardHello") : tout lui est renvoyé au prochain passage.
function Health.onHello(player)
    local Dir = LivingKnox.Directives
    local name = Dir and Dir.senderName and Dir.senderName(player) or nameOf(player)
    Health.sent[name] = nil
end

-- OnTick (autorité) : invulnérabilité des corps reliés toutes les APPLY_EVERY images ; envoi (serveur).
function Health.tick()
    local st = Health.state
    st.ticks = st.ticks + 1
    if st.ticks >= cfg().APPLY_EVERY then
        st.ticks = 0
        local B = LivingKnox.Bodies
        if B ~= nil and getCell() ~= nil then
            for id, z in pairs(B.bound) do
                if z ~= nil and not z:isDead() and not Health.decided[id] then Health.protect(z) end
            end
        end
    end
    if isServer() then
        local t = now()
        if st.sendMs == nil or t - st.sendMs >= cfg().SEND_MS then
            st.sendMs = t
            Health.sendPass()
        end
    end
end

local function onTick()
    LivingKnox.Health.tick()
end

local function onEveryOneMinute()
    if LivingKnox.isAuthority() then LivingKnox.Health.bleedPass() end
end

local function onHitZombie(zombie, wielder, part, weapon)
    LivingKnox.Health.onHitZombie(zombie, wielder, part, weapon)
end

local function onWeaponHitCharacter(wielder, target, weapon, damage)
    LivingKnox.Health.onWeaponHit(wielder, target, weapon, damage)
end

LivingKnox.subscribe("OnTick", "Health.tick", onTick)
LivingKnox.subscribe("EveryOneMinute", "Health.bleedPass", onEveryOneMinute)   -- LK07-T03
LivingKnox.subscribe("OnHitZombie", "Health.onHitZombie", onHitZombie)
LivingKnox.subscribe("OnWeaponHitCharacter", "Health.onWeaponHit", onWeaponHitCharacter)

if isServer() then
    local function onClientCommand(module, command, player, args)
        if module == Health.MODULE and command == LivingKnox.ZombieGuard.CMD_HELLO and player ~= nil
            and LivingKnox.ZombieGuard.helloAllowed(player, "Health") then
            LivingKnox.Health.onHello(player)
        end
    end
    require "LivingKnox/LK_ZombieGuard"
    LivingKnox.subscribe("OnClientCommand", "Health.onClientCommand", onClientCommand)
end

-- LK16-T04 : mort du corps courant publiée par LK_Bodies ("bodyDying"), avant le butin de LK_Loot (order 20).
LivingKnox.listen("bodyDying", "Health.onBodyDied", function(info)
    local H = LivingKnox.Health
    if H ~= nil and H.onBodyDied ~= nil then H.onBodyDied(info.npc, info.body) end
end, 10)

return Health
