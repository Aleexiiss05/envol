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
                        Image(systemName: "airplane.departure").font(.caption.bold()).foregroundStyle(.white)
                            .padding(7).background(.tint, in: Circle())
                    }
                    ForEach(visible) { d in
                        if let a = store.airportByCode[d.airport] {
                            let labelled = labelledCodes.contains(d.code) || selected?.code == d.code
                            MapPolyline(coordinates: [o.coordinate, a.coordinate], contourStyle: .geodesic)
                                .stroke(Color.accentColor.opacity(selected?.code == d.code ? 0.9 : 0.18), lineWidth: selected?.code == d.code ? 2 : 1)
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
            .safeAreaInset(edge: .top) { controls }
            .safeAreaInset(edge: .bottom) { if let d = selected { selectedCard(d) } else { summary } }
            .navigationTitle("Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { pickingOrigin = true } label: { Label("Depuis \(store.city(origin))", systemImage: "airplane.departure").labelStyle(.titleAndIcon) }
                }
            }
            .sheet(isPresented: $pickingOrigin) { PlacePicker(title: "Ville de départ", current: origin) { origin = $0 } }
            .navigationDestination(for: SearchQuery.self) { ResultsView(query: $0) }
            .task(id: "\(origin)-\(month)-\(directOnly)") { await load() }
            .sensoryFeedback(.selection, trigger: selected?.code)
        }
    }

    /// Seules les destinations les moins chères portent une étiquette ; les autres sont des points (touchez pour voir le prix)
    private var labelledCodes: Set<String> { Set(visible.sorted { $0.price < $1.price }.prefix(14).map { $0.code }) }
    private func priceDot(_ d: FlightStore.Destination) -> some View {
        Circle().fill(d.price <= cheapThreshold ? Color.green : Color.secondary)
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
            .font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 4)
            .foregroundStyle(isSel ? Color.white : good ? Color.green : Color.primary)
            .background(isSel ? Color.accentColor : Color(.systemBackground), in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .scaleEffect(isSel ? 1.15 : 1)
            .animation(.spring(duration: 0.3), value: isSel)
            .accessibilityLabel("\(store.city(d.code)), dès \(euros(d.price))")
    }

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(months, id: \.self) { m in
                        chip(Day.format(m, "MMMM").capitalized, on: m == month) { month = m }
                    }
                    Divider().frame(height: 20)
                    ForEach(vibes, id: \.0) { v in chip(v.1, on: vibe == v.0) { withAnimation { vibe = v.0 } } }
                    Divider().frame(height: 20)
                    chip("Direct", on: directOnly) { directOnly.toggle() }
                }
                .padding(.horizontal)
            }
            HStack {
                Text("Budget").font(.subheadline.weight(.medium))
                Slider(value: $budget, in: 50...2000, step: 10)
                Text(budget >= 2000 ? "Illimité" : "≤ \(euros(Int(budget)))").font(.subheadline).monospacedDigit().frame(width: 84, alignment: .trailing)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? Color.primary : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var summary: some View {
        Text("\(Fmt.plural(visible.count, "destination")) · touchez un prix")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(12).background(.regularMaterial)
    }

    private func selectedCard(_ d: FlightStore.Destination) -> some View {
        HStack(spacing: 12) {
            PlacePhoto(code: d.code, width: 300).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.city(d.code)).font(.headline)
                Text("\(store.country(d.code)) · \(Fmt.duration(d.duration))\(d.direct ? " · direct" : "")").font(.caption).foregroundStyle(.secondary)
                Text("dès \(euros(d.price)) le \(Day.format(d.date, "dMMM"))").font(.subheadline.weight(.semibold))
            }
            Spacer()
            Button("Voir") {
                var q = SearchQuery()
                q.from = origin; q.to = d.code; q.dep = d.date; q.ret = Day.add(d.date, 7)
                path.append(q)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal).padding(.bottom, 8)
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
