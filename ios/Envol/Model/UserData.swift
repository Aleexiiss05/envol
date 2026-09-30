import Foundation
import Observation
import UserNotifications

struct SavedFlight: Codable, Identifiable, Hashable {
    let key: String
    let from: String
    let to: String
    let date: String
    let savedPrice: Int
    var id: String { key }
}

struct PriceAlert: Codable, Identifiable, Hashable {
    var id = UUID()
    let from: String
    let to: String
    let dep: String
    let ret: String?
    let cabin: Cabin
    var referencePrice: Int
    let created: String
    var lastNotifiedPrice: Int?
}

/// Préférences et données de l'utilisateur, conservées sur l'appareil (UserDefaults).
@Observable
final class UserData {
    var favorites: [SavedFlight] = [] { didSet { save(favorites, "favorites") } }
    var alerts: [PriceAlert] = [] { didSet { save(alerts, "alerts") } }
    var recents: [SearchQuery] = [] { didSet { save(recents, "recents") } }
    var bagIncluded = false { didSet { UserDefaults.standard.set(bagIncluded, forKey: "bagIncluded") } }
    var notificationsAllowed = false
    /// Profil de voyage rempli à l'accueil (modifiable dans l'onglet Profil)
    var profile = TravelProfile() { didSet { save(profile, "profile") } }
    var onboarded = false { didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") } }
    var searchCount = 0 { didSet { UserDefaults.standard.set(searchCount, forKey: "searchCount") } }

    init() {
        favorites = load("favorites") ?? []
        alerts = load("alerts") ?? []
        recents = load("recents") ?? []
        bagIncluded = UserDefaults.standard.bool(forKey: "bagIncluded")
        profile = load("profile") ?? TravelProfile()
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
        searchCount = UserDefaults.standard.integer(forKey: "searchCount")
    }

    func resetOnboarding() { onboarded = false }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Favoris
    func isFavorite(_ key: String) -> Bool { favorites.contains { $0.key == key } }
    func toggleFavorite(_ r: FlightResult) {
        if let i = favorites.firstIndex(where: { $0.key == r.key }) { favorites.remove(at: i) }
        else { favorites.insert(SavedFlight(key: r.key, from: r.from, to: r.to, date: r.date, savedPrice: r.fare), at: 0) }
    }

    // MARK: Recherches récentes
    func remember(_ q: SearchQuery) {
        searchCount += 1
        recents.removeAll { $0.from == q.from && $0.to == q.to }
        recents.insert(q, at: 0)
        if recents.count > 5 { recents.removeLast(recents.count - 5) }
    }

    // MARK: Alertes prix
    func hasAlert(_ q: SearchQuery) -> Bool { alerts.contains { $0.from == q.from && $0.to == q.to && $0.dep == q.dep } }
    func toggleAlert(_ q: SearchQuery, askPermission: Bool = true) {
        if let i = alerts.firstIndex(where: { $0.from == q.from && $0.to == q.to && $0.dep == q.dep }) { alerts.remove(at: i); return }
        let p = FlightStore.shared.minPrice(from: q.from, to: q.to, date: q.dep, cabin: q.cabin) ?? 0
        alerts.insert(PriceAlert(from: q.from, to: q.to, dep: q.dep, ret: q.roundTrip ? q.ret : nil, cabin: q.cabin, referencePrice: p, created: Day.today), at: 0)
        if askPermission { requestNotifications() }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { self.notificationsAllowed = granted }
        }
    }

    /// Compare les prix actuels aux prix de référence ; envoie une notification locale pour chaque baisse.
    /// En production, ce contrôle serait fait côté serveur (notification push).
    func checkAlerts() {
        let store = FlightStore.shared
        for i in alerts.indices {
            let a = alerts[i]
            guard a.dep >= Day.today, let now = store.minPrice(from: a.from, to: a.to, date: a.dep, cabin: a.cabin) else { continue }
            let threshold = a.lastNotifiedPrice ?? a.referencePrice
            if now < threshold {
                let content = UNMutableNotificationContent()
                content.title = "\(store.city(a.from)) → \(store.city(a.to))"
                content.body = "Le prix a baissé de \(threshold - now) € : \(now) € le \(Day.short(a.dep))."
                content.sound = .default
                let req = UNNotificationRequest(identifier: a.id.uuidString + "-\(now)", content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
                UNUserNotificationCenter.current().add(req)
                alerts[i].lastNotifiedPrice = now
            }
        }
    }
}
