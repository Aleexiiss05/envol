/* Génère la base de données texte de 10 000 vols, modélisée sur les réseaux réels.
   Usage : node scripts/generate-db.js
   Sorties : data/flights.csv (la base), data/flights.js (copie pour ouverture en file://),
             data/reference.json + data/photos.json (mêmes données pour l'app iOS)

   Méthode :
   1. Routes directes réelles par compagnie (scripts/network.js), fréquences selon la demande et la distance.
   2. Horaires en vagues réalistes (ex. Europe → Amérique en fin de matinée, retour de nuit ; Europe → Asie le soir).
   3. Durées de vol : distance orthodromique, détour de routage (contournement de l'espace aérien russe
      vers le Japon et la Corée), vents dominants d'ouest (vols vers l'est plus rapides), temps de roulage.
   4. Correspondances construites en appariant les vrais horaires aux hubs (même compagnie ou même alliance),
      avec temps minimum de correspondance par aéroport.
   5. Tarif de base par distance, type de compagnie et concurrence ; la saison, le jour, l'heure et
      l'anticipation sont appliqués dans l'application (data/reference.js). */
const fs = require('fs');
const path = require('path');
const REF = require('../data/reference.js');
const NET = require('./network.js');

const TOTAL = 10000;
let seed = 20261001;
function rng() { // mulberry32 : base reproductible
  seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const between = (a, b) => a + rng() * (b - a);
const round5 = m => Math.round(m / 5) * 5;
function strHash(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

const AP = Object.fromEntries(REF.airports.map(a => [a.code, a]));
const AL = Object.fromEntries(REF.airlines.map(a => [a.code, a]));

function dist(a, b) {
  const A = AP[a], B = AP[b], r = Math.PI / 180;
  const h = Math.sin((B.lat - A.lat) * r / 2) ** 2 + Math.cos(A.lat * r) * Math.cos(B.lat * r) * Math.sin((B.lon - A.lon) * r / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
}
function bearing(a, b) {
  const A = AP[a], B = AP[b], r = Math.PI / 180;
  const y = Math.sin((B.lon - A.lon) * r) * Math.cos(B.lat * r);
  const x = Math.cos(A.lat * r) * Math.sin(B.lat * r) - Math.sin(A.lat * r) * Math.cos(B.lat * r) * Math.cos((B.lon - A.lon) * r);
  return Math.atan2(y, x); // radians, 0 = nord
}
const REGION = {};
'JFK MIA LAX SFO YUL MEX CUN PTP FDF GRU EZE'.split(' ').forEach(c => REGION[c] = 'AM');
'DXB DOH'.split(' ').forEach(c => REGION[c] = 'ME');
'DEL BKK SIN DPS HKG ICN HND MLE'.split(' ').forEach(c => REGION[c] = 'AS');
REGION.SYD = 'OC';
'DSS ABJ JNB RUN'.split(' ').forEach(c => REGION[c] = 'AF');
const region = c => REGION[c] || 'EU';

// ---------- Durée de vol ----------
function blockTime(a, b) {
  const km = dist(a, b);
  const ra = region(a), rb = region(b);
  let routing = 1.04;
  const pair = [ra, rb].sort().join('');
  if (pair === 'ASEU' && ['HND', 'ICN'].includes(ra === 'AS' ? a : b)) routing = 1.22; // contournement de la Russie
  else if (pair === 'ASEU' && ['HKG'].includes(ra === 'AS' ? a : b)) routing = 1.08;
  const midLat = Math.abs((AP[a].lat + AP[b].lat) / 2);
  const jet = midLat > 22 && midLat < 62 ? 70 : 25;
  const wind = jet * Math.sin(bearing(a, b)); // composante vers l'est
  const speed = (km < 800 ? 700 : km < 2500 ? 790 : 850) + wind;
  const taxi = km < 1500 ? 28 : km < 4000 ? 33 : 38;
  return round5(km * routing / speed * 60 + taxi);
}

// ---------- Réseau ----------
const routes = new Map(); // "AL|A|B" (A<B) -> { al, a, b }
for (const [al, bases] of Object.entries(NET)) {
  if (!AL[al]) throw new Error('Compagnie inconnue ' + al);
  for (const [base, list] of Object.entries(bases)) {
    for (const dest of list.split(/\s+/).filter(Boolean)) {
      if (!AP[base] || !AP[dest]) throw new Error(`Aéroport inconnu ${al} ${base}-${dest}`);
      if (base === dest) continue;
      const [a, b] = [base, dest].sort();
      routes.set(`${al}|${a}|${b}`, { al, a, b, base });
    }
  }
}
const carriersOnPair = new Map();
for (const r of routes.values()) { const k = r.a + r.b; carriersOnPair.set(k, (carriersOnPair.get(k) || 0) + 1); }

// Fréquences quotidiennes connues (ordre de grandeur réel) ; sinon calcul par demande et distance
const FREQ = {
  'AF|CDG|JFK': 5, 'AF|CDG|NCE': 7, 'AF|ORY|NCE': 5, 'AF|CDG|TLS': 4, 'AF|ORY|TLS': 5, 'AF|CDG|MRS': 5, 'AF|CDG|LHR': 5,
  'AF|CDG|AMS': 5, 'AF|CDG|FCO': 4, 'AF|CDG|MAD': 4, 'AF|CDG|BCN': 4, 'AF|CDG|LIS': 3, 'AF|CDG|MIA': 2, 'AF|CDG|LAX': 2,
  'AF|CDG|YUL': 3, 'AF|CDG|HND': 2, 'AF|CDG|DXB': 2, 'AF|CDG|PTP': 1, 'AF|CDG|RUN': 1,
  'KL|AMS|CDG': 5, 'KL|AMS|LHR': 7, 'KL|AMS|JFK': 3, 'LH|FRA|JFK': 3, 'LH|FRA|CDG': 5, 'LH|MUC|CDG': 4, 'LH|FRA|LHR': 6,
  'BA|LHR|JFK': 7, 'BA|LHR|CDG': 4, 'BA|LHR|AMS': 6, 'BA|LHR|MAD': 5, 'BA|LHR|DXB': 3, 'IB|MAD|BCN': 8, 'IB|MAD|LIS': 5,
  'EK|DXB|CDG': 3, 'EK|DXB|LHR': 6, 'QR|DOH|CDG': 3, 'QR|DOH|LHR': 6, 'TK|IST|CDG': 5, 'TK|IST|LHR': 6, 'DL|JFK|CDG': 3,
  'AA|JFK|LHR': 5, 'UA|SFO|LAX': 8, 'AA|JFK|LAX': 8, 'DL|JFK|LAX': 8, 'AA|JFK|MIA': 8, 'AC|YUL|CDG': 3,
  'U2|ORY|NCE': 5, 'U2|CDG|NCE': 3, 'U2|ORY|TLS': 4, 'VY|BCN|ORY': 4, 'VY|BCN|MAD': 6, 'FR|DUB|LGW': 6, 'TP|LIS|ORY': 5, 'TP|LIS|OPO': 6,
};
// Numéros de vol connus (aller, retour)
const KNOWN_FN = {
  'AF|CDG|JFK': [['006', '007'], ['008', '009'], ['010', '011'], ['022', '023'], ['012', '013']],
  'KL|AMS|JFK': [['641', '642'], ['643', '644'], ['645', '646']],
  'LH|FRA|JFK': [['400', '401'], ['402', '403'], ['404', '405']],
  'BA|LHR|JFK': [['117', '112'], ['115', '114'], ['173', '172'], ['175', '174'], ['177', '176'], ['179', '178'], ['113', '116']],
};

// Vagues de départ (minutes, heure locale) selon les régions de départ et d'arrivée pour le long-courrier
function windows(from, to, km) {
  if (km < 4200) return [[370, 1290]];
  const f = region(from), t = region(to), k = f + '>' + t;
  const W = {
    'EU>AM': [[600, 1050]], 'AM>EU': [[990, 1380]], 'EU>AS': [[660, 840], [1080, 1410]], 'AS>EU': [[5, 150], [570, 810]],
    'EU>ME': [[480, 1350]], 'ME>EU': [[90, 540], [780, 960]], 'EU>AF': [[600, 1020]], 'AF>EU': [[1200, 1435]],
    'ME>AS': [[120, 600], [1200, 1410]], 'ME>OC': [[120, 600], [1200, 1410]], 'AS>ME': [[5, 180], [1020, 1380]], 'OC>ME': [[1020, 1380]],
    'AM>AS': [[600, 900], [1320, 1435]], 'AS>AM': [[960, 1260]], 'AM>OC': [[1320, 1435]], 'OC>AM': [[600, 900]],
    'ME>AM': [[450, 600]], 'AM>ME': [[1200, 1380]], 'ME>AF': [[120, 600]], 'AF>ME': [[900, 1380]],
    'AM>AF': [[1260, 1420]], 'AF>AM': [[60, 200]], 'EU>OC': [[1200, 1380]], 'OC>EU': [[900, 1260]],
  };
  return W[k] || [[480, 1320]];
}
function spreadTimes(n, wins, lowcost, al) {
  const offset = (strHash(al) % 90) - 45; // chaque compagnie a sa propre banque horaire
  const total = wins.reduce((s, [a, b]) => s + (b - a), 0);
  const out = [];
  for (let i = 0; i < n; i++) {
    let pos = total * (i + (lowcost ? .25 : .5)) / n + offset + between(-15, 15);
    pos = Math.max(0, Math.min(total - 1, pos));
    for (const [a, b] of wins) { if (pos <= b - a) { out.push(round5(a + pos)); break; } pos -= b - a; }
  }
  return out;
}
const WEEK_PATTERNS = { 1: ['0000100', '0010000', '0000001'], 2: ['1000100', '0100010', '0010001'], 3: ['1010100', '0101010', '1001001'], 4: ['1010101', '1101010', '0110110'], 5: ['1110110', '1011101', '0111011'], 6: ['1111110', '1111101', '1011111'], 7: ['1111111'] };

// ---------- Flotte, services, prix ----------
const FLEET = {
  AF: [['A220-300', 'A320', 'A321', 'A318'], ['Boeing 777-300ER', 'A350-900', 'Boeing 787-9', 'A330-200']],
  KL: [['Boeing 737-800', 'Embraer 195-E2', 'Boeing 737-900'], ['Boeing 787-10', 'Boeing 777-300ER', 'A330-300']],
  LH: [['A320neo', 'A321', 'A319', 'Embraer 190'], ['A350-900', 'Boeing 747-8', 'A340-600', 'Boeing 787-9']],
  BA: [['A320neo', 'A321neo', 'A319'], ['Boeing 777-300ER', 'A350-1000', 'Boeing 787-9', 'A380-800']],
  IB: [['A320neo', 'A321neo', 'A321XLR'], ['A350-900', 'A330-200', 'A330-300']],
  AZ: [['A220-100', 'A320neo', 'A321'], ['A350-900', 'A330-900neo']],
  LX: [['A220-300', 'A320neo', 'A321neo'], ['Boeing 777-300ER', 'A330-300', 'A340-300']],
  SN: [['A320', 'A319'], ['A330-300']], OS: [['A320', 'Embraer 195', 'A321'], ['Boeing 777-200ER', 'Boeing 787-9']],
  SK: [['A320neo', 'A321LR'], ['A350-900', 'A330-300']], TP: [['A320neo', 'A321neo', 'A321LR'], ['A330-900neo', 'A321LR']],
  EI: [['A320neo', 'A321neo'], ['A330-300', 'A321XLR']], TK: [['A321neo', 'Boeing 737 MAX 8', 'A320neo'], ['A350-900', 'Boeing 787-9', 'Boeing 777-300ER', 'A330-300']],
  EK: [['Boeing 777-300ER'], ['A380-800', 'Boeing 777-300ER', 'A350-900']], QR: [['A320', 'Boeing 737 MAX 8', 'Boeing 787-8'], ['A350-1000', 'Boeing 787-9', 'Boeing 777-300ER', 'A380-800']],
  AT: [['Boeing 737-800', 'Boeing 737 MAX 8'], ['Boeing 787-8', 'Boeing 787-9']], TU: [['A320neo', 'A319'], ['A330-200']],
  AH: [['Boeing 737-800', 'A330-200'], ['A330-900neo']], MS: [['A220-300', 'Boeing 737-800', 'A320neo'], ['Boeing 787-9', 'A330-300', 'Boeing 777-300ER']],
  HF: [['A320neo', 'A319'], ['A330-900neo']], DL: [['A321neo', 'Boeing 757-200'], ['A350-900', 'A330-900neo', 'Boeing 767-400ER']],
  AA: [['A321', 'Boeing 737-800'], ['Boeing 777-300ER', 'Boeing 787-9', 'Boeing 777-200ER']], UA: [['Boeing 737 MAX 9', 'A320'], ['Boeing 787-10', 'Boeing 777-300ER', 'Boeing 767-300ER']],
  AC: [['A220-300', 'A321'], ['Boeing 787-9', 'Boeing 777-300ER', 'A330-300']], TS: [['A321LR'], ['A330-300', 'A321LR']],
  LA: [['A320neo', 'A321'], ['Boeing 787-9', 'Boeing 777-300ER']], AM: [['Boeing 737 MAX 8'], ['Boeing 787-9', 'Boeing 787-8']],
  JL: [['Boeing 737-800'], ['A350-1000', 'Boeing 787-9', 'Boeing 777-300ER']], NH: [['Boeing 737-800'], ['Boeing 787-9', 'Boeing 777-300ER']],
  KE: [['A321neo', 'Boeing 737-900'], ['Boeing 777-300ER', 'A380-800', 'Boeing 787-9', 'A330-300']], SQ: [['Boeing 737 MAX 8'], ['A350-900', 'Boeing 777-300ER', 'A380-800', 'Boeing 787-10']],
  CX: [['A321neo'], ['A350-1000', 'A350-900', 'Boeing 777-300ER']], TG: [['A320neo'], ['A350-900', 'Boeing 777-300ER', 'Boeing 787-9']],
  AI: [['A320neo', 'A321neo'], ['Boeing 777-300ER', 'Boeing 787-8', 'A350-900']], QF: [['Boeing 737-800'], ['A380-800', 'Boeing 787-9', 'A330-300']],
  UU: [['Boeing 737-800'], ['Boeing 787-8', 'Boeing 777-300ER']], TX: [['A350-900'], ['A350-1000', 'A350-900']], SS: [['A330-900neo'], ['A330-900neo']],
  BF: [['A350-900'], ['A350-900', 'A350-1000']], U2: [['A320', 'A320neo', 'A321neo', 'A319'], ['A321neo']],
  FR: [['Boeing 737-800', 'Boeing 737 MAX 8-200'], ['Boeing 737 MAX 8-200']], VY: [['A320', 'A320neo', 'A321neo'], ['A321neo']],
  W6: [['A321neo', 'A320'], ['A321XLR']], TO: [['Boeing 737-800', 'A320neo', 'A321neo'], ['A321neo']], V7: [['A320', 'A319'], ['A320']],
  DY: [['Boeing 737-800', 'Boeing 737 MAX 8'], ['Boeing 737 MAX 8']], PC: [['A320neo', 'A321neo', 'Boeing 737-800'], ['A321neo']],
  B6: [['A321neo', 'A220-300'], ['A321LR']],
};
const PREMIUM = new Set(['EK', 'QR', 'SQ', 'CX', 'LX', 'NH', 'JL']);
const LIGHT_NO_BAG = new Set(['AF', 'KL', 'LH', 'BA', 'IB', 'AZ', 'LX', 'SN', 'OS', 'SK', 'TP', 'EI', 'DL', 'AA', 'UA', 'AC']);
const SHORT_MEAL = new Set(['TK', 'EK', 'QR', 'AT', 'TU', 'AH', 'MS', 'SQ', 'CX', 'JL', 'NH', 'KE', 'TG', 'AI', 'LX', 'AF']);
const FLEX_BASE = new Set(['JL', 'NH', 'SQ', 'AA', 'UA', 'DL', 'AC', 'EK', 'QR', 'TK']);
const efficient = ac => /neo|787|350|220|MAX|E2|XLR|LR/.test(ac);
const thirsty = ac => /380|747|340|777-200|767|757/.test(ac);

function basePrice(al, a, b, km) {
  const A = AL[al];
  let p;
  if (A.lowcost && km < 4200) p = km < 1000 ? 29 + .045 * km : 38 + .032 * km;
  else if (km < 1000) p = 70 + .07 * km;
  else if (km < 3000) p = 90 + .055 * km;
  else p = 150 + .048 * km;
  if (A.lowcost && km >= 4200) p *= .62;
  if (PREMIUM.has(al)) p *= 1.12;
  if (['AT', 'TU', 'AH', 'MS', 'PC'].includes(al)) p *= .9;
  if (['DL', 'AA', 'UA'].includes(al)) p *= 1.05;
  const n = carriersOnPair.get([a, b].sort().join('')) || 1;
  p *= Math.max(.84, 1.06 - .03 * n);
  return p;
}

// ---------- Numéros de vol ----------
const used = new Set();
for (const [k, pairs] of Object.entries(KNOWN_FN)) for (const p of pairs) p.forEach(n => used.add(k.split('|')[0] + n));
const pools = {};
function nextNumber(al, long) {
  const key = al + (long ? 'L' : 'S');
  if (!pools[key]) pools[key] = long ? (['AF', 'BA', 'EK', 'QR', 'TK', 'SQ', 'CX', 'JL', 'NH', 'QF', 'DL', 'AA', 'UA', 'AC', 'LA', 'AM', 'KE', 'TG', 'AI'].includes(al) ? 14 : 100 + (strHash(al) % 6) * 100) : (AL[al].lowcost ? 1000 + (strHash(al) % 7) * 1000 : 1000 + (strHash(al) % 3) * 200);
  for (;;) {
    let n = pools[key]; pools[key] += 2;
    if (n % 2) n += 1;
    const out = String(n).padStart(3, '0'), ret = String(n + 1).padStart(3, '0');
    if (!used.has(al + out) && !used.has(al + ret)) { used.add(al + out); used.add(al + ret); return [al + out, al + ret]; }
  }
}

// ---------- 1. Vols directs ----------
const directs = [];
for (const r of routes.values()) {
  const { al, a, b } = r;
  const A = AL[al];
  const km = dist(a, b), long = km >= 4200;
  const popSum = AP[a].pop + AP[b].pop;
  const key1 = `${al}|${r.base}|${r.base === a ? b : a}`;
  let f = FREQ[key1];
  if (!f) {
    if (A.lowcost) f = long ? 1 : popSum >= 17 ? 2 : 1;
    else if (km < 1500) f = popSum >= 18 ? 4 : popSum >= 16 ? 3 : popSum >= 13 ? 2 : 1;
    else if (!long) f = popSum >= 16 ? 2 : 1;
    else f = popSum >= 18 ? 2 : 1;
    if (!A.hubs.includes(a) && !A.hubs.includes(b)) f = 1;
  }
  const hubRoute = A.hubs.includes(a) || A.hubs.includes(b);
  let perWeek;
  if (f >= 2 || (!A.lowcost && hubRoute && Math.min(AP[a].pop, AP[b].pop) >= 6 && (!long || popSum >= 15))) perWeek = 7;
  else if (A.lowcost) perWeek = long ? 3 + Math.floor(rng() * 3) : popSum >= 15 ? 7 : 2 + Math.floor(rng() * 5);
  else perWeek = long ? 3 + Math.floor(rng() * 5) : 4 + Math.floor(rng() * 4);
  const patterns = WEEK_PATTERNS[perWeek];
  const pattern = patterns[strHash(a + b + al) % patterns.length];
  const fleet = FLEET[al][long || km > 3800 ? 1 : 0];
  const known = KNOWN_FN[key1];
  const outFrom = r.base === a ? a : b, outTo = outFrom === a ? b : a;
  for (let i = 0; i < f; i++) {
    const [fnOut, fnRet] = known && known[i] ? [al + known[i][0], al + known[i][1]] : nextNumber(al, long);
    used.add(fnOut); used.add(fnRet);
    const ac = fleet[(strHash(a + b) + i) % fleet.length];
    for (const [from, to, fn] of [[outFrom, outTo, fnOut], [outTo, outFrom, fnRet]]) {
      directs.push({ al, from, to, km, long, fn, ac, pattern, idx: i, f, outbound: from === outFrom });
    }
  }
}
// Horaires : répartis dans les vagues de chaque sens
const byDir = new Map();
for (const d of directs) { const k = d.al + d.from + d.to; if (!byDir.has(k)) byDir.set(k, []); byDir.get(k).push(d); }
for (const list of byDir.values()) {
  const d0 = list[0];
  const times = spreadTimes(list.length, windows(d0.from, d0.to, d0.km), AL[d0.al].lowcost, d0.al).sort((x, y) => x - y);
  list.forEach((d, i) => {
    d.dep = times[i];
    d.dur = blockTime(d.from, d.to);
    // vol de nuit long-courrier : le retour part le lendemain de l'arrivée → motif décalé d'un jour
    const arrDay = Math.floor((d.dep + d.dur + (AP[d.to].tz - AP[d.from].tz) * 60) / 1440);
    d.days = d.pattern;
    if (d.long && !d.outbound) d.days = d.pattern.slice(-1) + d.pattern.slice(0, -1);
    d.arrLocal = d.dep + d.dur + (AP[d.to].tz - AP[d.from].tz) * 60;
    d.arrDay = arrDay;
  });
}
function services(al, km, ac) {
  const A = AL[al], long = km >= 4200;
  const cab = A.lowcost && !long && al !== 'B6' ? 0 : 1;
  const hold = A.lowcost ? 0 : long ? 1 : LIGHT_NO_BAG.has(al) ? 0 : 1;
  const meal = long ? (['BF'].includes(al) ? 0 : 1) : SHORT_MEAL.has(al) ? 1 : 0;
  const wifi = rng() < A.wifi ? 1 : 0;
  const pwr = rng() < (long ? (A.lowcost ? .6 : .9) : efficient(ac) ? .7 : .25) ? 1 : 0;
  const refund = A.lowcost ? 0 : FLEX_BASE.has(al) ? 1 : long && rng() < .4 ? 1 : 0;
  const perKm = km < 1500 ? .1 : km < 4200 ? .08 : .065;
  const co2 = km * perKm * (efficient(ac) ? .84 : thirsty(ac) ? 1.15 : 1);
  const ontime = Math.max(45, Math.min(97, Math.round(A.ontime + between(-7, 7))));
  return { cab, hold, meal, wifi, pwr, refund, co2, ontime };
}
for (const d of directs) {
  Object.assign(d, services(d.al, d.km, d.ac));
  d.price = basePrice(d.al, d.from, d.to, d.km) * between(.9, 1.12);
}

// ---------- 2. Correspondances ----------
const MCT = { CDG: 70, LHR: 75, FRA: 50, MUC: 40, AMS: 50, IST: 70, DXB: 75, DOH: 60, MAD: 50, FCO: 55, ZRH: 40, VIE: 30, CPH: 35, LIS: 55, BRU: 45, JFK: 90, MIA: 75, LAX: 90, SFO: 70, YUL: 60, SIN: 50, HKG: 55, HND: 60, ICN: 60, BKK: 60, DEL: 75, CMN: 60, CAI: 60, GRU: 75, MEX: 70 };
const PARTNERS = new Set(['EK|QF', 'QF|EK']);
const compatible = (a, b) => a === b || PARTNERS.has(a + '|' + b) || (AL[a].alliance !== 'Aucune' && AL[a].alliance === AL[b].alliance);
const cityOf = c => AP[c].city;
const directByFrom = new Map();
for (const d of directs) { if (!directByFrom.has(d.from)) directByFrom.set(d.from, []); directByFrom.get(d.from).push(d); }
const directCount = new Map();
for (const d of directs) { const k = d.from + d.to; directCount.set(k, (directCount.get(k) || 0) + 1); }
const hubsOf = new Set(REF.airlines.filter(a => !a.lowcost).flatMap(a => a.hubs));

// Jours d'opération combinés : jour du 1er vol où le 2e vol part aussi (décalage de jours pris en compte)
function combineDays(d1, dayShift, d2) {
  let s = '';
  for (let i = 0; i < 7; i++) s += d1.days[i] === '1' && d2.days[(i + dayShift) % 7] === '1' ? '1' : '0';
  return s;
}
function connect(first, H, second) {
  // first : vol arrivant en H (heure locale de H relative au jour de départ du 1er vol) ; second : vol partant de H
  const mct = (MCT[H] || 60) + (first.al === second.al ? 0 : 15);
  for (const k of [0, 1, 2]) {
    const dep2 = second.dep + k * 1440;
    const lay = dep2 - first.arrLocal;
    if (lay >= mct && lay <= (second.long ? 720 : 360)) return { lay, dayShift: Math.floor(dep2 / 1440) };
  }
  return null;
}
const conns = [];
for (const s1 of directs) {
  if (AL[s1.al].lowcost || !hubsOf.has(s1.to)) continue;
  const H = s1.to, O = s1.from;
  const best = new Map();
  for (const s2 of directByFrom.get(H) || []) {
    if (AL[s2.al].lowcost || s2.to === O || cityOf(s2.to) === cityOf(O) || !compatible(s1.al, s2.al)) continue;
    const D = s2.to, od = dist(O, D);
    if (od < 450 || s1.km + s2.km > od * 1.45 + 300) continue;
    const c = connect(s1, H, s2);
    if (!c) continue;
    const days = combineDays(s1, c.dayShift, s2);
    if (!days.includes('1')) continue;
    const prev = best.get(D);
    if (!prev || c.lay < prev.lay) best.set(D, { legs: [s1, s2], lay: [c.lay], days, O, D, od });
  }
  conns.push(...best.values());
}
// Deux escales, uniquement pour les paires sans vol direct ni à une escale (ex. Nantes → Sydney)
const oneStopPairs = new Set(conns.map(c => c.O + c.D));
const twoStops = [];
for (const c of conns) {
  const last = c.legs[1], H2 = last.to;
  if (!hubsOf.has(H2)) continue;
  const arr = { arrLocal: c.legs[0].dep + c.legs[0].dur + c.lay[0] + last.dur + (AP[H2].tz - AP[c.O].tz) * 60, al: last.al };
  for (const s3 of directByFrom.get(H2) || []) {
    const D = s3.to;
    if (AL[s3.al].lowcost || !compatible(last.al, s3.al) || cityOf(D) === cityOf(c.O) || D === c.legs[0].to) continue;
    if (directCount.get(c.O + D) || oneStopPairs.has(c.O + D)) continue;
    const od = dist(c.O, D);
    if (c.legs[0].km + last.km + s3.km > od * 1.5 + 500) continue;
    const k = connect(arr, H2, s3);
    if (!k) continue;
    const days = combineDays({ days: c.days }, k.dayShift, s3);
    if (!days.includes('1')) continue;
    twoStops.push({ legs: [c.legs[0], last, s3], lay: [c.lay[0], k.lay], days, O: c.O, D, od });
  }
}
// Sélection pondérée par la demande, en privilégiant les paires mal desservies en direct
const perPair = new Map();
function weight(c) {
  const direct = directCount.get(c.O + c.D) || 0;
  const demand = AP[c.O].pop * AP[c.D].pop;
  const layPenalty = c.lay.reduce((s, x) => s + x, 0) > 360 ? .5 : 1;
  return demand * (direct === 0 ? 3 : direct < 3 ? 1.3 : .35) * layPenalty * (c.legs.length === 3 ? .6 : 1);
}
const pool = [...conns, ...twoStops.filter((_, i) => i % 3 === 0)].map(c => ({ c, key: Math.pow(rng(), 1 / weight(c)) }));
pool.sort((x, y) => y.key - x.key);
const room = TOTAL - directs.length;
if (room < 0) throw new Error(`Trop de vols directs (${directs.length}) : réduisez les fréquences`);
const chosen = [];
for (const { c } of pool) {
  if (chosen.length >= room) break;
  const k = c.O + c.D, n = perPair.get(k) || 0;
  if (n >= 14) continue;
  perPair.set(k, n + 1);
  chosen.push(c);
}

// ---------- Écriture ----------
const header = 'id;al;fn;from;to;via;dep;dur;lay;days;ac;price;cab;hold;meal;wifi;pwr;refund;co2;ontime;ld';
const lines = [header];
let id = 0;
for (const d of directs) {
  lines.push([++id, d.al, d.fn, d.from, d.to, '', d.dep, d.dur, '', d.days, d.ac, Math.round(d.price), d.cab, d.hold, d.meal, d.wifi, d.pwr, d.refund, Math.round(d.co2), d.ontime, d.dur].join(';'));
}
for (const c of chosen) {
  const L = c.legs;
  const dur = L.reduce((s, l) => s + l.dur, 0) + c.lay.reduce((s, x) => s + x, 0);
  const factor = L.length === 3 ? .7 : .78;
  const price = Math.max(...L.map(l => basePrice(l.al, l.from, l.to, l.km))) * .2 + basePrice(L[0].al, c.O, c.D, c.od) * factor * between(.92, 1.1);
  const all = k => L.every(l => l[k]) ? 1 : 0;
  lines.push([++id, L[0].al, L.map(l => l.fn).join('+'), c.O, c.D, L.slice(1).map(l => l.from).join('-'), L[0].dep, dur, c.lay.join('-'), c.days,
    L.map(l => l.ac).join('|'), Math.round(price), all('cab'), all('hold'), L.some(l => l.meal) ? 1 : 0, all('wifi'), all('pwr'), Math.min(...L.map(l => l.refund)),
    Math.round(L.reduce((s, l) => s + l.co2, 0)), Math.min(...L.map(l => l.ontime)), L.map(l => l.dur).join('-')].join(';'));
}

const out = path.join(__dirname, '..', 'data');
const csv = lines.join('\n');
fs.writeFileSync(path.join(out, 'flights.csv'), csv);
fs.writeFileSync(path.join(out, 'flights.js'), '/* Généré par scripts/generate-db.js — copie de flights.csv pour ouverture sans serveur */\nwindow.FLIGHTS_CSV = `' + csv + '`;\n');
fs.writeFileSync(path.join(out, 'reference.json'), JSON.stringify(REF));
try {
  const photosSrc = fs.readFileSync(path.join(out, 'photos.js'), 'utf8');
  const json = photosSrc.slice(photosSrc.indexOf('{'), photosSrc.lastIndexOf('}') + 1);
  fs.writeFileSync(path.join(out, 'photos.json'), JSON.stringify(JSON.parse(json)));
} catch (e) { console.warn('photos.json non généré :', e.message); }

const stats = { total: lines.length - 1, directs: directs.length, routes: routes.size, oneStop: chosen.filter(c => c.legs.length === 2).length, twoStops: chosen.filter(c => c.legs.length === 3).length, pairs: new Set(lines.slice(1).map(l => l.split(';').slice(3, 5).join('-'))).size };
console.log('Base générée :', stats);
