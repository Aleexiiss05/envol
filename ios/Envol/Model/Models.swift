import Foundation
import CoreLocation

// MARK: - Référentiel (data/reference.json, partagé avec le site)

struct Airport: Codable, Identifiable, Hashable {
    let code: String
    let city: String
    let country: String
    let lat: Double
    let lon: Double
    let tz: Double
    let dst: String?
    let pop: Int
    let vibe: String
    let season: String
    let name: String
    var id: String { code }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct BagFee: Codable, Hashable {
    let cabin: Int
    let hold: Int
}

struct Airline: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let color: String
    let alliance: String
    let lowcost: Bool
    let hubs: [String]
    let site: String
    let ontime: Int
    let wifi: Double
    let bagFee: BagFee
    var id: String { code }
    var siteHost: String {
        URL(string: site)?.host()?.replacingOccurrences(of: "www.", with: "").replacingOccurrences(of: "wwws.", with: "") ?? site
    }
}

struct Holiday: Codable, Hashable {
    let from: String
    let to: String
    let k: Double
    let label: String
    let fr: Bool?
    let us: Bool?
}

struct Reference: Codable {
    let airports: [Airport]
    let airlines: [Airline]
    let seasons: [String: [Double]]
    let seasonLabels: [String: String]
    let holidays: [Holiday]
}

struct Photo: Codable, Hashable {
    let u: String
    let by: String
    let c: String?
}

// MARK: - Base de vols (data/flights.csv)

struct Leg: Hashable {
    let from: String
    let to: String
    let km: Double
    let minutes: Int
    let flightNumber: String
    let airline: String
    let aircraft: String
}

struct Flight: Identifiable, Hashable {
    let id: Int
    let airline: String
    let flightNumbers: [String]
    let from: String
    let to: String
    let via: [String]
    let dep: Int          // minutes, heure locale de départ
    let duration: Int     // minutes, escales comprises
    let layovers: [Int]
    let days: [Bool]      // lundi → dimanche
    let base: Double
    let cabinBag: Bool
    let holdBag: Bool
    let meal: Bool
    let wifi: Bool
    let power: Bool
    let refund: Int
    let co2: Int
    let ontime: Int
    let legs: [Leg]
    var isLong: Bool { legs.contains { $0.km > 4000 } }
}

// MARK: - Résultat de recherche (un billet, ou deux billets séparés)

struct Segment: Hashable, Identifiable {
    enum Kind: Hashable { case leg(Leg), layover(at: String, minutes: Int, selfTransfer: Bool) }
    let id = UUID()
    let kind: Kind
    let startUTC: Int
    let endUTC: Int
}

struct FlightResult: Identifiable, Hashable {
    let key: String
    let flights: [Flight]
    let date: String
    let offsets: [Int]
    let cabin: Cabin
    let segments: [Segment]
    let from: String
    let to: String
    let fare: Int
    var price: Int
    let dep: Int      // minutes locales relatives au jour de départ
    let arr: Int      // minutes locales (destination) relatives au jour de départ
    let duration: Int
    let layovers: [(at: String, minutes: Int, selfTransfer: Bool)]
    let carriers: [String]
    let seats: Int
    var score: Double = 0

    var id: String { key }
    var stops: Int { layovers.count }
    var isSelfTransfer: Bool { flights.count > 1 }
    var mainAirline: String { flights[0].airline }
    var holdBag: Bool { flights.allSatisfy(\.holdBag) }
    var cabinBag: Bool { flights.allSatisfy(\.cabinBag) }
    var meal: Bool { flights.contains(where: \.meal) }
    var wifi: Bool { flights.contains(where: \.wifi) }
    var power: Bool { flights.contains(where: \.power) }
    var refund: Int { flights.map(\.refund).min() ?? 0 }
    var co2: Int { flights.reduce(0) { $0 + $1.co2 } }
    var ontime: Int { flights.map(\.ontime).min() ?? 0 }
    var overnight: Bool { layovers.contains { $0.minutes >= 420 } }
    var flightNumbers: [String] { flights.flatMap(\.flightNumbers) }
    var dayOffset: Int { Int((Double(arr) / 1440).rounded(.down)) - Int((Double(dep) / 1440).rounded(.down)) }

    static func == (a: FlightResult, b: FlightResult) -> Bool { a.key == b.key && a.price == b.price }
    func hash(into h: inout Hasher) { h.combine(key) }
}

enum Cabin: String, CaseIterable, Codable, Identifiable {
    case eco, prem, bus, first
    var id: String { rawValue }
    var label: String {
        switch self { case .eco: "Économique"; case .prem: "Premium"; case .bus: "Affaires"; case .first: "Première" }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case best, cheap, fast, early, co2
    var id: String { rawValue }
    var label: String {
        switch self {
        case .best: "Recommandé"; case .cheap: "Moins cher"; case .fast: "Plus rapide"; case .early: "Départ le plus tôt"; case .co2: "Moins de CO₂"
        }
    }
}

struct SearchQuery: Hashable, Codable {
    var from: String = "PAR"
    var to: String = ""
    var dep: String = Day.add(Day.today, 21)
    var ret: String = Day.add(Day.today, 28)
    var roundTrip = true
    var adults = 1
    var children = 0
    var infants = 0
    var cabin: Cabin = .eco
    var directOnly = false
    var bagIncluded = false

    var passengers: Int { adults + children + infants }
    func total(_ perAdult: Int) -> Int {
        Int((Double(perAdult) * Double(adults) + Double(perAdult) * 0.75 * Double(children) + Double(perAdult) * 0.1 * Double(infants)).rounded())
    }
}
