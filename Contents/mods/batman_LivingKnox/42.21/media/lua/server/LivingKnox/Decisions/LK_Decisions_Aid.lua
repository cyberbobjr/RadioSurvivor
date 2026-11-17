-- Living Knox : cadre de décision des PNJ, coups reçus, appel à l'aide et reddition (LK06-T05, LK06-T12).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- ================================================================ LK06-T05 : coups reçus, aide, reddition (autorité)

-- Tables de mémoire créées à la demande (Decisions.reset les vide toutes) : hits (npcId -> dernier coup reçu), help
-- (gid -> demande d'aide), surrenders (gid -> { [compte] = { npc, since, last (reddition revue), seen (joueur perçu à
-- SURRENDER.KEEP cases) } }), betrayed (gid -> { [compte] =
-- minute de la rupture }).
local function bucket(name)
    local st = Decisions.state
    st[name] = st[name] or {}
    return st[name]
end

local function playerName(p)
    if p == nil or p.getUsername == nil then return nil end
    return tostring(p:getUsername())
end

-- Groupe et membre vivant du PNJ id (état de la cascade, sinon registre) : gid, mid, g, m ; ou nil.
local function memberOf(id)
    local G = LivingKnox.Groups
    local data = G ~= nil and G.isReady() and G.state.data or nil
    if data == nil then return nil end
    local s = Decisions.state.members[id]
    if s ~= nil and s.gid ~= nil then
        local g = data.groups[s.gid]
        local m = g and g.members[s.mid] or nil
        if m ~= nil and m.npc == id and m.alive then return s.gid, s.mid, g, m end
    end
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids)
    for _, gid in ipairs(ids) do
        local g = data.groups[gid]
        for mid, m in pairs(g.members) do
            if m.npc == id and m.alive then return gid, mid, g, m end
        end
    end
    return nil
end

-- Vrai si le groupe gid épargne le joueur de compte u : un de ses membres s'est rendu à lui (reddition en cours,
-- revue il y a SURRENDER.LINGER minutes au plus) et le joueur n'a plus frappé depuis (sinon la reddition est rompue).
function Decisions.spared(gid, u, minute)
    local per = bucket("surrenders")[gid]
    local s = per and u and per[u] or nil
    if s == nil or minute == nil then return false end
    return minute - s.last <= P.cfg().SURRENDER.LINGER
end

-- Demande d'aide en cours du groupe gid qui concerne un membre en (x, y, z) : même niveau que la victime, à
-- HELP.RADIUS cases au plus d'elle, posée il y a HELP.MINUTES minutes au plus. Rend la demande (table interne) ou nil.
function Decisions.helpFor(gid, x, y, z, minute)
    local h = bucket("help")[gid]
    if h == nil or minute == nil then return nil end
    local c = P.cfg().HELP
    if minute < h.minute or minute - h.minute > c.MINUTES then return nil end
    if h.oz ~= z or LivingKnox.Geo.cheb(x, y, h.ox + 0.5, h.oy + 0.5) > Decisions.helpRadius() then return nil end
    return h
end

-- Appel à l'aide du membre m (mid, corps body) du groupe gid contre l'agresseur rec = { kind = "player" | "zombie",
-- u (compte), key, zombie (objet), x, y, z } : demande d'aide posée (renfort des combattants proches), alerte du
-- groupe (LK_Alert : cri si l'alerte est nouvelle ou plus grave). Rend la demande.
function Decisions.callHelp(gid, g, mid, m, body, rec, minute, why)
    local label = rec.kind == "zombie" and ("zombie " .. tostring(rec.key)) or ("player " .. tostring(rec.u))
    local h = { npc = m.npc, mid = mid, kind = rec.kind, u = rec.u, key = rec.key, zombie = rec.zombie, x = rec.x,
        y = rec.y, z = rec.z, ox = math.floor(body:getX()), oy = math.floor(body:getY()), oz = math.floor(body:getZ()),
        minute = minute, why = why }
    bucket("help")[gid] = h
    Decisions.stats.helpCalls = Decisions.stats.helpCalls + 1
    LivingKnox.Log.info("group %s: npc %s (%s) calls for help against %s at %d,%d,%d (%s)", gid, tostring(m.npc), mid, label,
        h.x, h.y, h.z, tostring(why))
    local A = LivingKnox.Alert
    if A ~= nil and A.raise ~= nil then
        local female = m.female
        if female == nil and body.isFemale ~= nil then female = body:isFemale() end
        local dx, dy = h.x + 0.5 - body:getX(), h.y + 0.5 - body:getY()
        local t = { kind = rec.kind == "zombie" and "zombie" or "hostile",
            key = "help:" .. (rec.kind == "zombie" and tostring(rec.key) or ("p:" .. tostring(rec.u))),
            label = rec.kind == "zombie" and tostring(rec.key) or tostring(rec.u), x = h.x, y = h.y, z = h.z,
            d = math.floor(math.sqrt(dx * dx + dy * dy) * 10 + 0.5) / 10, seen = true }
        A.raise(gid, t, { npc = m.npc, mid = mid, x = body:getX(), y = body:getY(), z = h.oz,
            female = female == true }, body, minute, g.home, "called by")
    end
    return h
end

-- Coup accepté sur le PNJ id (corps body) par wielder (joueur ou zombie vanilla), appelé par LivingKnox.Health.applyHit
-- (autorité). Note le coup (danger, reddition), rompt une reddition du groupe envers ce joueur, appelle à l'aide.
-- Rend vrai si le coup est noté.
function Decisions.noteHit(id, body, wielder)
    if not LivingKnox.isAuthority() or wielder == nil or body == nil then return false end
    local minute = Decisions.currentMinute()
    if minute == nil then return false end
    local gid, mid, g, m = memberOf(id)
    if gid == nil then return false end
    local rec = { minute = minute, x = math.floor(wielder:getX()), y = math.floor(wielder:getY()),
        z = math.floor(wielder:getZ()) }
    if instanceof(wielder, "IsoPlayer") then
        rec.kind, rec.u = "player", playerName(wielder)
        if rec.u == nil then return false end
    elseif instanceof(wielder, "IsoZombie") then
        local Zm = LivingKnox.Zombies
        rec.kind, rec.zombie = "zombie", wielder
        rec.key = Zm ~= nil and Zm.keyOf ~= nil and Zm.keyOf(wielder) or "z?"
    else
        return false
    end
    bucket("hits")[id] = rec
    Decisions.stats.hitsNoted = Decisions.stats.hitsNoted + 1
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then Ac.note(gid, mid, "combat", "hit by " .. rec.kind .. " " .. tostring(rec.u or rec.key), id) end
    if rec.kind == "player" then
        local per = bucket("surrenders")[gid]
        local s = per and per[rec.u] or nil
        if s ~= nil then
            per[rec.u] = nil
            local b = bucket("betrayed")
            b[gid] = b[gid] or {}
            b[gid][rec.u] = minute
            Decisions.stats.surrenderBroken = Decisions.stats.surrenderBroken + 1
            LivingKnox.Log.info("group %s: %s hit npc %s after npc %s surrendered: surrender broken", gid, rec.u, id, s.npc)
            Decisions.setAlertGesture(s.npc, nil)   -- LK06-T12 : mains baissées sans attendre la décision suivante
            Decisions.announceSurrender(s.npc, "betrayed", minute)
        end
    end
    Decisions.callHelp(gid, g, mid, m, body, rec, minute, "hit")
    return true
end

-- Cible de renfort d'un combattant (contexte ctx, PNJ npc) pour la demande h : zombie vanilla encore là, même
-- niveau ; joueur présent, vivant, ni couvert (trêve, LK_Hostility.isCovered) ni épargné (reddition). Rend la cible
-- au format de Combat.targetFor (raison "help") ou nil.
function Decisions.helpTarget(gid, npc, h, ctx, players, minute)
    local tx, ty, out
    if h.kind == "zombie" then
        local z, Zm = h.zombie, LivingKnox.Zombies
        if z == nil or Zm == nil or not Zm.isVanilla(z) or not Zm.inWorld(z) then return nil end
        if math.floor(z:getZ()) ~= ctx.z then return nil end
        tx, ty = z:getX(), z:getY()
        out = { kind = "zombie", u = h.key, reason = "help", zombie = z }
    else
        if Decisions.spared(gid, h.u, minute) then return nil end
        local p = nil
        for _, q in ipairs(players or {}) do
            if playerName(q) == h.u then p = q end
        end
        if p == nil or p:isDead() then return nil end
        local Ho = LivingKnox.Hostility
        local key = Ho ~= nil and Ho.keyOf ~= nil and Ho.keyOf(p) or nil
        if key ~= nil and Ho.isCovered ~= nil and Ho.isCovered(gid, key, npc) then return nil end
        tx, ty = p:getX(), p:getY()
        out = { u = h.u, reason = "help" }
    end
    local dx, dy = tx - ctx.x, ty - ctx.y
    out.d = math.floor(math.sqrt(dx * dx + dy * dy) * 10 + 0.5) / 10
    Decisions.stats.helpTargets = Decisions.stats.helpTargets + 1
    return out
end

-- Entrées LK06-T05 du contexte : moral du groupe, coup reçu récent, joueurs perçus, reddition possible, en cours ou
-- refusée (trahison), cible épargnée (reddition), cible de renfort (demande d'aide du groupe).
function Decisions.defenceContext(ctx, gid, g, m, per, players, minute)
    ctx.morale = g.morale
    local hit = bucket("hits")[m.npc]
    if hit ~= nil and minute >= hit.minute and minute - hit.minute <= P.cfg().HIT_MINUTES then ctx.hit = hit end
    local seen = {}
    if per ~= nil and not per.stale then
        for _, e in ipairs(per.p or {}) do
            if (e.s or e.h) and seen[e.u] == nil then seen[e.u] = { x = e.x, y = e.y, z = e.z, d = e.d or 0 } end
        end
    end
    ctx.seen = seen
    local Ho = LivingKnox.Hostility
    ctx.canSurrender = not ctx.combatant and Ho ~= nil and Ho.firstStrike ~= nil and not Ho.firstStrike(g.type)
    local mine = Decisions.state.members[m.npc]
    local sur = bucket("surrenders")[gid]
    local cur = mine ~= nil and mine.b == "surrender" and sur ~= nil and sur[mine.u] or nil
    if cur ~= nil and cur.npc == m.npc then ctx.surrendered = { u = mine.u, last = cur.seen } end
    local betrayed = {}
    for u, at in pairs(bucket("betrayed")[gid] or {}) do
        if minute - at <= P.cfg().SURRENDER.BETRAYED then betrayed[u] = true end
    end
    ctx.betrayed = betrayed
    local tg = ctx.target
    if tg ~= nil and tg.kind ~= "zombie" and Decisions.spared(gid, tg.u, minute) then
        Decisions.stats.spared = Decisions.stats.spared + 1
        ctx.target = nil
        local Zm = LivingKnox.Zombies
        if Zm ~= nil and Zm.targetFor ~= nil then ctx.target = Zm.targetFor(m.npc) end
    end
    if ctx.target == nil then
        local h = Decisions.helpFor(gid, ctx.x, ctx.y, ctx.z, minute)
        -- LK06-T07 : tout membre vient en renfort contre un zombie ; contre un joueur, les seuls combattants.
        if h ~= nil and (ctx.combatant or h.kind == "zombie") then
            ctx.help = h
            ctx.target = Decisions.helpTarget(gid, m.npc, h, ctx, players, minute)
        end
    end
end

-- Suites d'une décision (evaluate) : reddition notée pour le groupe (ou close), retraite comptée ; un combattant qui
-- se retire passe sa cible aux autres (demande d'aide).
local function afterDecision(gid, g, mid, m, body, st, prev, ctx, fresh, minute)
    local id = m.npc
    local sur = bucket("surrenders")
    if prev ~= nil and prev.b == "surrender" and (st.b ~= "surrender" or st.u ~= prev.u) then
        local per = sur[gid]
        if per ~= nil and per[prev.u] ~= nil and per[prev.u].npc == id then per[prev.u] = nil end
        LivingKnox.Log.info("npc %s (%s %s): surrender to %s over", id, gid, mid, tostring(prev.u))
    end
    if st.b == "surrender" and st.u ~= nil then
        sur[gid] = sur[gid] or {}
        local s = sur[gid][st.u]
        if s == nil or s.npc ~= id then
            sur[gid][st.u] = { npc = id, since = minute, last = minute, seen = minute }
            Decisions.stats.surrenders = Decisions.stats.surrenders + 1
            LivingKnox.Log.info("npc %s (%s %s) surrenders to %s: %s", id, gid, mid, st.u, tostring(st.why))
            Decisions.announceSurrender(id, "surrender", minute)   -- LK06-T12 : une seule réplique par reddition
        else
            s.last = minute   -- reddition revue (validité de Decisions.spared)
            local e = (ctx.seen or {})[st.u]
            if e ~= nil and e.d <= P.cfg().SURRENDER.KEEP then s.seen = minute end   -- joueur encore perçu
        end
    end
    if fresh and st.b == "retreat" then
        Decisions.stats.retreats = Decisions.stats.retreats + 1
        LivingKnox.Log.info("npc %s (%s %s) retreats: %s", id, gid, mid, tostring(st.why))
        local tg = ctx.target
        if tg ~= nil then
            local rec
            if tg.kind == "zombie" and tg.zombie ~= nil then
                local z = tg.zombie
                rec = { kind = "zombie", key = tg.u, zombie = z, x = math.floor(z:getX()), y = math.floor(z:getY()),
                    z = math.floor(z:getZ()) }
            elseif tg.kind ~= "zombie" then
                local e = (ctx.seen or {})[tg.u]
                local p = Decisions.findPlayer(tg.u)
                local x, y, z = e and e.x, e and e.y, e and e.z
                if p ~= nil then x, y, z = p:getX(), p:getY(), p:getZ() end
                if x ~= nil then
                    rec = { kind = "player", u = tg.u, x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
                end
            end
            if rec ~= nil then Decisions.callHelp(gid, g, mid, m, body, rec, minute, "retreat") end
        end
    end
end

-- LK06-T12 (fiche docs/annexes/conception/fuite-reddition.md, « Reddition visible ») : réplique de gabarit du PNJ id, traduite
-- par chaque client (LivingKnox.Speech.say, clé IGUI_LK_Surrender_<n> à l'entrée en reddition, appelée une fois par
-- afterDecision à la création de la reddition ; IGUI_LK_Surrender_Betrayed_<n> quand le joueur la rompt, noteHit).
-- Variante tirée de (PNJ, minute) : reproductible, sans LLM. Personne à portée : journal debug seul, rien n'est redit.
-- Rend l'identifiant de la réplique, ou nil et la raison.
Decisions.SURRENDER_GESTURE = "surrender"
Decisions.SURRENDER_KEY = "IGUI_LK_Surrender_"
Decisions.SURRENDER_LINES = { surrender = { prefix = "", n = 4, salt = 1201, stat = "surrenderLines" },
    betrayed = { prefix = "Betrayed_", n = 2, salt = 1202, stat = "betrayalLines" } }
function Decisions.announceSurrender(id, kind, minute)
    local c = Decisions.SURRENDER_LINES[kind]
    local Sp = LivingKnox.Speech
    if c == nil or id == nil then return nil, "bad line" end
    if Sp == nil or Sp.say == nil then return nil, "speech not loaded" end
    local key = Decisions.SURRENDER_KEY .. c.prefix .. P.pick(1, c.n, Decisions.stream(id, minute or 0, c.salt))
    local out, why = Sp.say(id, { key = key })
    if out == nil then
        LivingKnox.Log.debug("npc %s: %s line not heard: %s", id, kind, tostring(why))
        return nil, why
    end
    Decisions.stats[c.stat] = Decisions.stats[c.stat] + 1
    LivingKnox.Log.info("npc %s says %s (%s)", id, key, kind)
    return out.id
end

-- Joueur de compte name (serveur : connectés ; solo : locaux), ou nil (LivingKnox.Combat.playerByName).
function Decisions.findPlayer(name)
    local C = LivingKnox.Combat
    if C ~= nil and C.playerByName ~= nil then return C.playerByName(name) end
    return nil
end

P.afterDecision = afterDecision
P.bucket = bucket
