import SwiftUI

// MARK: - Choix d'un aéroport (recherche, clavier, VoiceOver)

struct PlacePicker: View {
    let title: String
    let current: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private let store = FlightStore.shared

    var body: some View {
        NavigationStack {
            List(store.searchPlaces(text), id: \.self) { code in
                Button {
                    onPick(code)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(code).font(.subheadline.weight(.bold)).frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.city(code)).font(.body)
                            Text(store.subtitle(code)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if code == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(store.city(code)), \(code), \(store.subtitle(code))")
            }
            .listStyle(.plain)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ville, aéroport ou code")
            .overlay {
                if store.searchPlaces(text).isEmpty {
                    ContentUnavailableView.search(text: text)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
    }
}

// MARK: - Calendrier des prix

struct DatesSheet: View {
    @Binding var query: SearchQuery
    @Environment(\.dismiss) private var dismiss
    @State private var pickingReturn = false
    @State private var prices: [String: Int] = [:]
    private let store = FlightStore.shared
    private let months: [String] = (0..<6).map { Day.addMonths(String(Day.today.prefix(8)) + "01", $0) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if query.roundTrip {
                    Picker("Date", selection: $pickingReturn) {
                        Text("Aller · \(Day.short(query.dep))").tag(false)
                        Text("Retour · \(Day.short(query.ret))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(months, id: \.self) { m in monthView(m) }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                if !query.to.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Prix le plus bas par adulte. En vert : les jours les moins chers du mois.")
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(10)
                }
            }
            .navigationTitle(pickingReturn ? "Date de retour" : "Date d'aller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() }.bold() } }
            .task(id: pickingReturn) { await loadPrices() }
        }
    }

    private func monthView(_ first: String) -> some View {
        let offset = Day.weekday(first)
        let count = Day.daysInMonth(first)
        let days = (0..<count).map { Day.add(first, $0) }
        let monthPrices = days.compactMap { prices[$0] }.sorted()
        let cheapLimit = monthPrices.isEmpty ? 0 : monthPrices[monthPrices.count / 3]
        return VStack(alignment: .leading, spacing: 8) {
            Text(Day.format(first, "MMMMyyyy").capitalized).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "J", "V", "S", "D"][i]).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 48) }
                ForEach(days, id: \.self) { d in dayCell(d, cheap: (prices[d] ?? .max) <= cheapLimit) }
            }
        }
    }

    private func dayCell(_ d: String, cheap: Bool) -> some View {
        let disabled = d < Day.today || (pickingReturn && d < query.dep)
        let selected = d == (pickingReturn ? query.ret : query.dep)
        let inRange = query.roundTrip && d > query.dep && d < query.ret
        return Button {
            if pickingReturn { query.ret = d }
            else {
                query.dep = d
                if query.roundTrip { if query.ret < d { query.ret = Day.add(d, 7) }; pickingReturn = true }
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(Day.dayOfMonth(d))").font(.body.weight(selected ? .bold : .regular))
                if let p = prices[d], !disabled {
                    Text(euros(p)).font(.system(size: 10, weight: cheap ? .bold : .regular)).foregroundStyle(selected ? Color.white.opacity(0.85) : cheap ? Color.green : Color.secondary)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(disabled ? Color(.tertiaryLabel) : selected ? .white : .primary)
            .background {
                if selected { Circle().fill(.tint) } else if inRange { Rectangle().fill(Color.accentColor.opacity(0.1)) }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel("\(Day.long(d))\(prices[d].map { ", à partir de \(euros($0))" } ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func loadPrices() async {
        guard !query.to.isEmpty else { return }
        let (from, to) = pickingReturn ? (query.to, query.from) : (query.from, query.to)
        let cabin = query.cabin
        let dates = (0..<183).map { Day.add(Day.today, $0) }
        let result = await Task.detached(priority: .userInitiated) { () -> [String: Int] in
            var out: [String: Int] = [:]
            for d in dates { if let p = FlightStore.shared.minPrice(from: from, to: to, date: d, cabin: cabin) { out[d] = p } }
            return out
        }.value
        prices = result
    }
}

// MARK: - Voyageurs et cabine

struct PassengersSheet: View {
    @Binding var query: SearchQuery
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $query.adults, in: 1...max(1, 9 - query.children - query.infants)) {
                        row("Adultes", "12 ans et plus", query.adults)
                    }
                    Stepper(value: $query.children, in: 0...max(0, 9 - query.adults - query.infants)) {
                        row("Enfants", "2 à 11 ans", query.children)
                    }
                    Stepper(value: $query.infants, in: 0...min(query.adults, max(0, 9 - query.adults - query.children))) {
                        row("Bébés", "Moins de 2 ans, sur les genoux", query.infants)
                    }
                }
                Section("Cabine") {
                    Picker("Cabine", selection: $query.cabin) {
                        ForEach(Cabin.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Voyageurs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() }.bold() } }
        }
    }

    private func row(_ title: String, _ sub: String, _ n: Int) -> some View {
        VStack(alignment: .leading) {
            Text("\(title) : \(n)")
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
    }
}
