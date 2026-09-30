import Foundation

enum Companions: String, Codable, CaseIterable, Identifiable {
    case solo, couple, family, friends
    var id: String { rawValue }
    var label: String {
        switch self { case .solo: "Seul"; case .couple: "À deux"; case .family: "En famille"; case .friends: "Entre amis" }
    }
    var detail: String {
        switch self { case .solo: "1 adulte"; case .couple: "2 adultes"; case .family: "2 adultes, 2 enfants"; case .friends: "4 adultes" }
    }
    var symbol: String {
        switch self { case .solo: "person.fill"; case .couple: "person.2.fill"; case .family: "figure.2.and.child.holdinghands"; case .friends: "person.3.fill" }
    }
    var adults: Int { switch self { case .solo: 1; case .couple: 2; case .family: 2; case .friends: 4 } }
    var children: Int { self == .family ? 2 : 0 }
}

enum Vibe: String, Codable, CaseIterable, Identifiable {
    case plage, ville, culture, nature
    var id: String { rawValue }
    var label: String {
        switch self { case .plage: "Mer & plages"; case .ville: "Grandes villes"; case .culture: "Culture & histoire"; case .nature: "Nature & grands espaces" }
    }
    /// Destination servant d'illustration
    var photoCode: String {
        switch self { case .plage: "MLE"; case .ville: "JFK"; case .culture: "FCO"; case .nature: "RUN" }
    }
}

/// Ce que l'utilisateur nous dit de lui à l'accueil : sert à personnaliser recherches et suggestions.
struct TravelProfile: Codable, Equatable {
    var firstName = ""
    var homeCode = "PAR"
    var vibes: Set<Vibe> = []
    var companions: Companions = .solo
    var budget = 300
    var cabin: Cabin = .eco
    var bagUsually = false
    var directPreferred = false
    var memberSince = Day.today

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour >= 18 || hour < 5 ? "Bonsoir" : "Bonjour"
        return firstName.isEmpty ? hello : "\(hello) \(firstName)"
    }
}

extension SearchQuery {
    /// Requête pré-remplie avec les habitudes de l'utilisateur
    init(profile p: TravelProfile) {
        self.init()
        from = p.homeCode
        adults = p.companions.adults
        children = p.companions.children
        cabin = p.cabin
        bagIncluded = p.bagUsually
        directOnly = p.directPreferred
    }
}

extension FlightStore {
    /// Suggestions : destinations moins chères que le budget, correspondant aux envies, variées géographiquement
    func suggestions(for p: TravelProfile, limit: Int = 6) -> [Destination] {
        let dates = (10..<70).map { Day.add(Day.today, $0) }
        let all = cheapestDestinations(from: p.homeCode, dates: dates, directOnly: p.directPreferred)
        let wanted = Set(p.vibes.map(\.rawValue))
        var picks: [Destination] = []
        for d in all where d.price <= p.budget && (wanted.isEmpty || wanted.contains(airportByCode[d.airport]?.vibe ?? "")) {
            if picks.contains(where: { km($0.airport, d.airport) < 900 }) { continue }
            picks.append(d)
            if picks.count == limit { break }
        }
        if picks.isEmpty { picks = Array(all.prefix(limit)) }
        return picks
    }

    /// Aéroport (ou ville multi-aéroports) le plus proche d'une position
    func nearestPlace(lat: Double, lon: Double) -> String {
        let r = Double.pi / 180
        func d(_ a: Airport) -> Double {
            let h = pow(sin((a.lat - lat) * r / 2), 2) + cos(lat * r) * cos(a.lat * r) * pow(sin((a.lon - lon) * r / 2), 2)
            return asin(sqrt(h))
        }
        guard let best = airports.min(by: { d($0) < d($1) }) else { return "PAR" }
        return cityCode(best.code)
    }
}
