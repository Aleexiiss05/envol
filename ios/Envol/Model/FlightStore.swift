import Foundation

/// Moteur de recherche et de prix : portage fidèle de js/app.js (mêmes données, mêmes résultats que le site).
final class FlightStore {
    static let shared = FlightStore()

    let airports: [Airport]
    let airlines: [String: Airline]
    let airportByCode: [String: Airport]
    let photos: [String: Photo]
    private let seasons: [String: [Double]]
    let seasonLabels: [String: String]
    private let holidays: [Holiday]
    private(set) var flights: [Flight] = []
    private var byId: [Int: Flight] = [:]
    private var byRoute: [String: [Flight]] = [:]
    private var byFrom: [String: [Flight]] = [:]
    private var minCache: [String: Int?] = [:]
    private let lock = NSLock()

    /// Villes à plusieurs aéroports
    let groups: [String: (city: String, country: String, members: [String])] = [
        "PAR": ("Paris", "France", ["CDG", "ORY"]),
        "LON": ("Londres", "Royaume-Uni", ["LHR", "LGW"]),
    ]
    private let inFrance: Set<String>
    private let inUS: Set<String> = ["JFK", "MIA", "LAX", "SFO"]
    private let firstClass: Set<String> = ["AF", "EK", "QR", "SQ", "LH", "BA", "JL", "NH", "CX", "LX", "AA"]

    private init() {
        let ref = Self.load(Reference.self, "reference")
        airports = ref?.airports ?? []
        airlines = Dictionary(uniqueKeysWithValues: (ref?.airlines ?? []).map { ($0.code, $0) })
        airportByCode = Dictionary(uniqueKeysWithValues: airports.map { ($0.code, $0) })
        seasons = ref?.seasons ?? [:]
        seasonLabels = ref?.seasonLabels ?? [:]
        holidays = ref?.holidays ?? []
        photos = Self.load([String: Photo].self, "photos") ?? [:]
        inFrance = Set(airports.filter { $0.country == "France" }.map(\.code))
        parseCSV()
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Lecture de la base texte

    private func distance(_ a: String, _ b: String) -> Double {
        guard let A = airportByCode[a], let B = airportByCode[b] else { return 0 }
        let r = Double.pi / 180
        let h = pow(sin((B.lat - A.lat) * r / 2), 2) + cos(A.lat * r) * cos(B.lat * r) * pow(sin((B.lon - A.lon) * r / 2), 2)
        return 2 * 6371 * asin(sqrt(h))
    }
    func km(_ a: String, _ b: String) -> Double { distance(a, b) }

    private func parseCSV() {
        guard let url = Bundle.main.url(forResource: "flights", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var rows = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !rows.isEmpty else { return }
        rows.removeFirst()
        flights.reserveCapacity(rows.count)
        for row in rows {
            let p = row.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 20 else { continue }
            let fns = p[2].split(separator: "+").map(String.init)
            let via = p[5].isEmpty ? [] : p[5].split(separator: "-").map(String.init)
            let acs = p[10].split(separator: "|").map(String.init)
            let ld = p.count > 20 && !p[20].isEmpty ? p[20].split(separator: "-").compactMap { Int($0) } : []
            let points = [p[3]] + via + [p[4]]
            var legs: [Leg] = []
            for i in 0..<(points.count - 1) {
                let km = distance(points[i], points[i + 1])
                let fn = i < fns.count ? fns[i] : fns[0]
                legs.append(Leg(from: points[i], to: points[i + 1], km: km,
                                minutes: i < ld.count ? ld[i] : Int((km / 800 * 60 + 35) / 5) * 5,
                                flightNumber: fn, airline: String(fn.prefix(2)), aircraft: i < acs.count ? acs[i] : (acs.first ?? "")))
            }
            let f = Flight(id: Int(p[0]) ?? 0, airline: p[1], flightNumbers: fns, from: p[3], to: p[4], via: via,
                           dep: Int(p[6]) ?? 0, duration: Int(p[7]) ?? 0,
                           layovers: p[8].isEmpty ? [] : p[8].split(separator: "-").compactMap { Int($0) },
                           days: p[9].map { $0 == "1" }, base: Double(p[11]) ?? 0,
                           cabinBag: p[12] == "1", holdBag: p[13] == "1", meal: p[14] == "1", wifi: p[15] == "1", power: p[16] == "1",
                           refund: Int(p[17]) ?? 0, co2: Int(p[18]) ?? 0, ontime: Int(p[19]) ?? 0, legs: legs)
            flights.append(f)
            byId[f.id] = f
            byRoute[f.from + "-" + f.to, default: []].append(f)
            byFrom[f.from, default: []].append(f)
        }
    }

    // MARK: Lieux

    func expand(_ code: String) -> [String] { groups[code]?.members ?? [code] }
    func city(_ code: String) -> String { groups[code]?.city ?? airportByCode[code]?.city ?? code }
    func country(_ code: String) -> String { groups[code]?.country ?? airportByCode[code]?.country ?? "" }
    func cityCode(_ code: String) -> String { groups.first { $0.value.members.contains(code) }?.key ?? code }
    func subtitle(_ code: String) -> String {
        if let g = groups[code] { return "Tous les aéroports · " + g.members.joined(separator: ", ") }
        guard let a = airportByCode[code] else { return "" }
        return "\(a.name) · \(a.country)"
    }
    func photoURL(_ code: String, width: Int = 800) -> URL? {
        guard let p = photos[code] ?? photos[expand(code)[0]] else { return nil }
        return URL(string: "\(p.u)?w=\(width)&q=72&auto=format&fit=crop")
    }
    func logoURL(_ airline: String) -> URL? { URL(string: "https://pics.avs.io/al_square/64/64/\(airline).png") }
    func tz(_ code: String) -> Double { airportByCode[code]?.tz ?? 0 }

    /// Recherche d'aéroports : code exact, début de ville, puis correspondances partielles
    func searchPlaces(_ query: String) -> [String] {
        let n = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "fr_FR")).trimmingCharacters(in: .whitespaces)
        func norm(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "fr_FR")) }
        if n.isEmpty { return ["PAR", "LON"] + airports.filter { $0.pop >= 9 && !["CDG", "ORY", "LHR", "LGW"].contains($0.code) }.map(\.code) }
        var scored: [(Double, String)] = []
        for (code, g) in groups {
            let c = norm(g.city)
            if code.lowercased() == n || c.hasPrefix(n) { scored.append((0.5, code)) }
        }
        for a in airports {
            let c = norm(a.city), code = a.code.lowercased()
            let s: Double = code == n ? 0 : c.hasPrefix(n) ? 1 : code.hasPrefix(n) ? 2 : (c.contains(n) || norm(a.name + " " + a.country).contains(n)) ? 3 : 9
            if s < 9 { scored.append((s - Double(a.pop) / 100, a.code)) }
        }
        var seen = Set<String>()
        return scored.sorted { $0.0 < $1.0 }.map { $0.1 }.filter { seen.insert($0).inserted }.prefix(12).map { $0 }
    }

    // MARK: Prix (identique à priceFor du site)

    private func routeProfile(_ from: String, _ to: String) -> String {
        let a = airportByCode[from], b = airportByCode[to]
        return (inFrance.contains(to) && !inFrance.contains(from)) ? (a?.season ?? "city") : (b?.season ?? "city")
    }
    private func monthFactor(_ profile: String, _ date: String) -> Double {
        guard let s = seasons[profile], s.count == 12 else { return 1 }
        let m = Day.month(date), dim = Double(Day.daysInMonth(date))
        let pos = (Double(Day.dayOfMonth(date)) - 0.5) / dim
        let prev = s[(m + 11) % 12], cur = s[m], next = s[(m + 1) % 12]
        return pos < 0.5 ? prev + (cur - prev) * (pos + 0.5) : cur + (next - cur) * (pos - 0.5)
    }
    func holidaysFor(_ from: String, _ to: String, _ date: String) -> [Holiday] {
        holidays.filter { h in
            date >= h.from && date <= h.to &&
            ((h.fr == true && (inFrance.contains(from) || inFrance.contains(to))) || (h.us == true && (inUS.contains(from) || inUS.contains(to))))
        }
    }
    private func bookingFactor(_ ahead: Int, long: Bool) -> Double {
        if long {
            return ahead < 7 ? 1.55 : ahead < 14 ? 1.35 : ahead < 30 ? 1.15 : ahead < 60 ? 1.0 : ahead < 120 ? 0.92 : ahead < 240 ? 0.9 : 0.95
        }
        return ahead < 3 ? 1.7 : ahead < 7 ? 1.4 : ahead < 14 ? 1.18 : ahead < 21 ? 1.06 : ahead < 45 ? 0.95 : ahead < 90 ? 0.92 : ahead < 180 ? 0.96 : 1
    }
    private let dow: [Double] = [0.98, 0.92, 0.9, 1.0, 1.12, 0.97, 1.1]
    private func todFactor(_ m: Int) -> Double { m < 420 ? 0.9 : m < 600 ? 1.02 : m < 960 ? 1.0 : m < 1200 ? 1.06 : 0.93 }

    func price(_ f: Flight, _ date: String, cabin: Cabin = .eco, asOf: String = Day.today) -> Int? {
        let ahead = Day.diff(asOf, date)
        let wd = Day.weekday(date)
        if ahead < 0 || !f.days[wd] { return nil }
        let low = airlines[f.airline]?.lowcost ?? false
        var mult = 1.0
        switch cabin {
        case .eco: break
        case .prem: if !f.isLong || low { return nil }; mult = 1.75
        case .bus: if low && !f.isLong { return nil }; mult = f.isLong ? 3.6 : 2.3
        case .first: if !f.isLong || !firstClass.contains(f.airline) { return nil }; mult = 6.8
        }
        let season = monthFactor(routeProfile(f.from, f.to), date) * holidaysFor(f.from, f.to, date).reduce(1) { $0 * $1.k }
        let demand = 0.9 + hash01("\(f.id)|\(date)|\(asOf.dropFirst(5))") * 0.22
        var p = f.base * season * bookingFactor(ahead, long: f.isLong) * dow[wd] * todFactor(f.dep) * demand * mult
        p = max(p, f.base * 0.6 * mult * demand)
        return low && p >= 20 ? Int((p / 10).rounded(.down)) * 10 + 9 : Int(p.rounded())
    }

    /// Explication lisible de la période (haute saison, vacances…)
    func seasonNote(_ from: String, _ to: String, _ date: String) -> String {
        let a = expand(from)[0], b = expand(to)[0]
        let profile = routeProfile(a, b)
        let f = monthFactor(profile, date)
        var parts: [String] = []
        let label = seasonLabels[profile] ?? ""
        if f >= 1.15 { parts.append("haute saison (\(label))") } else if f <= 0.9 { parts.append("basse saison (\(label))") }
        parts += holidaysFor(a, b, date).map { $0.label.lowercased() }
        return parts.joined(separator: " · ")
    }

    // MARK: Construction d'un résultat

    private func segments(_ flights: [Flight], _ offsets: [Int]) -> [Segment] {
        var out: [Segment] = []
        for (i, f) in flights.enumerated() {
            var t = offsets[i] * 1440 + f.dep - Int(tz(f.from) * 60)
            for (j, leg) in f.legs.enumerated() {
                if j > 0 {
                    let lay = j - 1 < f.layovers.count ? f.layovers[j - 1] : 60
                    out.append(Segment(kind: .layover(at: leg.from, minutes: lay, selfTransfer: false), startUTC: t, endUTC: t + lay))
                    t += lay
                }
                out.append(Segment(kind: .leg(leg), startUTC: t, endUTC: t + leg.minutes))
                t += leg.minutes
            }
            if i < flights.count - 1 {
                let n = flights[i + 1]
                let nd = offsets[i + 1] * 1440 + n.dep - Int(tz(n.from) * 60)
                out.append(Segment(kind: .layover(at: n.from, minutes: nd - t, selfTransfer: true), startUTC: t, endUTC: nd))
            }
        }
        return out
    }

    func makeResult(_ flights: [Flight], date: String, offsets: [Int], prices: [Int], cabin: Cabin) -> FlightResult {
        let segs = segments(flights, offsets)
        var lays: [(at: String, minutes: Int, selfTransfer: Bool)] = []
        var legs: [Leg] = []
        for s in segs {
            switch s.kind {
            case .leg(let l): legs.append(l)
            case .layover(let at, let m, let st): lays.append((at: at, minutes: m, selfTransfer: st))
            }
        }
        let firstStart = segs.first?.startUTC ?? 0, lastEnd = segs.last?.endUTC ?? 0
        let from = legs.first?.from ?? flights[0].from, to = legs.last?.to ?? flights[0].to
        let key = flights.map { String($0.id) }.joined(separator: "+") + "@" + date
            + (offsets.contains { $0 != 0 } ? "~" + offsets.map(String.init).joined() : "") + ":" + cabin.rawValue
        let total = prices.reduce(0, +)
        var carriers: [String] = []
        for l in legs where !carriers.contains(l.airline) { carriers.append(l.airline) }
        return FlightResult(key: key, flights: flights, date: date, offsets: offsets, cabin: cabin, segments: segs, from: from, to: to,
                            fare: total, price: total,
                            dep: firstStart + Int(tz(from) * 60), arr: lastEnd + Int(tz(to) * 60), duration: lastEnd - firstStart,
                            layovers: lays, carriers: carriers, seats: 1 + Int(hash01(key) * 9))
    }

    func result(forKey key: String) -> FlightResult? {
        // format : 12+34@2026-10-21~01:eco
        let parts = key.split(separator: ":")
        guard parts.count == 2, let cabin = Cabin(rawValue: String(parts[1])) else { return nil }
        let left = parts[0].split(separator: "@")
        guard left.count == 2 else { return nil }
        let ids = left[0].split(separator: "+").compactMap { Int($0) }
        let dateAndOffs = left[1].split(separator: "~")
        let date = String(dateAndOffs[0])
        let offsets = dateAndOffs.count > 1 ? dateAndOffs[1].compactMap { Int(String($0)) } : ids.map { _ in 0 }
        let fl = ids.compactMap { byId[$0] }
        guard fl.count == ids.count, offsets.count == fl.count else { return nil }
        var prices: [Int] = []
        for (i, f) in fl.enumerated() {
            guard let p = price(f, Day.add(date, offsets[i]), cabin: cabin) else { return nil }
            prices.append(p)
        }
        return makeResult(fl, date: date, offsets: offsets, prices: prices, cabin: cabin)
    }

    // MARK: Recherche

    func search(from: String, to: String, date: String, cabin: Cabin) -> [FlightResult] {
        let origins = expand(from), dests = expand(to)
        var out: [FlightResult] = []
        for o in origins { for d in dests { for f in byRoute[o + "-" + d] ?? [] {
            if let p = price(f, date, cabin: cabin) { out.append(makeResult([f], date: date, offsets: [0], prices: [p], cabin: cabin)) }
        } } }
        out += selfTransfers(origins, dests, date, cabin)
        var seen = Set<String>()
        return out.filter { seen.insert($0.key).inserted }
    }

    /// « Billets séparés » : deux compagnies différentes via une ville tierce
    private func selfTransfers(_ origins: [String], _ dests: [String], _ date: String, _ cabin: Cabin) -> [FlightResult] {
        var found: [(Flight, Flight, Int, Int, Int)] = []
        for o in origins {
            for f1 in byFrom[o] ?? [] {
                if !f1.via.isEmpty || origins.contains(f1.to) || dests.contains(f1.to) { continue }
                let x = f1.to
                var p1: Int?? = nil
                for d in dests {
                    if distance(o, x) + distance(x, d) > distance(o, d) * 1.45 + 400 { continue }
                    guard let list = byRoute[x + "-" + d] else { continue }
                    if p1 == nil { p1 = .some(price(f1, date, cabin: cabin)) }
                    guard let pp1 = p1 ?? nil else { break }
                    let arr1 = f1.dep - Int(tz(o) * 60) + f1.duration
                    for f2 in list where f2.via.isEmpty && f2.airline != f1.airline {
                        for k in 0...1 {
                            let lay = k * 1440 + f2.dep - Int(tz(x) * 60) - arr1
                            if lay < 150 || lay > 1080 { continue }
                            guard let p2 = price(f2, Day.add(date, k), cabin: cabin) else { continue }
                            found.append((f1, f2, k, pp1, p2))
                            break
                        }
                    }
                }
            }
        }
        return found.sorted { $0.3 + $0.4 < $1.3 + $1.4 }.prefix(30).map {
            makeResult([$0.0, $0.1], date: date, offsets: [0, $0.2], prices: [$0.3, $0.4], cabin: cabin)
        }
    }

    func minPrice(from: String, to: String, date: String, cabin: Cabin = .eco) -> Int? {
        let key = from + to + date + cabin.rawValue
        lock.lock(); if let v = minCache[key] { lock.unlock(); return v }; lock.unlock()
        var m: Int?
        for o in expand(from) { for d in expand(to) { for f in byRoute[o + "-" + d] ?? [] {
            if let p = price(f, date, cabin: cabin), p < (m ?? .max) { m = p }
        } } }
        if m == nil { m = selfTransfers(expand(from), expand(to), date, cabin).first?.price }
        lock.lock(); minCache[key] = m; lock.unlock()
        return m
    }

    struct Destination: Identifiable, Hashable {
        let code: String
        let airport: String
        var price: Int
        var date: String
        var duration: Int
        var direct: Bool
        var id: String { code }
    }

    /// Destinations les moins chères depuis une origine sur une liste de dates
    func cheapestDestinations(from origin: String, dates: [String], directOnly: Bool = false) -> [Destination] {
        var best: [String: Destination] = [:]
        let own = expand(origin)
        for o in own {
            for f in byFrom[o] ?? [] {
                if directOnly && !f.via.isEmpty { continue }
                let cc = cityCode(f.to)
                if own.contains(f.to) || cc == origin { continue }
                for d in dates {
                    guard let p = price(f, d) else { continue }
                    if var cur = best[cc] {
                        if p < cur.price { cur.price = p; cur.date = d }
                        cur.duration = min(cur.duration, f.duration)
                        if f.via.isEmpty { cur.direct = true }
                        best[cc] = cur
                    } else {
                        best[cc] = Destination(code: cc, airport: f.to, price: p, date: d, duration: f.duration, direct: f.via.isEmpty)
                    }
                }
            }
        }
        return best.values.sorted { $0.price < $1.price }
    }

    /// Historique simulé : prix le plus bas affiché pour ce trajet et cette date ces 14 derniers jours
    func priceHistory(from: String, to: String, date: String, cabin: Cabin) -> [(day: String, price: Int)] {
        (0..<14).reversed().compactMap { k -> (String, Int)? in
            let asOf = Day.add(Day.today, -k)
            var m: Int?
            for o in expand(from) { for d in expand(to) { for f in byRoute[o + "-" + d] ?? [] {
                if let p = price(f, date, cabin: cabin, asOf: asOf), p < (m ?? .max) { m = p }
            } } }
            return m.map { (asOf, $0) }
        }
    }

    /// Coût d'un bagage en soute quand le tarif ne l'inclut pas
    func bagCost(_ r: FlightResult) -> Int {
        r.holdBag ? 0 : r.flights.reduce(0) { sum, f in
            let fee = airlines[f.airline]?.bagFee.hold ?? 0
            return sum + (f.holdBag ? 0 : (fee == 0 ? 30 : fee))
        }
    }
}
