'use strict';
// Démonstrations locales : aucune connexion au jeu, au serveur ou à un LLM.
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
function pressed(selector, selected) {
  $$(selector).forEach(button => {
    const active = button === selected;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  });
}
const voices = [
  ['Walt', 'Le confident · bois de l’Indiana', '« Si tu m’entends, baisse la lumière. Et raconte-moi ce qui se passe chez toi. »', 'Conseils, nouvelles du dehors et relais vers les autres contacts.'],
  ['L’infirmière', 'Une clinique dans la zone', '« Il me reste deux blessés et presque plus de pansements. Tu peux revenir avant la nuit ? »', 'Conseils de soins et demandes de médicaments sous forme de missions.'],
  ['Le déserteur', 'Mobile · toujours en fuite', '« Ne prends pas cette route. J’ai vu une patrouille. Et ne répète pas mon nom. »', 'Informations sur le cordon et les patrouilles ; une voix méfiante.'],
  ['La famille', 'Un bâtiment réel · un appel à l’aide', '« L’église en briques, en face de la station-service. On voit encore la route depuis les volets. »', 'Un secours guidé par des indices, des réserves et des conversations pendant le trajet.'],
  ['Le chroniqueur', 'Station pirate · bulletin du soir', '« Ce soir, on se souvient de ceux qui ont aidé. Et de ceux qui ne répondront plus. »', 'Chronique des faits confirmés du serveur et mémorial des personnages disparus.'],
  ['Le passeur', 'Rive de l’Indiana · une fois par semaine', '« Des piles, oui. Des promesses, non. Dis-moi ce que tu as trouvé, et on parle affaires. »', 'Négociation de troc et rendez-vous sur la berge, dans les limites des stocks et prix du serveur.']
];
$$('[data-voice]').forEach(button => button.addEventListener('click', () => {
  pressed('[data-voice]', button);
  const [name, role, line, use] = voices[Number(button.dataset.voice)];
  $('#voice-name').textContent = name; $('#voice-role').textContent = role;
  $('#voice-line').textContent = line; $('#voice-use').textContent = use;
}));
const situations = [
  ['Confiance : réservée', 'Une voix devant les barricades.', 'Mara vous écoute, sans vous ouvrir toutes les portes. Votre réputation peut orienter son premier jugement, mais ne remplace pas votre relation personnelle.', '« Pose ton sac. Dis-moi ce que tu cherches. »'],
  ['Confiance : en hausse ↗', 'Vous êtes revenu avec les fournitures.', 'La livraison est un fait validé. Mara peut revoir son attitude selon sa personnalité ; le résultat de mission contribue séparément à la réputation globale de votre personnage.', '« Tu es revenu. Je vais me souvenir de ça. »'],
  ['Trêve : décision à venir', 'Un membre du groupe ouvre le feu.', 'Les PNJ se défendent immédiatement contre l’agresseur. Le LLM décide ensuite du maintien, d’une réparation ou de la rupture de la trêve, avec validation serveur. Pas de rupture automatique avec toute la faction.', '« Reculez. On parlera de votre accord quand il aura baissé son arme. »']
];
$$('[data-situation]').forEach(button => button.addEventListener('click', () => {
  pressed('[data-situation]', button);
  ['#situation-level', '#situation-title', '#situation-body', '#situation-line'].forEach((selector, i) => {
    $(selector).textContent = situations[Number(button.dataset.situation)][i];
  });
  const index = Number(button.dataset.situation);
  $('#scene-dialogue').firstChild.textContent = situations[index][3];
}));
const contacts = [
  ['Mara Bennett', 'Confiance : confiante ↗', 'Pragmatique, protectrice. Se souvient de votre aide au refuge.', 'Trêve active · aucune alliance', '« Les pansements ont fait la différence. »'],
  ['Elias Ward', 'Confiance : réservée →', 'Chef prudent. Négocie les décisions de sa bande ; ses membres gardent leur propre avis.', 'Trêve active · aucune alliance', '« Votre négociatrice peut venir parler. »'],
  ['June Carter', 'Confiance : méfiante →', 'Indépendante. A quitté son groupe, en conservant ses souvenirs et ses trêves.', 'Trêve conservée · indépendante', '« Je pars seule. Notre accord tient toujours. »']
];
let contactIndex = 0;
const memoryNotes = {};
function noteKey() { return `RadioSurvivor.presentation.note.${contactIndex}`; }
function readNote() {
  try { return localStorage.getItem(noteKey()) || memoryNotes[noteKey()] || ''; }
  catch { return memoryNotes[noteKey()] || ''; }
}
function selectContact(button) {
  contactIndex = Number(button.dataset.contact);
  $$('[data-contact]').forEach(item => {item.classList.toggle('active', item === button);item.setAttribute('aria-pressed', String(item === button));});
  ['#contact-name', '#contact-trust', '#contact-description', '#contact-agreement', '#contact-conversation'].forEach((selector, i) => { $(selector).textContent = contacts[contactIndex][i]; });
  $('#personal-note').value = readNote();
  $('#note-status').textContent = 'Note personnelle de démonstration ; uniquement dans ce navigateur.';
}
$$('[data-contact]').forEach(button => button.addEventListener('click', () => selectContact(button)));
selectContact($('[data-contact="0"]'));
$('#personal-note').addEventListener('input', () => {
  const value = $('#personal-note').value; memoryNotes[noteKey()] = value;
  try { localStorage.setItem(noteKey(), value); $('#note-status').textContent = 'Note conservée dans ce navigateur.'; }
  catch { $('#note-status').textContent = 'Note conservée pour cette session ; stockage du navigateur indisponible.'; }
});
const tabs = $$('[data-tab]');
function activateTab(button, focus = false) {
  tabs.forEach(tab => {
    const active = tab === button;
    tab.classList.toggle('active', active); tab.setAttribute('aria-selected', String(active)); tab.tabIndex = active ? 0 : -1;
    $(`#panel-${tab.dataset.tab}`).hidden = !active;
  });
  if (focus) button.focus();
}
tabs.forEach((button, i) => {
  button.addEventListener('click', () => activateTab(button));
  button.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (i + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (i + tabs.length - 1) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next !== undefined) {event.preventDefault();activateTab(tabs[next], true);}
  });
});
let delivered = 2, claimed = false;
function renderMission() {
  const complete = delivered === 6;
  $('#delivery-count').textContent = `${delivered} / 6`;
  $('#delivery-progress').value = delivered;
  $('#mission-status').textContent = complete ? 'Mission réussie' : 'Livraison en cours';
  $('#deliver').hidden = complete;
  $('#deliver').disabled = !$('#near-npc').checked;
  $('#claim-reward').hidden = !complete;
  $('#claim-reward').disabled = claimed || !$('#near-npc').checked;
  $('#claim-reward').textContent = claimed ? 'Lot déjà récupéré par Alex ✓' : 'Récupérer la récompense ↗';
}
$('#near-npc').addEventListener('change', () => {
  renderMission();
  $('#delivery-feedback').textContent = $('#near-npc').checked ? 'Vous êtes près de Mara. La remise peut être confirmée.' : 'Rejoignez Mara pour livrer ou récupérer la récompense.';
});
$('#deliver').addEventListener('click', () => {
  if (!$('#near-npc').checked || delivered >= 6) return;
  $('#confirm-description').textContent = `${Math.min(2, 6 - delivered)} pansements propres seront remis à Mara. Progression actuelle : ${delivered} / 6.`;
  $('#delivery-dialog').returnValue = ''; $('#delivery-dialog').showModal();
});
$('#delivery-dialog').addEventListener('close', () => {
  if ($('#delivery-dialog').returnValue !== 'confirm' || !$('#near-npc').checked || delivered >= 6) return;
  delivered = Math.min(6, delivered + 2); renderMission();
  $('#delivery-feedback').textContent = delivered === 6 ? 'Réussite ! Alex et Camille reçoivent le même gain de réputation. Le lot commun reste à récupérer.' : 'Remise confirmée : 4 / 6. Progression partagée, sans gain de réputation intermédiaire.';
});
$('#claim-reward').addEventListener('click', () => {
  if (claimed || delivered !== 6 || !$('#near-npc').checked) return;
  claimed = true; renderMission();
  $('#delivery-feedback').textContent = 'Alex a récupéré les 20 cartouches du lot commun. Partage libre avec Camille ; aucun second retrait possible.';
});
$('#reset-mission').addEventListener('click', () => {
  delivered = 2; claimed = false; $('#near-npc').checked = true; renderMission();
  $('#delivery-feedback').textContent = 'Démo réinitialisée : aucun inventaire réel n’est modifié.';
});
renderMission();
let minutes = 80, clockState = 'online';
function renderClock() {
  $('#clock-time').textContent = `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
  $('#clock-caption').textContent = clockState === 'stopped' ? 'Serveur arrêté : délai suspendu.' : clockState === 'empty' ? 'Tous absents : le délai continue.' : 'Le délai continue.';
}
$$('[data-clock]').forEach(button => button.addEventListener('click', () => {
  pressed('[data-clock]', button); clockState = button.dataset.clock; renderClock();
}));
$('#advance-time').addEventListener('click', () => {
  if (clockState !== 'stopped') minutes = Math.max(0, minutes - 10);
  renderClock();
  if (minutes === 0) $('#clock-caption').textContent = 'Délai écoulé dans cette démonstration.';
});
const truces = {
  peace: ['TRÊVE ACTIVE', 'Relations personnelles conservées', 'Une trêve collective n’oblige pas chaque PNJ à vous apprécier. Les liens personnels continuent d’évoluer.'],
  attack: ['DÉFENSE CIBLÉE', 'Le sort de la trêve reste à décider', 'Les PNJ se défendent contre l’agresseur. Le LLM choisit ensuite maintien, réparation ou rupture ; le serveur valide. Les autres membres ne deviennent pas automatiquement des cibles.'],
  departure: ['TRÊVE CONSERVÉE', 'Le départ ne modifie pas l’accord', 'June quitte son groupe. Son identité, ses souvenirs, ses relations et les trêves existantes sont conservés. Un départ seul ne déclenche aucune renégociation.']
};
$$('[data-truce]').forEach(button => button.addEventListener('click', () => {
  pressed('[data-truce]', button);
  ['#truce-label', '#truce-caption', '#truce-explanation'].forEach((selector, i) => { $(selector).textContent = truces[button.dataset.truce][i]; });
}));
// Tous les textes viennent du dossier de conception ; aucun statut de fiche ne certifie un test en jeu.
const features = [
  ['Walt à la radio', 'social', 'Prototype existant', 'prototype', 'Un confident qui répond au joueur via le pont Python.', 'Le prototype traite le dialogue texte. Les essais rapportés du carnet initial ne prouvent pas les autres fonctionnalités ni l’intégration multijoueur Bandits!.'],
  ['Une personnalité pour chaque PNJ', 'social', 'Décision validée', 'accepted', 'Tous les PNJ Bandits!, amicaux ou hostiles, chefs ou membres.', 'Fiche immédiate côté serveur puis enrichissement asynchrone par le LLM. Les traits et faits vécus sont préservés.'],
  ['Parler à proximité et par radio', 'social', 'Décision validée', 'accepted', 'Le canal dépend de la portée et de l’équipement du PNJ.', '« Parler » identifie l’interlocuteur et conserve les échanges entendus. L’audibilité et les conditions radio sont vérifiées ; aucun accès global aux conversations privées.'],
  ['Initiatives et échanges entre PNJ', 'social', 'Décision validée', 'accepted', 'Des conversations liées aux événements et aux personnalités.', 'Observations personnelles, transmissions parlées et radio. Le joueur peut intervenir s’il entend. Quotas et durée bornée empêchent les boucles de conversations.'],
  ['Confiance et relations évolutives', 'social', 'Décision validée', 'accepted', 'Un PNJ peut devenir amical ou hostile selon les faits vécus.', 'Relations par personnage joueur ; niveaux qualitatifs et tendance visibles. Les libellés exacts et leurs seuils restent à fixer.'],
  ['Trêves et alliances de faction', 'social', 'Décision validée', 'accepted', 'Des accords explicites, conclus par les représentants autorisés.', 'Le propriétaire et ses négociateurs désignés représentent la faction. Défense ciblée en cas d’agression ; décision LLM sur la suite, validée côté serveur.'],
  ['Chef, contestation et départ', 'social', 'Décision validée', 'accepted', 'Les membres restent des individus, même au sein d’une bande.', 'Le chef décide ; les membres peuvent refuser ou contester. Départ décidé par le LLM et validé par le serveur ; identité et trêves conservées.'],
  ['Mensonges sans système de rumeurs', 'social', 'Périmètre retenu', 'accepted', 'Une personnalité peut mentir ou omettre en dialogue.', 'Aucun système de propagation ou de crédibilité des rumeurs. Une affirmation ne devient pas un acte réel et ne suffit pas à modifier la réputation.'],
  ['Les six voix du réseau', 'social', 'Carnet initial', 'planned', 'Confident, infirmière, déserteur, famille, chroniqueur et passeur.', 'Fiches serveur : histoire, ton, langue, horaires, fréquences, connaissances, secrets et actions autorisées. Édition par fichiers relus à chaud ; panneau admin ultérieur.'],
  ['Carnet classique unifié', 'system', 'Maquette validée', 'accepted', 'Contacts, Missions et Réputation dans une seule interface.', 'Bouton Carnet dans la barre latérale. Listes à gauche, détails à droite : confiance, accords, dernières conversations et notes personnelles.'],
  ['Carnet et module radio', 'system', 'Carnet initial', 'planned', 'Historique des échanges et accès depuis la radio.', 'Module Émettre prévu dans la fenêtre radio vanilla : saisie, dernières lignes et ouverture du carnet. Prise en charge envisagée des talkies, autoradios et radios posées émettrices.'],
  ['Livraisons solo ou de groupe', 'mission', 'Décision validée', 'accepted', 'Médicaments, nourriture et outils remis réellement au PNJ.', 'Le serveur prépare les offres possibles selon les besoins et ressources du PNJ. Le LLM choisit la mission et son destinataire selon personnalité, confiance et réputation. Première version : offre fixe, acceptation ou refus ; questions possibles sans modification des conditions, négociation reportée. Inscription personnelle, remises partielles et progression commune. Liste d’objets acceptés visible ; une pièce compte pour une unité. Livrer depuis le carnet près du PNJ.'],
  ['Chrono de mission partagé', 'mission', 'Décision validée', 'accepted', 'Le délai commence à la première acceptation.', 'Temps réel de fonctionnement du serveur. Aucun arrêt pendant les déconnexions ou la pause de simulation ; seule l’extinction du serveur suspend le décompte.'],
  ['Résultats et récompenses', 'mission', 'Décision validée', 'accepted', 'Même résultat de réputation pour tous les participants engagés.', 'Échec et abandon ont le même malus, sans calcul d’effort. Si le PNJ demandeur meurt pendant une mission en cours, elle est annulée sans malus de mission. Si un participant le tue, lui seul subit une très forte baisse de réputation : pas ses coéquipiers. Objets déjà livrés conservés par le PNJ en cas d’échec ou d’abandon. Lot matériel facultatif fixe, retrait unique par un participant et partage libre.'],
  ['Autres modèles de missions', 'mission', 'Carnet initial', 'planned', 'Signaler, retrouver, reconnaître, nettoyer et récupérer.', 'Le LLM formule une mission à partir de gabarits vérifiables. Le serveur valide signaux, objets, positions ou morts de zombies selon le modèle. Ces types ne sont pas détaillés comme M01.'],
  ['Survivants à secourir', 'mission', 'Carnet initial', 'planned', 'Un groupe radio à secourir par équipe, dans un bâtiment réel.', 'Indices plutôt que coordonnées exactes. Réserves en temps de jeu et seulement lorsqu’au moins un joueur est connecté. À temps : cache et note ; trop tard : scène et dernières pages.'],
  ['Signal Smoke facultatif', 'mission', 'Intégration prévue', 'planned', 'Fumées et fusées pour trouver, prévenir ou se signaler.', 'Sans dépendance obligatoire. L’attribution d’un signal au bon joueur exige des points d’intégration encore à vérifier ; les fusées joueur sont rouges dans le carnet initial.'],
  ['Troc avec le passeur', 'mission', 'Carnet initial', 'planned', 'Un passage hebdomadaire partagé par tout le serveur.', 'Quatre familles de marchandises ; stocks et prix serveur. Réservation à la radio et échange sans contact sur la berge. La capture Signal Smoke illustre le signal de rendez-vous, pas le passeur.'],
  ['Chronique et mémorial', 'mission', 'Carnet initial', 'planned', 'Un bulletin chaque soir de jeu, ancré dans les faits.', 'Missions, secours, morts, passages, météo et services interrompus. Personnages nommés, sans diffusion de positions exactes des bases ni de conversations privées.'],
  ['Les dernières pages', 'mission', 'Carnet initial', 'planned', 'Un journal de personnage à découvrir après sa mort.', 'Faits enregistrés et dernières paroles radio. Fonction prévue par défaut, désactivable par l’administrateur ; placement et verrouillage à vérifier dans le jeu cible.'],
  ['Carte, caches et scènes', 'mission', 'Actions prévues', 'planned', 'L’information devient un repère ou une découverte tangible.', 'Repères de lieux connus, zones révélées bornées, caches issues de tables serveur et scènes de gabarits placées au chargement de zone.'],
  ['Réputation globale individuelle', 'system', 'Décision validée', 'accepted', 'Mauvaise, neutre ou bonne, avec les motifs récents.', 'Par personnage, pas par compte. Départ neutre, amélioration par actes et missions ; pas par attente. Certains PNJ proposent des missions de rachat. Aucun détecteur PvP, vol ou destruction dans le périmètre initial.'],
  ['Comportement envers les PNJ', 'social', 'Modalités à préciser', 'open', 'Les incidents de dialogue peuvent contribuer à la réputation.', 'Classification contextuelle proposée pour insultes et menaces dirigées ; un juron isolé n’est pas automatiquement une agression. Barème, limites et mise en œuvre ne sont pas validés.'],
  ['CharacterReputation & API ouverte', 'system', 'Coquille créée', 'prototype', 'Un mod indépendant, utilisable par plusieurs projets.', 'Architecture prévue : profils, fournisseurs de sujets, types d’événements, lectures, historique, notifications et contributions dédupliquées. Les capacités métier ne sont pas encore implémentées.'],
  ['Adaptateur MilitaryDrop', 'system', 'Architecture prévue', 'planned', 'Même moteur, confiance de station militaire séparée.', 'Conserver les règles de station, plafonds, coupures et largages. Migration versionnée prévue ; ne pas attribuer une confiance collective à chaque personnage.'],
  ['Autorité et cohérence serveur', 'system', 'Architecture prévue', 'planned', 'Une identité et un état canonique, partagés avec les bons clients.', 'Validation des actions, révisions, persistance, rejets des réponses LLM périmées et projections autorisées. Pas de delta de réputation décidé par un client.'],
  ['Budget, secrets et secours technique', 'system', 'Architecture prévue', 'planned', 'Limiter les appels et préserver le fonctionnement normal du jeu.', '60 appels par heure par défaut dans le carnet initial. Actions en liste fermée, mémoire bornée, secrets hors prompts, journal admin. Sans pont disponible, aucun nouvel engagement matériel inventé.'],
  ['Décisions et déplacements Bandits!', 'system', 'Faisabilité à vérifier', 'open', 'Le LLM choisit les intentions, Bandits! exécute les gestes.', 'Le serveur valide. Adaptateur, inventaires, contrôle actif, ciblage sélectif, reprise et persistance des PNJ restent à établir en 42.21, particulièrement avec plusieurs clients.']
];
let filter = 'all';
function renderFeatures() {
  const query = $('#feature-search').value.trim().toLocaleLowerCase('fr');
  const selected = features.filter(feature => (filter === 'all' || feature[1] === filter) && [feature[0], feature[2], feature[4], feature[5]].join(' ').toLocaleLowerCase('fr').includes(query));
  $('#feature-grid').replaceChildren(...selected.map(([title, category, status, statusClass, intro, detail]) => {
    const article = document.createElement('article'); article.className = 'feature-card';
    const badge = document.createElement('span'); badge.className = `status ${statusClass}`; badge.textContent = status;
    const h3 = document.createElement('h3'); h3.textContent = title;
    const p = document.createElement('p'); p.textContent = intro;
    const details = document.createElement('details'); const summary = document.createElement('summary'); summary.textContent = 'Lire les règles';
    const body = document.createElement('p'); body.textContent = detail; details.append(summary, body); article.append(badge, h3, p, details); return article;
  }));
  $('#feature-count').textContent = `${selected.length} / ${features.length} fonctionnalités présentées`;
  $('#no-features').hidden = selected.length !== 0;
}
$$('[data-filter]').forEach(button => button.addEventListener('click', () => {
  pressed('[data-filter]', button); filter = button.dataset.filter; renderFeatures();
}));
$('#feature-search').addEventListener('input', renderFeatures);
renderFeatures();
$$('.scene, .encounter-art, .trader-story').forEach(container => {
  const image = container.querySelector('img');
  const button = document.createElement('button');
  button.className = 'capture-expand'; button.textContent = 'Voir la capture ↗';
  button.setAttribute('aria-label', 'Voir la capture en jeu en plein format');
  container.append(button);
  button.addEventListener('click', () => {
    $('#full-capture').src = image.src; $('#full-capture').alt = image.alt;
    $('#capture-description').textContent = image.alt; $('#capture-dialog').showModal();
  });
});
$('#close-capture').addEventListener('click', () => $('#capture-dialog').close());
if ('IntersectionObserver' in window) {
  const navObserver = new IntersectionObserver(entries => entries.forEach(entry => {
    const link = $(`.topbar nav a[href="#${entry.target.id}"]`);
    if (link) link.classList.toggle('current', entry.isIntersecting);
  }), {rootMargin: '-15% 0px -60% 0px'});
  $$('main section[id]').forEach(section => navObserver.observe(section));
}
