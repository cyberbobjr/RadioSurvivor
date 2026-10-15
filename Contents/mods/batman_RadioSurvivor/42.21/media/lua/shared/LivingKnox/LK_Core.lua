-- Living Knox : espace de noms global unique du moteur de PNJ.
-- Chaque module range ses fonctions dans sa table (LivingKnox.Config, LivingKnox.Log...) et les appelle par
-- cette table : un autre mod peut ainsi les envelopper. Aucun effet de bord au chargement hors définitions.
LivingKnox = LivingKnox or {}
local LK = LivingKnox

LK.VERSION = "0.1.0"
LK.TAG = "[LivingKnox]"
LK.OPTION_PAGE = "LivingKnox"

LK.SIDE_SERVER = "server"
LK.SIDE_CLIENT = "client"
LK.SIDE_SOLO = "solo"

-- Côté d'exécution : "server" (serveur dédié ou hébergé), "client" (client MP) ou "solo".
function LK.side()
    if isServer() then return LK.SIDE_SERVER end
    if isClient() then return LK.SIDE_CLIENT end
    return LK.SIDE_SOLO
end

-- Vrai là où se prennent les décisions persistantes : serveur MP ou solo.
function LK.isAuthority()
    return not isClient()
end

-- Vrai là où tournent l'interface et le joueur local : client MP ou solo.
function LK.hasLocalPlayer()
    return not isServer()
end

-- Inscription idempotente à un événement : un rechargement du fichier remplace l'abonné précédent au lieu
-- d'en ajouter un second (Events.X.Add ne dédoublonne pas). key identifie l'abonné dans tout le moteur.
LK.handlers = LK.handlers or {}
-- LK13-T12 : rang du dernier Add de chaque abonné (ordre réel de la liste de son événement, Event.java : Add en fin
-- de liste). Lu par la mesure de charge (LK_Load) pour remettre ses enveloppes dans le même ordre.
LK.handlerSeq = LK.handlerSeq or {}
LK.handlerSeqN = LK.handlerSeqN or 0

function LK.markAdded(slot)
    LK.handlerSeqN = LK.handlerSeqN + 1
    LK.handlerSeq[slot] = LK.handlerSeqN
end

function LK.subscribe(eventName, key, fn)
    local event = Events[eventName]
    if not event then return false end
    local slot = eventName .. "/" .. key
    local previous = LK.handlers[slot]
    if previous then event.Remove(previous) end
    event.Add(fn)
    LK.handlers[slot] = fn
    LK.markAdded(slot)
    return true
end

-- LK13-T12 : remet en fin de liste de son événement l'abonné inscrit sous (eventName, key) s'il est encore fn, ou
-- l'enveloppe de mesure de fn (LK_Load) : avec ou sans mesure, la même place. Jamais depuis un déclenchement du même
-- événement (l'abonné rajouté serait appelé aussitôt, base kahlua-lua.md). Rend true si l'abonné a été déplacé.
function LK.requeue(eventName, key, fn)
    local event = Events ~= nil and Events[eventName] or nil
    local slot = eventName .. "/" .. key
    local cur = LK.handlers[slot]
    if event == nil or cur == nil then return false end
    if cur ~= fn then
        local w = LK.Load ~= nil and LK.Load.wrapped ~= nil and LK.Load.wrapped[slot] or nil
        if w == nil or w.wrapper ~= cur or w.fn ~= fn then return false end
    end
    event.Remove(cur)
    event.Add(cur)
    LK.markAdded(slot)
    return true
end

-- Faits du moteur publiés aux autres modules (E08-T07, avant les événements publics de LK12-T02). Le moteur publie,
-- un consommateur s'abonne (RS_Carnet_Server) : aucune dépendance du moteur vers lui. LK.listen(name, key, fn) est
-- idempotent par clé (un rechargement remplace l'abonné) ; LK.publish(name, info) appelle les abonnés dans l'ordre
-- d'inscription, chacun sous pcall (une erreur est journalisée et n'arrête ni le moteur ni les suivants). info est
-- une table propre à l'autorité (peut contenir un objet du moteur) : jamais à envoyer telle quelle à un client.
-- Noms publiés : "memberDied" (LK_Bodies, LK_Groups.applyDeath), "npcDied" (LK_Bodies, LK07-T04), "assaultSeen"
-- (LK_Hostility.record), "groupCreated", "memberLeft", "groupRemoved" (LK_Groups), "encounterStarted"
-- (LK_Encounters), "aidDecided", "revengeSworn", "revengeStarted", "revengeEnded" (LK_Relations), "raidScouting",
-- "raidAnnounced", "raidLaunched", "raidEnded" (LK_Raids, LK11-T07), "memberHit" (LK_Bodies, E09-T06) ; LK12-T02 relaie
-- les sept premiers en événements Lua publics (LK_API). Champs dans
-- docs/api.md, section « Faits publiés ».
LK.listeners = LK.listeners or {}

function LK.listen(name, key, fn)
    local list = LK.listeners[name]
    if not list then
        list = {}
        LK.listeners[name] = list
    end
    for _, entry in ipairs(list) do
        if entry.key == key then
            entry.fn = fn
            return true
        end
    end
    list[#list + 1] = { key = key, fn = fn }
    return true
end

function LK.publish(name, info)
    local list = LK.listeners[name]
    if not list then return 0 end
    local called = 0
    for _, entry in ipairs(list) do
        local ok, err = pcall(entry.fn, info)
        if ok then
            called = called + 1
        elseif LK.Log then
            LK.Log.error("listener %s of %s failed: %s", tostring(entry.key), tostring(name), tostring(err))
        else
            print(LK.TAG .. " listener " .. tostring(entry.key) .. " of " .. tostring(name) .. " failed: "
                .. tostring(err))
        end
    end
    return called
end

return LK
