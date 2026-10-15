/* Maquette locale : aucune commande réseau ni mutation du jeu. */
'use strict';
const $ = id => document.getElementById(id);
const npcs = [
  {name:'Mara Bennett',short:'Mara',initials:'MB',role:'Soigneuse · Le Refuge',traits:['Protectrice','Pragmatique','Méfiante']},
  {name:'Elias Ward',short:'Elias',initials:'EW',role:'Chef · Le Refuge',traits:['Prudent','Direct','Loyal']}
];
let state, selection, contact = 0, toastTimer;
const notes = {};
const labels = {offer:'Offre à accepter',active:'En cours',success:'Réussie · lot disponible',claimed:'Terminée · lot retiré',refused:'Offre refusée'};
const scenes = {
  dialogue:['1 / Dialogue de proximité','Écrivez une question, puis consultez l’offre. Les fenêtres se déplacent par leur barre de titre.'],
  offre:['2 / Offre de mission','Consultez les conditions avant votre acceptation personnelle. Fermer le carnet ne refuse pas la mission.'],
  suivi:['3 / Suivi partagé','Exemple : Camille a déjà remis deux pansements. Vous pouvez compléter la livraison avec les objets de votre sac.'],
  livraison:['4 / Livraison près du PNJ','Choisissez les objets propres et les quantités. La confirmation précède leur retrait de l’inventaire.'],
  recompense:['5 / Retour de quête','La mission est réussie. Un participant engagé retire le lot commun une seule fois.'],
  contacts:['6 / Fiche du PNJ','Confiance, accords, conversations et notes privées se retrouvent dans le même carnet.']
};
function toast(message) { clearTimeout(toastTimer); $('toast').textContent=message; $('toast').hidden=false; toastTimer=setTimeout(()=>{$('toast').hidden=true;},4500); }
function feedback(message) { $('operation-feedback').textContent=message; toast(message); }
function tab(name) {
  document.querySelectorAll('[data-tab]').forEach(b=>{const on=b.dataset.tab===name;b.classList.toggle('active',on);b.setAttribute('aria-selected',on);b.tabIndex=on?0:-1;$('ui-panel-'+b.dataset.tab).hidden=!on;});
}
function markScene(name) {
  document.querySelectorAll('[data-scene]').forEach(b=>{const on=b.dataset.scene===name;b.classList.toggle('selected',on);b.setAttribute('aria-pressed',on);});
  $('scene-caption').querySelector('b').textContent=scenes[name][0];$('scene-caption').querySelector('span').textContent=scenes[name][1];
  if(name==='suivi')$('scene-caption').querySelector('span').textContent='Progression commune : '+state.delivered+' / 6 pansements remis. Le carnet conserve le délai et les engagements de chacun.';
}
function notebook(name='missions') { $('journal-window').hidden=false;$('journal-window').classList.remove('minimized');$('dialogue-window').hidden=true;tab(name);markScene(name==='contacts'?'contacts':state.status==='active'?'suivi':['success','claimed'].includes(state.status)?'recompense':'offre'); }
function line(who, message) {
  const p=document.createElement('p'), b=document.createElement('strong'), span=document.createElement('span');
  p.className='chat-line'+(who==='Vous'?' mine':'');
  b.textContent=who;span.textContent=message;p.append(b,span);$('conversation').append(p);$('conversation').scrollTop=$('conversation').scrollHeight;
}
function contactRender() {
  const npc=npcs[contact];$('npc-name').textContent=npc.name;$('npc-role').textContent=npc.role;
  $('npc-initials').replaceChildren(document.createTextNode(npc.initials));const small=document.createElement('small');small.textContent='CONTACT';$('npc-initials').append(small);
  $('npc-traits').replaceChildren(...npc.traits.map(t=>{const s=document.createElement('span');s.textContent=t;return s;}));
  $('npc-trust').textContent=(state.status==='success'||state.status==='claimed')&&contact===0?'Confiante · en hausse ↗':'Réservée · stable →';
  $('talk-to-contact').textContent='Parler à '+npc.short;
  $('contact-history').replaceChildren(...state.history[contact].slice(-4).map(h=>{const p=document.createElement('p');p.textContent=h;return p;}));
  try { notes[contact] ??= localStorage.getItem('RadioSurvivor.interface.note.'+contact)||''; } catch { notes[contact] ??=''; }
  $('npc-note').value=notes[contact];$('note-save-state').textContent='Notes privées de cette maquette.';
  document.querySelectorAll('[data-contact]').forEach(b=>b.classList.toggle('current',Number(b.dataset.contact)===contact));
}
function action(id,text,fn,disabled=false) { const b=document.createElement('button');b.id=id;b.className='paper-button';b.textContent=text;b.disabled=disabled;b.addEventListener('click',fn);$('mission-buttons').append(b); }
function render() {
  const completed=['success','claimed'].includes(state.status), active=state.status==='active', near=$('nearby').checked;
  $('list-mission-state').textContent=labels[state.status];$('mission-state').textContent=labels[state.status];
  $('mission-stamp').textContent=completed?'RÉUSSIE':active?'EN COURS':state.status==='refused'?'REFUSÉE':'PROPOSITION';$('mission-stamp').classList.toggle('success',completed);
  $('mission-timer').textContent=active?'Temps restant : '+Math.floor(state.minutes/60)+' h '+String(state.minutes%60).padStart(2,'0'):completed?'Objectif accompli':'Délai : 2 h après acceptation';
  $('supply-count').textContent=state.delivered+' / 6 remis';$('supply-remaining').textContent=(6-state.delivered)+' restants';$('mission-progress').style.width=(state.delivered/6*100)+'%';
  $('participants-section').hidden=!active&&!completed;$('group-legend').textContent=active||completed?'Alex et Camille · deux acceptations personnelles confirmées.':'L’acceptation de chaque joueur est personnelle.';
  $('mission-receipt').hidden=state.status!=='claimed';$('mission-cautions').hidden=completed;
  $('reputation-result').textContent=completed?'Gain attribué à chaque participant':'Gain à la réussite';
  $('global-reputation').textContent=completed?'Bonne':'Neutre';$('neutral-level').classList.toggle('active',!completed);$('good-level').classList.toggle('active',completed);
  $('reputation-history').textContent=completed?'Mission « Soigner le refuge » réussie : gain personnel attribué. Le niveau Bonne est illustratif ; le barème reste à définir.':'Aucun changement : accepter ou livrer partiellement ne donne pas de réputation.';
  $('journal-footer-state').textContent=labels[state.status];$('mission-buttons').replaceChildren();
  if(state.status==='offer') { action('accept-mission','Accepter la mission',()=>{state.status='active';state.revision++;state.history[0].push('Vous : « Je m’engage à livrer les six pansements. »');render();feedback('Mission acceptée. Le délai commun commence : 2 h.');});action('refuse-mission','Refuser',()=>{state.status='refused';render();feedback('Offre refusée. Aucun engagement ni malus.');}); }
  if(active) action('deliver-mission','Livrer des fournitures',delivery,!near);
  if(state.status==='success') action('claim-mission-reward','Récupérer les 20 cartouches',()=>{if(!$('nearby').checked||state.status!=='success')return;state.status='claimed';state.revision++;render();feedback('Alex a récupéré le lot commun de 20 cartouches. Aucun second retrait possible.');},!near);
  if(state.status==='claimed') action('claim-mission-reward','Lot déjà récupéré',()=>{},true);
  action('view-contact-mission','Fiche de Mara',()=>{contact=0;contactRender();tab('contacts');});
  $('mission-action-hint').textContent=active||state.status==='success'?(near?'Mara est à portée : échange disponible.':'Rejoignez Mara pour effectuer l’échange.'):'Les conditions affichées ne sont pas négociables.';
  $('dialogue-channel').textContent=near?'Proximité':'Hors portée';$('send-dialogue').disabled=!near;$('dialogue-input').disabled=!near;
  $('talk-to-contact').disabled=!near;$('dialogue-offer').hidden=contact!==0||state.status!=='offer';
  $('preview-state').textContent=labels[state.status]+' · '+(near?'PNJ à proximité':'PNJ hors portée');
  contactRender();if(!$('delivery-window').hidden) selectionRender();
  if(!$('journal-window').hidden&&!$('ui-panel-missions').hidden&&$('delivery-window').hidden)markScene(active?'suivi':completed?'recompense':'offre');
}
function dialogue() {
  markScene('dialogue');
  $('dialogue-window').hidden=false;$('dialogue-window').classList.remove('minimized');$('journal-window').hidden=true;
  const npc=npcs[contact];$('dialogue-window').querySelector('.pz-title>span').textContent='Parler — '+npc.name;
  $('dialogue-window').querySelector('h1').textContent=npc.name;$('dialogue-window').querySelector('.dialogue-identity p').textContent=npc.role;$('dialogue-window').querySelector('.npc-avatar').textContent=npc.initials;
  $('dialogue-input').placeholder='Parler à '+npc.short+'…';$('conversation').replaceChildren();
  line(npc.short,contact===0?(state.status==='offer'?'Il nous manque six pansements propres. Si vous pouvez les apporter en deux heures, j’ai vingt cartouches pour vous.':state.status==='active'?'Merci pour votre aide. Il nous manque encore '+(6-state.delivered)+' pansements.':state.status==='refused'?'D’accord. Je vais chercher quelqu’un d’autre.':'Vous avez tenu parole. Le refuge vous remercie.'):'Le refuge tient grâce aux gens qui respectent leurs engagements.');render();
}
function delivery() { if(state.status!=='active'||!$('nearby').checked)return;selection={bandage:0,cloth:0};$('delivery-window').hidden=false;selectionRender();markScene('livraison'); }
function selectionRender() {
  const total=selection.bandage+selection.cloth, near=$('nearby').checked;
  for(const type of ['bandage','cloth']) { $('qty-'+type).textContent=selection[type];$('available-'+type).textContent=state.inventory[type]+' dans votre inventaire'; }
  $('delivery-remaining').textContent=(6-state.delivered)+' pansements restent à livrer.';$('delivery-total').textContent=(state.delivered+total)+' / 6 pansements';
  $('confirm-selection').disabled=!total||!near||state.status!=='active';$('delivery-selection-status').textContent=!near?'Mara est hors portée. Rejoignez-la.':total?total+' objet(s) sélectionné(s).':'Sélectionnez les objets à remettre.';
  document.querySelectorAll('[data-qty]').forEach(b=>{const type=b.dataset.qty,delta=Number(b.dataset.change);b.disabled=!near||(delta<0?selection[type]===0:selection[type]>=state.inventory[type]||total>=6-state.delivered);});
}
function preset(name) {
  if($('confirmation').open)$('confirmation').close('cancel');
  state={status:['suivi','livraison'].includes(name)?'active':name==='recompense'?'success':'offer',delivered:['suivi','livraison'].includes(name)?2:name==='recompense'?6:0,minutes:['suivi','livraison'].includes(name)?80:120,inventory:{bandage:4,cloth:2},revision:0,history:[['Mara : « Les pansements propres, c’est ce qui nous manque. »','Vous : « Je vais regarder ce que j’ai dans mon sac. »'],['Elias : « Respectez la trêve avec le refuge. »']]};
  selection={bandage:0,cloth:0};contact=0;$('operation-feedback').textContent='';$('delivery-window').hidden=true;$('toast').hidden=true;
  document.querySelectorAll('.draggable').forEach(w=>{w.style.left='';w.style.top='';w.style.right='';w.classList.remove('minimized');});
  document.querySelectorAll('[data-scene]').forEach(b=>{const on=b.dataset.scene===name;b.classList.toggle('selected',on);b.setAttribute('aria-pressed',on);});
  $('scene-caption').querySelector('b').textContent=scenes[name][0];$('scene-caption').querySelector('span').textContent=scenes[name][1];
  render();if(name==='dialogue')dialogue();else notebook(name==='contacts'?'contacts':'missions');if(name==='livraison')delivery();
}
document.querySelectorAll('[data-scene]').forEach(b=>b.addEventListener('click',()=>preset(b.dataset.scene)));
document.querySelectorAll('[data-tab]').forEach(b=>{
  b.addEventListener('click',()=>tab(b.dataset.tab));
  b.addEventListener('keydown',e=>{const tabs=[...document.querySelectorAll('[data-tab]')],i=tabs.indexOf(b);let next;if(e.key==='ArrowRight')next=tabs[(i+1)%tabs.length];if(e.key==='ArrowLeft')next=tabs[(i+tabs.length-1)%tabs.length];if(e.key==='Home')next=tabs[0];if(e.key==='End')next=tabs.at(-1);if(next){e.preventDefault();tab(next.dataset.tab);next.focus();}});
});
document.querySelectorAll('[data-contact]').forEach(b=>b.addEventListener('click',()=>{contact=Number(b.dataset.contact);contactRender();}));
$('npc-note').addEventListener('input',()=>{notes[contact]=$('npc-note').value;try{localStorage.setItem('RadioSurvivor.interface.note.'+contact,notes[contact]);$('note-save-state').textContent='Note enregistrée sur cet ordinateur.';}catch{$('note-save-state').textContent='Note conservée pendant cette session.';}});
$('open-notebook').onclick=()=>notebook();$('view-offer').onclick=()=>notebook();$('dialogue-contact').onclick=()=>notebook('contacts');$('talk-to-contact').onclick=dialogue;
for(const [id,window] of [['close-dialogue','dialogue-window'],['close-notebook','journal-window'],['close-delivery','delivery-window'],['cancel-selection','delivery-window']])$(id).onclick=()=>{$(window).hidden=true;};
for(const [id,window] of [['minimize-dialogue','dialogue-window'],['minimize-notebook','journal-window']])$(id).onclick=()=>$(window).classList.toggle('minimized');
$('nearby').onchange=render;$('large-font').onchange=()=>$('game-stage').classList.toggle('large-font',$('large-font').checked);$('hide-world').onchange=()=>$('game-stage').classList.toggle('neutral',$('hide-world').checked);$('restart').onclick=()=>preset('dialogue');
$('dialogue-form').onsubmit=e=>{
  e.preventDefault();const input=$('dialogue-input'),message=input.value.trim();if(!message||!$('nearby').checked)return;line('Vous',message);state.history[contact].push('Vous : « '+message+' »');input.value='';
  let reply=contact===1?'Je préfère que chacun sache à quoi il s’engage. Mara pourra vous expliquer ce dont nous avons besoin.':/temps|délai|heure|durée/i.test(message)?'Deux heures à partir de la première acceptation. Le délai continue pendant les déconnexions.':/cartouche|récompense|payer|lot/i.test(message)?'Vingt cartouches pour toute la mission. Un seul lot, à partager entre vous.':/sale|tissu|bandage|pansement|combien/i.test(message)?'Six pièces propres : bandages ou bandes de tissu. Les bandages sales ne conviennent pas.':/plus|négoci|moins/i.test(message)?'Je garde les conditions annoncées. Vous pouvez accepter ou refuser.':'Ce qui m’importe, c’est de pouvoir soigner les gens du refuge. Les conditions sont dans votre carnet.';
  line(npcs[contact].short,reply);state.history[contact].push(npcs[contact].short+' : « '+reply+' »');contactRender();
};
document.querySelectorAll('[data-qty]').forEach(b=>b.onclick=()=>{const type=b.dataset.qty,delta=Number(b.dataset.change);if(b.disabled)return;selection[type]+=delta;selectionRender();});
$('confirm-selection').onclick=()=>{
  if($('confirm-selection').disabled)return;
  $('confirmation-items').replaceChildren(...['bandage','cloth'].filter(t=>selection[t]>0).map(t=>{const li=document.createElement('li');li.textContent=selection[t]+' × '+(t==='bandage'?'Bandage propre':'Bande de tissu propre');return li;}));
  $('confirmation-progress').textContent='Progression après remise : '+(state.delivered+selection.bandage+selection.cloth)+' / 6.';$('confirmation').returnValue='';$('confirmation').showModal();
};
$('confirmation').addEventListener('close',()=>{
  if($('confirmation').returnValue!=='confirm')return;const total=selection.bandage+selection.cloth;
  if(!total||!$('nearby').checked||state.status!=='active'||total>6-state.delivered||['bandage','cloth'].some(t=>selection[t]>state.inventory[t])) {feedback('La remise ne peut plus être effectuée. Vérifiez la portée et les objets.');return;}
  for(const t of ['bandage','cloth'])state.inventory[t]-=selection[t];state.delivered+=total;state.revision++;selection={bandage:0,cloth:0};$('delivery-window').hidden=true;
  if(state.delivered===6)state.status='success';state.history[0].push('Mara : « Merci pour ces '+total+' pansements propres. »');render();feedback(state.status==='success'?'Mission réussie. Réputation attribuée ; le lot commun peut être récupéré.':'Remise enregistrée. '+(6-state.delivered)+' pansements restent à livrer. Aucun gain de réputation pour cette remise partielle.');
});
document.querySelectorAll('.drag-handle').forEach(handle=>{
  const win=handle.closest('.pz-window');if(!win)return;let drag;
  handle.addEventListener('pointerdown',e=>{if(e.target.closest('button')||e.button!==0)return;const r=win.getBoundingClientRect(),s=$('game-stage').getBoundingClientRect();drag={x:e.clientX,y:e.clientY,left:r.left-s.left,top:r.top-s.top};handle.setPointerCapture(e.pointerId);e.preventDefault();});
  handle.addEventListener('pointermove',e=>{if(!drag)return;win.style.right='auto';win.style.left=Math.max(0,Math.min($('game-stage').clientWidth-win.offsetWidth,drag.left+e.clientX-drag.x))+'px';win.style.top=Math.max(0,Math.min($('game-stage').clientHeight-win.offsetHeight,drag.top+e.clientY-drag.y))+'px';});
  for(const ev of ['pointerup','pointercancel'])handle.addEventListener(ev,()=>{drag=null;});
});
preset('dialogue');
