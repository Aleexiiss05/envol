import SwiftUI

struct Filters: Equatable {
    var stops: Set<Int> = [0, 1, 2]
    var maxPrice: Double?
    var maxDuration: Double?
    var depBuckets: Set<Int> = []   // 0 nuit, 1 matin, 2 après-midi, 3 soir
    var arrBuckets: Set<Int> = []
    var excludedAirlines: Set<String> = []
    var kind = 0                    // 0 toutes, 1 classiques, 2 low-cost
    var holdBag = false
    var cabinBag = false
    var wifi = false
    var refundable = false
    var noOvernight = false
    var allowSelfTransfer = true

    static func bucket(_ m: Int) -> Int { let v = ((m % 1440) + 1440) % 1440; return v < 360 ? 0 : v < 720 ? 1 : v < 1080 ? 2 : 3 }

    func passes(_ r: FlightResult, airlines: [String: Airline]) -> Bool {
        if !stops.contains(min(r.stops, 2)) { return false }
        if let p = maxPrice, Double(r.price) > p { return false }
        if let d = maxDuration, Double(r.duration) > d { return false }
        if !depBuckets.isEmpty && !depBuckets.contains(Self.bucket(r.dep)) { return false }
        if !arrBuckets.isEmpty && !arrBuckets.contains(Self.bucket(r.arr)) { return false }
        if r.carriers.contains(where: excludedAirlines.contains) { return false }
        let low = r.flights.contains { airlines[$0.airline]?.lowcost == true }
        if kind == 1 && low { return false }
        if kind == 2 && !low { return false }
        if holdBag && !r.holdBag { return false }
        if cabinBag && !r.cabinBag { return false }
        if wifi && !r.wifi { return false }
        if refundable && r.refund < 1 { return false }
        if noOvernight && r.overnight { return false }
        if !allowSelfTransfer && r.isSelfTransfer { return false }
        return true
    }

    var activeCount: Int {
        var n = 0
        if stops.count < 3 { n += 1 }
        if maxPrice != nil { n += 1 }
        if maxDuration != nil { n += 1 }
        if !depBuckets.isEmpty { n += 1 }
        if !arrBuckets.isEmpty { n += 1 }
        if !excludedAirlines.isEmpty { n += 1 }
        if kind != 0 { n += 1 }
        n += [holdBag, cabinBag, wifi, refundable, noOvernight, !allowSelfTransfer].filter { $0 }.count
        return n
    }
}

struct DayPrice: Hashable { let date: String; let price: Int? }
struct Insight: Hashable { let level: Int; let text: String }
private struct LoadOutput { let list: [FlightResult]; let days: [DayPrice]; let insight: Insight? }

struct ResultsView: View {
    @Environment(UserData.self) private var user
    @State var query: SearchQuery
    @State private var step = 1
    @State private var outbound: FlightResult?
    @State private var results: [FlightResult] = []
    @State private var sort: SortOrder = .best
    @State private var filters = Filters()
    @State private var loading = true
    @State private var showFilters = false
    @State private var detail: FlightResult?
    @State private var strip: [DayPrice] = []
    @State private var insight: Insight?
    @State private var favTrigger = false
    private let store = FlightStore.shared

    private var leg: (from: String, to: String, date: String) {
        step == 2 ? (query.to, query.from, query.ret) : (query.from, query.to, query.dep)
    }
    private var filtered: [FlightResult] {
        let list = results.filter { filters.passes($0, airlines: store.airlines) }
        return sorted(list, by: sort)
    }
    private func sorted(_ list: [FlightResult], by s: SortOrder) -> [FlightResult] {
        switch s {
        case .best: list.sorted { $0.score < $1.score }
        case .cheap: list.sorted { ($0.price, $0.duration) < ($1.price, $1.duration) }
        case .fast: list.sorted { ($0.duration, $0.price) < ($1.duration, $1.price) }
        case .early: list.sorted { $0.dep < $1.dep }
        case .co2: list.sorted { $0.co2 < $1.co2 }
        }
    }

    var body: some View {
        List {
            Section { journey.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            Section {
                dateStrip.listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)).listRowBackground(Color.clear)
                Picker("Tri", selection: $sort) {
                    ForEach([SortOrder.best, .cheap, .fast]) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .sensoryFeedback(.selection, trigger: sort)
                if let insight {
                    Label {
                        Text(insight.text).font(.subheadline)
                    } icon: {
                        Image(systemName: insight.level < 0 ? "arrow.down.circle.fill" : insight.level > 0 ? "exclamationmark.circle.fill" : "equal.circle.fill")
                            .foregroundStyle(insight.level < 0 ? .green : insight.level > 0 ? .orange : .secondary)
                    }
                }
            }
            if loading {
                // Squelettes de chargement : la mise en page ne saute pas quand les vols arrivent
                Section {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { RoundedRectangle(cornerRadius: 8).frame(width: 30, height: 30); Text("Compagnie aérienne"); Spacer(); Text("Recommandé") }
                            HStack { Text("00:00").font(.title2); Spacer(); Text("0 h 00"); Spacer(); Text("00:00").font(.title2) }
                            HStack { Text("Bagages"); Spacer(); Text("000 €").font(.title3) }
                        }
                        .padding(.vertical, 6)
                        .redacted(reason: .placeholder)
                        .shimmering()
                    }
                }
            } else if filtered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(results.isEmpty ? "Aucun vol ce jour-là" : "Aucun vol avec ces filtres", systemImage: "airplane.circle")
                    } description: {
                        Text(results.isEmpty ? "Essayez une date voisine dans la barre ci-dessus." : "\(Fmt.plural(results.count, "vol")) existent mais ne correspondent pas à vos critères.")
                    } actions: {
                        if !results.isEmpty { Button("Réinitialiser les filtres") { filters = Filters() } }
                    }
                }
            } else {
                Section {
                    ForEach(filtered) { r in
                        FlightRow(result: r, badge: badge(r), perAdultLabel: priceLabel, showBag: user.bagIncluded, bag: store.bagCost(r),
                                  isFavorite: user.isFavorite(r.key))
                            .contentShape(Rectangle())
                            .onTapGesture { detail = r }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button { user.toggleFavorite(r); favTrigger.toggle() } label: {
                                    Label(user.isFavorite(r.key) ? "Retirer" : "Favori", systemImage: user.isFavorite(r.key) ? "heart.slash" : "heart")
                                }
                                .tint(.pink)
                            }
                            .contextMenu {
                                Button { user.toggleFavorite(r) } label: { Label(user.isFavorite(r.key) ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "heart") }
                                ShareLink(item: shareText(r)) { Label("Partager ce vol", systemImage: "square.and.arrow.up") }
                            }
                            .accessibilityAction(named: "Ajouter aux favoris") { user.toggleFavorite(r) }
                    }
                } header: {
                    Text("\(Fmt.plural(filtered.count, "vol"))\(filtered.count != results.count ? " sur \(results.count)" : "") · \(user.bagIncluded ? "bagage en soute compris" : "taxes incluses")")
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(step == 2 ? "Vol retour" : query.roundTrip ? "Vol aller" : "Votre vol")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { user.toggleAlert(query) } label: {
                    Image(systemName: user.hasAlert(query) ? "bell.fill" : "bell")
                }
                .accessibilityLabel(user.hasAlert(query) ? "Ne plus surveiller le prix" : "Surveiller le prix")
                Button { showFilters = true } label: {
                    Image(systemName: filters.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .overlay(alignment: .topTrailing) {
                            if filters.activeCount > 0 {
                                Text("\(filters.activeCount)").font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(4).background(.tint, in: Circle()).offset(x: 8, y: -8)
                            }
                        }
                }
                .accessibilityLabel("Filtres, \(filters.activeCount) actif\(filters.activeCount > 1 ? "s" : "")")
            }
        }
        .sheet(isPresented: $showFilters) {
            FiltersSheet(filters: $filters, results: results, matching: filtered.count, bagIncluded: Binding(get: { user.bagIncluded }, set: { user.bagIncluded = $0 }))
        }
        .sheet(item: $detail) { r in
            FlightDetailView(result: r, outbound: step == 2 ? outbound : nil, query: query, pendingOutbound: query.roundTrip && step == 1) {
                detail = nil
                choose(r)
            }
        }
        .sensoryFeedback(.success, trigger: favTrigger)
        .task { if user.bagIncluded != query.bagIncluded && query.bagIncluded { user.bagIncluded = true }; await load() }
        .onChange(of: user.bagIncluded) { _, _ in Task { await load() } }
        .animation(.default, value: step)
    }

    private var priceLabel: String {
        query.roundTrip ? (step == 1 ? "Aller, par adulte" : "Retour, par adulte") : "Par adulte"
    }

    // MARK: Parcours aller / retour
    /// Trajectoire : l'avion avance sur l'arc à chaque étape (même principe que le site)
    private var journey: some View {
        let steps = query.roundTrip ? ["Recherche", "Aller", "Retour", "Tarif", "Réservation"] : ["Recherche", "Vol", "Tarif", "Réservation"]
        let current = step == 2 ? 2 : 1
        let cheapest = filtered.map(\.price).min()
        let retDate = Day.format(query.ret, "dMMM")
        var details = ["\(query.from) → \(query.to)", step == 1 ? cheapest.map { "dès \(euros($0))" } ?? "" : outbound.map { Fmt.time($0.dep) } ?? ""]
        if query.roundTrip { details.append(step == 2 ? cheapest.map { "dès \(euros($0))" } ?? "" : retDate) }
        let total: Int? = step == 2 ? outbound.flatMap { o in cheapest.map { o.price + $0 } } : cheapest
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(current + 1)/\(steps.count)")
                    .font(.caption.weight(.bold)).foregroundStyle(.tint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                Text(step == 2 ? "Choisissez le retour" : query.roundTrip ? "Choisissez l'aller" : "Choisissez votre vol")
                    .font(.title3.weight(.bold))
                    .contentTransition(.opacity)
                Spacer()
                if let total {
                    Text("dès \(euros(total))").font(.headline).monospacedDigit()
                        .contentTransition(.numericText(value: Double(total)))
                }
            }
            FlightPathProgress(steps: steps, current: current, details: details)
                .frame(height: 84)
                .padding(.bottom, 30)
                .padding(.horizontal, 6)
            if step == 2, let o = outbound {
                HStack(spacing: 10) {
                    AirlineLogo(code: o.mainAirline, size: 24)
                    Text("Aller : \(Fmt.time(o.dep)) → \(Fmt.time(o.arr)) · \(euros(o.price))").font(.subheadline)
                    Spacer()
                    Button("Changer") { withAnimation(.spring(duration: 0.45)) { step = 1; outbound = nil }; Task { await load() } }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.5), value: step)
        .animation(.snappy, value: total)
    }
    enum TileState { case current, done, todo }
    private func journeyTile(title: String, from: String, to: String, date: String, state: TileState, chosen: FlightResult?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if state == .done { Image(systemName: "checkmark.circle.fill") }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(state == .current ? Color.accentColor : state == .done ? Color.green : Color.secondary)
            Text("\(from) → \(to)").font(.headline).foregroundStyle(state == .todo ? .secondary : .primary)
            if let c = chosen {
                Text("\(Fmt.time(c.dep))–\(Fmt.time(c.arr)) · \(euros(c.price))").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(Day.short(date)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(state == .current ? Color(.systemBackground) : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(state == .current ? Color.accentColor : .clear, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityHint(state == .done ? "Touchez pour changer l'aller" : "")
    }

    // MARK: Jours voisins
    private var dateStrip: some View {
        let valid = strip.compactMap(\.price)
        let minP = valid.min()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(strip, id: \.date) { item in
                        let selected = item.date == leg.date
                        Button {
                            guard item.price != nil else { return }
                            if step == 2 { query.ret = item.date } else {
                                query.dep = item.date
                                if query.roundTrip && query.ret < query.dep { query.ret = Day.add(query.dep, 7) }
                            }
                            Task { await load() }
                        } label: {
                            VStack(spacing: 2) {
                                Text(Day.format(item.date, "EEEd")).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                                Text(item.price.map(euros) ?? "—").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selected ? Color.white : item.price == minP ? Color.green : item.price == nil ? Color.secondary : Color.primary)
                            }
                            .frame(width: 76, height: 56)
                            .background(selected ? Color.accentColor : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(item.price == nil)
                        .id(item.date)
                        .accessibilityLabel("\(Day.long(item.date)), \(item.price.map { "à partir de \(euros($0))" } ?? "aucun vol")")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(leg.date, anchor: .center) }
            .onChange(of: strip.count) { _, _ in proxy.scrollTo(leg.date, anchor: .center) }
        }
    }

    // MARK: Données
    private func load() async {
        loading = true
        let (from, to, date) = leg
        let cabin = query.cabin, bag = user.bagIncluded, retLimit = query.roundTrip && step == 1 ? query.ret : nil, depMin = step == 2 ? query.dep : nil
        let output = await Task.detached(priority: .userInitiated) { () -> LoadOutput in
            let store = FlightStore.shared
            var list = store.search(from: from, to: to, date: date, cabin: cabin)
            if bag { list = list.map { var r = $0; r.price = r.fare + store.bagCost(r); return r } }
            if let mp = list.map(\.price).min(), let md = list.map(\.duration).min() {
                list = list.map { var r = $0
                    r.score = Double(r.price) / Double(mp) + 0.55 * Double(r.duration) / Double(md) + 0.12 * Double(r.stops) + (r.isSelfTransfer ? 0.2 : 0) + (r.overnight ? 0.15 : 0)
                    return r }
            }
            let days: [DayPrice] = (-3...3).map { k in
                let d = Day.add(date, k)
                let blocked = d < Day.today || (retLimit.map { d > $0 } ?? false) || (depMin.map { d < $0 } ?? false)
                return DayPrice(date: d, price: blocked ? nil : store.minPrice(from: from, to: to, date: d, cabin: cabin))
            }
            // Conseil : prix du jour comparé aux dates voisines (±15 jours)
            var win: [DayPrice] = []
            for k in stride(from: -15, through: 15, by: 3) {
                let d = Day.add(date, k)
                if d > Day.today, let p = store.minPrice(from: from, to: to, date: d, cabin: cabin) { win.append(DayPrice(date: d, price: p)) }
            }
            var info: Insight?
            let prices = win.compactMap { $0.price }
            if let cur = list.map({ $0.fare }).min(), prices.count > 2 {
                let avg = Double(prices.reduce(0, +)) / Double(prices.count)
                let ratio = Double(cur) / avg
                let note = store.seasonNote(from, to, date)
                let suffix = note.isEmpty ? "" : " Période : \(note)."
                let best = win.min { ($0.price ?? .max) < ($1.price ?? .max) }
                if ratio < 0.92 {
                    info = Insight(level: -1, text: "Prix bas : \(Int(((1 - ratio) * 100).rounded())) % de moins que les dates voisines.\(suffix)")
                } else if ratio > 1.08, let best, let bp = best.price, best.date != date {
                    info = Insight(level: 1, text: "Prix élevé. Le \(Day.format(best.date, "dMMMM")), ce trajet coûte \(euros(cur - bp)) de moins.\(suffix)")
                } else {
                    info = Insight(level: 0, text: "Prix habituel pour ces dates.\(suffix)")
                }
            }
            return LoadOutput(list: list, days: days, insight: info)
        }.value
        results = output.list
        strip = output.days
        insight = output.insight
        if Demo.screen == "detail", detail == nil { detail = sorted(output.list, by: .best).first }
        if filters.maxPrice != nil || filters.maxDuration != nil { filters.maxPrice = nil; filters.maxDuration = nil }
        loading = false
    }

    private func badge(_ r: FlightResult) -> String? {
        let all = results
        if r.price == all.map(\.price).min() { return "Le moins cher" }
        if r.key == sorted(all, by: .best).first?.key { return "Recommandé" }
        if r.duration == all.map(\.duration).min() { return "Le plus rapide" }
        return nil
    }

    private func choose(_ r: FlightResult) {
        if query.roundTrip && step == 1 {
            outbound = r
            withAnimation(.spring(duration: 0.4)) { step = 2 }
            Task { await load() }
        }
    }

    private func shareText(_ r: FlightResult) -> String {
        "\(store.city(r.from)) → \(store.city(r.to)), \(Day.long(r.date)) : \(r.flightNumbers.joined(separator: " + ")), \(Fmt.time(r.dep))–\(Fmt.time(r.arr)), \(euros(r.price)) (via Envol)"
    }
}
