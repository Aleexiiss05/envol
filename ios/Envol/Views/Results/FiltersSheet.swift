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
        VStack(spacing: 0) {
            SheetHeader(title: "Filtres", subtitle: "\(Fmt.plural(matching, "vol")) sur \(results.count)") {
                if filters.activeCount > 0 {
                    Button("Effacer") { withAnimation(.snappy) { filters = Filters() } }
                        .font(.inter(14, .semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Theme.accentBg, in: Capsule())
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.snappy, value: filters.activeCount > 0)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Escales") {
                        HStack(spacing: 8) {
                            stopTile(0, "Direct")
                            stopTile(1, "1 escale")
                            stopTile(2, "2 et +")
                        }
                    }

                    EnvolSection(title: "Bagages", fill: Theme.gray) {
                        ToggleRow(title: "Prix avec bagage en soute", subtitle: "Ajoute le bagage aux tarifs qui ne l'incluent pas", isOn: $bagIncluded)
                        RowDivider()
                        ToggleRow(title: "Bagage en soute inclus", isOn: $filters.holdBag)
                        RowDivider()
                        ToggleRow(title: "Bagage cabine inclus", isOn: $filters.cabinBag)
                    }

                    EnvolSection(title: "Prix et durée", fill: Theme.gray) {
                        slider("Prix maximum", filters.maxPrice.map { euros(Int($0)) } ?? "Tous",
                               Binding(get: { filters.maxPrice ?? priceRange.upperBound },
                                       set: { filters.maxPrice = $0 >= priceRange.upperBound ? nil : $0 }), priceRange, step: 1)
                        RowDivider()
                        slider("Durée maximum", filters.maxDuration.map { Fmt.duration(Int($0)) } ?? "Toutes",
                               Binding(get: { filters.maxDuration ?? durationRange.upperBound },
                                       set: { filters.maxDuration = $0 >= durationRange.upperBound ? nil : $0 }), durationRange, step: 15)
                    }

                    group("Heure de départ") { buckets($filters.depBuckets) }
                    group("Heure d'arrivée") { buckets($filters.arrBuckets) }

                    group("Compagnies") {
                        SegmentedPicker(options: [(0, "Toutes"), (1, "Classiques"), (2, "Low-cost")], selection: $filters.kind)
                        VStack(spacing: 0) {
                            ForEach(Array(carriers.enumerated()), id: \.element) { i, c in
                                if i > 0 { RowDivider(inset: 52) }
                                let on = !filters.excludedAirlines.contains(c)
                                Button {
                                    withAnimation(.snappy) { if on { filters.excludedAirlines.insert(c) } else { filters.excludedAirlines.remove(c) } }
                                } label: {
                                    HStack(spacing: 12) {
                                        AirlineLogo(code: c, size: 26)
                                        Text(store.airlines[c]?.name ?? c).font(.inter(15, .medium)).foregroundStyle(on ? Theme.ink : Theme.faint)
                                        Spacer()
                                        Text(minPrice { $0.carriers.contains(c) }).font(.inter(14)).foregroundStyle(Theme.muted).monospacedDigit()
                                        check(on)
                                    }
                                    .padding(.horizontal, 14).frame(minHeight: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .background(Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }

                    EnvolSection(title: "Conditions", fill: Theme.gray) {
                        ToggleRow(title: "Wi-Fi à bord", isOn: $filters.wifi)
                        RowDivider()
                        ToggleRow(title: "Modifiable ou remboursable", isOn: $filters.refundable)
                        RowDivider()
                        ToggleRow(title: "Pas de nuit en escale", isOn: $filters.noOvernight)
                        RowDivider()
                        ToggleRow(title: "Billets séparés", subtitle: "Deux compagnies, souvent moins cher, correspondance non protégée", isOn: $filters.allowSelfTransfer)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            Button { dismiss() } label: {
                Text(matching > 0 ? "Afficher \(Fmt.plural(matching, "vol"))" : "Aucun vol : assouplissez les filtres")
                    .contentTransition(.numericText(value: Double(matching)))
            }
            .buttonStyle(PillButtonStyle(fullWidth: true))
            .disabled(matching == 0)
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
            .background(.white)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            .animation(.snappy, value: matching)
        }
        .envolSheet()
        .sensoryFeedback(.selection, trigger: filters)
    }

    private var carriers: [String] {
        var seen: [String] = []
        for r in results.sorted(by: { $0.price < $1.price }) { for c in r.carriers where !seen.contains(c) { seen.append(c) } }
        return seen
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.inter(13, .semibold)).foregroundStyle(Theme.muted).padding(.leading, 6)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func check(_ on: Bool) -> some View {
        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            .foregroundStyle(on ? Color.white : Color.clear)
            .frame(width: 22, height: 22)
            .background(on ? Theme.accent : Color.clear, in: Circle())
            .overlay(Circle().strokeBorder(on ? Color.clear : Theme.gray2, lineWidth: 2))
    }

    /// Tuile d'escale façon tri du site : prix minimum en dessous
    private func stopTile(_ n: Int, _ label: String) -> some View {
        let on = filters.stops.contains(n)
        return Button {
            withAnimation(.snappy) { if on { filters.stops.remove(n) } else { filters.stops.insert(n) } }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.inter(13, .semibold)).foregroundStyle(on ? Theme.accent : Theme.muted)
                Text(minPrice { min($0.stops, 2) == n }).font(.inter(16, .bold)).foregroundStyle(on ? Theme.ink : Theme.faint).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(on ? Color.white : Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(label), dès \(minPrice { min($0.stops, 2) == n })")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func slider(_ title: String, _ value: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(value).font(.inter(15, .semibold)).foregroundStyle(Theme.accent).monospacedDigit()
            }
            Slider(value: binding, in: range, step: step).tint(Theme.accent)
                .accessibilityLabel(title).accessibilityValue(value)
        }
        .padding(14)
    }

    private func buckets(_ set: Binding<Set<Int>>) -> some View {
        let items = [("Nuit", "0 h – 6 h", "moon"), ("Matin", "6 h – 12 h", "sunrise"), ("Après-midi", "12 h – 18 h", "sun.max"), ("Soir", "18 h – 24 h", "sunset")]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                let on = set.wrappedValue.contains(i)
                Button {
                    withAnimation(.snappy) { if on { set.wrappedValue.remove(i) } else { set.wrappedValue.insert(i) } }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: items[i].2).font(.system(size: 15)).foregroundStyle(on ? Theme.accent : Theme.muted).frame(width: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(items[i].0).font(.inter(14, .semibold)).foregroundStyle(Theme.ink)
                            Text(items[i].1).font(.inter(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(height: 54)
                    .background(on ? Color.white : Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
