import SwiftUI

/// Accueil « Vols » : même construction que la page d'accueil du site (hero, carte de recherche, hublots, petits prix).
struct SearchHomeView: View {
    @Environment(UserData.self) private var user
    @State private var query = SearchQuery()
    @State private var path: [SearchQuery] = []
    @State private var picking: PlaceField?
    @State private var showDates = false
    @State private var showPassengers = false
    @State private var destinations: [FlightStore.Destination] = []
    @State private var shake = false
    @State private var didInit = false
    @State private var forYou: [FlightStore.Destination] = []
    @State private var swapTurns = 0.0
    private let store = FlightStore.shared

    enum PlaceField: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandBar
                    hero
                    searchCard
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                    if !user.recents.isEmpty { recents.padding(.top, 28) }
                    if !forYou.isEmpty { forYouSection.padding(.top, 36) }
                    featured.padding(.top, 36)
                    deals.padding(.top, 36)
                }
                .padding(.bottom, 32)
            }
            .background(.white)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SearchQuery.self) { q in ResultsView(query: q) }
            .sheet(item: $picking) { field in
                PlacePicker(title: field == .from ? "Départ" : "Arrivée", current: field == .from ? query.from : query.to) { code in
                    if field == .from { query.from = code; loadDestinations() } else { query.to = code; showDates = true }
                }
            }
            .sheet(isPresented: $showDates) { DatesSheet(query: $query) }
            .sheet(isPresented: $showPassengers) { PassengersSheet(query: $query).presentationDetents([.fraction(0.72), .large]) }
            .task {
                if !didInit {
                    query = SearchQuery(profile: user.profile); didInit = true
                    if Demo.screen == "results" || Demo.screen == "detail" { path.append(Demo.query) }
                }
                if destinations.isEmpty { loadDestinations() }
                loadForYou()
            }
            .onChange(of: user.profile) { old, new in
                if old.homeCode != new.homeCode { query.from = new.homeCode; loadDestinations() }
                query.cabin = new.cabin; query.bagIncluded = new.bagUsually; query.directOnly = new.directPreferred
                loadForYou()
            }
        }
    }

    // MARK: En-tête (logo + salutation, comme la barre du site)
    private var brandBar: some View {
        HStack {
            BrandWordmark(size: 20)
            Spacer()
            if !user.profile.firstName.isEmpty {
                Text(String(user.profile.firstName.prefix(1)).uppercased())
                    .font(.inter(14, .semibold)).foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34).background(Theme.gray, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(user.profile.greeting).font(.inter(15, .medium)).foregroundStyle(Theme.muted)
            Text("Le ciel,\nau juste prix.").display(38).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Carte de recherche (reprend .search du site)
    private var searchCard: some View {
        VStack(spacing: 12) {
            SegmentedPicker(options: [(true, "Aller-retour"), (false, "Aller simple")], selection: $query.roundTrip)

            // Départ / arrivée : blocs gris avec bouton d'inversion au milieu
            ZStack {
                VStack(spacing: 4) {
                    placeRow("De", code: query.from, top: true) { picking = .from }
                    placeRow("À", code: query.to, top: false) { picking = .to }
                }
                Button {
                    guard !query.to.isEmpty else { return }
                    withAnimation(.spring(duration: 0.35)) { let t = query.from; query.from = query.to; query.to = t; swapTurns += 180 }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .rotationEffect(.degrees(swapTurns))
                        .frame(width: 36, height: 36)
                        .background(.white, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.field, lineWidth: 3))
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 18)
                .accessibilityLabel("Inverser départ et arrivée")
                .sensoryFeedback(.impact(weight: .light), trigger: query.from)
            }

            HStack(spacing: 4) {
                Button { showDates = true } label: {
                    field("Aller", Day.format(query.dep, "EEEdMMM"), symbol: "calendar")
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Aller : \(Day.long(query.dep))")
                if query.roundTrip {
                    Button { showDates = true } label: {
                        field("Retour", Day.format(query.ret, "EEEdMMM"), symbol: nil)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Retour : \(Day.long(query.ret))")
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))

            Button { showPassengers = true } label: {
                field("Voyageurs", "\(Fmt.plural(query.passengers, "voyageur")) · \(query.cabin.label)", symbol: "person")
            }
            .buttonStyle(PressableStyle())

            HStack(spacing: 8) {
                ChipButton(label: "Direct", on: query.directOnly) { withAnimation(.snappy) { query.directOnly.toggle() } }
                ChipButton(label: "Bagage en soute", on: query.bagIncluded) { withAnimation(.snappy) { query.bagIncluded.toggle() } }
                Spacer(minLength: 0)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold))
                    Text("Rechercher")
                }
            }
            .buttonStyle(PillButtonStyle(fullWidth: true))
            .sensoryFeedback(.error, trigger: shake)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.06), radius: 24, y: 10)
        .animation(.spring(duration: 0.35), value: query.roundTrip)
    }

    private func placeRow(_ label: String, code: String, top: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label).font(.inter(13, .medium)).foregroundStyle(Theme.faint).frame(width: 22, alignment: .leading)
                if code.isEmpty {
                    Text("Où allez-vous ?").font(.inter(17, .medium)).foregroundStyle(Theme.faint)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(store.city(code)).font(.inter(17, .semibold)).foregroundStyle(Theme.ink)
                            Text(code).font(.inter(13, .semibold)).foregroundStyle(Theme.muted)
                        }
                        Text(store.subtitle(code)).font(.inter(12)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                }
                Spacer(minLength: 56)
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background(Theme.field, in: UnevenRoundedRectangle(
                topLeadingRadius: top ? Theme.radiusM : 6, bottomLeadingRadius: top ? 6 : Theme.radiusM,
                bottomTrailingRadius: top ? 6 : Theme.radiusM, topTrailingRadius: top ? Theme.radiusM : 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(code.isEmpty ? "\(label == "De" ? "Départ" : "Arrivée") : à choisir" : "\(label == "De" ? "Départ" : "Arrivée") : \(store.city(code)), \(code)")
    }

    private func field(_ label: String, _ value: String, symbol: String?) -> some View {
        HStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.faint) }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.inter(12, .medium)).foregroundStyle(Theme.faint)
                Text(value).font(.inter(15, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
    }

    private func submit() {
        guard !query.to.isEmpty, store.expand(query.from) != store.expand(query.to) else { shake.toggle(); picking = .to; return }
        if query.roundTrip && query.ret < query.dep { query.ret = Day.add(query.dep, 7) }
        user.remember(query)
        user.bagIncluded = query.bagIncluded
        path.append(query)
    }

    // MARK: Sections
    private func sectionHead(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).display(22, .bold).foregroundStyle(Theme.ink)
            if let subtitle { Text(subtitle).font(.inter(14)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .accessibilityAddTraits(.isHeader)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHead("Recherches récentes")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(user.recents, id: \.self) { r in
                        Button {
                            query = r
                            if query.dep < Day.today { query.dep = Day.add(Day.today, 14); query.ret = Day.add(query.dep, 7) }
                            submit()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13)).foregroundStyle(Theme.faint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(store.city(r.from)) → \(store.city(r.to))").font(.inter(14, .semibold)).foregroundStyle(Theme.ink)
                                    Text(Day.short(r.dep)).font(.inter(12)).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(.horizontal, 14).frame(height: 50)
                            .background(Theme.field, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHead("Pour vous", forYouSubtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(forYou) { d in
                        Button { open(d) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                PlacePhoto(code: d.code, width: 600)
                                    .frame(width: 240, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(store.city(d.code)).font(.inter(16, .semibold)).foregroundStyle(Theme.ink)
                                        Text("\(Day.short(d.date)) · \(Fmt.duration(d.duration))").font(.inter(13)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text(euros(d.price)).font(.inter(16, .bold)).foregroundStyle(Theme.ink)
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(width: 240)
                        }
                        .buttonStyle(PressableStyle())
                        .scrollTransition { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.7)
                        }
                        .accessibilityLabel("\(store.city(d.code)), dès \(euros(d.price))")
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
    private var forYouSubtitle: String {
        let vibes = user.profile.vibes.map(\.label).sorted().joined(separator: ", ").lowercased()
        let budget = user.profile.budget >= 1500 ? "" : " · moins de \(euros(user.profile.budget))"
        let head: String = vibes.isEmpty ? "Selon vos habitudes" : vibes.prefix(1).uppercased() + String(vibes.dropFirst())
        return head + budget
    }
    private func loadForYou() {
        let p = user.profile
        Task.detached(priority: .utility) {
            let list = FlightStore.shared.suggestions(for: p, limit: 8)
            await MainActor.run { withAnimation(.smooth) { forYou = list } }
        }
    }

    /// Bande grise « Destinations à la une » avec les hublots, comme sur le site
    private var featured: some View {
        let picks = featuredPicks()
        return VStack(alignment: .leading, spacing: 16) {
            sectionHead("Destinations à la une", "Depuis \(store.city(query.from)), les meilleurs prix des prochaines semaines")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(picks) { d in
                        Button { open(d) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Porthole(code: d.code).frame(width: 136)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(store.city(d.code)).font(.inter(16, .semibold)).foregroundStyle(Theme.ink)
                                    Text("dès \(euros(d.price))").font(.inter(14)).foregroundStyle(Theme.muted)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(store.city(d.code)), dès \(euros(d.price))")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 24)
        .background(Theme.gray)
    }

    private var deals: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHead("Petits prix", "Au départ de \(store.city(query.from))")
            VStack(spacing: 8) {
                ForEach(destinations.prefix(8)) { d in
                    Button { open(d) } label: {
                        HStack(spacing: 12) {
                            PlacePhoto(code: d.code, width: 200).frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.city(d.code)).font(.inter(16, .semibold)).foregroundStyle(Theme.ink)
                                Text("\(store.country(d.code)) · \(Fmt.duration(d.duration))\(d.direct ? " · direct" : "")").font(.inter(13)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(euros(d.price)).font(.inter(16, .bold)).foregroundStyle(Theme.ink)
                                Text(Day.short(d.date)).font(.inter(12)).foregroundStyle(Theme.faint)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                        .padding(10)
                        .background(Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func featuredPicks() -> [FlightStore.Destination] {
        let home = store.country(query.from)
        var picks: [FlightStore.Destination] = []
        let candidates = destinations.filter { store.country($0.code) != home && (store.airportByCode[$0.airport]?.pop ?? 0) >= 7 }
            .sorted { $0.duration > $1.duration }.prefix(22).sorted { $0.price < $1.price }
        for d in candidates where !picks.contains(where: { store.km($0.airport, d.airport) < 2500 }) {
            picks.append(d)
            if picks.count == 5 { break }
        }
        return picks
    }

    private func loadDestinations() {
        let origin = query.from
        Task.detached(priority: .userInitiated) {
            let dates = (7..<57).map { Day.add(Day.today, $0) }
            let list = FlightStore.shared.cheapestDestinations(from: origin, dates: dates)
            await MainActor.run { destinations = list }
        }
    }

    private func open(_ d: FlightStore.Destination) {
        query.to = d.code
        query.dep = d.date
        query.ret = Day.add(d.date, 7)
        submit()
    }
}
