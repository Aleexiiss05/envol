import SwiftUI
import Charts
import UserNotifications

// MARK: - Favoris

struct FavoritesView: View {
    @Environment(UserData.self) private var user
    @State private var detail: FlightResult?
    private let store = FlightStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if user.favorites.isEmpty {
                    ContentUnavailableView("Aucun favori", systemImage: "heart",
                                           description: Text("Dans les résultats, balayez un vol vers la gauche pour l'enregistrer ici et suivre son prix."))
                } else {
                    List {
                        ForEach(user.favorites) { f in
                            let current = f.date >= Day.today ? store.result(forKey: f.key) : nil
                            Button { if let current { detail = current } } label: { row(f, current) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { user.favorites.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Favoris")
            .toolbar { if !user.favorites.isEmpty { EditButton() } }
            .sheet(item: $detail) { r in
                FlightDetailView(result: r, outbound: nil, query: oneWay(r), pendingOutbound: false) {}
            }
        }
    }

    private func oneWay(_ r: FlightResult) -> SearchQuery {
        var q = SearchQuery()
        q.from = r.from; q.to = r.to; q.dep = r.date; q.roundTrip = false
        return q
    }

    private func row(_ f: SavedFlight, _ r: FlightResult?) -> some View {
        HStack(spacing: 12) {
            PlacePhoto(code: store.cityCode(f.to), width: 200).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.city(f.from)) → \(store.city(f.to))").font(.body.weight(.semibold))
                Text("\(f.from) – \(f.to) · \(Day.short(f.date))\(r.map { " · \(Fmt.time($0.dep))" } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(r.map { euros($0.fare) } ?? "—").font(.body.weight(.bold)).monospacedDigit()
                delta(r?.fare, f.savedPrice)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

@ViewBuilder
func delta(_ now: Int?, _ then: Int) -> some View {
    if let now {
        let d = now - then
        Text(d < 0 ? "−\(euros(-d))" : d > 0 ? "+\(euros(d))" : "Inchangé")
            .font(.caption.weight(.semibold))
            .foregroundStyle(d < 0 ? Color.green : d > 0 ? Color.red : Color.secondary)
            .accessibilityLabel(d < 0 ? "En baisse de \(euros(-d))" : d > 0 ? "En hausse de \(euros(d))" : "Prix inchangé")
    } else {
        Text("Indisponible").font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Alertes prix

struct AlertsView: View {
    @Environment(UserData.self) private var user
    private let store = FlightStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if user.alerts.isEmpty {
                    ContentUnavailableView("Aucune alerte", systemImage: "bell",
                                           description: Text("Depuis une recherche, touchez la cloche : vous serez prévenu quand le prix baisse."))
                } else {
                    List {
                        if !user.notificationsAllowed {
                            Section {
                                Button { user.requestNotifications() } label: {
                                    Label("Autoriser les notifications pour être prévenu des baisses", systemImage: "bell.badge")
                                }
                            }
                        }
                        ForEach(user.alerts) { a in
                            Section { AlertRow(alert: a) }
                        }
                        .onDelete { user.alerts.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Alertes")
            .refreshable { user.checkAlerts() }
            .onAppear {
                UNUserNotificationCenterWrapper.status { user.notificationsAllowed = $0 }
            }
        }
    }
}

private struct AlertRow: View {
    let alert: PriceAlert
    private let store = FlightStore.shared
    var body: some View {
        let history = store.priceHistory(from: alert.from, to: alert.to, date: alert.dep, cabin: alert.cabin)
        let current = history.last?.price
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.city(alert.from)) → \(store.city(alert.to))").font(.headline)
                    Text("\(Day.short(alert.dep))\(alert.ret.map { " – \(Day.short($0))" } ?? "") · \(alert.cabin.label)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(current.map(euros) ?? "—").font(.title3.weight(.bold)).monospacedDigit()
                    delta(current, alert.referencePrice)
                }
            }
            if history.count > 1 {
                Chart(history.indices, id: \.self) { i in
                    LineMark(x: .value("Jour", Day.date(history[i].day)), y: .value("Prix", history[i].price))
                        .interpolationMethod(.monotone)
                    if i == history.count - 1 {
                        PointMark(x: .value("Jour", Day.date(history[i].day)), y: .value("Prix", history[i].price))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .frame(height: 70)
                .accessibilityLabel("Évolution du prix sur 14 jours, de \(euros(history.first?.price ?? 0)) à \(euros(current ?? 0))")
                Text("Prix le plus bas affiché ces 14 derniers jours").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

enum UNUserNotificationCenterWrapper {
    static func status(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { completion(s.authorizationStatus == .authorized || s.authorizationStatus == .provisional) }
        }
    }
}
