import SwiftUI

struct FiltersSheet: View {
    @Binding var filters: Filters
    let results: [FlightResult]
    let matching: Int
    @Binding var bagIncluded: Bool
    @Environment(\.dismiss) private var dismiss
    private let store = FlightStore.shared

    private var priceRange: ClosedRange<Double> {
        let p = results.map { Double($0.price) }
        guard let lo = p.min(), let hi = p.max(), hi > lo else { return 0...1 }
        return lo...hi
    }
    private var durationRange: ClosedRange<Double> {
        let d = results.map { Double($0.duration) }
        guard let lo = d.min(), let hi = d.max(), hi > lo else { return 0...1 }
        return lo...hi
    }
    private func minPrice(_ where: (FlightResult) -> Bool) -> String {
        results.filter(`where`).map(\.price).min().map(euros) ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Escales") {
                    stopToggle(0, "Direct")
                    stopToggle(1, "1 escale")
                    stopToggle(2, "2 escales ou plus")
                }
                Section {
                    Toggle(isOn: $bagIncluded) {
                        VStack(alignment: .leading) {
                            Text("Prix avec bagage en soute")
                            Text("Ajoute le coût d'un bagage aux tarifs qui ne l'incluent pas").font(.inter(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Bagage en soute inclus", isOn: $filters.holdBag)
                    Toggle("Bagage cabine inclus", isOn: $filters.cabinBag)
                } header: { Text("Bagages") }
                Section {
                    VStack(alignment: .leading) {
                        HStack { Text("Prix maximum"); Spacer(); Text(filters.maxPrice.map { euros(Int($0)) } ?? "Tous").foregroundStyle(.secondary) }
                        Slider(value: Binding(get: { filters.maxPrice ?? priceRange.upperBound },
                                              set: { filters.maxPrice = $0 >= priceRange.upperBound ? nil : $0 }), in: priceRange)
                            .accessibilityValue(filters.maxPrice.map { euros(Int($0)) } ?? "Tous les prix")
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("Durée maximum"); Spacer(); Text(filters.maxDuration.map { Fmt.duration(Int($0)) } ?? "Toutes").foregroundStyle(.secondary) }
                        Slider(value: Binding(get: { filters.maxDuration ?? durationRange.upperBound },
                                              set: { filters.maxDuration = $0 >= durationRange.upperBound ? nil : $0 }), in: durationRange, step: 15)
                    }
                } header: { Text("Prix et durée") }
                Section("Heure de départ") { buckets($filters.depBuckets) }
                Section("Heure d'arrivée") { buckets($filters.arrBuckets) }
                Section("Compagnies") {
                    SegmentedPicker(options: [(0, "Toutes"), (1, "Classiques"), (2, "Low-cost")], selection: $filters.kind)
                    ForEach(carriers, id: \.self) { c in
                        Toggle(isOn: Binding(get: { !filters.excludedAirlines.contains(c) }, set: { on in
                            if on { filters.excludedAirlines.remove(c) } else { filters.excludedAirlines.insert(c) }
                        })) {
                            HStack(spacing: 10) {
                                AirlineLogo(code: c, size: 24)
                                Text(store.airlines[c]?.name ?? c)
                                Spacer()
                                Text(minPrice { $0.carriers.contains(c) }).foregroundStyle(.secondary).font(.inter(.subheadline))
                            }
                        }
                    }
                }
                Section("Conditions") {
                    Toggle("Wi-Fi à bord", isOn: $filters.wifi)
                    Toggle("Modifiable ou remboursable", isOn: $filters.refundable)
                    Toggle("Pas de nuit en escale", isOn: $filters.noOvernight)
                    Toggle(isOn: $filters.allowSelfTransfer) {
                        VStack(alignment: .leading) {
                            Text("Billets séparés")
                            Text("Deux compagnies, souvent moins cher, correspondance non protégée").font(.inter(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tout effacer") { filters = Filters() }.disabled(filters.activeCount == 0) }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() }.bold() }
            }
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text(matching > 0 ? "Afficher \(Fmt.plural(matching, "vol"))" : "Aucun vol : assouplissez les filtres")
                }
                .buttonStyle(PillButtonStyle(fullWidth: true))
                .padding(.horizontal, 16).padding(.vertical, 10).background(.white)
            }
            .sensoryFeedback(.selection, trigger: filters)
        }
    }

    private var carriers: [String] {
        var seen: [String] = []
        for r in results.sorted(by: { $0.price < $1.price }) { for c in r.carriers where !seen.contains(c) { seen.append(c) } }
        return seen
    }

    private func stopToggle(_ n: Int, _ label: String) -> some View {
        Toggle(isOn: Binding(get: { filters.stops.contains(n) }, set: { on in
            if on { filters.stops.insert(n) } else { filters.stops.remove(n) }
        })) {
            HStack { Text(label); Spacer(); Text(minPrice { min($0.stops, 2) == n }).foregroundStyle(.secondary).font(.inter(.subheadline)) }
        }
    }

    private func buckets(_ set: Binding<Set<Int>>) -> some View {
        let items = [("Nuit", "0 h – 6 h", "moon"), ("Matin", "6 h – 12 h", "sunrise"), ("Après-midi", "12 h – 18 h", "sun.max"), ("Soir", "18 h – 24 h", "sunset")]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                let on = set.wrappedValue.contains(i)
                Button {
                    if on { set.wrappedValue.remove(i) } else { set.wrappedValue.insert(i) }
                } label: {
                    HStack {
                        Image(systemName: items[i].2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(items[i].0).font(.inter(.subheadline, .medium))
                            Text(items[i].1).font(.inter(.caption2)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(on ? Theme.accentBg : Theme.gray, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 1.5))
                    .foregroundStyle(on ? Theme.accent : Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
