import SwiftUI
import MapKit

/// Carte des destinations : tout ce qui décolle d'une ville, avec le prix sur la carte (Apple Plans).
struct ExploreView: View {
    @State private var origin = "PAR"
    @State private var month = Day.addMonths(String(Day.add(Day.today, 1).prefix(8)) + "01", 0)
    @State private var budget: Double = 2000
    @State private var vibe = "all"
    @State private var directOnly = false
    @State private var all: [FlightStore.Destination] = []
    @State private var selected: FlightStore.Destination?
    @State private var position: MapCameraPosition = .automatic
    @State private var pickingOrigin = false
    @State private var path: [SearchQuery] = []
    private let store = FlightStore.shared
    private let vibes = [("all", "Tout"), ("plage", "Plages"), ("ville", "Villes"), ("culture", "Culture"), ("nature", "Nature")]

    private var visible: [FlightStore.Destination] {
        all.filter { Double($0.price) <= budget && (vibe == "all" || store.airportByCode[$0.airport]?.vibe == vibe) }
    }
    private var months: [String] { (0..<4).map { Day.addMonths(String(Day.add(Day.today, 1).prefix(8)) + "01", $0) } }
    private var cheapThreshold: Int {
        let s = all.map(\.price).sorted()
        return s.isEmpty ? 0 : s[s.count / 3]
    }

    var body: some View {
        NavigationStack(path: $path) {
            Map(position: $position, selection: Binding(get: { selected?.code }, set: { code in selected = visible.first { $0.code == code } })) {
                if let o = store.airportByCode[store.expand(origin)[0]] {
                    Annotation(store.city(origin), coordinate: o.coordinate) {
                        Image(systemName: "airplane").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Theme.ink, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    ForEach(visible) { d in
                        if let a = store.airportByCode[d.airport] {
                            let labelled = labelledCodes.contains(d.code) || selected?.code == d.code
                            MapPolyline(coordinates: [o.coordinate, a.coordinate], contourStyle: .geodesic)
                                .stroke(Theme.accent.opacity(selected?.code == d.code ? 0.9 : 0.18), lineWidth: selected?.code == d.code ? 2 : 1)
                            Annotation(store.city(d.code), coordinate: a.coordinate, anchor: labelled ? .bottom : .center) {
                                if labelled { pricePin(d) } else { priceDot(d) }
                            }
                            .tag(d.code)
                            .annotationTitles(.hidden)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .safeAreaInset(edge: .top, spacing: 0) { controls }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group { if let d = selected { selectedCard(d) } else { summary } }
                    .animation(.spring(duration: 0.35), value: selected?.code)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $pickingOrigin) { PlacePicker(title: "Ville de départ", current: origin) { origin = $0 } }
            .navigationDestination(for: SearchQuery.self) { ResultsView(query: $0) }
            .task(id: "\(origin)-\(month)-\(directOnly)") { await load() }
            .sensoryFeedback(.selection, trigger: selected?.code)
        }
    }

    /// Étiquettes de prix pour les moins chères, sans chevauchement : on saute une destination trop proche d'une déjà étiquetée
    private var labelledCodes: Set<String> {
        var picked: [FlightStore.Destination] = []
        for d in visible.sorted(by: { $0.price < $1.price }) {
            if picked.contains(where: { store.km($0.airport, d.airport) < 700 }) { continue }
            picked.append(d)
            if picked.count == 12 { break }
        }
        return Set(picked.map(\.code))
    }
    private func priceDot(_ d: FlightStore.Destination) -> some View {
        Circle().fill(d.price <= cheapThreshold ? Theme.good : Theme.faint)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
            .padding(8)
            .contentShape(Circle())
            .accessibilityLabel("\(store.city(d.code)), dès \(euros(d.price))")
    }

    private func pricePin(_ d: FlightStore.Destination) -> some View {
        let isSel = selected?.code == d.code
        let good = d.price <= cheapThreshold
        return Text(euros(d.price))
            .font(.inter(12, .semibold)).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(isSel ? Color.white : good ? Theme.good : Theme.ink)
            .background(isSel ? Theme.accent : Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .scaleEffect(isSel ? 1.15 : 1)
            .animation(.spring(duration: 0.3), value: isSel)
            .accessibilityLabel("\(store.city(d.code)), dès \(euros(d.price))")
    }

    /// Panneau flottant en verre (même matière que les menus du site)
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Explorer").display(26).foregroundStyle(Theme.ink)
                    Text("\(Fmt.plural(visible.count, "destination")) · \(Day.format(month, "MMMM"))").font(.inter(13)).foregroundStyle(Theme.muted)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button { pickingOrigin = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane.departure").font(.system(size: 12, weight: .semibold))
                        Text(store.city(origin)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.inter(14, .semibold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Départ : \(store.city(origin)). Changer")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(months, id: \.self) { m in
                        chip(Day.format(m, "MMMM").capitalized, on: m == month) { month = m }
                    }
                    Rectangle().fill(Theme.gray2).frame(width: 1, height: 20).padding(.horizontal, 4)
                    ForEach(vibes, id: \.0) { v in chip(v.1, on: vibe == v.0) { withAnimation { vibe = v.0 } } }
                    Rectangle().fill(Theme.gray2).frame(width: 1, height: 20).padding(.horizontal, 4)
                    chip("Direct", on: directOnly) { directOnly.toggle() }
                }
            }
            .scrollClipDisabled()
            HStack(spacing: 10) {
                Text("Budget").font(.inter(14, .medium)).foregroundStyle(Theme.ink2)
                Slider(value: $budget, in: 50...2000, step: 10).tint(Theme.accent)
                    .accessibilityValue(budget >= 2000 ? "Illimité" : euros(Int(budget)))
                Text(budget >= 2000 ? "Tous" : "≤ \(euros(Int(budget)))").font(.inter(14, .semibold)).foregroundStyle(Theme.ink).monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(0.62)))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        ChipButton(label: label, on: on, offFill: .white, action: action)
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.good).frame(width: 7, height: 7)
            Text("Les moins chères du mois · touchez un prix").font(.inter(13, .medium)).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 14).frame(height: 34)
        .background(.white.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    private func selectedCard(_ d: FlightStore.Destination) -> some View {
        HStack(spacing: 12) {
            PlacePhoto(code: d.code, width: 300).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.city(d.code)).font(.inter(17, .semibold)).foregroundStyle(Theme.ink)
                Text("\(store.country(d.code)) · \(Fmt.duration(d.duration))\(d.direct ? " · direct" : "")").font(.inter(12)).foregroundStyle(Theme.muted)
                Text("dès \(euros(d.price)) le \(Day.format(d.date, "dMMM"))").font(.inter(14, .semibold)).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button("Voir") {
                var q = SearchQuery()
                q.from = origin; q.to = d.code; q.dep = d.date; q.ret = Day.add(d.date, 7)
                path.append(q)
            }
            .buttonStyle(CompactPillStyle())
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .padding(.horizontal, 12).padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func load() async {
        let o = origin, m = month, direct = directOnly
        let list = await Task.detached(priority: .userInitiated) { () -> [FlightStore.Destination] in
            let n = Day.daysInMonth(m)
            let dates = (0..<n).map { Day.add(m, $0) }.filter { $0 > Day.today }
            return FlightStore.shared.cheapestDestinations(from: o, dates: dates, directOnly: direct)
        }.value
        all = list
        selected = nil
        if let maxP = list.map(\.price).max() { budget = min(2000, Double((maxP / 50 + 1) * 50)) }
        withAnimation { position = .automatic }
    }
}
