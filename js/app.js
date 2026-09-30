/* ================= Envol — application ================= */
(() => {
  'use strict';

  // ---------- Utilitaires ----------
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const norm = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const icon = (id, cls = '') => `<svg class="${cls}" aria-hidden="true"><use href="#i-${id}"/></svg>`;
  const store = {
    get(k, d) { try { const v = localStorage.getItem('envol.' + k); return v ? JSON.parse(v) : d; } catch { return d; } },
    set(k, v) { try { localStorage.setItem('envol.' + k, JSON.stringify(v)); } catch { /* stockage indisponible */ } },
  };
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Dates en UTC pur (chaînes AAAA-MM-JJ) : aucun décalage de fuseau navigateur
  const toISO = d => d.toISOString().slice(0, 10);
  const parseISO = s => { const [y, m, d] = s.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); };
  const addDays = (s, n) => { const d = parseISO(s); d.setUTCDate(d.getUTCDate() + n); return toISO(d); };
  const addMonths = (m, n) => { const d = parseISO(m + '-01'); d.setUTCMonth(d.getUTCMonth() + n); return toISO(d).slice(0, 7); };
  const diffDays = (a, b) => Math.round((parseISO(b) - parseISO(a)) / 864e5);
  const now = new Date();
  const TODAY = toISO(new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())));
  const fmtD = (s, o = { weekday: 'short', day: 'numeric', month: 'short' }) => new Intl.DateTimeFormat('fr-FR', { ...o, timeZone: 'UTC' }).format(parseISO(s));
  const longD = s => fmtD(s, { weekday: 'long', day: 'numeric', month: 'long' });
  const hm = m => { m = ((m % 1440) + 1440) % 1440; return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
  const dayOff = m => Math.floor(m / 1440);
  const fmtDur = m => `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}`;
  const plural = (n, w) => `${n} ${w}${n > 1 ? 's' : ''}`;
  function hash01(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return ((h >>> 0) % 100000) / 100000; }

  // ---------- Référentiel ----------
  const { airports, airlines } = window.REF;
  const PHOTOS = window.PHOTOS || {};
  const AP = Object.fromEntries(airports.map(a => [a.code, a]));
  const AL = Object.fromEntries(airlines.map(a => [a.code, a]));
  const GROUPS = {
    PAR: { code: 'PAR', city: 'Paris', country: 'France', members: ['CDG', 'ORY'] },
    LON: { code: 'LON', city: 'Londres', country: 'Royaume-Uni', members: ['LHR', 'LGW'] },
  };
  const expand = c => GROUPS[c] ? GROUPS[c].members : [c];
  const placeOf = c => GROUPS[c] || AP[c];
  const cityOf = c => placeOf(c)?.city || c;
  const cityCode = c => Object.values(GROUPS).find(g => g.members.includes(c))?.code || c;
  const countryOf = c => placeOf(c)?.country || '';
  const photo = (code, w = 800) => {
    const p = PHOTOS[code] || PHOTOS[expand(code)[0]];
    return p ? `${p.u}?w=${w}&q=72&auto=format&fit=crop` : '';
  };
  const img = (code, w, alt = '') => { const u = photo(code, w); return u ? `<img src="${u}" srcset="${u} 1x, ${photo(code, w * 2)} 2x" alt="${esc(alt)}" loading="lazy" decoding="async">` : ''; };

  function dist(a, b) {
    const A = AP[a], B = AP[b], r = Math.PI / 180;
    const h = Math.sin((B.lat - A.lat) * r / 2) ** 2 + Math.cos(A.lat * r) * Math.cos(B.lat * r) * Math.sin((B.lon - A.lon) * r / 2) ** 2;
    return 2 * 6371 * Math.asin(Math.sqrt(h));
  }
  const legMinutes = km => Math.round((km / 800 * 60 + 35) / 5) * 5; // même formule que le générateur

  // ---------- Base de données texte ----------
  let FL = [];
  const FLID = new Map(), byRoute = new Map(), byFrom = new Map();
  function parseDB(csv) {
    const rows = csv.trim().split('\n');
    rows.shift();
    FL = rows.map(line => {
      const p = line.split(';');
      const acs = p[10].split('|'), ld = p[20] ? p[20].split('-').map(Number) : null;
      const f = {
        id: +p[0], al: p[1], fn: p[2].split('+'), from: p[3], to: p[4], via: p[5] ? p[5].split('-') : [],
        dep: +p[6], dur: +p[7], lay: p[8] ? p[8].split('-').map(Number) : [], days: p[9], ac: acs[0], base: +p[11],
        cab: +p[12], hold: +p[13], meal: +p[14], wifi: +p[15], pwr: +p[16], refund: +p[17], co2: +p[18], ontime: +p[19],
      };
      const pts = [f.from, ...f.via, f.to];
      f.legs = pts.slice(0, -1).map((a, i) => { const km = dist(a, pts[i + 1]); const fn = f.fn[i] || f.fn[0]; return { from: a, to: pts[i + 1], km, min: ld ? ld[i] : legMinutes(km), fn, al: fn.slice(0, 2), ac: acs[i] || acs[0] }; });
      f.long = f.legs.some(l => l.km > 4000);
      return f;
    });
    for (const f of FL) {
      FLID.set(f.id, f);
      const k = f.from + '-' + f.to;
      if (!byRoute.has(k)) byRoute.set(k, []);
      byRoute.get(k).push(f);
      if (!byFrom.has(f.from)) byFrom.set(f.from, []);
      byFrom.get(f.from).push(f);
    }
  }

  // ---------- Modèle de prix simulé (déterministe) ----------
  const CABINS = { eco: 'Économique', prem: 'Premium', bus: 'Affaires', first: 'Première' };
  const FIRST = new Set(['AF', 'EK', 'QR', 'SQ', 'LH', 'BA', 'JL', 'NH', 'CX', 'LX', 'AA']);
  // Saisonnalité : profil mensuel de la destination (interpolé jour par jour) × vacances scolaires / pics connus
  const SEASONS = window.REF.seasons, HOLIDAYS = window.REF.holidays;
  const IN_FRANCE = new Set(airports.filter(a => a.country === 'France').map(a => a.code));
  const IN_US = new Set(['JFK', 'MIA', 'LAX', 'SFO']);
  const routeProfile = (from, to) => (IN_FRANCE.has(to) && !IN_FRANCE.has(from)) ? AP[from].season : AP[to].season;
  const monthCache = new Map();
  function monthFactor(profile, date) {
    const k = profile + date;
    if (monthCache.has(k)) return monthCache.get(k);
    const S = SEASONS[profile], d = parseISO(date), m = d.getUTCMonth();
    const dim = new Date(Date.UTC(d.getUTCFullYear(), m + 1, 0)).getUTCDate();
    const pos = (d.getUTCDate() - .5) / dim;
    const v = pos < .5 ? S[(m + 11) % 12] + (S[m] - S[(m + 11) % 12]) * (pos + .5) : S[m] + (S[(m + 1) % 12] - S[m]) * (pos - .5);
    monthCache.set(k, v);
    return v;
  }
  function holidayOf(from, to, date) {
    return HOLIDAYS.filter(h => date >= h.from && date <= h.to && ((h.fr && (IN_FRANCE.has(from) || IN_FRANCE.has(to))) || (h.us && (IN_US.has(from) || IN_US.has(to)))));
  }
  const holidayCache = new Map();
  function holidayFactor(from, to, date) {
    const k = (IN_FRANCE.has(from) || IN_FRANCE.has(to) ? 'F' : '') + (IN_US.has(from) || IN_US.has(to) ? 'U' : '') + date;
    if (!holidayCache.has(k)) holidayCache.set(k, holidayOf(from, to, date).reduce((a, h) => a * h.k, 1));
    return holidayCache.get(k);
  }
  // Courbe d'anticipation : le moins cher vers 3 à 8 semaines (court-courrier) ou 2 à 6 mois (long-courrier)
  function bookingFactor(ahead, long) {
    if (ahead < 0) return null;
    if (long) return ahead < 7 ? 1.55 : ahead < 14 ? 1.35 : ahead < 30 ? 1.15 : ahead < 60 ? 1.0 : ahead < 120 ? .92 : ahead < 240 ? .9 : .95;
    return ahead < 3 ? 1.7 : ahead < 7 ? 1.4 : ahead < 14 ? 1.18 : ahead < 21 ? 1.06 : ahead < 45 ? .95 : ahead < 90 ? .92 : ahead < 180 ? .96 : 1;
  }
  const DOW = [.98, .92, .9, 1.0, 1.12, .97, 1.1]; // lun → dim : mardi et mercredi les moins chers
  const todFactor = m => m < 420 ? .9 : m < 600 ? 1.02 : m < 960 ? 1.0 : m < 1200 ? 1.06 : .93; // vols très matinaux et tardifs moins chers
  const dayCache = new Map();
  function dayInfo(date, asOf) {
    const k = date + asOf;
    let v = dayCache.get(k);
    if (!v) { v = { dow: (parseISO(date).getUTCDay() + 6) % 7, ahead: diffDays(asOf, date) }; dayCache.set(k, v); }
    return v;
  }
  function priceFor(f, date, cabin = 'eco', asOf = TODAY) {
    const di = dayInfo(date, asOf);
    if (di.ahead < 0 || f.days[di.dow] !== '1') return null;
    let mult = 1;
    const low = AL[f.al].lowcost;
    if (cabin === 'prem') { if (!f.long || low) return null; mult = 1.75; }
    if (cabin === 'bus') { if (low && !f.long) return null; mult = f.long ? 3.6 : 2.3; }
    if (cabin === 'first') { if (!f.long || !FIRST.has(f.al)) return null; mult = 6.8; }
    const season = monthFactor(routeProfile(f.from, f.to), date) * holidayFactor(f.from, f.to, date);
    const demand = .9 + hash01(f.id + '|' + date + '|' + asOf.slice(5)) * .22; // remplissage du vol ce jour-là
    let p = f.base * season * bookingFactor(di.ahead, f.long) * DOW[di.dow] * todFactor(f.dep) * demand * mult;
    p = Math.max(p, f.base * .6 * mult * demand);
    return low && p >= 20 ? Math.floor(p / 10) * 10 + 9 : Math.round(p); // les low-cost affichent des prix en …9 €
  }
  // Explication lisible du niveau de prix d'une date (utilisée dans le conseil et les infobulles)
  function seasonNote(from, to, date) {
    const f = monthFactor(routeProfile(expand(from)[0], expand(to)[0]), date);
    const h = holidayOf(expand(from)[0], expand(to)[0], date);
    const label = REF_SEASON_LABEL[routeProfile(expand(from)[0], expand(to)[0])];
    const parts = [];
    if (f >= 1.15) parts.push(`haute saison (${label})`);
    else if (f <= .9) parts.push(`basse saison (${label})`);
    h.forEach(x => parts.push(x.label.toLowerCase()));
    return parts.join(' · ');
  }
  const REF_SEASON_LABEL = window.REF.seasonLabels;

  // ---------- Devises ----------
  const FX = { EUR: 1, USD: 1.08, GBP: .85, CHF: .94, CAD: 1.49, MAD: 10.8 };
  let currency = store.get('cur', 'EUR');
  const fmts = {};
  const money = eur => (fmts[currency] ||= new Intl.NumberFormat('fr-FR', { style: 'currency', currency, maximumFractionDigits: 0 })).format(eur * FX[currency]);

  // ---------- État ----------
  const S = { from: 'PAR', to: null, dep: addDays(TODAY, 21), ret: addDays(TODAY, 28), trip: 'rt', adults: 1, children: 0, infants: 0, cabin: 'eco', direct: false, bag: false };
  const R = { step: 1, results: [], filtered: [], sort: 'best', view: 'list', shown: 0, out: null, F: null, compare: [], lastKey: '', withBag: store.get('withBag', false) };
  let recent = store.get('recent', []);
  // Coût d'un bagage en soute quand le tarif ne l'inclut pas (grille publique moyenne de chaque compagnie)
  const bagCost = r => r.hold ? 0 : r.flights.reduce((s, f) => s + (f.hold ? 0 : (AL[f.al].bagFee.hold || 30)), 0);
  let favs = store.get('favs', []);
  let alerts = store.get('alerts', []);
  const paxCount = () => S.adults + S.children + S.infants;
  const paxTotal = p => Math.round(p * S.adults + p * .75 * S.children + p * .1 * S.infants);

  // ---------- Résultats (billet unique ou billets séparés) ----------
  function segments(flights, offs) {
    const out = [];
    flights.forEach((f, i) => {
      let t = offs[i] * 1440 + f.dep - AP[f.from].tz * 60;
      f.legs.forEach((lg, j) => {
        if (j > 0) { out.push({ type: 'lay', at: lg.from, min: f.lay[j - 1], self: false, start: t }); t += f.lay[j - 1]; }
        out.push({ type: 'leg', ...lg, depU: t, arrU: t + lg.min });
        t += lg.min;
      });
      if (i < flights.length - 1) {
        const n = flights[i + 1], nd = offs[i + 1] * 1440 + n.dep - AP[n.from].tz * 60;
        out.push({ type: 'lay', at: n.from, min: nd - t, self: true, start: t });
      }
    });
    return out;
  }
  function mkResult(flights, date, offs, prices, cabin = S.cabin) {
    const sg = segments(flights, offs);
    const legs = sg.filter(s => s.type === 'leg'), lays = sg.filter(s => s.type === 'lay');
    const first = legs[0], last = legs[legs.length - 1];
    const from = first.from, to = last.to;
    const key = flights.map(f => f.id).join('+') + '@' + date + (offs.some(Boolean) ? '~' + offs.join('') : '') + ':' + cabin;
    return {
      key, flights, date, offs, cabin, segs: sg, from, to, price: prices.reduce((a, b) => a + b, 0),
      dep: first.depU + AP[from].tz * 60, arr: last.arrU + AP[to].tz * 60, dur: last.arrU - first.depU,
      stops: lays.length, lays, self: flights.length > 1, al: flights[0].al, carriers: [...new Set(legs.map(l => l.al))],
      hold: flights.every(f => f.hold), cab: flights.every(f => f.cab), meal: flights.some(f => f.meal), wifi: flights.some(f => f.wifi), pwr: flights.some(f => f.pwr),
      refund: Math.min(...flights.map(f => f.refund)), co2: flights.reduce((a, f) => a + f.co2, 0), ontime: Math.min(...flights.map(f => f.ontime)),
      lowcost: flights.some(f => AL[f.al].lowcost), overnight: lays.some(l => l.min >= 420),
      seats: 1 + Math.floor(hash01(key) * 9), aircraft: [...new Set(legs.map(l => l.ac))], fns: legs.map(l => l.fn),
    };
  }
  function resultFromKey(key) {
    const m = key.match(/^([\d+]+)@(\d{4}-\d\d-\d\d)(?:~(\d+))?:(\w+)$/);
    if (!m) return null;
    const flights = m[1].split('+').map(id => FLID.get(+id));
    if (flights.some(f => !f)) return null;
    const offs = m[3] ? m[3].split('').map(Number) : flights.map(() => 0);
    const prices = flights.map((f, i) => priceFor(f, addDays(m[2], offs[i]), m[4]));
    if (prices.some(p => p === null)) return null;
    return mkResult(flights, m[2], offs, prices, m[4]);
  }

  // ---------- Moteur de recherche ----------
  function searchLeg(from, to, date, cabin = S.cabin) {
    const out = [], origins = expand(from), dests = expand(to);
    for (const o of origins) for (const d of dests) {
      for (const f of byRoute.get(o + '-' + d) || []) {
        const p = priceFor(f, date, cabin);
        if (p !== null) out.push(mkResult([f], date, [0], [p], cabin));
      }
    }
    out.push(...combos(origins, dests, date, cabin));
    const seen = new Set();
    return out.filter(r => !seen.has(r.key) && seen.add(r.key));
  }
  // « Combinaisons malines » : deux billets séparés via une ville tierce
  function combos(origins, dests, date, cabin) {
    const found = [];
    for (const o of origins) {
      for (const f1 of byFrom.get(o) || []) {
        if (f1.via.length || origins.includes(f1.to) || dests.includes(f1.to)) continue;
        const X = f1.to;
        let p1;
        for (const d of dests) {
          if (dist(o, X) + dist(X, d) > dist(o, d) * 1.45 + 400) continue;
          const list = byRoute.get(X + '-' + d);
          if (!list) continue;
          if (p1 === undefined) p1 = priceFor(f1, date, cabin);
          if (p1 === null) break;
          const arr1 = f1.dep - AP[o].tz * 60 + f1.dur;
          for (const f2 of list) {
            if (f2.via.length || f2.al === f1.al) continue;
            for (const k of [0, 1]) {
              const lay = k * 1440 + f2.dep - AP[X].tz * 60 - arr1;
              if (lay < 150 || lay > 1080) continue;
              const p2 = priceFor(f2, addDays(date, k), cabin);
              if (p2 === null) continue;
              found.push([f1, f2, k, p1, p2]);
              break;
            }
          }
        }
      }
    }
    found.sort((a, b) => (a[3] + a[4]) - (b[3] + b[4]));
    return found.slice(0, 30).map(([f1, f2, k, p1, p2]) => mkResult([f1, f2], date, [0, k], [p1, p2], cabin));
  }
  const minCache = new Map();
  function minPrice(from, to, date, cabin = S.cabin) {
    const k = from + to + date + cabin;
    if (minCache.has(k)) return minCache.get(k);
    let m = null;
    for (const o of expand(from)) for (const d of expand(to)) for (const f of byRoute.get(o + '-' + d) || []) {
      const p = priceFor(f, date, cabin);
      if (p !== null && (m === null || p < m)) m = p;
    }
    if (m === null) { const c = combos(expand(from), expand(to), date, cabin); m = c.length ? c[0].price : null; }
    minCache.set(k, m);
    return m;
  }
  function level(p, list) {
    const s = list.filter(x => x != null).sort((a, b) => a - b);
    if (!s.length || p == null) return '';
    const lo = s[Math.floor(s.length / 3)], hi = s[Math.floor(s.length * 2 / 3)];
    return p <= lo ? 'low' : p >= hi ? 'high' : 'mid';
  }
  // Destinations les moins chères depuis une origine, sur une plage de dates
  function cheapestFrom(origin, dates, directOnly = false) {
    const best = new Map(), own = expand(origin);
    for (const o of own) {
      for (const f of byFrom.get(o) || []) {
        if (directOnly && f.via.length) continue;
        const cc = cityCode(f.to);
        if (own.includes(f.to) || cc === origin) continue;
        let cur = best.get(cc);
        for (const d of dates) {
          const p = priceFor(f, d, 'eco');
          if (p === null) continue;
          if (!cur) { cur = { code: cc, ap: f.to, price: p, date: d, dur: f.dur, direct: !f.via.length }; best.set(cc, cur); }
          else if (p < cur.price) Object.assign(cur, { ap: f.to, price: p, date: d });
        }
        if (cur) { cur.dur = Math.min(cur.dur, f.dur); if (!f.via.length) cur.direct = true; }
      }
    }
    return [...best.values()].sort((a, b) => a.price - b.price);
  }

  // ---------- Logos ----------
  function logo(code, size = '') {
    const a = AL[code] || { name: code, color: '#111' };
    return `<span class="logo ${size}" style="--c:${a.color}" title="${esc(a.name)}">${code}<img src="https://pics.avs.io/al_square/64/64/${code}.png" alt="" loading="lazy" decoding="async" data-code="${code}"></span>`;
  }
  document.addEventListener('error', e => {
    const im = e.target;
    if (im.tagName !== 'IMG') return;
    if (im.dataset.code) {
      if (!im.dataset.fb) { im.dataset.fb = '1'; im.src = `https://images.kiwi.com/airlines/64/${im.dataset.code}.png`; }
      else im.remove(); // repli : monogramme aux couleurs de la compagnie
    } else im.style.visibility = 'hidden';
  }, true);

  // ---------- Toast / infobulle ----------
  let toastT;
  function toast(msg, ic = 'check') {
    const t = $('#toast');
    t.innerHTML = icon(ic) + esc(msg);
    t.classList.add('show');
    clearTimeout(toastT);
    toastT = setTimeout(() => t.classList.remove('show'), 2600);
  }
  const tipEl = document.createElement('div');
  tipEl.className = 'tip'; tipEl.hidden = true; document.body.appendChild(tipEl);
  function showTip(html, x, y) {
    tipEl.innerHTML = html; tipEl.hidden = false;
    const r = tipEl.getBoundingClientRect();
    tipEl.style.left = clamp(x - r.width / 2, 8, innerWidth - r.width - 8) + 'px';
    tipEl.style.top = (y - r.height - 10 < 8 ? y + 16 : y - r.height - 10) + 'px';
  }
  const hideTip = () => { tipEl.hidden = true; };
  document.addEventListener('mouseover', e => {
    const t = e.target.closest('[data-tip]');
    if (!t) return;
    const r = t.getBoundingClientRect();
    showTip(t.dataset.tip, r.left + r.width / 2, r.top);
  });
  document.addEventListener('mouseout', e => { if (e.target.closest('[data-tip]')) hideTip(); });

  const porthole = (code = 'HERO2', cls = '') => `<div class="porthole ${cls}"><div class="ph-glass">${img(code, 300)}</div></div>`;

  // ================= FORMULAIRE =================
  function placeLabel(code) {
    const p = placeOf(code);
    if (!p) return '';
    return GROUPS[code] ? `<b>${code}</b>Tous les aéroports · ${esc(p.members.join(', '))}` : `<b>${code}</b>${esc(p.name)} · ${esc(p.country)}`;
  }
  function syncForm() {
    $$('[data-trip]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.trip === S.trip)));
    for (const w of ['from', 'to']) {
      const c = S[w];
      $(`#${w}Input`).value = c ? cityOf(c) : '';
      $(`#${w}Sub`).innerHTML = c ? placeLabel(c) : (w === 'to' ? 'Ville, aéroport ou « partout »' : '');
    }
    $('#depVal').textContent = S.dep ? fmtD(S.dep, { day: 'numeric', month: 'short' }) : '—';
    $('#depSub').textContent = S.dep ? fmtD(S.dep, { weekday: 'long' }) : '';
    const rb = $('#retBtn');
    rb.disabled = S.trip === 'ow';
    $('#retVal').textContent = S.trip === 'ow' ? 'Aller simple' : S.ret ? fmtD(S.ret, { day: 'numeric', month: 'short' }) : 'Choisir';
    $('#retVal').classList.toggle('placeholder', S.trip === 'ow' || !S.ret);
    $('#retSub').textContent = S.trip === 'rt' && S.ret ? fmtD(S.ret, { weekday: 'long' }) + ' · ' + plural(diffDays(S.dep, S.ret), 'nuit') : '';
    const parts = [plural(S.adults, 'adulte')];
    if (S.children) parts.push(plural(S.children, 'enfant'));
    if (S.infants) parts.push(plural(S.infants, 'bébé'));
    $('#paxVal').textContent = parts.join(', ');
    $('#cabVal').textContent = CABINS[S.cabin];
    $('#qDirect').checked = S.direct; $('#qBag').checked = S.bag;
  }
  $$('[data-trip]').forEach(b => b.addEventListener('click', () => {
    S.trip = b.dataset.trip;
    if (S.trip === 'rt' && (!S.ret || S.ret <= S.dep)) S.ret = addDays(S.dep, 7);
    syncForm();
  }));
  $('#qDirect').addEventListener('change', e => { S.direct = e.target.checked; });
  $('#qBag').addEventListener('change', e => { S.bag = e.target.checked; });
  $('#swapBtn').addEventListener('click', () => { if (!S.to) return; [S.from, S.to] = [S.to, S.from]; syncForm(); renderHome(); });

  // ---------- Popovers ----------
  let openPop = null;
  function place(pop, anchor, align = 'left') {
    pop.hidden = false;
    const r = anchor.getBoundingClientRect(), w = pop.offsetWidth;
    let left = align === 'right' ? r.right - w : r.left;
    left = clamp(left, 12, document.documentElement.clientWidth - w - 12);
    pop.style.left = left + scrollX + 'px';
    pop.style.top = r.bottom + scrollY + 8 + 'px';
    openPop = pop;
  }
  function closePops(except) {
    ['#acPop', '#calPop', '#paxPop'].forEach(s => { const p = $(s); if (p !== except) p.hidden = true; });
    $$('.sf.active').forEach(f => f.classList.remove('active'));
    $$('[role=combobox]').forEach(i => i.setAttribute('aria-expanded', 'false'));
    if (!except) openPop = null;
  }
  document.addEventListener('pointerdown', e => {
    if (!openPop || openPop.hidden) return;
    if (e.target.closest('.popover, .sf, .origin-link')) return;
    closePops();
  });

  // ---------- Autocomplétion ----------
  let acMode = null, acItems = [], acIndex = 0;
  const POPULAR = airports.filter(a => a.pop >= 9).map(a => a.code);
  function acSearch(q, which) {
    const n = norm(q.trim());
    const items = [];
    if (!n) {
      if (which === 'to') items.push({ type: 'anywhere' });
      items.push({ type: 'head', label: 'Destinations populaires' });
      if (which !== 'to') Object.values(GROUPS).forEach(g => items.push({ type: 'group', code: g.code }));
      POPULAR.filter(c => !(which !== 'to' && expand('PAR').concat(expand('LON')).includes(c))).forEach(c => items.push({ type: 'ap', code: c }));
      return items.slice(0, 12);
    }
    const score = (city, code, extra) => {
      const nc = norm(city), cc = code.toLowerCase();
      if (cc === n) return 0;
      if (nc.startsWith(n)) return 1;
      if (cc.startsWith(n)) return 2;
      if (nc.includes(n) || norm(extra).includes(n)) return 3;
      return 9;
    };
    const scored = [];
    Object.values(GROUPS).forEach(g => { const s = score(g.city, g.code, g.country); if (s < 9) scored.push({ s: s - .5, type: 'group', code: g.code }); });
    airports.forEach(a => { const s = score(a.city, a.code, a.name + ' ' + a.country); if (s < 9) scored.push({ s, type: 'ap', code: a.code, pop: a.pop }); });
    scored.sort((a, b) => a.s - b.s || (b.pop || 0) - (a.pop || 0));
    const seen = new Set();
    for (const it of scored) {
      if (seen.has(it.code)) continue;
      seen.add(it.code); items.push(it);
      if (it.type === 'group') GROUPS[it.code].members.forEach(m => { seen.add(m); items.push({ type: 'ap', code: m, sub: true }); });
    }
    return items.slice(0, 10);
  }
  function hl(text, q) {
    const n = norm(q.trim()), i = n ? norm(text).indexOf(n) : -1;
    return i < 0 ? esc(text) : esc(text.slice(0, i)) + '<mark>' + esc(text.slice(i, i + n.length)) + '</mark>' + esc(text.slice(i + n.length));
  }
  function renderAC(anchor, mode, q = '') {
    acMode = mode;
    acItems = acSearch(q, mode === 'ex' ? 'from' : mode);
    acIndex = acItems.findIndex(i => i.type !== 'head');
    $('#acList').innerHTML = acItems.length ? acItems.map((it, i) => {
      if (it.type === 'head') return `<li class="ac-group" role="presentation">${it.label}</li>`;
      if (it.type === 'anywhere') return `<li role="option" id="ac-${i}" data-i="${i}" aria-selected="${i === acIndex}"><span class="ac-ic">${icon('pin')}</span><span class="ac-t"><b>Partout</b><span>Voir toutes les destinations sur la carte</span></span></li>`;
      const p = placeOf(it.code);
      const sub = it.type === 'group' ? `Tous les aéroports · ${p.country}` : `${p.name} · ${p.country}`;
      return `<li role="option" id="ac-${i}" class="${it.sub ? 'sub' : ''}" data-i="${i}" aria-selected="${i === acIndex}"><span class="ac-code">${it.code}</span><span class="ac-t"><b>${hl(p.city, q)}</b><span>${esc(sub)}</span></span></li>`;
    }).join('') : `<li class="empty">Aucun aéroport ne correspond à « ${esc(q)} ».</li>`;
    const pop = $('#acPop');
    closePops(pop);
    anchor.classList.add('active');
    place(pop, anchor);
  }
  function pickAC(i) {
    const it = acItems[i];
    if (!it || it.type === 'head') return;
    const mode = acMode;
    closePops();
    if (it.type === 'anywhere') { EX.origin = S.from; location.hash = '#/explorer'; return; }
    if (mode === 'ex') { EX.origin = it.code; renderExplorer(); return; }
    if (mode === 'deals') { S.from = it.code; syncForm(); renderHome(); return; }
    S[mode] = it.code;
    syncForm();
    if (mode === 'from') { renderHome(); $('#toInput').focus(); }
    else setTimeout(() => $('#depBtn').click(), 60);
  }
  $$('.sf-place input').forEach(input => {
    const which = input.id.startsWith('from') ? 'from' : 'to';
    const field = input.closest('.sf');
    input.addEventListener('focus', () => { input.select(); renderAC(field, which, ''); input.setAttribute('aria-expanded', 'true'); });
    input.addEventListener('input', () => { renderAC(field, which, input.value); input.setAttribute('aria-expanded', 'true'); });
    input.addEventListener('keydown', e => {
      if ($('#acPop').hidden) return;
      const move = d => {
        let i = acIndex;
        do { i = clamp(i + d, 0, acItems.length - 1); } while (acItems[i]?.type === 'head' && i > 0 && i < acItems.length - 1);
        acIndex = i;
        $$('#acList li[data-i]').forEach(li => li.setAttribute('aria-selected', String(+li.dataset.i === acIndex)));
        input.setAttribute('aria-activedescendant', 'ac-' + acIndex);
        $('#ac-' + acIndex)?.scrollIntoView({ block: 'nearest' });
      };
      if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
      else if (e.key === 'Enter') { e.preventDefault(); pickAC(acIndex); }
      else if (e.key === 'Escape') { closePops(); syncForm(); }
    });
    input.addEventListener('blur', () => setTimeout(() => { if ($('#acPop').hidden) syncForm(); }, 150));
  });
  $('#acList').addEventListener('mousedown', e => { const li = e.target.closest('li[data-i]'); if (li) { e.preventDefault(); pickAC(+li.dataset.i); } });

  // ---------- Calendrier des prix ----------
  let calMonth = null, calPick = 'dep';
  function renderCal() {
    const hasRoute = S.from && S.to;
    const from = calPick === 'ret' ? S.to : S.from, to = calPick === 'ret' ? S.from : S.to;
    const cells = [];
    $('#calMonths').innerHTML = [calMonth, addMonths(calMonth, 1)].map(m => {
      const first = parseISO(m + '-01');
      const startDow = (first.getUTCDay() + 6) % 7;
      const nDays = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
      let g = ['L', 'M', 'M', 'J', 'V', 'S', 'D'].map(d => `<span class="dow">${d}</span>`).join('');
      for (let i = 0; i < startDow; i++) g += '<span></span>';
      for (let d = 1; d <= nDays; d++) {
        const ds = `${m}-${String(d).padStart(2, '0')}`;
        const disabled = ds < TODAY || (calPick === 'ret' && ds < S.dep);
        const p = hasRoute && !disabled ? minPrice(from, to, ds) : null;
        if (p !== null) cells.push(p);
        g += `<button type="button" class="cal-day" data-d="${ds}" data-p="${p ?? ''}" ${disabled ? 'disabled' : ''} aria-label="${longD(ds)}${p ? ', à partir de ' + money(p) : ''}">${d}${p ? `<small>${money(p).replace(/\s/g, ' ')}</small>` : ''}</button>`;
      }
      return `<div class="cal-month"><h4>${fmtD(m + '-01', { month: 'long', year: 'numeric' })}</h4><div class="cal-grid">${g}</div></div>`;
    }).join('');
    $$('#calMonths .cal-day').forEach(b => {
      const ds = b.dataset.d, p = b.dataset.p ? +b.dataset.p : null;
      if (p && level(p, cells) === 'low') b.classList.add('lv-low');
      if (ds === TODAY) b.classList.add('today');
      if (ds === S.dep || (S.trip === 'rt' && ds === S.ret)) b.classList.add('sel');
      if (S.trip === 'rt' && S.ret && ds > S.dep && ds < S.ret) b.classList.add('inrange');
    });
    $('#calHint').textContent = !hasRoute ? 'Choisissez une destination pour afficher les prix' : calPick === 'dep' ? `Aller · ${cityOf(S.from)} → ${cityOf(S.to)}` : `Retour · ${cityOf(S.to)} → ${cityOf(S.from)}`;
    $('#calPrev').disabled = calMonth <= TODAY.slice(0, 7);
  }
  function openCal(which, anchor) {
    const pop = $('#calPop');
    calPick = which;
    calMonth = ((which === 'ret' ? S.ret : S.dep) || S.dep || TODAY).slice(0, 7);
    closePops(pop);
    anchor.classList.add('active');
    renderCal();
    place(pop, anchor, innerWidth > 900 ? 'right' : 'left');
  }
  $$('[data-cal]').forEach(b => b.addEventListener('click', e => {
    if (!$('#calPop').hidden && calPick === b.dataset.cal) { closePops(); return; }
    openCal(b.dataset.cal, e.currentTarget);
  }));
  $('#calPrev').addEventListener('click', () => { calMonth = addMonths(calMonth, -1); renderCal(); });
  $('#calNext').addEventListener('click', () => { calMonth = addMonths(calMonth, 1); renderCal(); });
  $('#calMonths').addEventListener('click', e => {
    const b = e.target.closest('.cal-day');
    if (!b || b.disabled) return;
    const d = b.dataset.d;
    if (calPick === 'dep') {
      S.dep = d;
      if (S.trip === 'rt') {
        if (!S.ret || S.ret < d) S.ret = null;
        calPick = 'ret';
        $$('.sf.active').forEach(f => f.classList.remove('active'));
        $('#retBtn').classList.add('active');
        syncForm(); renderCal();
        return;
      }
    } else S.ret = d;
    syncForm(); renderCal();
    setTimeout(closePops, 220);
  });
  $('#calMonths').addEventListener('mouseover', e => {
    const b = e.target.closest('.cal-day');
    if (!b || calPick !== 'ret' || b.disabled) return;
    $$('#calMonths .cal-day').forEach(x => x.classList.toggle('inrange', x.dataset.d > S.dep && x.dataset.d < b.dataset.d));
  });
  $('#calDone').addEventListener('click', () => { if (S.trip === 'rt' && !S.ret) S.ret = addDays(S.dep, 7); syncForm(); closePops(); });

  // ---------- Voyageurs ----------
  function syncPax() {
    $$('.stepper').forEach(st => {
      const k = st.dataset.pax, v = S[k];
      st.querySelector('output').textContent = v;
      const [minus, plus] = st.querySelectorAll('button');
      minus.disabled = v <= (k === 'adults' ? 1 : 0);
      plus.disabled = paxCount() >= 9 || (k === 'infants' && S.infants >= S.adults);
    });
    $$('[data-cabin]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.cabin === S.cabin)));
    syncForm();
  }
  $('#paxBtn').addEventListener('click', e => {
    const pop = $('#paxPop');
    if (!pop.hidden) { closePops(); return; }
    closePops(pop); e.currentTarget.classList.add('active'); syncPax(); place(pop, e.currentTarget, 'right');
  });
  $('#paxPop').addEventListener('click', e => {
    const b = e.target.closest('.stepper button');
    if (b) {
      const k = b.parentElement.dataset.pax;
      S[k] += b === b.parentElement.lastElementChild ? 1 : -1;
      if (S.infants > S.adults) S.infants = S.adults;
      syncPax();
    }
    const c = e.target.closest('[data-cabin]');
    if (c) { S.cabin = c.dataset.cabin; syncPax(); }
  });
  $('#paxDone').addEventListener('click', () => closePops());

  // ---------- Soumission & URL ----------
  function toParams() {
    const p = new URLSearchParams({ from: S.from, to: S.to, dep: S.dep, trip: S.trip, ad: S.adults, ch: S.children, in: S.infants, cab: S.cabin });
    if (S.trip === 'rt') p.set('ret', S.ret);
    if (S.direct) p.set('direct', '1');
    if (S.bag) p.set('bag', '1');
    return p.toString();
  }
  function fromParams(q) {
    const p = new URLSearchParams(q);
    const ok = c => c && (AP[c] || GROUPS[c]);
    if (ok(p.get('from'))) S.from = p.get('from');
    if (ok(p.get('to'))) S.to = p.get('to');
    const isDate = v => /^\d{4}-\d\d-\d\d$/.test(v || '');
    if (isDate(p.get('dep'))) S.dep = p.get('dep');
    S.trip = p.get('trip') === 'ow' ? 'ow' : 'rt';
    if (isDate(p.get('ret'))) S.ret = p.get('ret');
    S.adults = clamp(+p.get('ad') || 1, 1, 9); S.children = clamp(+p.get('ch') || 0, 0, 8); S.infants = clamp(+p.get('in') || 0, 0, S.adults);
    S.cabin = CABINS[p.get('cab')] ? p.get('cab') : 'eco';
    S.direct = p.get('direct') === '1'; S.bag = p.get('bag') === '1';
    if (S.dep < TODAY) S.dep = addDays(TODAY, 1);
    if (S.trip === 'rt' && (!S.ret || S.ret < S.dep)) S.ret = addDays(S.dep, 7);
  }
  $('#searchForm').addEventListener('submit', e => {
    e.preventDefault();
    closePops();
    const bad = [];
    if (!S.from) bad.push('[data-place=from]');
    if (!S.to || expand(S.from).some(c => expand(S.to).includes(c))) bad.push('[data-place=to]');
    if (bad.length) {
      bad.forEach(s => $(s).classList.add('error'));
      setTimeout(() => $$('.sf.error').forEach(f => f.classList.remove('error')), 1600);
      toast(!S.to ? 'Choisissez une destination' : 'Le départ et l\'arrivée doivent être différents', 'alert');
      $('#toInput').focus();
      return;
    }
    if (S.trip === 'rt' && !S.ret) S.ret = addDays(S.dep, 7);
    R.lastKey = '';
    recent = [{ from: S.from, to: S.to, dep: S.dep, ret: S.ret, trip: S.trip }, ...recent.filter(r => !(r.from === S.from && r.to === S.to))].slice(0, 4);
    store.set('recent', recent);
    takeoff(() => { location.hash = '#/vols?' + toParams(); });
  });
  function takeoff(done) {
    if (reduced) { done(); return; }
    const t = $('#takeoff'), im = $('#takeoffImg');
    if (!im.src) im.src = photo('HERO2', 300);
    t.hidden = false;
    setTimeout(() => { done(); setTimeout(() => { t.hidden = true; }, 80); }, 450);
  }
  // Le formulaire est un seul composant, déplacé entre l'accueil et l'en-tête des résultats
  function mountForm(slot) { const f = $('#searchForm'); if (f.parentElement !== slot) slot.appendChild(f); }

  // ================= ACCUEIL =================
  const VIBES = [['all', 'Tout'], ['plage', 'Mer & plages'], ['ville', 'Villes'], ['culture', 'Culture'], ['nature', 'Nature']];
  let homeVibe = 'all';
  const tabs = (el, cur, role = 'radio') => {
    el.innerHTML = VIBES.map(([k, l]) => `<button type="button" role="${role}" data-vibe="${k}" ${role === 'tab' ? 'aria-selected' : 'aria-checked'}="${k === cur}">${l}</button>`).join('');
  };
  function dealCard(d, i, extra = '') {
    const a = AP[d.ap];
    return `<button type="button" class="deal" data-go="${d.code}" data-date="${d.date}" style="animation-delay:${Math.min(i, 8) * 40}ms" ${extra}>
      <div class="deal-img">${img(d.code, 640, cityOf(d.code))}${d.direct ? '<span class="tag">Vol direct</span>' : ''}</div>
      <div class="deal-body">
        <div><h3>${esc(cityOf(d.code))}<code>${d.code}</code></h3><p>${esc(a.country)} · ${fmtDur(d.dur)} · le ${fmtD(d.date, { day: 'numeric', month: 'short' })}</p></div>
        <div class="deal-price"><small>à partir de</small><b>${money(d.price)}</b></div>
      </div></button>`;
  }
  function renderHome() {
    const origin = S.from || 'PAR';
    const dates = Array.from({ length: 50 }, (_, i) => addDays(TODAY, 7 + i));
    const all = cheapestFrom(origin, dates);
    // Hublots : 4 destinations lointaines, pays distincts, parmi les moins chères
    const home = countryOf(origin);
    const picks = [];
    for (const d of all.filter(x => AP[x.ap].country !== home && AP[x.ap].pop >= 7).sort((a, b) => b.dur - a.dur).slice(0, 22).sort((a, b) => a.price - b.price)) {
      if (picks.some(p => dist(p.ap, d.ap) < 2500)) continue; // horizons variés
      picks.push(d);
      if (picks.length === 4) break;
    }
    $('#cabinSub').textContent = `Au départ de ${cityOf(origin)}, meilleurs prix des sept prochaines semaines.`;
    $('#portholes').innerHTML = picks.map(d => `<button type="button" class="porthole-card" data-go="${d.code}" data-date="${d.date}">
      <div class="porthole"><div class="ph-glass">${img(d.code, 520, cityOf(d.code))}</div></div>
      <div class="ph-meta"><div><h3>${esc(cityOf(d.code))}</h3><p><code>${d.code}</code> · ${esc(AP[d.ap].country)} · ${fmtDur(d.dur)}</p></div><div class="ph-price"><small>dès</small><b>${money(d.price)}</b></div></div>
    </button>`).join('');
    $('#dealsOrigin').textContent = cityOf(origin);
    tabs($('#homeVibes'), homeVibe, 'tab');
    const list = all.filter(d => homeVibe === 'all' || AP[d.ap].vibe === homeVibe).slice(0, 6);
    $('#deals').innerHTML = list.map((d, i) => dealCard(d, i)).join('') || '<p class="muted">Aucune destination dans cette catégorie.</p>';
    renderPhone(origin, all.find(d => d.direct && AP[d.ap].pop >= 7) || all[0]);
    drift();
  }
  // Maquette de l'app iPhone, remplie avec de vrais résultats de la base
  function renderPhone(origin, d) {
    if (!d) return;
    const res = searchLeg(origin, d.code, d.date, 'eco').sort((a, b) => a.price - b.price).slice(0, 3);
    if (!res.length) return;
    $('#psRoute').innerHTML = `<b>${res[0].from}</b> → <b>${res[0].to}</b><span>${fmtD(d.date, { day: 'numeric', month: 'short' })} · 1 adulte</span>`;
    $('#psList').innerHTML = res.map(r => `<div class="ps-card">${logo(r.al, 's')}<div class="ps-t"><b>${hm(r.dep)} – ${hm(r.arr)}</b><span>${esc(AL[r.al].name)} · ${r.stops ? plural(r.stops, 'escale') : 'Direct'}</span></div><b class="ps-p">${money(r.price)}</b></div>`).join('');
    const drop = 8 + Math.floor(hash01(d.code + TODAY) * 22);
    $('#psNotifTitle').textContent = `${cityOf(origin)} → ${cityOf(d.code)}`;
    $('#psNotifText').textContent = `Le prix a baissé de ${money(drop)} : ${money(res[0].price)} le ${fmtD(d.date, { day: 'numeric', month: 'short' })}.`;
  }
  $('#homeVibes').addEventListener('click', e => { const b = e.target.closest('[data-vibe]'); if (b) { homeVibe = b.dataset.vibe; renderHome(); } });
  document.addEventListener('click', e => {
    const b = e.target.closest('#view-home [data-go]');
    if (!b) return;
    S.to = b.dataset.go; S.dep = b.dataset.date;
    if (S.trip === 'rt') S.ret = addDays(S.dep, 7);
    syncForm();
    $('#searchForm').requestSubmit();
  });
  $('#dealsOrigin').addEventListener('click', e => renderAC(e.currentTarget, 'deals'));
  // Les paysages défilent doucement derrière les hublots au fil du scroll
  function drift() {
    if (reduced) return;
    const vh = innerHeight;
    $$('.portholes .ph-glass').forEach(g => {
      const r = g.getBoundingClientRect();
      if (r.bottom < 0 || r.top > vh) return;
      g.style.setProperty('--drift', ((r.top + r.height / 2 - vh / 2) * -.06).toFixed(1) + 'px');
    });
  }

  // ================= RÉSULTATS =================
  function defaultFilters(results) {
    const maxP = Math.max(0, ...results.map(r => r.price)), maxD = Math.max(0, ...results.map(r => r.dur));
    return {
      stops: new Set(S.direct ? [0] : [0, 1, 2]), priceMax: maxP, priceCap: maxP, depT: new Set(), arrT: new Set(),
      durMax: maxD, durCap: maxD, exAl: new Set(), alliances: new Set(), kind: 'all', hold: S.bag, cab: false,
      wifi: false, meal: false, pwr: false, refund: false, layMax: 1440, noNight: false, exHubs: new Set(), self: true, lowCo2: false, ontime: false,
    };
  }
  const bucket = m => { m = ((m % 1440) + 1440) % 1440; return m < 360 ? 'n' : m < 720 ? 'm' : m < 1080 ? 'a' : 'e'; };
  function passes(r, F) {
    if (!F.stops.has(Math.min(r.stops, 2))) return false;
    if (r.price > F.priceMax) return false;
    if (F.depT.size && !F.depT.has(bucket(r.dep))) return false;
    if (F.arrT.size && !F.arrT.has(bucket(r.arr))) return false;
    if (r.dur > F.durMax) return false;
    if (r.carriers.some(c => F.exAl.has(c))) return false;
    if (F.alliances.size && !F.alliances.has(AL[r.al].alliance)) return false;
    if (F.kind === 'low' && !r.lowcost) return false;
    if (F.kind === 'full' && r.lowcost) return false;
    if (F.hold && !r.hold) return false;
    if (F.cab && !r.cab) return false;
    if (F.wifi && !r.wifi) return false;
    if (F.meal && !r.meal) return false;
    if (F.pwr && !r.pwr) return false;
    if (F.refund && r.refund < 1) return false;
    if (F.layMax < 1440 && r.lays.some(l => l.min > F.layMax)) return false;
    if (F.noNight && r.overnight) return false;
    if (F.exHubs.size && r.lays.some(l => F.exHubs.has(l.at))) return false;
    if (!F.self && r.self) return false;
    if (F.lowCo2 && r.co2 > R.avgCo2 * .95) return false;
    if (F.ontime && r.ontime < 85) return false;
    return true;
  }
  const SORTS = {
    best: ['Recommandé', null],
    cheap: ['Le moins cher', (a, b) => a.price - b.price || a.dur - b.dur],
    fast: ['Le plus rapide', (a, b) => a.dur - b.dur || a.price - b.price],
    early: ['Départ le plus tôt', (a, b) => a.dep - b.dep],
    late: ['Départ le plus tard', (a, b) => b.dep - a.dep],
    arr: ['Arrivée la plus tôt', (a, b) => a.arr - b.arr],
    co2: ['Moins d\'émissions', (a, b) => a.co2 - b.co2],
  };
  const sortFn = k => SORTS[k][1] || ((a, b) => a.score - b.score);
  $('#sortSelect').innerHTML = Object.entries(SORTS).map(([k, [l]]) => `<option value="${k}">${l}</option>`).join('');
  $('#sortSelect').addEventListener('change', e => { R.sort = e.target.value; applyFilters(); });

  const legParams = () => R.step === 2 ? { from: S.to, to: S.from, date: S.ret } : { from: S.from, to: S.to, date: S.dep };
  function runSearch(keep = false) {
    const { from, to, date } = legParams();
    R.results = searchLeg(from, to, date);
    R.results.forEach(r => { r.fare = r.price; r.bag = bagCost(r); if (R.withBag) r.price = r.fare + r.bag; });
    if (R.results.length) {
      const mp = Math.min(...R.results.map(r => r.price)), md = Math.min(...R.results.map(r => r.dur));
      R.results.forEach(r => { r.score = r.price / mp + .55 * r.dur / md + .12 * r.stops + (r.self ? .2 : 0) + (r.overnight ? .15 : 0); });
    }
    R.avgCo2 = R.results.reduce((a, r) => a + r.co2, 0) / (R.results.length || 1);
    R.ext = { cheap: Math.min(...R.results.map(r => r.price)), fast: Math.min(...R.results.map(r => r.dur)) };
    if (!keep || !R.F) R.F = defaultFilters(R.results);
    else {
      const maxP = Math.max(0, ...R.results.map(r => r.price)), maxD = Math.max(0, ...R.results.map(r => r.dur));
      if (R.F.priceMax >= R.F.priceCap) R.F.priceMax = maxP;
      if (R.F.durMax >= R.F.durCap) R.F.durMax = maxD;
      R.F.priceCap = maxP; R.F.durCap = maxD;
    }
    renderHead();
    renderDateStrip();
    renderFilters();
    applyFilters();
  }
  function applyFilters() {
    R.filtered = R.results.filter(r => passes(r, R.F)).sort(sortFn(R.sort));
    R.bestKey = R.filtered.slice().sort(sortFn('best'))[0]?.key;
    $('#sortSelect').value = R.sort;
    renderSorts();
    renderActiveChips();
    $('#applyFilters').textContent = R.filtered.length ? `Afficher ${plural(R.filtered.length, 'vol')}` : 'Aucun vol : assouplissez les filtres';
    renderList();
    renderJourney();
    updateHist();
  }

  // ---------- En-tête : trajet & parcours aller/retour ----------
  const rp = code => `<div class="rp"><b>${code}</b><span>${esc(cityOf(code))}${GROUPS[code] ? ' · ' + GROUPS[code].members.join(', ') : ''}</span></div>`;
  function renderHead() {
    $('#rRoute').innerHTML = `${rp(S.from)}<span class="rt-line"><i></i>${icon('plane')}<i></i></span>${rp(S.to)}`;
    const pax = paxCount();
    $('#rMeta').textContent = `${S.trip === 'rt' ? 'Aller-retour' : 'Aller simple'} · ${fmtD(S.dep)}${S.trip === 'rt' ? ' – ' + fmtD(S.ret) : ''} · ${plural(pax, 'voyageur')} · ${CABINS[S.cabin]}`;
    const alerted = alerts.some(a => a.from === S.from && a.to === S.to && a.dep === S.dep);
    $('#alertBtn').classList.toggle('on', alerted);
    $('#alertBtn').setAttribute('aria-label', alerted ? 'Alerte active — retirer' : 'Surveiller le prix');
    $('#alertBtn').dataset.tip = alerted ? 'Prix surveillé' : 'Surveiller le prix';
    const { from, to, date } = legParams();
    const leg = R.step === 2 ? 'retour' : 'aller';
    $('#stepTitle').innerHTML = `<p class="step-ctx">${S.trip === 'rt' ? (R.step === 2 ? 'Vols retour' : 'Vols aller') : 'Vols'} · <code>${from}</code> ${esc(cityOf(from))} → <code>${to}</code> ${esc(cityOf(to))} · ${longD(date)}</p>`;
  }
  // ---------- Suivi de progression (pleine largeur) ----------
  // Phases : select (choix des vols) → fare (tarif, dans le détail) → check (vérifications) → book (redirection) → done
  R.phase = 'select';
  R.trip = null;
  function trackerSteps() {
    const rt = S.trip === 'rt';
    const list = R.filtered, all = R.results;
    const cheapest = list.length ? Math.min(...list.map(r => r.price)) : null;
    const fastest = list.length ? Math.min(...list.map(r => r.dur)) : null;
    const directs = list.filter(r => !r.stops).length;
    const depTimes = list.map(r => r.dep).sort((a, b) => a - b);
    const t = R.trip;
    const inSelect = R.phase === 'select';
    const selecting = (from, to, date) => ({
      lines: [
        `<b>${plural(list.length, 'vol')}</b>${list.length !== all.length ? ` sur ${all.length}` : ''} le ${fmtD(date)}`,
        cheapest ? `Dès <b>${money(cheapest)}</b> · ${directs ? directs + (directs > 1 ? ' vols directs' : ' vol direct') : 'aucun vol direct'}` : 'Aucun vol avec ces filtres',
        fastest ? `Le plus rapide : ${fmtDur(fastest)}` : '',
        depTimes.length ? `Départs de ${hm(depTimes[0])} à ${hm(depTimes[depTimes.length - 1])}` : '',
      ],
    });
    const chosenLines = r => [
      `<span class="trk-flight">${logo(r.al, 'xs')}<b>${esc(r.fns.join(' + '))}</b></span>`,
      `${hm(r.dep)} ${r.from} → ${hm(r.arr)}${dayOff(r.arr) - dayOff(r.dep) ? `<sup>+${dayOff(r.arr) - dayOff(r.dep)}</sup>` : ''} ${r.to}`,
      `${fmtDur(r.dur)} · ${r.stops ? plural(r.stops, 'escale') + ' ' + r.lays.map(l => l.at).join(', ') : 'direct'}`,
      `Soute ${r.hold ? 'incluse' : 'non incluse'} · <b>${money(r.price)}</b>`,
    ];
    const steps = [];
    steps.push({
      key: 'search', label: 'Recherche', state: 'done', action: 'Modifier',
      lines: [
        `<b>${S.from} → ${S.to}</b> · ${esc(cityOf(S.from))} → ${esc(cityOf(S.to))}`,
        `${rt ? 'Aller-retour' : 'Aller simple'} · ${fmtD(S.dep, { day: 'numeric', month: 'short' })}${rt ? ` → ${fmtD(S.ret, { day: 'numeric', month: 'short' })} · ${plural(diffDays(S.dep, S.ret), 'nuit')}` : ''}`,
        `${plural(S.adults, 'adulte')}${S.children ? ', ' + plural(S.children, 'enfant') : ''}${S.infants ? ', ' + plural(S.infants, 'bébé') : ''} · ${CABINS[S.cabin]}`,
        [S.direct && 'Directs uniquement', R.withBag && 'Prix avec bagage'].filter(Boolean).join(' · ') || 'Toutes escales · sans bagage',
      ],
    });
    const outState = inSelect && R.step === 1 ? 'current' : 'done';
    const outRes = rt ? R.out || t?.out : t?.out;
    steps.push({
      key: 'out', label: rt ? 'Vol aller' : 'Vol', state: outState, action: outState === 'done' ? 'Changer' : '',
      lines: outState === 'current' ? selecting(S.from, S.to, S.dep).lines : outRes ? chosenLines(outRes) : [],
    });
    if (rt) {
      const retState = inSelect ? (R.step === 2 ? 'current' : 'todo') : 'done';
      const retMin = retState === 'todo' ? minPrice(S.to, S.from, S.ret) : null;
      steps.push({
        key: 'ret', label: 'Vol retour', state: retState,
        lines: retState === 'current' ? selecting(S.to, S.from, S.ret).lines
          : retState === 'done' && t?.ret ? chosenLines(t.ret)
            : [`<b>${S.to} → ${S.from}</b> · ${fmtD(S.ret)}`, retMin ? `Dès ${money(retMin)} ce jour-là` : 'Aucun vol ce jour-là', 'Disponible après le choix de l\'aller'],
      });
    }
    const order = ['select', 'fare', 'check', 'book', 'done'];
    const at = order.indexOf(R.phase);
    const st = i => at > i ? 'done' : at === i ? 'current' : 'todo';
    const sites = t ? [...new Set([t.out, t.ret].filter(Boolean).flatMap(r => r.flights.map(f => siteHost(AL[f.al].site))))] : [];
    steps.push({
      key: 'fare', label: 'Tarif', state: st(1),
      lines: t?.fare && at >= 1 ? [`<b>${t.fare.name}</b> · ${money(t.fare.price)} par adulte`, t.fare.inc.filter(([ok]) => ok).map(([, l]) => l).slice(0, 2).join(' · '), at === 1 ? 'Comparez Light, Standard et Flex' : 'Tarif choisi']
        : ['Light, Standard ou Flex', 'Bagages, siège, modification', 'Prix détaillé, 0 € de frais'],
    });
    steps.push({
      key: 'check', label: 'Vérifications', state: st(2),
      lines: ['Noms comme sur le passeport', 'Formalités d\'entrée et visas', at > 2 ? 'Vérifications faites' : 'Bagages et enregistrement'],
    });
    steps.push({
      key: 'book', label: 'Réservation', state: at >= 3 ? (R.phase === 'done' ? 'done' : 'current') : 'todo',
      lines: at >= 3 ? [`Ouvert sur <b>${esc(sites.join(' + '))}</b>`, 'Paiement directement à la compagnie', 'Rappel calendrier disponible']
        : [sites.length ? `Sur ${esc(sites.join(' + '))}` : 'Sur le site de la compagnie', 'Paiement direct, sans intermédiaire', '0 € de frais Envol'],
    });
    return steps;
  }
  function trackerTotal() {
    const rt = S.trip === 'rt';
    const cheapest = R.filtered.length ? Math.min(...R.filtered.map(r => r.price)) : null;
    if (R.trip?.fare && R.phase !== 'select') return { label: rt ? 'Aller-retour, tarif ' + R.trip.fare.name : 'Tarif ' + R.trip.fare.name, per: R.trip.fare.price, exact: true };
    if (!rt) return { label: 'Prix du vol', per: cheapest, exact: false };
    if (R.step === 2 && R.out) return { label: 'Aller-retour', per: cheapest !== null ? R.out.price + cheapest : null, exact: false, note: `Aller ${money(R.out.price)} + retour dès ${cheapest !== null ? money(cheapest) : '—'}` };
    const ret = minPrice(S.to, S.from, S.ret);
    return { label: 'Aller-retour', per: cheapest !== null && ret !== null ? cheapest + ret : null, exact: false, note: cheapest !== null && ret !== null ? `Aller dès ${money(cheapest)} + retour dès ${money(ret)}` : '' };
  }
  // Trajectoire : un arc fin, l'avion avance d'étape en étape (plein derrière, pointillés devant)
  const ARC = { h: 120, y0: 96, peak: 4 };   // courbe de Bézier quadratique dans un repère 1000 × 64
  const arcY = t => (1 - t) ** 2 * ARC.y0 + 2 * (1 - t) * t * ARC.peak + t * t * ARC.y0;
  const arcT = i => .03 + i * .94 / (R.trkN - 1);  // position des étapes sur la courbe
  R.trkT = null;
  function shortDetail(s) {
    const t = R.trip, list = R.filtered;
    const cheapest = list.length ? Math.min(...list.map(r => r.price)) : null;
    const pick = r => r ? `${r.fns[0].slice(0, 2)} ${r.fns[0].slice(2)} · ${hm(r.dep)}` : '';
    switch (s.key) {
      case 'search': return `${S.from} → ${S.to}`;
      case 'out': return s.state === 'current' ? (cheapest !== null ? `dès ${money(cheapest)}` : 'aucun vol') : pick(S.trip === 'rt' ? R.out || t?.out : t?.out);
      case 'ret': return s.state === 'current' ? (cheapest !== null ? `dès ${money(cheapest)}` : 'aucun vol') : s.state === 'done' ? pick(t?.ret) : fmtD(S.ret, { day: 'numeric', month: 'short' });
      case 'fare': return t?.fare && s.state !== 'todo' ? t.fare.name : '';
      case 'check': return s.state === 'done' ? 'OK' : '';
      case 'book': return s.state !== 'todo' && t ? siteHost(AL[t.out.al].site) : '';
    }
    return '';
  }
  function renderJourney() {
    const J = $('#journey');
    const steps = trackerSteps();
    R.trkN = steps.length;
    const doneAll = steps.every(s => s.state === 'done');
    const cur = doneAll ? steps.length - 1 : Math.max(0, steps.findIndex(s => s.state === 'current'));
    const tot = trackerTotal();
    const headline = doneAll ? 'Bon voyage'
      : { search: 'Votre recherche', out: S.trip === 'rt' ? 'Choisissez votre vol aller' : 'Choisissez votre vol', ret: 'Choisissez votre vol retour', fare: 'Choisissez votre tarif', check: 'Vérifiez avant de réserver', book: 'Finalisez chez la compagnie' }[steps[cur].key];
    const short = { search: 'Recherche', out: S.trip === 'rt' ? 'Aller' : 'Vol', ret: 'Retour', fare: 'Tarif', check: 'Vérifications', book: 'Réservation' };
    const d = `M0,${ARC.y0} Q500,${ARC.peak} 1000,${ARC.y0}`;
    J.className = 'flightpath';
    J.innerHTML = `
      <div class="fp-top">
        <p class="fp-now" aria-live="polite"><span>${cur + 1}/${steps.length}</span>${headline}</p>
        <p class="fp-total">${tot.per === null ? '' : `<span>${esc(tot.label)}</span> <b>${(tot.exact ? '' : 'dès ') + money(tot.per)}</b>${paxCount() > 1 ? `<small>${money(paxTotal(tot.per))} pour ${paxCount()}</small>` : ''}`}</p>
      </div>
      <div class="fp-sky" role="progressbar" aria-valuemin="1" aria-valuemax="${steps.length}" aria-valuenow="${cur + 1}" aria-valuetext="Étape ${cur + 1} sur ${steps.length} : ${headline}">
        <svg class="fp-svg" viewBox="0 0 1000 ${ARC.h}" preserveAspectRatio="none" aria-hidden="true">
          <path class="fp-ahead" d="${d}"/>
          <path class="fp-done" id="fpDone" d="M0,${ARC.y0}"/>
        </svg>
        <span class="fp-plane" id="fpPlane" aria-hidden="true">${icon('plane')}</span>
        ${steps.map((s, i) => {
          const t = arcT(i), detail = shortDetail(s);
          const act = s.key === 'search' || (s.key === 'out' && s.state === 'done');
          return `<${act ? 'button type="button"' : 'div'} class="fp-wp ${s.state}" style="left:${(t * 100).toFixed(2)}%;--y:${(arcY(t) / ARC.h * 100).toFixed(2)}%" ${act ? `data-trk="${s.key}" title="${s.key === 'search' ? 'Modifier la recherche' : 'Changer de vol aller'}"` : ''}>
            <i class="fp-dot"></i><span class="fp-label">${short[s.key]}</span>${detail ? `<span class="fp-detail">${esc(detail)}</span>` : ''}
          </${act ? 'button' : 'div'}>`;
        }).join('')}
      </div>`;
    // Barre compacte collante : même trajectoire en miniature
    $('#trkSticky').innerHTML = `
      <div class="ts-in">
        <p class="ts-now"><span>${cur + 1}/${steps.length}</span>${headline}</p>
        <div class="ts-track"><i class="ts-fill" id="tsFill"></i><span class="ts-plane" id="tsPlane">${icon('plane')}</span></div>
        <p class="ts-total">${tot.per === null ? '' : `${(tot.exact ? '' : 'dès ') + money(tot.per)}`}</p>
      </div>`;
    flyTo(doneAll ? 1 : arcT(cur));
  }
  // Animation de l'avion le long de l'arc, de l'étape précédente à la nouvelle
  let flyRaf;
  function flyTo(target) {
    const from = R.trkT ?? Math.max(0, target - .12);
    R.trkT = target;
    cancelAnimationFrame(flyRaf);
    const t0 = performance.now(), dur = reduced ? 0 : 1100;
    const frame = now => {
      const k = dur ? Math.min(1, (now - t0) / dur) : 1;
      const e = 1 - (1 - k) ** 3;
      placePlane(from + (target - from) * e);
      if (k < 1) flyRaf = requestAnimationFrame(frame);
    };
    flyRaf = requestAnimationFrame(frame);
  }
  function placePlane(t) {
    const sky = $('.fp-sky'), plane = $('#fpPlane'), done = $('#fpDone');
    if (!sky || !plane) return;
    const w = sky.clientWidth, h = sky.clientHeight;
    const x = t * w, y = arcY(t) / ARC.h * h;
    // pente de la courbe en pixels écran → orientation de l'avion
    const dy = (2 * (1 - t) * (ARC.peak - ARC.y0) + 2 * t * (ARC.y0 - ARC.peak)) / ARC.h * h;
    const angle = Math.atan2(dy, w) * 180 / Math.PI;
    plane.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%) rotate(${angle + 90}deg)`;
    // portion de la courbe déjà parcourue (subdivision de la Bézier en t)
    done.setAttribute('d', `M0,${ARC.y0} Q${(t * 500).toFixed(1)},${(ARC.y0 + t * (ARC.peak - ARC.y0)).toFixed(2)} ${(t * 1000).toFixed(1)},${arcY(t).toFixed(2)}`);
    const fill = $('#tsFill'), sp = $('#tsPlane');
    if (fill) fill.style.width = (t * 100).toFixed(2) + '%';
    if (sp) sp.style.left = (t * 100).toFixed(2) + '%';
  }
  addEventListener('resize', () => { if (R.trkT !== null && !$('#view-results').hidden) placePlane(R.trkT); });
  $('#journey').addEventListener('click', e => {
    const b = e.target.closest('[data-trk]');
    if (!b) return;
    if (b.dataset.trk === 'search') { $('#editBtn').click(); $('#slotResults').scrollIntoView({ block: 'center', behavior: 'smooth' }); }
    if (b.dataset.trk === 'out' && S.trip === 'rt') { R.phase = 'select'; R.trip = null; goStep(1); }
    if (b.dataset.trk === 'out' && S.trip === 'ow') { R.phase = 'select'; R.trip = null; renderJourney(); }
  });
  $('#trkSticky').addEventListener('click', () => scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' }));
  new IntersectionObserver(es => {
    const show = !es[0].isIntersecting && !$('#view-results').hidden;
    $('#trkSticky').classList.toggle('show', show);
  }, { rootMargin: '-64px 0px 0px 0px' }).observe($('#journey'));
  function setPhase(p) { R.phase = p; renderJourney(); }
  function goStep(n) {
    R.step = n;
    R.phase = 'select';
    if (n === 1) R.out = null;
    const m = $('#rMain');
    m.classList.remove('slide'); void m.offsetWidth; m.classList.add('slide');
    scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' });
    runSearch(false);
  }

  function renderDateStrip() {
    const { from, to, date } = legParams();
    const days = [-3, -2, -1, 0, 1, 2, 3].map(k => addDays(date, k));
    const prices = days.map(d => (d < TODAY || (R.step === 2 && d < S.dep) || (R.step === 1 && S.trip === 'rt' && d > S.ret)) ? null : minPrice(from, to, d));
    const valid = prices.filter(p => p !== null);
    const max = Math.max(...valid, 1), min = Math.min(...valid);
    $('#dateStrip').innerHTML = days.map((d, i) => {
      const p = prices[i];
      const diff = p !== null && prices[3] ? p - prices[3] : 0;
      return `<button type="button" role="tab" class="ds-day ${p !== null && p === min ? 'cheapest' : ''}" data-date="${d}" aria-selected="${d === date}" ${p === null ? 'disabled' : ''} ${p !== null && d !== date ? `data-tip="${longD(d)}<br>${diff < 0 ? money(-diff) + ' de moins' : diff > 0 ? money(diff) + ' de plus' : 'Même prix'}"` : ''}>
        <span class="d">${fmtD(d, { weekday: 'short', day: 'numeric' })}</span>
        <span class="p ${p === null ? 'none' : ''}">${p === null ? '—' : money(p)}</span>
        <span class="bar"><i style="width:${p ? Math.round(p / max * 100) : 0}%"></i></span>
      </button>`;
    }).join('');
  }
  $('#dateStrip').addEventListener('click', e => {
    const b = e.target.closest('.ds-day');
    if (!b || b.disabled) return;
    if (R.step === 2) S.ret = b.dataset.date;
    else { S.dep = b.dataset.date; if (S.trip === 'rt' && S.ret < S.dep) S.ret = addDays(S.dep, 7); }
    hideTip();
    R.lastKey = toParams();
    history.replaceState(null, '', '#/vols?' + R.lastKey);
    syncForm();
    runSearch(true);
  });

  function renderSorts() {
    const list = R.filtered;
    const by = k => list.slice().sort(sortFn(k))[0];
    const tabBtn = (k, lbl) => {
      const r = by(k);
      return `<button type="button" class="sort-tab" data-sort="${k}" aria-pressed="${R.sort === k}"><span class="st-l">${lbl}</span><span class="st-p">${r ? money(r.price) : '—'}</span><span class="st-s">${r ? fmtDur(r.dur) + ' · ' + (r.stops ? plural(r.stops, 'escale') : 'direct') : ''}</span></button>`;
    };
    $('#sorts').innerHTML = tabBtn('best', 'Recommandé') + tabBtn('cheap', 'Le moins cher') + tabBtn('fast', 'Le plus rapide');
    $('#sorts .sort-tab[data-sort="best"]').dataset.tip = 'Meilleur équilibre entre prix, durée et nombre d\'escales';
    // Conseil : prix du jour comparé aux dates voisines (±15 jours)
    const { from, to, date } = legParams();
    const win = [];
    for (let k = -15; k <= 15; k += 3) { const d = addDays(date, k); if (d > TODAY) { const p = minPrice(from, to, d); if (p !== null) win.push({ d, p }); } }
    const cur = R.results.length ? Math.min(...R.results.map(r => r.price)) : null;
    let html = '';
    if (cur && win.length > 2) {
      const avg = win.reduce((a, x) => a + x.p, 0) / win.length, ratio = cur / avg;
      const lvl = ratio < .92 ? 'low' : ratio > 1.08 ? 'high' : 'mid';
      const bestW = win.reduce((a, x) => x.p < a.p ? x : a);
      const ahead = diffDays(TODAY, date);
      const txt = lvl === 'low' ? `<b>${Math.round((1 - ratio) * 100)} % de moins</b> que la moyenne des dates voisines.`
        : lvl === 'high' ? (bestW.d !== date ? `Le ${fmtD(bestW.d, { day: 'numeric', month: 'long' })}, ce trajet coûte <b>${money(cur - bestW.p)} de moins</b>. <button type="button" data-jump="${bestW.d}">Voir cette date</button>` : 'Les prix sont élevés sur toute la période.')
          : `Dans la moyenne des dates voisines.${ahead > 21 && ahead < 40 ? ' Les prix montent souvent à moins de 21 jours du départ.' : ''}`;
      const note = seasonNote(from, to, date);
      html = `<span class="lvl ${lvl}">${lvl === 'low' ? 'Prix bas.' : lvl === 'high' ? 'Prix élevé.' : 'Prix habituel.'}</span><p>${txt}${note ? ` <span class="season">Période : ${esc(note)}.</span>` : ''}</p>`;
    }
    $('#insight').innerHTML = html;
    const n = list.length, tot = R.results.length;
    $('#rcount').innerHTML = `<b>${plural(n, 'vol')}</b>${n !== tot ? ` sur ${tot}` : ''} · prix par adulte, ${R.withBag ? 'taxes et bagage en soute inclus' : 'taxes incluses'}`;
  }
  document.addEventListener('click', e => {
    const s = e.target.closest('[data-sort]');
    if (s) { R.sort = s.dataset.sort; applyFilters(); return; }
    const j = e.target.closest('[data-jump]');
    if (j) {
      const day = $(`.ds-day[data-date="${j.dataset.jump}"]`);
      if (day && !day.disabled) { day.click(); return; }
      if (R.step === 2) S.ret = j.dataset.jump; else S.dep = j.dataset.jump;
      R.lastKey = toParams();
      history.replaceState(null, '', '#/vols?' + R.lastKey);
      syncForm(); runSearch(true);
    }
  });

  // ---------- Cartes de vol ----------
  function track(r) {
    const t0 = r.segs[0].depU;
    const dots = r.lays.map(l => `<span class="stopdot ${l.self ? 'self' : ''}" style="left:${((l.start + l.min / 2 - t0) / r.dur * 100).toFixed(1)}%" data-tip="${l.self ? 'Changement de billet' : 'Escale'} à ${esc(cityOf(l.at))} (${l.at})<br>${fmtDur(l.min)}${l.min >= 420 ? ' · nuit sur place' : ''}"></span>`).join('');
    return `<div class="track"><span class="end a"></span>${dots}<span class="end b"></span></div>`;
  }
  const arrSup = r => { const d = dayOff(r.arr) - dayOff(r.dep); return d ? `<sup title="Arrivée ${d > 0 ? d > 1 ? d + ' jours après' : 'le lendemain' : 'la veille'} (heure locale)">${d > 0 ? '+' : ''}${d}</sup>` : ''; };
  function tags(r) {
    const t = [];
    if (r.price === R.ext.cheap) t.push('<span class="ftag good">Le moins cher</span>');
    if (r.key === R.bestKey) t.push('<span class="ftag" data-tip="Meilleur équilibre entre prix, durée et escales">Recommandé</span>');
    if (r.dur === R.ext.fast) t.push('<span class="ftag">Le plus rapide</span>');
    if (r.self) t.push('<span class="ftag warn self" data-tip="Deux billets distincts : récupérez vos bagages et repassez la sécurité. Correspondance non garantie.">Billets séparés</span>');
    if (r.overnight) t.push('<span class="ftag warn">Nuit en escale</span>');
    return t.join('');
  }
  function card(r, i) {
    const isFav = favs.some(f => f.key === r.key), inCmp = R.compare.includes(r.key);
    const names = r.carriers.map(c => AL[c].name).join(' + ');
    const cta = S.trip === 'rt' ? (R.step === 1 ? 'Choisir cet aller' : 'Choisir ce retour') : 'Sélectionner';
    const pct = Math.round((r.co2 / (R.avgCo2 || r.co2) - 1) * 100);
    const perk = (ok, ic, l) => `<span class="perk ${ok ? 'yes' : 'no'}">${icon(ic)}${l}</span>`;
    return `<article class="fcard ${r.key === R.bestKey && R.sort === 'best' ? 'best' : ''}" data-key="${r.key}" style="animation-delay:${Math.min(i % 20, 10) * 25}ms" tabindex="0" aria-label="${esc(names)}, ${hm(r.dep)} ${cityOf(r.from)} – ${hm(r.arr)} ${cityOf(r.to)}, ${fmtDur(r.dur)}, ${r.stops ? plural(r.stops, 'escale') : 'direct'}, ${money(r.price)}">
      <div class="fc-al"><span class="logos-stack">${r.carriers.slice(0, 3).map(c => logo(c)).join('')}</span><div class="names"><b>${esc(names)}</b><small>${esc(r.fns.join(' · '))}</small></div></div>
      <div class="fc-route">
        <div class="fc-t"><b>${hm(r.dep)}</b><span class="ap"><code>${r.from}</code><span>${esc(AP[r.from].city)}</span></span></div>
        <div class="fc-line"><span class="dur">${fmtDur(r.dur)}</span>${track(r)}${r.stops ? `<span class="stops">${plural(r.stops, 'escale')} <span>${r.lays.map(l => l.at).join(' · ')}</span></span>` : '<span class="stops direct">Direct</span>'}</div>
        <div class="fc-t r"><b>${hm(r.arr)}${arrSup(r)}</b><span class="ap"><code>${r.to}</code><span>${esc(AP[r.to].city)}</span></span></div>
      </div>
      <div class="fc-price">
        <div class="price"><small>${S.trip === 'rt' ? (R.step === 1 ? 'Aller, par adulte' : 'Retour, par adulte') : 'Par adulte'}</small><b>${money(r.price)}</b>${paxCount() > 1 ? `<span class="total">${money(paxTotal(r.price))} pour ${paxCount()}</span>` : ''}${R.withBag && r.bag ? `<span class="total">dont bagage ${money(r.bag)}</span>` : ''}${r.seats <= 3 ? `<span class="seats">${plural(r.seats, 'place')} à ce prix</span>` : ''}</div>
        <button type="button" class="btn-dark" data-act="choose">${cta}</button>
      </div>
      <div class="fc-foot">
        <div class="fc-tags">${tags(r)}</div>
        ${perk(r.cab, 'cabin', 'Cabine')}${perk(r.hold, 'bag', 'Soute')}${r.wifi ? perk(1, 'wifi', 'Wi-Fi') : ''}
        <span class="perk" data-tip="${r.co2} kg CO₂ estimés par passager<br>Moyenne du trajet : ${Math.round(R.avgCo2)} kg">${icon('leaf')}${pct <= -5 ? pct + ' %' : pct >= 5 ? '+' + pct + ' %' : 'Moyenne'}</span>
        <span class="spacer"></span>
        <button type="button" class="icon-act ${isFav ? 'on' : ''}" data-act="fav" aria-pressed="${isFav}" aria-label="Favori">${icon(isFav ? 'heart' : 'heart-o')}</button>
        <button type="button" class="icon-act ${inCmp ? 'on' : ''}" data-act="cmp" aria-pressed="${inCmp}" aria-label="Comparer">${icon('compare')}</button>
      </div>
    </article>`;
  }
  const PAGE = 20;
  function renderList() {
    const el = $('#resultsList');
    R.shown = 0;
    if (!R.filtered.length) {
      const has = R.results.length;
      el.innerHTML = `<div class="empty-state">${porthole('HERO2')}<h3>${has ? 'Aucun vol avec ces filtres' : 'Aucun vol ce jour-là'}</h3>
        <p>${has ? `${plural(R.results.length, 'vol')} existent pour ce trajet mais ne correspondent pas à vos critères.` : 'Aucune compagnie ne dessert ce trajet à cette date. Essayez une date voisine ou explorez d\'autres destinations.'}</p>
        <div class="actions">${has ? '<button type="button" class="btn-dark" data-reset>Réinitialiser les filtres</button>' : ''}<a class="btn-line" href="#/explorer">Explorer la carte</a></div></div>`;
      return;
    }
    if (R.view === 'timeline') { el.innerHTML = timeline(R.filtered.slice(0, 40)); return; }
    el.innerHTML = '';
    more();
  }
  function more() {
    if (R.view !== 'list' || R.shown >= R.filtered.length) return;
    const slice = R.filtered.slice(R.shown, R.shown + PAGE);
    $('#resultsList').insertAdjacentHTML('beforeend', slice.map((r, i) => card(r, R.shown + i)).join(''));
    R.shown += slice.length;
  }
  new IntersectionObserver(es => { if (es[0].isIntersecting && !$('#view-results').hidden) more(); }, { rootMargin: '600px' }).observe($('#sentinel'));

  function timeline(list) {
    const span = clamp(Math.ceil(Math.max(1440, ...list.map(r => r.dep + r.dur)) / 180) * 180, 1440, 2880);
    const lo = Math.max(0, Math.floor(Math.min(...list.map(r => r.dep)) / 180) * 180), range = span - lo;
    const step = range > 1800 ? 360 : 180, ticks = [];
    for (let t = lo; t <= span; t += step) ticks.push(t);
    const x = t => ((t - lo) / range * 100).toFixed(2) + '%';
    const cheapest = Math.min(...list.map(r => r.price));
    const rows = list.map(r => `<div class="tl-row ${r.price === cheapest ? 'cheap' : ''}" data-key="${r.key}" tabindex="0" data-tip="${esc(AL[r.al].name)} · ${hm(r.dep)} → ${hm(r.arr)}<br>${fmtDur(r.dur)} · ${r.stops ? r.lays.map(l => l.at + ' ' + fmtDur(l.min)).join(', ') : 'direct'}<br>${money(r.price)}">
        <div class="tl-n">${logo(r.al, 'xs')}<span>${hm(r.dep)} · ${esc(AL[r.al].name)}</span></div>
        <div class="tl-b"><div class="tl-bar" style="left:${x(r.dep)};width:${(r.dur / range * 100).toFixed(2)}%">${r.segs.map(s => `<i class="${s.type === 'lay' ? 'lay' : ''}" style="flex:${s.min}"></i>`).join('')}</div></div>
        <div class="tl-p">${money(r.price)}</div></div>`).join('');
    return `<div class="tl"><div class="tl-axis">${ticks.map(t => `<span style="left:${x(t)}">${hm(t)}${t >= 1440 ? ' +1' : ''}</span>`).join('')}</div>
      <div class="tl-rows"><div class="tl-grid">${ticks.map(t => `<i style="left:${x(t)}"></i>`).join('')}</div>${rows}</div>
      <div class="tl-legend"><span><i></i>En vol</span><span><i class="lay"></i>Escale</span><span><i class="cheap"></i>Le moins cher</span><span>Heures de départ locales${list.length === 40 ? ' · 40 premiers vols' : ''}</span></div></div>`;
  }
  $$('[data-view-mode]').forEach(b => b.addEventListener('click', () => {
    R.view = b.dataset.viewMode;
    $$('[data-view-mode]').forEach(x => x.setAttribute('aria-checked', String(x === b)));
    renderList();
  }));

  const findResult = key => R.results.find(r => r.key === key) || (R.out?.key === key ? R.out : null) || resultFromKey(key);
  $('#resultsList').addEventListener('click', e => {
    if (e.target.closest('[data-reset]')) { resetFilters(); return; }
    const c = e.target.closest('[data-key]');
    if (!c) return;
    const r = findResult(c.dataset.key);
    const act = e.target.closest('[data-act]')?.dataset.act;
    if (act === 'fav') toggleFav(r, e.target.closest('button'));
    else if (act === 'cmp') toggleCompare(r);
    else if (act === 'choose') choose(r);
    else openDetail(r);
  });
  $('#resultsList').addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.matches('[data-key]')) openDetail(findResult(e.target.dataset.key)); });

  function choose(r) {
    if (S.trip === 'rt' && R.step === 1) {
      R.out = r;
      goStep(2);
      toast(`Aller retenu · ${money(r.price)} — choisissez votre retour`);
      return;
    }
    openDetail(r, true);
  }

  // ---------- Filtres ----------
  function renderFilters() {
    const res = R.results, F = R.F;
    const minBy = pred => { let m = null; for (const r of res) if (pred(r) && (m === null || r.price < m)) m = r.price; return m; };
    const chk = (f, v, on, label, price, extra = '') => `<label class="check"><input type="checkbox" data-f="${f}" value="${v}" ${on ? 'checked' : ''} ${price === null && f === 'stops' ? 'disabled' : ''}><span class="c-label">${label}</span>${extra}<span class="c-price">${price === null ? '—' : money(price)}</span></label>`;
    const times = key => `<div class="timegrid">${[['n', 'Nuit', '00–06'], ['m', 'Matin', '06–12'], ['a', 'Après-midi', '12–18'], ['e', 'Soir', '18–24']].map(([k, l, s]) =>
      `<label class="timechip"><input type="checkbox" data-f="${key}" value="${k}" ${F[key].has(k) ? 'checked' : ''}><span>${l}<em>${s}</em></span></label>`).join('')}</div>`;
    const sw = (key, lbl, sub = '') => `<label class="switch-row"><span class="sr-t">${lbl}${sub ? `<small>${sub}</small>` : ''}</span><input type="checkbox" class="switch" data-f="${key}" ${F[key] ? 'checked' : ''}></label>`;
    const carriers = [...new Set(res.flatMap(r => r.carriers))].map(c => ({ c, m: minBy(r => r.carriers.includes(c)) })).sort((a, b) => a.m - b.m);
    const hubs = [...new Set(res.flatMap(r => r.lays.map(l => l.at)))].sort();
    const alliances = ['SkyTeam', 'Star Alliance', 'oneworld'].filter(a => res.some(r => AL[r.al].alliance === a));
    const pMin = res.length ? Math.min(...res.map(r => r.price)) : 0, dMin = res.length ? Math.min(...res.map(r => r.dur)) : 0;
    $('#filtersBody').innerHTML = `
      <div class="fgroup"><h3>Escales</h3>
        ${chk('stops', 0, F.stops.has(0), '<span>Direct</span>', minBy(r => r.stops === 0))}
        ${chk('stops', 1, F.stops.has(1), '<span>1 escale</span>', minBy(r => r.stops === 1))}
        ${chk('stops', 2, F.stops.has(2), '<span>2 escales ou plus</span>', minBy(r => r.stops >= 2))}</div>
      <div class="fgroup"><h3>Prix maximum <small id="priceVal"></small></h3>
        <div class="hist" id="hist" aria-hidden="true"></div>
        <input type="range" id="priceRange" min="${pMin}" max="${F.priceCap}" step="1" value="${F.priceMax}" aria-label="Prix maximum">
        <div class="range-lbl"><span>${money(pMin)}</span><span>${money(F.priceCap)}</span></div></div>
      <div class="fgroup"><h3>Horaires</h3><p class="sublabel">Départ de ${esc(cityOf(legParams().from))}</p>${times('depT')}<p class="sublabel">Arrivée à ${esc(cityOf(legParams().to))}</p>${times('arrT')}</div>
      <div class="fgroup"><h3>Durée maximum <small id="durVal"></small></h3>
        <input type="range" id="durRange" min="${dMin}" max="${F.durCap}" step="15" value="${F.durMax}" aria-label="Durée maximale"></div>
      <div class="fgroup"><h3>Bagages</h3>${sw('hold', 'Bagage en soute inclus', '23 kg compris dans le prix')}${sw('cab', 'Bagage cabine inclus', 'Valise cabine en plus du sac')}</div>
      <div class="fgroup"><h3>Compagnies <small>${carriers.length}</small></h3>
        <div class="seg-mini" role="radiogroup" aria-label="Type de compagnie">${[['all', 'Toutes'], ['full', 'Classiques'], ['low', 'Low-cost']].map(([k, l]) => `<button type="button" role="radio" data-kind="${k}" aria-checked="${F.kind === k}">${l}</button>`).join('')}</div>
        ${carriers.map(({ c, m }, i) => `<label class="check" ${i >= 8 ? 'data-extra hidden' : ''}><input type="checkbox" data-f="al" value="${c}" ${F.exAl.has(c) ? '' : 'checked'}><span class="c-label">${logo(c, 'xs')}<span>${esc(AL[c].name)}</span></span><button type="button" class="only" data-only="${c}">seule</button><span class="c-price">${money(m)}</span></label>`).join('')}
        ${carriers.length > 8 ? `<button type="button" class="more-btn" id="moreAl">Afficher les ${carriers.length - 8} autres</button>` : ''}
        ${alliances.length ? `<p class="sublabel" style="margin-top:14px">Alliances</p>${alliances.map(a => `<label class="check"><input type="checkbox" data-f="alliance" value="${a}" ${F.alliances.has(a) ? 'checked' : ''}><span class="c-label"><span>${a}</span></span></label>`).join('')}` : ''}</div>
      ${hubs.length ? `<div class="fgroup"><h3>Correspondances <small id="layVal"></small></h3>
        <input type="range" id="layRange" min="60" max="1440" step="30" value="${F.layMax}" aria-label="Durée d'escale maximale">
        ${sw('noNight', 'Pas de nuit en escale')}
        ${res.some(r => r.self) ? sw('self', 'Billets séparés', 'Combinaisons de deux compagnies, souvent moins chères') : ''}
        <p class="sublabel" style="margin-top:10px">Aéroports d'escale</p>
        ${hubs.map(h => `<label class="check"><input type="checkbox" data-f="hub" value="${h}" ${F.exHubs.has(h) ? '' : 'checked'}><span class="c-label"><code>${h}</code><span class="muted">${esc(cityOf(h))}</span></span></label>`).join('')}</div>` : ''}
      <div class="fgroup"><h3>À bord</h3>${sw('wifi', 'Wi-Fi')}${sw('meal', 'Repas inclus')}${sw('pwr', 'Prises électriques')}</div>
      <div class="fgroup"><h3>Conditions</h3>${sw('refund', 'Modifiable ou remboursable')}${sw('ontime', 'Ponctualité supérieure à 85 %')}${sw('lowCo2', 'Émissions inférieures à la moyenne')}</div>`;
    updateRangeLabels();
  }
  function updateRangeLabels() {
    const F = R.F;
    if ($('#priceVal')) $('#priceVal').textContent = F.priceMax >= F.priceCap ? 'Tous' : money(F.priceMax);
    if ($('#durVal')) $('#durVal').textContent = F.durMax >= F.durCap ? 'Toutes' : fmtDur(F.durMax);
    if ($('#layVal')) $('#layVal').textContent = F.layMax >= 1440 ? 'Toutes' : '≤ ' + fmtDur(F.layMax);
  }
  function updateHist() {
    const h = $('#hist');
    if (!h) return;
    const ps = R.results.map(r => r.price);
    if (!ps.length) { h.innerHTML = ''; return; }
    const lo = Math.min(...ps), hi = Math.max(...ps), n = 24, w = (hi - lo) / n || 1;
    const bins = Array(n).fill(0);
    ps.forEach(p => bins[Math.min(n - 1, Math.floor((p - lo) / w))]++);
    const max = Math.max(...bins);
    h.innerHTML = bins.map((c, i) => `<i class="${lo + i * w <= R.F.priceMax ? 'in' : ''}" style="height:${c ? 8 + 92 * c / max : 0}%"></i>`).join('');
  }
  let filterRaf;
  const refilter = () => { cancelAnimationFrame(filterRaf); filterRaf = requestAnimationFrame(applyFilters); };
  $('#filtersBody').addEventListener('input', e => {
    const t = e.target, F = R.F;
    if (t.id === 'priceRange') F.priceMax = +t.value;
    else if (t.id === 'durRange') F.durMax = +t.value;
    else if (t.id === 'layRange') F.layMax = +t.value;
    else return;
    updateRangeLabels(); refilter();
  });
  $('#filtersBody').addEventListener('change', e => {
    const t = e.target, F = R.F, f = t.dataset.f;
    if (!f) return;
    const toggle = (set, v, on) => on ? set.add(v) : set.delete(v);
    if (f === 'stops') toggle(F.stops, +t.value, t.checked);
    else if (f === 'depT' || f === 'arrT') toggle(F[f], t.value, t.checked);
    else if (f === 'al') toggle(F.exAl, t.value, !t.checked);
    else if (f === 'hub') toggle(F.exHubs, t.value, !t.checked);
    else if (f === 'alliance') toggle(F.alliances, t.value, t.checked);
    else if (f in F) F[f] = t.checked;
    refilter();
  });
  $('#filtersBody').addEventListener('click', e => {
    const only = e.target.closest('[data-only]');
    if (only) {
      e.preventDefault();
      const c = only.dataset.only;
      R.F.exAl = new Set(R.results.flatMap(r => r.carriers).filter(x => x !== c));
      $$('[data-f=al]').forEach(i => { i.checked = i.value === c; });
      refilter();
    }
    const k = e.target.closest('[data-kind]');
    if (k) { R.F.kind = k.dataset.kind; $$('[data-kind]').forEach(b => b.setAttribute('aria-checked', String(b === k))); refilter(); }
    if (e.target.id === 'moreAl') { $$('[data-extra]').forEach(x => { x.hidden = false; }); e.target.remove(); }
  });
  function resetFilters() { S.direct = false; S.bag = false; R.F = defaultFilters(R.results); renderFilters(); applyFilters(); }
  $('#resetFilters').addEventListener('click', resetFilters);

  function renderActiveChips() {
    const F = R.F, chips = [], tl = { n: 'nuit', m: 'matin', a: 'après-midi', e: 'soir' };
    if (F.stops.size < 3) chips.push(['stops', [...F.stops].sort().map(s => ['Direct', '1 escale', '2+ escales'][s]).join(' ou ') || 'Aucune escale']);
    if (F.priceMax < F.priceCap) chips.push(['price', '≤ ' + money(F.priceMax)]);
    if (F.depT.size) chips.push(['depT', 'Départ ' + [...F.depT].map(k => tl[k]).join(', ')]);
    if (F.arrT.size) chips.push(['arrT', 'Arrivée ' + [...F.arrT].map(k => tl[k]).join(', ')]);
    if (F.durMax < F.durCap) chips.push(['dur', '≤ ' + fmtDur(F.durMax)]);
    if (F.exAl.size) chips.push(['al', plural(F.exAl.size, 'compagnie') + ' exclue' + (F.exAl.size > 1 ? 's' : '')]);
    if (F.alliances.size) chips.push(['alliance', [...F.alliances].join(', ')]);
    if (F.kind !== 'all') chips.push(['kind', F.kind === 'low' ? 'Low-cost' : 'Compagnies classiques']);
    [['hold', 'Soute incluse'], ['cab', 'Cabine incluse'], ['wifi', 'Wi-Fi'], ['meal', 'Repas'], ['pwr', 'Prises'], ['refund', 'Modifiable'], ['noNight', 'Sans nuit en escale'], ['lowCo2', 'Émissions réduites'], ['ontime', 'Ponctuel']].forEach(([k, l]) => { if (F[k]) chips.push([k, l]); });
    if (!F.self) chips.push(['self', 'Sans billets séparés']);
    if (F.layMax < 1440) chips.push(['lay', 'Escale ≤ ' + fmtDur(F.layMax)]);
    if (F.exHubs.size) chips.push(['hub', 'Sans ' + [...F.exHubs].join(', ')]);
    $('#activeChips').innerHTML = chips.map(([k, l]) => `<button type="button" data-chip="${k}" aria-label="Retirer le filtre ${esc(l)}">${esc(l)} ${icon('x')}</button>`).join('');
    $('#activeFilterCount').textContent = chips.length || '';
  }
  $('#activeChips').addEventListener('click', e => {
    const b = e.target.closest('[data-chip]');
    if (!b) return;
    const F = R.F, D = defaultFilters(R.results), k = b.dataset.chip;
    const map = { price: 'priceMax', dur: 'durMax', al: 'exAl', lay: 'layMax', hub: 'exHubs', alliance: 'alliances' };
    if (k === 'stops') F.stops = new Set([0, 1, 2]);
    else if (map[k]) F[map[k]] = D[map[k]];
    else if (k === 'depT' || k === 'arrT') F[k] = new Set();
    else if (k === 'kind') F.kind = 'all';
    else if (k === 'self') F.self = true;
    else F[k] = false;
    if (k === 'hold') S.bag = false;
    renderFilters(); applyFilters();
  });
  $('#openFilters').addEventListener('click', () => { $('#filters').classList.add('open'); $('#scrim').hidden = false; setTimeout(() => $('#closeFilters').focus(), 50); });
  const closeFilters = () => { if (!$('#filters').classList.contains('open')) return; $('#filters').classList.remove('open'); if ($('#drawer').hidden) $('#scrim').hidden = true; $('#openFilters').focus(); };
  $('#closeFilters').addEventListener('click', closeFilters);
  $('#applyFilters').addEventListener('click', closeFilters);

  // ---------- Détail du vol (tiroir) ----------
  let lastFocus = null;
  function legBlock(r, title) {
    let html = `<div class="leg-head"><h3>${title}</h3><span>${longD(r.date)}</span></div>
      <p class="leg-route">${r.from} → ${r.to}</p><p class="leg-cities">${esc(AP[r.from].city)} → ${esc(AP[r.to].city)} · ${fmtDur(r.dur)} · ${r.stops ? plural(r.stops, 'escale') : 'direct'}</p>`;
    const transit = r.lays.map(l => l.at).find(c => ['JFK', 'MIA', 'LAX', 'SFO', 'YUL', 'LHR', 'LGW'].includes(c));
    if (transit) html += `<div class="selfwarn">${icon('alert')}<div><b>Escale ${AP[transit].country === 'États-Unis' ? 'aux États-Unis : ESTA obligatoire' : AP[transit].country === 'Canada' ? 'au Canada : AVE obligatoire' : 'au Royaume-Uni : ETA ou visa de transit selon votre nationalité'}</b>, même sans quitter l'aéroport.</div></div>`;
    if (r.self) html += `<div class="selfwarn">${icon('alert')}<div><b>Deux billets séparés.</b> Vous récupérez vos bagages et repassez l'enregistrement à ${esc(cityOf(r.lays.find(l => l.self).at))}. En cas de retard du premier vol, la seconde compagnie n'est pas tenue de vous réacheminer.</div></div>`;
    html += '<div class="itin">';
    for (const s of r.segs) {
      if (s.type === 'lay') {
        html += `<div class="layover ${s.min >= 420 || s.self ? 'warn' : ''}">${icon(s.min >= 420 ? 'moon' : 'clock')}${s.self ? 'Changement de billet' : 'Escale'} à ${esc(cityOf(s.at))} (${s.at}) · ${fmtDur(s.min)}${s.min >= 420 ? ' · nuit sur place' : s.min < 75 ? ' · correspondance courte' : ''}</div>`;
        continue;
      }
      const dl = s.depU + AP[s.from].tz * 60, al = s.arrU + AP[s.to].tz * 60;
      html += `<div class="seg-b">
        <div class="seg-pt"><b>${hm(dl)}</b><code>${s.from}</code><span>${esc(AP[s.from].city)} · ${esc(AP[s.from].name)}</span><em>${fmtD(addDays(r.date, dayOff(dl)), { day: 'numeric', month: 'short' })}</em></div>
        <div class="seg-info">${logo(s.al, 's')}<div><b>${esc(AL[s.al].name)} · <span class="mono">${s.fn}</span></b><span>${esc(s.ac)} · ${fmtDur(s.min)} · ${Math.round(s.km).toLocaleString('fr-FR')} km</span></div></div>
        <div class="seg-pt"><b>${hm(al)}</b><code>${s.to}</code><span>${esc(AP[s.to].city)} · ${esc(AP[s.to].name)}</span><em>${fmtD(addDays(r.date, dayOff(al)), { day: 'numeric', month: 'short' })}</em></div></div>`;
    }
    html += `</div><div class="facts">
      <div class="fact">${icon('cabin')}<div><b>${r.cab ? 'Inclus' : 'Petit sac seulement'}</b><span>Bagage cabine</span></div></div>
      <div class="fact">${icon('bag')}<div><b>${r.hold ? '1 × 23 kg' : 'En option'}</b><span>Bagage en soute</span></div></div>
      <div class="fact">${icon('meal')}<div><b>${r.meal ? 'Inclus' : 'Payant à bord'}</b><span>Restauration</span></div></div>
      <div class="fact">${icon('wifi')}<div><b>${r.wifi ? 'Disponible' : 'Non'}${r.pwr ? ' · prises' : ''}</b><span>Connectivité</span></div></div>
      <div class="fact">${icon('leaf')}<div><b>${r.co2} kg CO₂</b><span>Par passager, estimation</span></div></div>
      <div class="fact">${icon('shield')}<div><b>${['Non remboursable', 'Modifiable avec frais', 'Remboursable'][r.refund]}</b><span>Tarif de base</span></div></div>
    </div><div class="reliab"><span>Ponctualité</span><span class="meter"><i style="width:${r.ontime}%"></i></span><b>${r.ontime} %</b></div>`;
    return html;
  }
  function fareOptions(t) {
    const base = t.out.price + (t.ret?.price || 0);
    const low = t.out.lowcost || t.ret?.lowcost;
    const hold = t.out.hold && (!t.ret || t.ret.hold), cab = t.out.cab && (!t.ret || t.ret.cab);
    const n = t.ret ? 2 : 1;
    return low ? [
      { name: 'Basic', price: base, inc: [[1, 'Petit sac sous le siège'], [cab, 'Bagage cabine 10 kg'], [hold, 'Bagage soute 23 kg'], [0, 'Modification']] },
      { name: 'Regular', price: base + 28 * n, pop: true, inc: [[1, 'Petit sac sous le siège'], [1, 'Bagage cabine 10 kg'], [1, 'Siège au choix'], [0, 'Modification']] },
      { name: 'Plus', price: base + 62 * n, inc: [[1, 'Bagage cabine 10 kg'], [1, 'Bagage soute 23 kg'], [1, 'Embarquement prioritaire'], [1, 'Modification gratuite']] },
    ] : [
      { name: 'Light', price: base, inc: [[cab, 'Bagage cabine 12 kg'], [hold, 'Bagage soute 23 kg'], [0, 'Modification'], [0, 'Remboursement']] },
      { name: 'Standard', price: Math.round(base * 1.16 + (hold ? 0 : 20 * n)), pop: true, inc: [[1, 'Bagage cabine 12 kg'], [1, 'Bagage soute 23 kg'], [1, 'Choix du siège'], [1, 'Modification avec frais']] },
      { name: 'Flex', price: Math.round(base * 1.45 + 30 * n), inc: [[1, 'Bagage cabine 12 kg'], [1, 'Deux bagages en soute'], [1, 'Modification gratuite'], [1, 'Remboursable']] },
    ];
  }
  const siteHost = u => u.replace(/^https?:\/\/(www[s]?\.)?/, '').replace(/\/.*$/, '');
  function openDetail(r, booking = false) {
    if (!r) return;
    const isRet = S.trip === 'rt' && R.step === 2 && R.out && r.key !== R.out.key;
    const trip = { out: isRet ? R.out : r, ret: isRet ? r : null, pending: S.trip === 'rt' && R.step === 1 && !$('#view-results').hidden };
    const fares = fareOptions(trip);
    trip.fare = fares[0];
    lastFocus = document.activeElement;
    $('#drawerTitle').textContent = trip.ret ? 'Votre aller-retour' : trip.pending ? 'Vol aller' : 'Votre vol';
    const body = $('#drawerBody');
    body.innerHTML = legBlock(trip.out, trip.ret || trip.pending ? 'Aller' : 'Vol') + (trip.ret ? '<hr class="divider">' + legBlock(trip.ret, 'Retour') : '') +
      (trip.pending ? '<p class="demo-note">Prix de l\'aller seul. Vous choisirez ensuite votre retour ; le total sera recalculé.</p>' :
        `<p class="section-t">Tarif</p>
        <div class="fares" role="radiogroup" aria-label="Tarif">${fares.map((fa, i) => `<button type="button" class="fare" role="radio" data-fare="${i}" aria-checked="${i === 0}">${fa.pop ? '<span class="pop">Conseillé</span>' : ''}<h4>${fa.name}</h4><span class="fp">${money(fa.price)} <small>/ adulte</small></span><ul>${fa.inc.map(([ok, l]) => `<li class="${ok ? '' : 'n'}">${icon(ok ? 'check' : 'x')}${l}</li>`).join('')}</ul></button>`).join('')}</div>
        <p class="section-t">Détail du prix</p><div class="breakdown" id="breakdown"></div>`);
    body.scrollTop = 0;
    if (!trip.pending && !$('#view-results').hidden) { R.trip = trip; setPhase('fare'); }
    const foot = () => {
      const fa = trip.fare, tot = paxTotal(fa.price);
      if (!trip.pending) {
        $('#breakdown').innerHTML = `
          <div><span>${plural(S.adults, 'adulte')} × ${money(fa.price)}</span><span>${money(fa.price * S.adults)}</span></div>
          ${S.children ? `<div><span>${plural(S.children, 'enfant')} (−25 %)</span><span>${money(fa.price * .75 * S.children)}</span></div>` : ''}
          ${S.infants ? `<div><span>${plural(S.infants, 'bébé')} (10 %)</span><span>${money(fa.price * .1 * S.infants)}</span></div>` : ''}
          <div class="sub"><span>dont taxes et redevances aéroportuaires</span><span>${money(tot * .27)}</span></div>
          <div class="zero"><span>Frais Envol</span><span>${money(0)}</span></div>
          <div class="tot"><span>Total estimé, payé à la compagnie</span><span>${money(tot)}</span></div>`;
      }
      $('#drawerFoot').innerHTML = `<div class="price"><small>${trip.pending ? 'Aller, par adulte' : 'Total · ' + plural(paxCount(), 'voyageur')}</small><b>${money(trip.pending ? trip.out.price : tot)}</b></div>
        <button type="button" class="btn-dark" id="dCta">${trip.pending ? 'Choisir cet aller' : 'Continuer'} ${icon('arrow')}</button>`;
    };
    foot();
    body.onclick = e => {
      const b = e.target.closest('[data-fare]');
      if (!b) return;
      trip.fare = fares[+b.dataset.fare];
      $$('[data-fare]', body).forEach(x => x.setAttribute('aria-checked', String(x === b)));
      foot();
      if (R.trip === trip) renderJourney();
    };
    $('#drawerFoot').onclick = e => {
      if (!e.target.closest('#dCta')) return;
      closeDrawer(true);
      if (trip.pending) choose(trip.out); else openBooking(trip);
    };
    $('#scrim').hidden = false;
    $('#drawer').hidden = false;
    $('#drawer [data-close]').focus();
    if (booking) setTimeout(() => $('.fares')?.scrollIntoView({ behavior: 'smooth', block: 'center' }), 300);
  }
  function closeDrawer(keepPhase = false) {
    $('#drawer').hidden = true;
    if (!keepPhase && R.phase === 'fare') { R.trip = null; setPhase('select'); }
    if (!$('#filters').classList.contains('open')) $('#scrim').hidden = true;
    lastFocus?.focus?.();
  }
  $('#drawer [data-close]').addEventListener('click', () => closeDrawer());
  $('#scrim').addEventListener('click', () => { closeDrawer(); closeFilters(); });

  // ---------- Accompagnement jusqu'au site de la compagnie ----------
  function tickets(t) {
    const list = [];
    const add = (r, label) => r.flights.forEach((f, i) => list.push({ al: f.al, label: r.self ? `${label} · billet ${i + 1}/${r.flights.length}` : label, r, f }));
    add(t.out, 'Aller');
    if (t.ret) add(t.ret, 'Retour');
    const merged = [];
    for (const k of list) {
      const m = !t.out.self && !t.ret?.self && merged.find(x => x.al === k.al);
      if (m) m.label = 'Aller et retour'; else merged.push({ ...k });
    }
    return merged;
  }
  function visaNote(t) {
    const notes = {
      'États-Unis': 'Autorisation ESTA obligatoire, à demander au moins 72 h avant le départ sur le site officiel.',
      Canada: 'Autorisation de voyage électronique (AVE) obligatoire.',
      'Royaume-Uni': 'Autorisation ETA britannique requise pour de nombreux voyageurs.',
      Australie: 'Visa électronique (eVisitor ou ETA) obligatoire.',
      Inde: 'e-Visa requis pour la plupart des nationalités.',
      Égypte: 'Visa requis (e-Visa ou à l\'arrivée, selon la nationalité).',
    };
    return notes[AP[t.out.to].country] || 'Vérifiez les formalités d\'entrée sur diplomatie.gouv.fr, rubrique Conseils aux voyageurs.';
  }
  function openBooking(t) {
    const tk = tickets(t), tot = paxTotal(t.fare.price);
    let step = 1;
    const render = () => {
      if (!$('#view-results').hidden) { R.trip = t; setPhase(step === 3 ? 'done' : 'check'); }
      let html = `<div class="bsteps">${['Récapitulatif', 'Vérifications', 'Réservation'].map((l, i) => `<div class="${i < step ? 'on' : ''}">${i + 1}. ${l}</div>`).join('')}</div>`;
      if (step === 1) {
        $('#modalTitle').textContent = 'Récapitulatif';
        const leg = (r, l) => `<div class="bp-leg"><div class="big"><b>${r.from}</b><span>${esc(AP[r.from].city)}</span><small>${hm(r.dep)} · ${fmtD(r.date, { day: 'numeric', month: 'short' })}</small></div>
          <div class="mid">${l} · ${fmtDur(r.dur)}<span class="ln"></span>${icon('plane')}${r.stops ? r.lays.map(x => x.at).join(' · ') : 'Direct'}</div>
          <div class="big r"><b>${r.to}</b><span>${esc(AP[r.to].city)}</span><small>${hm(r.arr)}${dayOff(r.arr) - dayOff(r.dep) ? ' (+' + (dayOff(r.arr) - dayOff(r.dep)) + ')' : ''}</small></div></div>`;
        html += `<div class="bpass"><div class="bpass-main">
            <div class="bpass-head"><span class="bp-al">${logo(t.out.al, 's')}${esc(AL[t.out.al].name)}${t.ret && t.ret.al !== t.out.al ? ' + ' + esc(AL[t.ret.al].name) : ''}</span></div>
            ${leg(t.out, 'Aller')}${t.ret ? leg(t.ret, 'Retour') : ''}
            <div class="bp-grid"><div><small>Passagers</small><b>${paxCount()}</b></div><div><small>Cabine</small><b>${CABINS[S.cabin]}</b></div><div><small>Tarif</small><b>${t.fare.name}</b></div><div><small>Billets</small><b>${tk.length}</b></div></div>
          </div><div class="bpass-stub"><small>Total estimé, ${plural(paxCount(), 'voyageur')}</small><b>${money(tot)}</b></div></div>
          <div class="breakdown"><div><span>Payé directement à</span><span>${tk.map(x => esc(AL[x.al].name)).join(' + ')}</span></div><div class="zero"><span>Frais Envol</span><span>${money(0)}</span></div><div class="sub"><span>Le prix final est confirmé par la compagnie</span><span></span></div></div>
          <div class="bnav" style="margin-top:24px"><button type="button" class="btn-line" data-close>Modifier</button><button type="button" class="btn-dark" data-next>Continuer ${icon('arrow')}</button></div>`;
      } else if (step === 2) {
        $('#modalTitle').textContent = 'Avant de réserver';
        html += `<div class="checklist">
            <label><input type="checkbox"><div><b>Noms identiques au passeport</b><span>Prénoms et nom exactement comme sur le document. Une erreur peut coûter un nouveau billet.</span></div></label>
            <label><input type="checkbox"><div><b>Document de voyage valide</b><span>Passeport valide au moins six mois après le retour pour de nombreuses destinations hors UE.</span></div></label>
            <label><input type="checkbox"><div><b>Formalités d'entrée</b><span>${esc(visaNote(t))}</span></div></label>
            <label><input type="checkbox"><div><b>Bagages</b><span>Tarif ${t.fare.name} : ${t.fare.inc.map(([ok, l]) => (ok ? '' : 'sans ') + l.toLowerCase()).join(', ')}. Un bagage ajouté à l'aéroport coûte souvent deux fois plus cher.</span></div></label>
            ${tk.length > 1 ? `<label><input type="checkbox"><div><b>${tk.length} réservations distinctes</b><span>Vous réserverez ${tk.length} billets sur ${tk.length} sites. Commencez par le vol le plus contraint.</span></div></label>` : ''}
          </div>
          <div class="bnav"><button type="button" class="btn-line" data-prev>Retour</button><button type="button" class="btn-dark" data-go>Réserver sur ${esc(siteHost(AL[tk[0].al].site))} ${icon('external')}</button></div>`;
      } else {
        $('#modalTitle').textContent = 'Réservation';
        html += `<div class="redirect">${porthole('HERO')}
          <h3>Finalisez sur le site de ${esc(AL[tk[0].al].name)}</h3>
          <p>Le site de la compagnie s'est ouvert dans un nouvel onglet. La réservation et le paiement se font là-bas ; Envol n'a pas accès à vos données bancaires.</p>
          <div class="rd-links">${tk.map(x => `<a class="rd-link" href="${AL[x.al].site}" target="_blank" rel="noopener">${logo(x.al, 's')}<span class="rl-t"><b>${esc(AL[x.al].name)} · ${esc(x.label)}</b><span>${x.r.from} → ${x.r.to} · ${fmtD(x.r.date, { day: 'numeric', month: 'short' })} · ${x.f.fn.join(' + ')}</span></span>${icon('external')}</a>`).join('')}</div>
          <p class="demo-note">Démonstration : les liens mènent à l'accueil des compagnies. En production, un lien profond fourni par le partenaire pré-remplit trajet, dates et passagers.</p>
          <div class="bnav" style="margin-top:20px;justify-content:center"><button type="button" class="btn-line" data-ics>${icon('cal')} Ajouter au calendrier</button><button type="button" class="btn-line" data-copy>Copier le récapitulatif</button></div></div>`;
      }
      $('#modalBody').innerHTML = html;
    };
    const summary = () => {
      const l = r => `${r.from} → ${r.to} · ${fmtD(r.date)} · ${hm(r.dep)}–${hm(r.arr)} · ${r.fns.join('+')}`;
      return `Envol — récapitulatif\n${l(t.out)}${t.ret ? '\n' + l(t.ret) : ''}\nTarif ${t.fare.name} · ${plural(paxCount(), 'voyageur')} · ${money(tot)}`;
    };
    $('#modalBody').onclick = e => {
      if (e.target.closest('[data-next]')) { step = 2; render(); }
      else if (e.target.closest('[data-prev]')) { step = 1; render(); }
      else if (e.target.closest('[data-go]')) { window.open(AL[tk[0].al].site, '_blank', 'noopener'); step = 3; render(); }
      else if (e.target.closest('[data-copy]')) navigator.clipboard?.writeText(summary()).then(() => toast('Récapitulatif copié'), () => toast('Copie impossible', 'alert'));
      else if (e.target.closest('[data-ics]')) downloadIcs(t);
      else if (e.target.closest('[data-close]')) closeModal();
    };
    $('#modal .modal-card').classList.remove('wide');
    $('#modal').hidden = false;
    render();
    $('#modal .modal-head [data-close]').focus();
  }
  function closeModal() {
    $('#modal').hidden = true;
    if (R.phase === 'check') { R.trip = null; setPhase('select'); }
    lastFocus?.focus?.();
  }
  $('#modal .modal-head [data-close]').addEventListener('click', closeModal);
  $('#modal').addEventListener('click', e => { if (e.target === e.currentTarget) closeModal(); });

  // ---------- Favoris ----------
  function toggleFav(r, btn) {
    const i = favs.findIndex(f => f.key === r.key);
    if (i >= 0) { favs.splice(i, 1); toast('Retiré des favoris'); }
    else { favs.unshift({ key: r.key, price: r.price, from: r.from, to: r.to, date: r.date }); toast('Ajouté aux favoris'); }
    store.set('favs', favs);
    if (btn) { const on = i < 0; btn.classList.toggle('on', on); btn.setAttribute('aria-pressed', String(on)); btn.innerHTML = icon(on ? 'heart' : 'heart-o'); }
    updateCounts();
  }
  function updateCounts() {
    const fc = $('#favCount'), ac = $('#alertCount');
    fc.hidden = !favs.length; fc.textContent = favs.length;
    ac.hidden = !alerts.length; ac.textContent = alerts.length;
  }
  function delta(cur, then) {
    if (cur == null) return '<small class="eq">Plus disponible</small>';
    const d = cur - then;
    return d < 0 ? `<small class="down">−${money(-d)} depuis l'ajout</small>` : d > 0 ? `<small class="up">+${money(d)} depuis l'ajout</small>` : '<small class="eq">Prix inchangé</small>';
  }
  const emptySaved = (t, p) => `<div class="empty-state">${porthole('HERO2')}<h3>${t}</h3><p>${p}</p><div class="actions"><a class="btn-dark" href="#/">Rechercher un vol</a></div></div>`;
  function renderFavs() {
    const el = $('#favList');
    if (!favs.length) { el.innerHTML = emptySaved('Aucun favori', 'Enregistrez un vol avec le cœur pour le retrouver ici et suivre son prix.'); return; }
    el.innerHTML = favs.map((f, i) => {
      const r = f.date >= TODAY ? resultFromKey(f.key) : null;
      return `<div class="saved" style="animation-delay:${i * 40}ms">
        <div class="sv-img">${img(cityCode(f.to), 200)}</div>
        <div><div class="sv-route">${esc(AP[f.from].city)} → ${esc(AP[f.to].city)}<code>${f.from} – ${f.to}</code></div><div class="sv-meta">${fmtD(f.date)}${r ? ` · ${hm(r.dep)} · ${fmtDur(r.dur)} · ${esc(AL[r.al].name)}` : ''}</div></div>
        <div class="sv-price"><b>${r ? money(r.price) : '—'}</b>${delta(r?.price, f.price)}</div>
        <div class="sv-actions">${r ? `<button type="button" class="btn-line" data-fav-open="${i}">Voir</button>` : ''}<button type="button" class="btn-icon" data-fav-del="${i}" aria-label="Supprimer">${icon('x')}</button></div></div>`;
    }).join('');
  }
  $('#favList').addEventListener('click', e => {
    const o = e.target.closest('[data-fav-open]'), d = e.target.closest('[data-fav-del]');
    if (d) { favs.splice(+d.dataset.favDel, 1); store.set('favs', favs); renderFavs(); updateCounts(); }
    if (o) { const r = resultFromKey(favs[+o.dataset.favOpen].key); if (r) { S.trip = 'ow'; R.step = 1; openDetail(r); } }
  });

  // ---------- Alertes prix ----------
  $('#alertBtn').addEventListener('click', () => {
    const i = alerts.findIndex(a => a.from === S.from && a.to === S.to && a.dep === S.dep);
    if (i >= 0) { alerts.splice(i, 1); toast('Alerte supprimée'); }
    else {
      alerts.unshift({ from: S.from, to: S.to, dep: S.dep, ret: S.trip === 'rt' ? S.ret : null, cabin: S.cabin, price: minPrice(S.from, S.to, S.dep), created: TODAY });
      toast('Alerte créée : vous serez prévenu d\'une baisse de prix', 'bell');
    }
    store.set('alerts', alerts); updateCounts(); renderHead();
  });
  function spark(a) {
    // Historique simulé : prix le plus bas affiché pour ce trajet sur les 14 derniers jours
    const pts = [];
    for (let k = 13; k >= 0; k--) {
      const asOf = addDays(TODAY, -k);
      let m = null;
      for (const o of expand(a.from)) for (const d of expand(a.to)) for (const f of byRoute.get(o + '-' + d) || []) { const p = priceFor(f, a.dep, a.cabin, asOf); if (p !== null && (m === null || p < m)) m = p; }
      pts.push(m);
    }
    const v = pts.filter(x => x != null);
    if (v.length < 2) return '';
    const lo = Math.min(...v), hi = Math.max(...v), W = 100, H = 30;
    const xy = pts.map((p, i) => p == null ? null : [(i / 13 * (W - 6) + 3).toFixed(1), (H - 4 - (hi === lo ? .5 : (p - lo) / (hi - lo)) * (H - 8)).toFixed(1)]).filter(Boolean);
    const last = xy[xy.length - 1];
    return `<svg class="spark" viewBox="0 0 ${W} ${H}" role="img" aria-label="Prix sur 14 jours : de ${money(v[0])} à ${money(v[v.length - 1])}"><path d="M${xy.map(p => p.join(',')).join('L')}"/><circle cx="${last[0]}" cy="${last[1]}" r="2.5"/></svg>`;
  }
  function renderAlerts() {
    const el = $('#alertList');
    if (!alerts.length) { el.innerHTML = emptySaved('Aucune alerte', 'Depuis une recherche, touchez la cloche pour suivre l\'évolution du prix d\'un trajet.'); return; }
    el.innerHTML = alerts.map((a, i) => {
      const cur = a.dep >= TODAY ? minPrice(a.from, a.to, a.dep, a.cabin) : null;
      return `<div class="saved" style="animation-delay:${i * 40}ms">
        <div class="sv-img">${img(a.to, 200)}</div>
        <div><div class="sv-route">${esc(cityOf(a.from))} → ${esc(cityOf(a.to))}<code>${a.from} – ${a.to}</code></div><div class="sv-meta">${fmtD(a.dep)}${a.ret ? ' – ' + fmtD(a.ret) : ''} · ${CABINS[a.cabin]} · depuis le ${fmtD(a.created, { day: 'numeric', month: 'short' })}</div></div>
        <div class="sv-price">${a.dep >= TODAY ? spark(a) : ''}<b>${cur ? money(cur) : '—'}</b>${delta(cur, a.price)}</div>
        <div class="sv-actions"><button type="button" class="btn-line" data-al-open="${i}">Rechercher</button><button type="button" class="btn-icon" data-al-del="${i}" aria-label="Supprimer l'alerte">${icon('x')}</button></div></div>`;
    }).join('');
  }
  $('#alertList').addEventListener('click', e => {
    const o = e.target.closest('[data-al-open]'), d = e.target.closest('[data-al-del]');
    if (d) { alerts.splice(+d.dataset.alDel, 1); store.set('alerts', alerts); renderAlerts(); updateCounts(); }
    if (o) {
      const a = alerts[+o.dataset.alOpen];
      Object.assign(S, { from: a.from, to: a.to, dep: a.dep, ret: a.ret || addDays(a.dep, 7), trip: a.ret ? 'rt' : 'ow', cabin: a.cabin });
      location.hash = '#/vols?' + toParams();
    }
  });

  // ---------- Comparateur ----------
  function toggleCompare(r) {
    const i = R.compare.indexOf(r.key);
    if (i >= 0) R.compare.splice(i, 1);
    else { if (R.compare.length >= 3) { toast('Trois vols maximum', 'alert'); return; } R.compare.push(r.key); }
    $$(`[data-key="${CSS.escape(r.key)}"] [data-act=cmp]`).forEach(b => { const on = R.compare.includes(r.key); b.classList.toggle('on', on); b.setAttribute('aria-pressed', String(on)); });
    renderCompareBar();
  }
  function renderCompareBar() {
    $('#compareBar').hidden = !R.compare.length || $('#view-results').hidden;
    $('#cbItems').innerHTML = R.compare.map(k => { const r = findResult(k); return r ? `<span>${logo(r.al, 'xs')}${hm(r.dep)} · ${money(r.price)}</span>` : ''; }).join('');
    $('#cbGo').disabled = R.compare.length < 2;
    $('#cbGo').style.opacity = R.compare.length < 2 ? .5 : 1;
  }
  $('#cbClear').addEventListener('click', () => { R.compare = []; $$('[data-act=cmp].on').forEach(b => { b.classList.remove('on'); b.setAttribute('aria-pressed', 'false'); }); renderCompareBar(); });
  $('#cbGo').addEventListener('click', () => {
    const list = R.compare.map(findResult).filter(Boolean);
    if (list.length < 2) return;
    const rows = [
      ['Compagnie', r => `<span class="cmp-h">${logo(r.al, 's')}${esc(r.carriers.map(c => AL[c].name).join(' + '))}</span>`],
      ['Horaires', r => `${hm(r.dep)} ${r.from} → ${hm(r.arr)} ${r.to}`],
      ['Prix', r => money(r.price), r => r.price],
      ['Durée', r => fmtDur(r.dur), r => r.dur],
      ['Escales', r => r.stops ? r.lays.map(l => `${l.at} (${fmtDur(l.min)})`).join(', ') : 'Direct', r => r.stops],
      ['Bagage cabine', r => r.cab ? 'Inclus' : '—', r => -r.cab],
      ['Bagage soute', r => r.hold ? '23 kg' : '—', r => -r.hold],
      ['Repas', r => r.meal ? 'Oui' : '—'],
      ['Wi-Fi', r => r.wifi ? 'Oui' : '—'],
      ['CO₂', r => r.co2 + ' kg', r => r.co2],
      ['Ponctualité', r => r.ontime + ' %', r => -r.ontime],
      ['Conditions', r => ['Non remboursable', 'Modifiable', 'Remboursable'][r.refund], r => -r.refund],
      ['Appareil', r => esc(r.aircraft.join(', '))],
    ];
    $('#modalTitle').textContent = 'Comparaison';
    $('#modalBody').innerHTML = `<div style="overflow-x:auto"><table class="cmp-table"><tbody>${rows.map(([l, f, score]) => {
      const best = score ? Math.min(...list.map(score)) : null;
      const unique = score && list.filter(r => score(r) === best).length < list.length;
      return `<tr><th scope="row">${l}</th>${list.map(r => `<td class="${unique && score(r) === best ? 'win' : ''}">${f(r)}</td>`).join('')}</tr>`;
    }).join('')}<tr><th></th>${list.map(r => `<td><button type="button" class="btn-dark" data-cmp-choose="${r.key}">Choisir</button></td>`).join('')}</tr></tbody></table></div>`;
    $('#modalBody').onclick = e => { const b = e.target.closest('[data-cmp-choose]'); if (b) { closeModal(); choose(findResult(b.dataset.cmpChoose)); } };
    $('#modal .modal-card').classList.add('wide');
    lastFocus = document.activeElement;
    $('#modal').hidden = false;
  });

  // ---------- Actions de l'en-tête ----------
  $('#editBtn').addEventListener('click', e => {
    const slot = $('#slotResults'), open = slot.hidden;
    slot.hidden = !open;
    e.currentTarget.setAttribute('aria-expanded', String(open));
    if (open) { syncForm(); $('#fromInput').blur(); }
  });
  $('#shareBtn').addEventListener('click', () => {
    const url = location.href;
    if (navigator.share) navigator.share({ title: 'Envol', text: `${cityOf(S.from)} → ${cityOf(S.to)}`, url }).catch(() => { });
    else navigator.clipboard?.writeText(url).then(() => toast('Lien de la recherche copié'));
  });

  // ================= EXPLORER : carte =================
  const EX = { origin: 'PAR', month: null, budget: Infinity, vibe: 'all', direct: false, data: [], sort: 'price', vb: null };
  const W = window.WORLD;
  // Projection Natural Earth I (identique à d3.geoNaturalEarth1, utilisée pour pré-calculer le fond de carte)
  function project(lon, lat) {
    const l = lon * Math.PI / 180, p = lat * Math.PI / 180, p2 = p * p, p4 = p2 * p2;
    const x = l * (0.8707 - 0.131979 * p2 + p4 * (-0.013791 + p4 * (0.003971 * p2 - 0.001529 * p4)));
    const y = p * (1.007226 + p2 * (0.015085 + p4 * (-0.044475 + 0.028874 * p2 - 0.005916 * p4)));
    return [W.w / 2 + W.k * x, W.h / 2 - W.k * y];
  }
  // Arc de grand cercle, coupé à l'antiméridien
  function arcPath(a, b) {
    const r = Math.PI / 180, A = AP[a], B = AP[b];
    const v = (lat, lon) => [Math.cos(lat * r) * Math.cos(lon * r), Math.cos(lat * r) * Math.sin(lon * r), Math.sin(lat * r)];
    const p = v(A.lat, A.lon), q = v(B.lat, B.lon);
    const d = Math.acos(clamp(p[0] * q[0] + p[1] * q[1] + p[2] * q[2], -1, 1));
    const n = Math.max(8, Math.round(d * 40));
    let path = '', prev = null;
    for (let i = 0; i <= n; i++) {
      const t = i / n, s1 = Math.sin((1 - t) * d) / Math.sin(d), s2 = Math.sin(t * d) / Math.sin(d);
      const x = s1 * p[0] + s2 * q[0], y = s1 * p[1] + s2 * q[1], z = s1 * p[2] + s2 * q[2];
      const pt = project(Math.atan2(y, x) / r, Math.atan2(z, Math.hypot(x, y)) / r);
      path += (prev && Math.abs(pt[0] - prev[0]) < W.w / 2 ? 'L' : 'M') + pt[0].toFixed(1) + ',' + pt[1].toFixed(1);
      prev = pt;
    }
    return path;
  }
  function renderExplorer() {
    const months = [];
    for (let i = 0; i < 4; i++) months.push(addMonths(addDays(TODAY, 1).slice(0, 7), i));
    if (!months.includes(EX.month)) EX.month = months[0];
    $('#exOrigin').textContent = cityOf(EX.origin);
    $('#exMonths').innerHTML = months.map(m => `<button type="button" role="radio" data-month="${m}" aria-checked="${m === EX.month}">${fmtD(m + '-01', { month: 'long' })}</button>`).join('');
    tabs($('#exVibes'), EX.vibe);
    const first = parseISO(EX.month + '-01');
    const nDays = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
    const dates = [];
    for (let d = 1; d <= nDays; d++) { const s = `${EX.month}-${String(d).padStart(2, '0')}`; if (s > TODAY) dates.push(s); }
    EX.data = cheapestFrom(EX.origin, dates, EX.direct);
    const max = EX.data.length ? EX.data[EX.data.length - 1].price : 1500;
    const bud = $('#exBudget');
    bud.min = EX.data.length ? Math.floor(EX.data[0].price / 10) * 10 : 50;
    bud.max = Math.max(+bud.min + 50, Math.ceil(max / 50) * 50);
    if (!(EX.budget < +bud.max)) EX.budget = +bud.max;
    bud.value = EX.budget;
    EX.vb = null;
    drawExplore();
  }
  const exList = () => EX.data.filter(d => d.price <= EX.budget && (EX.vibe === 'all' || AP[d.ap].vibe === EX.vibe));
  function drawExplore() {
    const list = exList();
    const unlimited = EX.budget >= +$('#exBudget').max;
    $('#exBudgetVal').textContent = unlimited ? 'sans limite' : '≤ ' + money(EX.budget);
    const sorted = list.slice().sort(EX.sort === 'dur' ? (a, b) => a.dur - b.dur : EX.sort === 'name' ? (a, b) => cityOf(a.code).localeCompare(cityOf(b.code), 'fr') : (a, b) => a.price - b.price);
    $('#exCount').innerHTML = `${plural(list.length, 'destination')} <em>en ${fmtD(EX.month + '-01', { month: 'long' })}</em>`;
    $('#exGrid').innerHTML = sorted.map((d, i) => dealCard(d, i)).join('') || '<p class="muted">Aucune destination ne correspond : augmentez le budget ou changez de mois.</p>';
    drawMap(list);
  }
  function drawMap(list) {
    const svg = $('#map');
    if (!W) { svg.outerHTML = '<p class="map-empty">Carte indisponible.</p>'; return; }
    const o = expand(EX.origin)[0];
    const O = project(AP[o].lon, AP[o].lat);
    const pts = list.map(d => ({ d, p: project(AP[d.ap].lon, AP[d.ap].lat) }));
    // Cadrage automatique sur l'origine et les destinations visibles
    const xs = [O[0], ...pts.map(x => x.p[0])], ys = [O[1], ...pts.map(x => x.p[1])];
    let x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
    const box = svg.getBoundingClientRect(), ratio = (box.width || 1600) / (box.height || 740);
    let w = Math.max(x1 - x0, 260) * 1.3, h = Math.max(y1 - y0, 120) * 1.3;
    if (w / h > ratio) h = w / ratio; else w = h * ratio;
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    const target = [cx - w / 2, cy - h / 2, w, h];
    const s = w / (box.width || 1600); // unités carte par pixel écran
    const prices = EX.data.map(x => x.price);
    // Étiquettes de prix sans chevauchement, les moins chères d'abord
    const placed = [], fs = 12 * s, ph = 22 * s;
    const labels = pts.slice().sort((a, b) => a.d.price - b.d.price).map(({ d, p }) => {
      const good = level(d.price, prices) === 'low';
      const txt = `${cityOf(d.code)}  ${money(d.price)}`;
      const lw = (txt.length * 6.6 + 18) * s;
      const cands = [[p[0] + 8 * s, p[1] - ph / 2], [p[0] - 8 * s - lw, p[1] - ph / 2], [p[0] - lw / 2, p[1] - ph - 8 * s], [p[0] - lw / 2, p[1] + 8 * s]];
      const inside = ([x, y]) => x >= target[0] + 4 * s && x + lw <= target[0] + target[2] - 4 * s && y >= target[1] + 4 * s && y + ph <= target[1] + target[3] - 4 * s;
      const ok = cands.filter(inside).find(([x, y]) => !placed.some(q => x < q[0] + q[2] + 2 * s && x + lw + 2 * s > q[0] && y < q[1] + q[3] + 2 * s && y + ph + 2 * s > q[1]));
      if (!ok) return { d, p, good, show: false, lw, pos: cands.find(inside) || cands[0] };
      placed.push([ok[0], ok[1], lw, ph]);
      return { d, p, good, show: true, lw, pos: ok };
    });
    const lbl = ({ d, good, lw, pos }, hidden) => `<g class="lbl ${good ? 'good' : ''}" data-code="${d.code}" ${hidden ? 'data-hover-only style="display:none"' : ''}>
      <rect x="${pos[0].toFixed(1)}" y="${pos[1].toFixed(1)}" width="${lw.toFixed(1)}" height="${ph.toFixed(1)}" rx="${(ph / 2).toFixed(1)}" stroke-width="${s.toFixed(2)}"/>
      <text x="${(pos[0] + 9 * s).toFixed(1)}" y="${(pos[1] + ph / 2 + fs * .36).toFixed(1)}" font-size="${fs.toFixed(1)}">${esc(cityOf(d.code))}<tspan class="p" dx="${(5 * s).toFixed(1)}"> ${money(d.price)}</tspan></text></g>`;
    svg.innerHTML = `<path class="land" d="${W.d}"/>
      <g>${pts.map(({ d }) => `<path class="arc" data-code="${d.code}" d="${arcPath(o, d.ap)}"/>`).join('')}</g>
      <g>${labels.map(l => `<circle class="pt ${l.good ? 'good' : ''}" cx="${l.p[0].toFixed(1)}" cy="${l.p[1].toFixed(1)}" r="${(3.2 * s).toFixed(2)}"/><circle class="hit" data-code="${l.d.code}" cx="${l.p[0].toFixed(1)}" cy="${l.p[1].toFixed(1)}" r="${(11 * s).toFixed(1)}"/>`).join('')}</g>
      <g class="origin"><circle class="ring" cx="${O[0]}" cy="${O[1]}" r="${(14 * s).toFixed(1)}" stroke-width="${s.toFixed(2)}"/><circle class="core" cx="${O[0]}" cy="${O[1]}" r="${(5 * s).toFixed(1)}"/><text x="${O[0]}" y="${(O[1] - 20 * s).toFixed(1)}" font-size="${(12 * s).toFixed(1)}" text-anchor="middle">${EX.origin}</text></g>
      <g>${labels.map(l => lbl(l, !l.show)).join('')}</g>`;
    $('#mapLegend').innerHTML = `<span><i></i>Destination</span><span><i class="good"></i>Meilleurs prix du mois</span><span>${plural(list.length, 'destination')} · ${placed.length} étiquetée${placed.length > 1 ? 's' : ''}</span>`;
    // Transition douce du cadrage
    const from = EX.vb || [0, 0, W.w, W.h];
    EX.vb = target;
    if (reduced) { svg.setAttribute('viewBox', target.join(' ')); return; }
    const t0 = performance.now();
    const step = () => {
      const k = Math.min(1, (performance.now() - t0) / 600), e = 1 - (1 - k) ** 3;
      svg.setAttribute('viewBox', from.map((v, i) => (v + (target[i] - v) * e).toFixed(1)).join(' '));
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }
  function exHighlight(code) {
    $$('#map .arc').forEach(a => a.classList.toggle('on', a.dataset.code === code));
    $$('#map .lbl').forEach(g => {
      const on = g.dataset.code === code;
      g.classList.toggle('on', on);
      if (g.hasAttribute('data-hover-only')) g.style.display = on ? '' : 'none';
      if (on) g.parentNode.appendChild(g);
    });
    $$('#exGrid .deal').forEach(b => b.classList.toggle('hl', b.dataset.go === code));
  }
  function exGo(code) {
    const d = EX.data.find(x => x.code === code);
    if (!d) return;
    Object.assign(S, { from: EX.origin, to: code, dep: d.date, ret: addDays(d.date, 7) });
    location.hash = '#/vols?' + toParams();
  }
  const mapCode = e => e.target.closest('[data-code]')?.dataset.code;
  $('#map').addEventListener('pointerover', e => { const c = mapCode(e); if (c) exHighlight(c); });
  $('#map').addEventListener('pointerleave', () => exHighlight(null));
  $('#map').addEventListener('click', e => { const c = mapCode(e); if (c) exGo(c); });
  $('#exGrid').addEventListener('mouseover', e => { const b = e.target.closest('.deal'); exHighlight(b ? b.dataset.go : null); });
  $('#exGrid').addEventListener('mouseleave', () => exHighlight(null));
  $('#exGrid').addEventListener('click', e => { const b = e.target.closest('.deal'); if (b) exGo(b.dataset.go); });
  $('#exMonths').addEventListener('click', e => { const b = e.target.closest('[data-month]'); if (b) { EX.month = b.dataset.month; renderExplorer(); } });
  $('#exVibes').addEventListener('click', e => { const b = e.target.closest('[data-vibe]'); if (b) { EX.vibe = b.dataset.vibe; $$('#exVibes button').forEach(x => x.setAttribute('aria-checked', String(x === b))); drawExplore(); } });
  let budT;
  $('#exBudget').addEventListener('input', e => { EX.budget = +e.target.value; $('#exBudgetVal').textContent = '≤ ' + money(EX.budget); clearTimeout(budT); budT = setTimeout(drawExplore, 120); });
  $('#exDirect').addEventListener('change', e => { EX.direct = e.target.checked; renderExplorer(); });
  $('#exSort').addEventListener('change', e => { EX.sort = e.target.value; drawExplore(); });
  $('#exOrigin').addEventListener('click', e => renderAC(e.currentTarget, 'ex'));
  let resizeT;
  addEventListener('resize', () => { clearTimeout(resizeT); resizeT = setTimeout(() => { if (!$('#view-explorer').hidden) drawMap(exList()); }, 200); });

  // ================= FONCTIONNALITÉS D'AIDE =================
  // Prix avec bagage en soute
  $('#withBag').checked = R.withBag;
  $('#withBag').addEventListener('change', e => {
    R.withBag = e.target.checked; store.set('withBag', R.withBag);
    runSearch(true);
    toast(R.withBag ? 'Les prix incluent maintenant un bagage en soute' : 'Prix sans bagage en soute');
  });

  // Grille des prix aller × retour (±3 jours)
  $('#matrixBtn').addEventListener('click', () => {
    const outs = [-3, -2, -1, 0, 1, 2, 3].map(k => addDays(S.dep, k)), rets = [-3, -2, -1, 0, 1, 2, 3].map(k => addDays(S.ret, k));
    const cell = (d, r) => {
      if (d < TODAY || r < d) return null;
      const a = minPrice(S.from, S.to, d), b = minPrice(S.to, S.from, r);
      return a === null || b === null ? null : a + b;
    };
    const vals = outs.flatMap(d => rets.map(r => cell(d, r))).filter(v => v !== null);
    const min = Math.min(...vals);
    $('#modalTitle').textContent = 'Grille des prix';
    $('#modalBody').innerHTML = `<p class="muted" style="margin-bottom:14px">Total aller-retour le plus bas par adulte selon vos dates. Touchez une case pour l'appliquer.</p>
      <div class="matrix-wrap"><table class="matrix"><thead><tr><th scope="col"><span class="sr">Aller / Retour</span></th>${rets.map(r => `<th scope="col">Retour<br><b>${fmtD(r, { weekday: 'short', day: 'numeric' })}</b></th>`).join('')}</tr></thead>
      <tbody>${outs.map(d => `<tr><th scope="row">Aller<br><b>${fmtD(d, { weekday: 'short', day: 'numeric' })}</b></th>${rets.map(r => {
        const v = cell(d, r);
        const cls = [v === min ? 'best' : '', d === S.dep && r === S.ret ? 'cur' : ''].join(' ');
        return v === null ? '<td class="none">—</td>' : `<td class="${cls}"><button type="button" data-mx="${d}|${r}" aria-label="Aller ${longD(d)}, retour ${longD(r)} : ${money(v)}">${money(v)}</button></td>`;
      }).join('')}</tr>`).join('')}</tbody></table></div>`;
    $('#modalBody').onclick = e => {
      const b = e.target.closest('[data-mx]');
      if (!b) return;
      [S.dep, S.ret] = b.dataset.mx.split('|');
      closeModal();
      location.hash = '#/vols?' + toParams();
    };
    $('#modal .modal-card').classList.add('wide');
    lastFocus = document.activeElement;
    $('#modal').hidden = false;
    $('#modal .modal-head [data-close]').focus();
  });

  // Fichier calendrier (.ics) pour les vols réservés
  function downloadIcs(t) {
    const stamp = (date, min, tz) => { // heure locale → UTC
      const d = parseISO(date); d.setUTCMinutes(d.getUTCMinutes() + min - tz * 60);
      return d.toISOString().replace(/[-:]/g, '').slice(0, 15) + 'Z';
    };
    const events = [t.out, t.ret].filter(Boolean).map((r, i) => `BEGIN:VEVENT
UID:envol-${r.key.replace(/[^\w]/g, '')}-${i}@envol.demo
DTSTAMP:${new Date().toISOString().replace(/[-:]/g, '').slice(0, 15)}Z
DTSTART:${stamp(r.date, r.dep, AP[r.from].tz)}
DTEND:${stamp(r.date, r.arr, AP[r.to].tz)}
SUMMARY:Vol ${r.fns.join(' + ')} ${r.from} → ${r.to}
LOCATION:${AP[r.from].name}, ${AP[r.from].city}
DESCRIPTION:${cityOf(r.from)} → ${cityOf(r.to)} · ${fmtDur(r.dur)} · ${r.stops ? plural(r.stops, 'escale') : 'direct'}. Vérifiez les horaires auprès de la compagnie.
BEGIN:VALARM
TRIGGER:-PT24H
ACTION:DISPLAY
DESCRIPTION:Enregistrement en ligne
END:VALARM
END:VEVENT`).join('\n');
    const ics = `BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Envol//FR\n${events}\nEND:VCALENDAR`.replace(/\n/g, '\r\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([ics], { type: 'text/calendar' }));
    a.download = `envol-${t.out.from}-${t.out.to}.ics`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    toast('Fichier calendrier téléchargé (rappel 24 h avant)');
  }

  // Aide : raccourcis et lexique
  function openHelp() {
    $('#modalTitle').textContent = 'Aide';
    $('#modalBody').innerHTML = `<div class="help">
      <h3>Raccourcis clavier</h3>
      <dl class="keys">
        <div><dt><kbd>/</kbd></dt><dd>Nouvelle recherche</dd></div>
        <div><dt><kbd>F</kbd></dt><dd>Ouvrir les filtres</dd></div>
        <div><dt><kbd>←</kbd> <kbd>→</kbd></dt><dd>Jour précédent / suivant</dd></div>
        <div><dt><kbd>Échap</kbd></dt><dd>Fermer une fenêtre</dd></div>
        <div><dt><kbd>?</kbd></dt><dd>Afficher cette aide</dd></div>
      </dl>
      <h3>Lexique</h3>
      <dl class="terms">
        <div><dt>Recommandé</dt><dd>Le meilleur équilibre entre le prix, la durée totale et le nombre d'escales.</dd></div>
        <div><dt>+1</dt><dd>Arrivée le lendemain, en heure locale de la destination.</dd></div>
        <div><dt>Billets séparés</dt><dd>Deux réservations indépendantes. Souvent moins cher, mais la correspondance n'est pas protégée : prévoyez de la marge.</dd></div>
        <div><dt>Prix avec bagage</dt><dd>Ajoute le coût d'un bagage en soute aux tarifs qui ne l'incluent pas, pour comparer à armes égales.</dd></div>
        <div><dt>Prix bas / habituel / élevé</dt><dd>Comparaison avec les dates voisines (±15 jours), en tenant compte de la saison et des vacances scolaires.</dd></div>
        <div><dt>CO₂</dt><dd>Émissions estimées par passager en classe économique, comparées à la moyenne des vols du trajet.</dd></div>
      </dl>
      <div class="bnav" style="margin-top:20px"><button type="button" class="btn-line" data-tour-restart>Revoir la visite guidée</button><button type="button" class="btn-dark" data-close-help>Compris</button></div></div>`;
    $('#modalBody').onclick = e => {
      if (e.target.closest('[data-close-help]')) closeModal();
      if (e.target.closest('[data-tour-restart]')) { closeModal(); if ($('#view-results').hidden) toast('La visite démarre à la prochaine recherche'); else startTour(); store.set('tourDone', false); }
    };
    $('#modal .modal-card').classList.remove('wide');
    lastFocus = document.activeElement;
    $('#modal').hidden = false;
    $('#modal .modal-head [data-close]').focus();
  }
  $('#helpBtn').addEventListener('click', openHelp);

  // Visite guidée (première recherche) : 4 étapes, une seule fois
  const TOUR = [
    ['#journey', 'Où vous en êtes', 'Les 6 étapes jusqu\'à la réservation : ce qui est fait, ce qui est en cours, ce qui reste. Le total se met à jour à droite.'],
    ['#dateStrip', 'Les jours voisins', 'Comparez les prix d\'un coup d\'œil. Le vert indique le jour le moins cher. Raccourci : ← →'],
    ['#sorts', 'Trois façons de trier', 'Recommandé équilibre prix, durée et escales. Touchez une case pour changer le tri.'],
    ['#openFilters', 'Filtres', 'Escales, horaires, bagages, compagnies… Tout est rangé ici. Raccourci : F'],
  ];
  let tourStep = 0;
  function startTour() { tourStep = 0; showTourStep(); }
  function showTourStep() {
    const [sel, title, text] = TOUR[tourStep];
    const target = $(sel), tour = $('#tour');
    if (!target) { endTour(); return; }
    target.scrollIntoView({ block: 'center', behavior: reduced ? 'auto' : 'smooth' });
    setTimeout(() => {
      const r = target.getBoundingClientRect();
      $('#tourSpot').style.cssText = `left:${r.left - 6}px;top:${r.top - 6}px;width:${r.width + 12}px;height:${r.height + 12}px`;
      $('#tourCard').innerHTML = `<p class="tour-step">${tourStep + 1} sur ${TOUR.length}</p><h3>${title}</h3><p>${text}</p>
        <div class="bnav"><button type="button" class="btn-line" data-tour-skip>Passer</button><button type="button" class="btn-dark" data-tour-next>${tourStep === TOUR.length - 1 ? 'Terminer' : 'Suivant'}</button></div>`;
      const card = $('#tourCard'), below = r.bottom + 220 < innerHeight;
      card.style.left = clamp(r.left, 16, innerWidth - 336) + 'px';
      card.style.top = (below ? r.bottom + 16 : Math.max(16, r.top - card.offsetHeight - 16)) + 'px';
      tour.hidden = false;
      $('[data-tour-next]', card).focus();
    }, reduced ? 0 : 320);
  }
  function endTour() { $('#tour').hidden = true; store.set('tourDone', true); }
  $('#tour').addEventListener('click', e => {
    if (e.target.closest('[data-tour-skip]')) endTour();
    else if (e.target.closest('[data-tour-next]')) { tourStep++; if (tourStep >= TOUR.length) endTour(); else showTourStep(); }
  });

  // Recherches récentes
  function renderRecent() {
    const el = $('#recent');
    el.innerHTML = recent.length ? '<span class="recent-l">Récentes</span>' + recent.map((r, i) => `<button type="button" data-recent="${i}">${esc(cityOf(r.from))} → ${esc(cityOf(r.to))}<small>${fmtD(r.dep, { day: 'numeric', month: 'short' })}</small></button>`).join('') : '';
  }
  $('#recent').addEventListener('click', e => {
    const b = e.target.closest('[data-recent]');
    if (!b) return;
    Object.assign(S, recent[+b.dataset.recent]);
    if (S.dep < TODAY) { S.dep = addDays(TODAY, 14); S.ret = addDays(S.dep, 7); }
    syncForm();
    $('#searchForm').requestSubmit();
  });

  // Bannière app (mobile uniquement, masquable)
  if (!store.get('appBannerClosed', false)) $('#appBanner').hidden = false;
  $('#appBanner [data-close]').addEventListener('click', () => { $('#appBanner').hidden = true; store.set('appBannerClosed', true); });

  // ================= MENUS DÉROULANTS (verre dépoli) =================
  const nextWeekday = (from, wd) => { let d = addDays(from, 1); while (((parseISO(d).getUTCDay() + 6) % 7) !== wd) d = addDays(d, 1); return d; };
  const megaLink = (attrs, title, sub = '', ic = '') => `<button type="button" class="mg-link" ${attrs}>${ic ? `<span class="mg-ic">${icon(ic)}</span>` : ''}<span><b>${title}</b>${sub ? `<small>${sub}</small>` : ''}</span></button>`;
  const MEGA = {
    home() {
      const fri = nextWeekday(TODAY, 4), sun = addDays(fri, 2);
      return `<div class="mg-col"><p class="mg-h">Rechercher</p>
          ${megaLink('data-mg="search-rt"', 'Aller-retour', 'Le plus demandé', 'swap')}
          ${megaLink('data-mg="search-ow"', 'Aller simple', 'Un seul trajet', 'arrow')}
          ${megaLink('data-mg="weekend"', 'Week-end prochain', `${fmtD(fri, { weekday: 'short', day: 'numeric' })} → ${fmtD(sun, { weekday: 'short', day: 'numeric', month: 'short' })}`, 'cal')}
          ${megaLink('data-mg="direct"', 'Vols directs uniquement', 'Sans escale', 'plane')}</div>
        <div class="mg-col"><p class="mg-h">Reprendre</p>${recent.length ? recent.slice(0, 4).map((r, i) => megaLink(`data-mg="recent" data-i="${i}"`, `${esc(cityOf(r.from))} → ${esc(cityOf(r.to))}`, fmtD(r.dep, { day: 'numeric', month: 'short' }) + (r.trip === 'rt' && r.ret ? ' → ' + fmtD(r.ret, { day: 'numeric', month: 'short' }) : ''), 'clock')).join('') : '<p class="mg-empty">Vos recherches récentes apparaîtront ici.</p>'}</div>
        <a class="mg-card" href="#app-ios" data-mg="close"><span class="mg-card-ph"><span class="brand-mark"></span></span><b>Envol pour iPhone</b><small>Alertes de prix en notification, carte, hors ligne.</small><span class="mg-more">Découvrir ${icon('chev')}</span></a>`;
    },
    explorer() {
      const months = [0, 1, 2, 3].map(i => addMonths(addDays(TODAY, 1).slice(0, 7), i));
      return `<div class="mg-col"><p class="mg-h">Par envie</p>
          ${[['plage', 'Mer & plages', 'pin'], ['ville', 'Villes', 'search'], ['culture', 'Culture', 'sparkle'], ['nature', 'Nature', 'leaf']].map(([k, l, ic]) => megaLink(`data-mg="vibe" data-v="${k}"`, l, '', ic)).join('')}</div>
        <div class="mg-col"><p class="mg-h">Par mois</p>${months.map(m => megaLink(`data-mg="month" data-v="${m}"`, fmtD(m + '-01', { month: 'long', year: 'numeric' }).replace(/^./, x => x.toUpperCase()))).join('')}</div>
        <div class="mg-col"><p class="mg-h">Par budget</p>${[100, 250, 500].map(b => megaLink(`data-mg="budget" data-v="${b}"`, `Moins de ${money(b)}`, 'aller, par adulte')).join('')}</div>
        <a class="mg-card map" href="#/explorer" data-mg="close"><span class="mg-card-map" aria-hidden="true"></span><b>La carte des destinations</b><small>Tout ce qui décolle de ${esc(cityOf(S.from || 'PAR'))}, prix sur la carte.</small><span class="mg-more">Ouvrir ${icon('chev')}</span></a>`;
    },
    favoris() {
      return `<div class="mg-col wide"><p class="mg-h">Vos vols enregistrés</p>${favs.length ? favs.slice(0, 4).map((fv, i) => {
        const r = fv.date >= TODAY ? resultFromKey(fv.key) : null;
        return megaLink(`data-mg="fav" data-i="${i}"`, `${esc(AP[fv.from].city)} → ${esc(AP[fv.to].city)}`, `${fmtD(fv.date, { day: 'numeric', month: 'short' })}${r ? ' · ' + hm(r.dep) + ' · ' + money(r.price) : ' · indisponible'}`, 'heart');
      }).join('') : '<p class="mg-empty">Touchez le cœur d\'un vol pour le retrouver ici et suivre son prix.</p>'}
        <a class="mg-all" href="#/favoris" data-mg="close">Tous les favoris ${icon('chev')}</a></div>`;
    },
    alertes() {
      return `<div class="mg-col wide"><p class="mg-h">Trajets surveillés</p>${alerts.length ? alerts.slice(0, 4).map((a, i) => {
        const cur = a.dep >= TODAY ? minPrice(a.from, a.to, a.dep, a.cabin) : null, d = cur !== null && a.price ? cur - a.price : 0;
        return megaLink(`data-mg="alert" data-i="${i}"`, `${esc(cityOf(a.from))} → ${esc(cityOf(a.to))}`, `${fmtD(a.dep, { day: 'numeric', month: 'short' })} · ${cur !== null ? money(cur) : '—'}${d ? (d < 0 ? ' · −' + money(-d) : ' · +' + money(d)) : ''}`, 'bell');
      }).join('') : '<p class="mg-empty">Lancez une recherche puis touchez la cloche : nous suivons le prix pour vous.</p>'}
        <a class="mg-all" href="#/alertes" data-mg="close">Toutes les alertes ${icon('chev')}</a></div>`;
    },
  };
  const mega = $('#mega'), megaIn = $('#megaIn');
  let megaTimer, megaFor = null;
  const canHover = matchMedia('(hover: hover) and (pointer: fine)').matches;
  function openMega(link) {
    const key = link.dataset.nav;
    if (!MEGA[key]) { closeMega(); return; }
    clearTimeout(megaTimer);
    if (megaFor === link && !mega.hidden) return;
    $$('.nav-links a').forEach(a => a.setAttribute('aria-expanded', String(a === link)));
    megaIn.innerHTML = MEGA[key]();
    megaIn.dataset.key = key;
    const wasOpen = !mega.hidden;
    mega.hidden = false;
    const r = link.getBoundingClientRect(), w = mega.offsetWidth;
    const left = clamp(r.left + r.width / 2 - w / 2, 16, innerWidth - w - 16);
    mega.style.setProperty('--x', left + 'px');
    mega.style.setProperty('--caret', (r.left + r.width / 2 - left) + 'px');
    mega.classList.toggle('moving', wasOpen);
    requestAnimationFrame(() => mega.classList.add('open'));
    megaFor = link;
  }
  function closeMega(now = false) {
    clearTimeout(megaTimer);
    const done = () => { mega.classList.remove('open'); setTimeout(() => { if (!mega.classList.contains('open')) mega.hidden = true; }, 220); megaFor = null; $$('.nav-links a').forEach(a => a.setAttribute('aria-expanded', 'false')); };
    if (now) done(); else megaTimer = setTimeout(done, 160);
  }
  $$('.nav-links a[data-nav]').forEach(a => {
    if (canHover) {
      a.addEventListener('mouseenter', () => { clearTimeout(megaTimer); megaTimer = setTimeout(() => openMega(a), mega.hidden ? 90 : 0); });
      a.addEventListener('mouseleave', () => closeMega());
    }
    a.addEventListener('keydown', e => { if (e.key === 'ArrowDown') { e.preventDefault(); openMega(a); $('#megaIn .mg-link, #megaIn a')?.focus(); } });
  });
  mega.addEventListener('mouseenter', () => clearTimeout(megaTimer));
  mega.addEventListener('mouseleave', () => closeMega());
  mega.addEventListener('keydown', e => { if (e.key === 'Escape') { closeMega(true); megaFor?.focus(); } });
  mega.addEventListener('click', e => {
    const b = e.target.closest('[data-mg]');
    if (!b) return;
    const k = b.dataset.mg, v = b.dataset.v, i = +b.dataset.i;
    closeMega(true);
    const toSearch = () => { if (location.hash !== '#/' && location.hash !== '') location.hash = '#/'; setTimeout(() => { $('#searchForm').scrollIntoView({ block: 'center', behavior: 'smooth' }); $('#toInput').focus(); }, 80); };
    if (k === 'search-rt' || k === 'search-ow') { S.trip = k === 'search-rt' ? 'rt' : 'ow'; if (S.trip === 'rt' && (!S.ret || S.ret <= S.dep)) S.ret = addDays(S.dep, 7); syncForm(); toSearch(); }
    else if (k === 'weekend') { S.trip = 'rt'; S.dep = nextWeekday(TODAY, 4); S.ret = addDays(S.dep, 2); syncForm(); toSearch(); toast('Dates du week-end prochain appliquées'); }
    else if (k === 'direct') { S.direct = true; syncForm(); toSearch(); }
    else if (k === 'recent') { Object.assign(S, recent[i]); if (S.dep < TODAY) { S.dep = addDays(TODAY, 14); S.ret = addDays(S.dep, 7); } syncForm(); location.hash = '#/vols?' + toParams(); }
    else if (k === 'vibe' || k === 'month' || k === 'budget') {
      if (k === 'vibe') EX.vibe = v; if (k === 'month') EX.month = v; if (k === 'budget') EX.budget = +v;
      if (location.hash === '#/explorer') renderExplorer(); else location.hash = '#/explorer';
    }
    else if (k === 'fav') { const r = resultFromKey(favs[i].key); if (r) { S.trip = 'ow'; R.step = 1; openDetail(r); } else location.hash = '#/favoris'; }
    else if (k === 'alert') { const a = alerts[i]; Object.assign(S, { from: a.from, to: a.to, dep: a.dep, ret: a.ret || addDays(a.dep, 7), trip: a.ret ? 'rt' : 'ow', cabin: a.cabin }); location.hash = '#/vols?' + toParams(); }
  });
  addEventListener('scroll', () => { if (!mega.hidden) closeMega(true); }, { passive: true });

  // ================= ROUTEUR =================
  const VIEWS = ['home', 'results', 'explorer', 'favoris', 'alertes'];
  function show(view) {
    VIEWS.forEach(v => { $('#view-' + v).hidden = v !== view; });
    document.body.dataset.view = view;
    $$('[data-nav]').forEach(a => a.classList.toggle('active', a.dataset.nav === view || (view === 'results' && a.dataset.nav === 'home')));
    closePops(); hideTip();
    if (!$('#drawer').hidden) closeDrawer();
    $('#modal').hidden = true;
    renderCompareBar();
  }
  function route() {
    const [path, q] = (location.hash.slice(1) || '/').split('?');
    if (path === '/vols' && q) {
      fromParams(q);
      syncForm();
      show('results');
      mountForm($('#slotResults'));
      $('#slotResults').hidden = true;
      $('#editBtn').setAttribute('aria-expanded', 'false');
      if (q !== R.lastKey) { R.step = 1; R.out = null; R.phase = 'select'; R.trip = null; R.trkT = null; R.compare = []; R.sort = 'best'; R.lastKey = q; runSearch(false); }
      if (!store.get('tourDone', false)) setTimeout(startTour, 700);
      scrollTo(0, 0);
    } else if (path === '/explorer') { show('explorer'); renderExplorer(); scrollTo(0, 0); }
    else if (path === '/favoris') { show('favoris'); renderFavs(); scrollTo(0, 0); }
    else if (path === '/alertes') { show('alertes'); renderAlerts(); scrollTo(0, 0); }
    else {
      show('home'); mountForm($('#slotHome')); syncForm(); renderRecent();
      if (path === 'app-ios') setTimeout(() => $('#app-ios').scrollIntoView({ behavior: reduced ? 'auto' : 'smooth' }), 60);
    }
  }
  addEventListener('hashchange', route);

  // ---------- Global ----------
  addEventListener('keydown', e => {
    const typing = e.target.closest('input:not([type=checkbox]):not([type=radio]), select, textarea, [contenteditable]');
    if (!typing && !e.metaKey && !e.ctrlKey && !e.altKey && $('#modal').hidden && $('#drawer').hidden && !$('#filters').classList.contains('open')) {
      const inResults = !$('#view-results').hidden;
      if (e.key === '/') { e.preventDefault(); if (inResults) $('#editBtn').click(); setTimeout(() => $('#toInput').focus(), 50); return; }
      if (e.key === '?') { e.preventDefault(); openHelp(); return; }
      if (inResults && (e.key === 'f' || e.key === 'F')) { e.preventDefault(); $('#openFilters').click(); return; }
      if (inResults && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
        const days = $$('.ds-day'), i = days.findIndex(d => d.getAttribute('aria-selected') === 'true');
        const next = days[i + (e.key === 'ArrowLeft' ? -1 : 1)];
        if (next && !next.disabled) { e.preventDefault(); next.click(); }
        return;
      }
    }
    if (e.key !== 'Escape') return;
    if ($('#tour') && !$('#tour').hidden) { endTour(); return; }
    if (!$('#modal').hidden) closeModal();
    else if (!$('#drawer').hidden) closeDrawer();
    else if ($('#filters').classList.contains('open')) closeFilters();
    else closePops();
  });
  let scrollRaf;
  addEventListener('scroll', () => {
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => { scrollRaf = null; $('#nav').classList.toggle('scrolled', scrollY > 4); if (!$('#view-home').hidden) drift(); });
  }, { passive: true });
  $('#currency').value = currency;
  $('#currency').addEventListener('change', e => {
    currency = e.target.value; store.set('cur', currency);
    const v = VIEWS.find(x => !$('#view-' + x).hidden);
    renderHome();
    if (v === 'results') { renderHead(); renderDateStrip(); renderFilters(); applyFilters(); }
    else if (v === 'explorer') drawExplore();
    else if (v === 'favoris') renderFavs();
    else if (v === 'alertes') renderAlerts();
    toast(`Prix affichés en ${currency} (taux indicatif)`);
  });

  function boot(csv) {
    parseDB(csv);
    $('#heroImg').src = photo('HERO', 520);
    EX.origin = S.from;
    syncForm();
    renderHome();
    updateCounts();
    route();
  }
  if (window.FLIGHTS_CSV) boot(window.FLIGHTS_CSV);
  else fetch('data/flights.csv').then(r => r.text()).then(boot).catch(() => { document.body.insertAdjacentHTML('afterbegin', '<p style="padding:16px">Base de vols introuvable. Lancez <code>node scripts/generate-db.js</code>.</p>'); });
})();
