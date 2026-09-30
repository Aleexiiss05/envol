import Foundation

/// Mode démonstration, utilisé par la CI pour capturer chaque écran dans le simulateur.
/// Lancement : xcrun simctl launch booted fr.envol.app -demoScreen results
/// Écrans : onboarding0 … onboarding7, home, results, detail, explore, favoris, alertes, profile
enum Demo {
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    static var isOnboarding: Bool { screen?.hasPrefix("onboarding") == true }
    static var onboardingPage: Int { Int(screen?.dropFirst("onboarding".count) ?? "") ?? 0 }

    static var tab: Int {
        switch screen {
        case "explore": 1
        case "favoris": 2
        case "alertes": 3
        case "profile": 4
        default: 0
        }
    }

    /// Requête de démonstration : Paris → Lisbonne dans un mois, pour 2 personnes
    static var query: SearchQuery {
        var q = SearchQuery(profile: profile)
        q.to = "LIS"
        q.dep = Day.add(Day.today, 30)
        q.ret = Day.add(Day.today, 37)
        return q
    }

    static var profile: TravelProfile {
        var p = TravelProfile()
        p.firstName = "Alexis"
        p.homeCode = "PAR"
        p.vibes = [.plage, .culture]
        p.companions = .couple
        p.budget = 400
        return p
    }

    /// Prépare les données selon l'écran demandé
    static func prepare(_ user: UserData) {
        guard let screen else { return }
        if isOnboarding { user.onboarded = false; return }
        user.profile = profile
        user.onboarded = true
        user.searchCount = max(user.searchCount, 12)
        let store = FlightStore.shared
        if user.alerts.isEmpty {
            for (to, days) in [("LIS", 30), ("HND", 60), ("CUN", 90)] {
                var q = query; q.to = to; q.dep = Day.add(Day.today, days); q.ret = Day.add(q.dep, 7)
                user.toggleAlert(q, askPermission: false)
                // prix de référence un peu plus haut : l'alerte affiche une baisse
                if let i = user.alerts.firstIndex(where: { $0.to == to }) { user.alerts[i].referencePrice += 18 + days / 10 }
            }
        }
        if user.favorites.isEmpty {
            for to in ["LIS", "BCN", "JFK"] {
                if let r = store.search(from: "PAR", to: to, date: Day.add(Day.today, 30), cabin: .eco).min(by: { $0.price < $1.price }) {
                    user.toggleFavorite(r)
                }
            }
        }
        if user.recents.isEmpty { user.remember(query) }
    }
}
