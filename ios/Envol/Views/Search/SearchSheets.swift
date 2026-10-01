import SwiftUI

// MARK: - Choix d'un aéroport (recherche, clavier, VoiceOver)

struct PlacePicker: View {
    let title: String
    let current: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    private let store = FlightStore.shared

    var body: some View {
        let places = store.searchPlaces(text)
        VStack(spacing: 0) {
            SheetHeader(title: title)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
                TextField("Ville, aéroport ou code", text: $text)
                    .font(.inter(16)).autocorrectionDisabled().focused($focused).submitLabel(.search)
                    .onSubmit { if let first = places.first { pick(first) } }
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Theme.faint, in: Circle())
                    }
                    .accessibilityLabel("Effacer")
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(Theme.gray, in: Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if places.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "Aucun résultat", text: "Essayez le nom d'une ville ou un code à trois lettres, comme LIS.")
                    }
                    ForEach(places, id: \.self) { code in
                        let on = code == current
                        Button { pick(code) } label: {
                            HStack(spacing: 12) {
                                Text(code).font(.inter(13, .bold)).foregroundStyle(on ? Color.white : Theme.ink)
                                    .frame(width: 46, height: 34)
                                    .background(on ? Theme.accent : Theme.gray, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(store.city(code)).font(.inter(16, .medium)).foregroundStyle(Theme.ink)
                                    Text(store.subtitle(code)).font(.inter(13)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer()
                                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(store.city(code)), \(code), \(store.subtitle(code))")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .envolSheet()
        .onAppear { focused = true }
    }

    private func pick(_ code: String) {
        onPick(code)
        dismiss()
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
        VStack(spacing: 0) {
            SheetHeader(title: "Dates", subtitle: query.to.isEmpty ? nil : "\(store.city(query.from)) → \(store.city(query.to))")
            if query.roundTrip {
                SegmentedPicker(options: [(false, "Aller · \(Day.short(query.dep))"), (true, "Retour · \(Day.short(query.ret))")], selection: $pickingReturn)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
            HStack(spacing: 0) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "J", "V", "S", "D"][i]).font(.inter(12, .semibold)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.gray2).frame(height: 1) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(months, id: \.self) { m in monthView(m) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            VStack(spacing: 10) {
                if !query.to.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.good).frame(width: 6, height: 6)
                        Text("Prix le plus bas par adulte · en vert, les jours les moins chers")
                    }
                    .font(.inter(12)).foregroundStyle(Theme.muted)
                }
                Button { dismiss() } label: {
                    Text(query.roundTrip ? "\(Day.short(query.dep)) – \(Day.short(query.ret)) · Valider" : "\(Day.short(query.dep)) · Valider")
                }
                .buttonStyle(PillButtonStyle(fullWidth: true))
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
            .background(.white)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .envolSheet()
        .task(id: pickingReturn) { await loadPrices() }
    }

    private func monthView(_ first: String) -> some View {
        let offset = Day.weekday(first)
        let count = Day.daysInMonth(first)
        let days = (0..<count).map { Day.add(first, $0) }
        let monthPrices = days.compactMap { prices[$0] }.sorted()
        let cheapLimit = monthPrices.isEmpty ? 0 : monthPrices[monthPrices.count / 3]
        return VStack(alignment: .leading, spacing: 10) {
            Text(Day.format(first, "MMMMyyyy").capitalized).font(.inter(17, .semibold)).foregroundStyle(Theme.ink).padding(.leading, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 50) }
                ForEach(days, id: \.self) { d in dayCell(d, cheap: (prices[d] ?? .max) <= cheapLimit) }
            }
        }
    }

    private func dayCell(_ d: String, cheap: Bool) -> some View {
        let disabled = d < Day.today || (pickingReturn && d < query.dep)
        let isDep = d == query.dep
        let isRet = query.roundTrip && d == query.ret
        let selected = isDep || isRet
        let inRange = query.roundTrip && d > query.dep && d < query.ret
        return Button {
            if pickingReturn { query.ret = d }
            else {
                query.dep = d
                if query.roundTrip { if query.ret < d { query.ret = Day.add(d, 7) }; withAnimation(.snappy) { pickingReturn = true } }
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(Day.dayOfMonth(d))").font(.inter(16, selected ? .semibold : .regular))
                if let p = prices[d], !disabled {
                    Text(euros(p)).font(.inter(10, cheap ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : cheap ? Theme.good : Theme.faint)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(disabled ? Theme.faint.opacity(0.4) : selected ? Color.white : Theme.ink)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isDep ? Theme.ink : Theme.accent).padding(.horizontal, 2)
                } else if inRange {
                    Rectangle().fill(Theme.accentBg)
                }
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
        withAnimation(.easeOut(duration: 0.25)) { prices = result }
    }
}

// MARK: - Voyageurs et cabine

struct PassengersSheet: View {
    @Binding var query: SearchQuery
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Voyageurs")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnvolSection(fill: Theme.gray) {
                        EnvolStepper(title: "Adultes", subtitle: "12 ans et plus", value: $query.adults, range: 1...max(1, 9 - query.children - query.infants))
                        RowDivider()
                        EnvolStepper(title: "Enfants", subtitle: "2 à 11 ans", value: $query.children, range: 0...max(0, 9 - query.adults - query.infants))
                        RowDivider()
                        EnvolStepper(title: "Bébés", subtitle: "Moins de 2 ans, sur les genoux", value: $query.infants, range: 0...min(query.adults, max(0, 9 - query.adults - query.children)))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cabine").font(.inter(13, .semibold)).foregroundStyle(Theme.muted).padding(.leading, 6)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(Cabin.allCases) { c in
                                let on = query.cabin == c
                                Button { withAnimation(.snappy) { query.cabin = c } } label: {
                                    HStack {
                                        Text(c.label).font(.inter(15, on ? .semibold : .medium)).foregroundStyle(on ? Theme.accent : Theme.ink)
                                        Spacer()
                                        if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent) }
                                    }
                                    .padding(.horizontal, 14).frame(height: 50)
                                    .background(on ? Color.white : Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            Button { dismiss() } label: { Text("Valider · \(Fmt.plural(query.passengers, "voyageur"))") }
                .buttonStyle(PillButtonStyle(fullWidth: true))
                .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .envolSheet()
        .sensoryFeedback(.selection, trigger: query.cabin)
    }
}
