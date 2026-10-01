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
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PageHeader(title: "Favoris", subtitle: user.favorites.isEmpty ? nil : "\(Fmt.plural(user.favorites.count, "vol")) suivi\(user.favorites.count > 1 ? "s" : "") · prix mis à jour")
                    if user.favorites.isEmpty {
                        EmptyState(symbol: "heart", title: "Aucun favori",
                                   text: "Touchez le cœur d'un vol dans les résultats pour le retrouver ici et suivre son prix.")
                            .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                            .padding(.horizontal, 16)
                    } else {
                        ForEach(user.favorites) { f in
                            let current = f.date >= Day.today ? store.result(forKey: f.key) : nil
                            card(f, current)
                                .padding(.horizontal, 16)
                                .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(.spring(duration: 0.35), value: user.favorites.map(\.id))
            }
            .background(Theme.gray)
            .toolbar(.hidden, for: .navigationBar)
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

    private func card(_ f: SavedFlight, _ r: FlightResult?) -> some View {
        HStack(spacing: 12) {
            PlacePhoto(code: store.cityCode(f.to), width: 200).frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.city(f.from)) → \(store.city(f.to))").font(.inter(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(Day.short(f.date))\(r.map { " · \(Fmt.time($0.dep))" } ?? "") · \(f.from)–\(f.to)").font(.inter(13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(r.map { euros($0.fare) } ?? "—").font(.inter(17, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                delta(r?.fare, f.savedPrice)
            }
            Button {
                withAnimation { user.favorites.removeAll { $0.id == f.id } }
            } label: {
                Image(systemName: "heart.fill").font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#FF2D55"))
                    .frame(width: 34, height: 34)
                    .background(Theme.gray, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Retirer des favoris")
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .onTapGesture { if let r { detail = r } }
        .opacity(r == nil ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

@ViewBuilder
func delta(_ now: Int?, _ then: Int) -> some View {
    if let now {
        let d = now - then
        Text(d < 0 ? "−\(euros(-d))" : d > 0 ? "+\(euros(d))" : "Inchangé")
            .font(.inter(12, .semibold))
            .foregroundStyle(d < 0 ? Theme.good : d > 0 ? Theme.bad : Theme.muted)
            .padding(.horizontal, 7).frame(height: 20)
            .background((d < 0 ? Theme.good : d > 0 ? Theme.bad : Theme.muted).opacity(0.09), in: Capsule())
            .accessibilityLabel(d < 0 ? "En baisse de \(euros(-d))" : d > 0 ? "En hausse de \(euros(d))" : "Prix inchangé")
    } else {
        Text("Indisponible").font(.inter(12)).foregroundStyle(Theme.faint)
    }
}

struct AlertsView: View {
    @Environment(UserData.self) private var user
    private let store = FlightStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PageHeader(title: "Alertes", subtitle: user.alerts.isEmpty ? nil : "Prévenu dès qu'un prix baisse")
                    if user.alerts.isEmpty {
                        EmptyState(symbol: "bell", title: "Aucune alerte",
                                   text: "Depuis une recherche, touchez la cloche : vous serez prévenu quand le prix baisse.")
                            .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                            .padding(.horizontal, 16)
                    } else {
                        if !user.notificationsAllowed {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                                    .frame(width: 36, height: 36).background(Theme.accentBg, in: Circle())
                                Text("Autorisez les notifications pour être prévenu des baisses.").font(.inter(14)).foregroundStyle(Theme.ink2)
                                Spacer(minLength: 4)
                                Button("Activer") { user.requestNotifications() }.buttonStyle(CompactPillStyle())
                            }
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                        ForEach(user.alerts) { a in
                            AlertCard(alert: a) { withAnimation { user.alerts.removeAll { $0.id == a.id } } }
                                .padding(.horizontal, 16)
                                .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(.spring(duration: 0.35), value: user.alerts.map(\.id))
            }
            .background(Theme.gray)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { user.checkAlerts() }
            .onAppear {
                UNUserNotificationCenterWrapper.status { user.notificationsAllowed = $0 }
            }
        }
    }
}

private struct AlertCard: View {
    let alert: PriceAlert
    let onDelete: () -> Void
    private let store = FlightStore.shared
    var body: some View {
        let history = store.priceHistory(from: alert.from, to: alert.to, date: alert.dep, cabin: alert.cabin)
        let current = history.last?.price
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.city(alert.from)) → \(store.city(alert.to))").font(.inter(16, .semibold)).foregroundStyle(Theme.ink)
                    Text("\(Day.short(alert.dep))\(alert.ret.map { " – \(Day.short($0))" } ?? "") · \(alert.cabin.label)").font(.inter(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(current.map(euros) ?? "—").font(.inter(19, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    delta(current, alert.referencePrice)
                }
                Menu {
                    Button("Supprimer l'alerte", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
                        .frame(width: 34, height: 34).background(Theme.gray, in: Circle())
                }
                .accessibilityLabel("Options de l'alerte")
            }
            if history.count > 1 {
                Chart(history.indices, id: \.self) { i in
                    AreaMark(x: .value("Jour", Day.date(history[i].day)), y: .value("Prix", history[i].price))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Jour", Day.date(history[i].day)), y: .value("Prix", history[i].price))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    if i == history.count - 1 {
                        PointMark(x: .value("Jour", Day.date(history[i].day)), y: .value("Prix", history[i].price))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(50)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(Theme.gray2)
                        AxisValueLabel { if let p = v.as(Int.self) { Text(euros(p)).font(.inter(10)).foregroundStyle(Theme.faint) } }
                    }
                }
                .frame(height: 76)
                .accessibilityLabel("Évolution du prix sur 14 jours, de \(euros(history.first?.price ?? 0)) à \(euros(current ?? 0))")
                Text("Prix le plus bas affiché ces 14 derniers jours").font(.inter(11)).foregroundStyle(Theme.faint)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .contextMenu { Button("Supprimer l'alerte", systemImage: "trash", role: .destructive, action: onDelete) }
    }
}

enum UNUserNotificationCenterWrapper {
    static func status(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { completion(s.authorizationStatus == .authorized || s.authorizationStatus == .provisional) }
        }
    }
}
