/* Recherche 4 photos Unsplash candidates (hors « Unsplash+ ») par destination.
   Usage : node scripts/fetch-photos.js   →  data/photos.candidates.json
   La sélection finale (data/photos.js) a été faite à la main à partir de ces candidates.
   En production, passez par l'API officielle Unsplash (clé d'accès) et respectez ses règles d'attribution. */
const fs = require('fs');
const path = require('path');

const Q = {
  CDG: 'paris eiffel tower', ORY: 'paris rooftops', NCE: 'nice promenade des anglais', LYS: 'lyon city', MRS: 'marseille old port',
  TLS: 'toulouse city', BOD: 'bordeaux city', NTE: 'nantes city', LHR: 'london city', LGW: 'london thames',
  AMS: 'amsterdam canal', FRA: 'frankfurt skyline', MUC: 'munich city', BER: 'berlin city', MAD: 'madrid city',
  BCN: 'barcelona city', PMI: 'mallorca beach', LIS: 'lisbon city', OPO: 'porto city', FCO: 'rome city',
  MXP: 'milan city', ZRH: 'zurich city', GVA: 'geneva lake', BRU: 'brussels city', VIE: 'vienna city',
  CPH: 'copenhagen nyhavn', DUB: 'dublin city', PRG: 'prague city', ATH: 'athens acropolis', IST: 'istanbul city',
  CMN: 'casablanca', RAK: 'marrakech', TUN: 'tunisia sidi bou said', ALG: 'algiers city', CAI: 'cairo pyramids',
  DSS: 'dakar senegal', ABJ: 'abidjan', JNB: 'johannesburg skyline', RUN: 'reunion island', DXB: 'dubai skyline',
  DOH: 'doha skyline', MLE: 'maldives', DEL: 'new delhi india gate', BKK: 'bangkok city', SIN: 'singapore marina bay',
  DPS: 'bali rice terraces', HKG: 'hong kong skyline', ICN: 'seoul city', HND: 'tokyo city', SYD: 'sydney opera house',
  JFK: 'new york city', MIA: 'miami beach', LAX: 'los angeles', SFO: 'san francisco golden gate', YUL: 'montreal city',
  MEX: 'mexico city', CUN: 'cancun beach', PTP: 'guadeloupe beach', FDF: 'martinique', GRU: 'sao paulo city',
  EZE: 'buenos aires', HERO: 'airplane window wing clouds', HERO2: 'above clouds sky',
};

const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const out = {};
  for (const [code, q] of Object.entries(Q)) {
    try {
      const res = await fetch(`https://unsplash.com/napi/search/photos?query=${encodeURIComponent(q)}&per_page=12&orientation=landscape`);
      const json = await res.json();
      const pick = json.results.filter(p => !p.premium && !p.plus && p.urls.raw.startsWith('https://images.unsplash.com/'))
        .slice(0, 4).map(p => ({ id: p.id, url: p.urls.raw.split('?')[0], by: p.user.name, color: p.color }));
      out[code] = pick;
      console.log(code, pick.length);
    } catch (e) { console.log(code, 'ERR', e.message); }
    await sleep(250);
  }
  fs.writeFileSync(path.join(__dirname, '..', 'data', 'photos.candidates.json'), JSON.stringify(out, null, 1));
})();
