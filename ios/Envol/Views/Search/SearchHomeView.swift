import SwiftUI

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
    private let store = FlightStore.shared

    enum PlaceField: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                    searchCard
                    if !user.recents.isEmpty { recents }
                    if !forYou.isEmpty { forYouSection }
                    featured
                    deals
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vols")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SearchQuery.self) { q in ResultsView(query: q) }
            .sheet(item: $picking) { field in
                PlacePicker(title: field == .from ? "Départ" : "Arrivée", current: field == .from ? query.from : query.to) { code in
                    if field == .from { query.from = code; loadDestinations() } else { query.to = code; showDates = true }
                }
            }
            .sheet(isPresented: $showDates) { DatesSheet(query: $query) }
            .sheet(isPresented: $showPassengers) { PassengersSheet(query: $query).presentationDetents([.medium]) }
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

    // MARK: En-tête personnalisé
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.profile.greeting).font(.largeTitle.weight(.bold))
            Text("Où allons-nous au départ de \(store.city(query.from)) ?").font(.title3).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .accessibilityAddTraits(.isHeader)
    }

    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pour vous").font(.title3.weight(.bold))
                Text(forYouSubtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(forYou) { d in
                        Button { open(d) } label: {
                            ZStack(alignment: .bottomLeading) {
                                PlacePhoto(code: d.code, width: 600).frame(width: 260, height: 190).clipped()
                                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.city(d.code)).font(.title3.weight(.bold))
                                    Text("dès \(euros(d.price)) · \(Day.short(d.date))").font(.subheadline)
                                }
                                .foregroundStyle(.white).padding(14)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        .scrollTransition { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.92).opacity(phase.isIdentity ? 1 : 0.7)
                        }
                        .accessibilityLabel("\(store.city(d.code)), dès \(euros(d.price))")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
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

    // MARK: Formulaire
    private var searchCard: some View {
        VStack(spacing: 0) {
            Picker("Type de voyage", selection: $query.roundTrip) {
                Text("Aller-retour").tag(true)
                Text("Aller simple").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(12)

            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    placeRow("Départ", code: query.from) { picking = .from }
                    Divider().padding(.leading, 16)
                    placeRow("Arrivée", code: query.to) { picking = .to }
                }
                Button {
                    guard !query.to.isEmpty else { return }
                    withAnimation(.spring(duration: 0.35)) { let t = query.from; query.from = query.to; query.to = t }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.body.weight(.semibold))
                        .frame(width: 38, height: 38).background(.background, in: Circle())
                        .overlay(Circle().strokeBorder(.quaternary))
                }
                .padding(.trailing, 16)
                .accessibilityLabel("Inverser départ et arrivée")
                .sensoryFeedback(.impact(weight: .light), trigger: query.from)
            }
            Divider().padding(.leading, 16)
            Button { showDates = true } label: {
                HStack {
                    field("Aller", Day.format(query.dep, "EEEdMMM"))
                    if query.roundTrip {
                        Divider().frame(height: 36)
                        field("Retour", Day.format(query.ret, "EEEdMMM"))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(query.roundTrip ? "Dates : aller \(Day.long(query.dep)), retour \(Day.long(query.ret))" : "Date : \(Day.long(query.dep))")
            Divider().padding(.leading, 16)
            Button { showPassengers = true } label: {
                field("Voyageurs", "\(Fmt.plural(query.passengers, "voyageur")) · \(query.cabin.label)")
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 16)
            Toggle("Vols directs uniquement", isOn: $query.directOnly).padding(.horizontal, 16).padding(.vertical, 6)
            Toggle("Bagage en soute inclus", isOn: $query.bagIncluded).padding(.horizontal, 16).padding(.vertical, 6)
            Button(action: submit) {
                Label("Rechercher", systemImage: "magnifyingglass").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(12)
            .sensoryFeedback(.error, trigger: shake)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 8)
    }

    private func placeRow(_ label: String, code: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if code.isEmpty {
                    Text("Où allez-vous ?").font(.title3).foregroundStyle(.tertiary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(code).font(.title3.weight(.bold))
                        Text(store.city(code)).font(.title3)
                    }
                    Text(store.subtitle(code)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(code.isEmpty ? "\(label) : à choisir" : "\(label) : \(store.city(code)), \(code)")
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        guard !query.to.isEmpty, store.expand(query.from) != store.expand(query.to) else { shake.toggle(); picking = .to; return }
        if query.roundTrip && query.ret < query.dep { query.ret = Day.add(query.dep, 7) }
        user.remember(query)
        user.bagIncluded = query.bagIncluded
        path.append(query)
    }

    // MARK: Récentes
    private var recents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recherches récentes").font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(user.recents, id: \.self) { r in
                        Button {
                            query = r
                            if query.dep < Day.today { query.dep = Day.add(Day.today, 14); query.ret = Day.add(query.dep, 7) }
                            submit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(store.city(r.from)) → \(store.city(r.to))").font(.subheadline.weight(.semibold))
                                Text(Day.short(r.dep)).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Hublots & petits prix
    private var featured: some View {
        let picks = featuredPicks()
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Destinations à la une").font(.title3.weight(.bold))
                Text("Au départ de \(store.city(query.from)), meilleurs prix des prochaines semaines").font(.subheadline).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(picks) { d in
                        Button { open(d) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Porthole(code: d.code).frame(width: 150)
                                Text(store.city(d.code)).font(.headline)
                                Text("dès \(euros(d.price))").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(store.city(d.code)), dès \(euros(d.price))")
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var deals: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Petits prix au départ de \(store.city(query.from))").font(.title3.weight(.bold))
            VStack(spacing: 0) {
                ForEach(Array(destinations.prefix(8).enumerated()), id: \.element.id) { i, d in
                    if i > 0 { Divider().padding(.leading, 80) }
                    Button { open(d) } label: {
                        HStack(spacing: 12) {
                            PlacePhoto(code: d.code, width: 200).frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.city(d.code)).font(.body.weight(.semibold))
                                Text("\(store.country(d.code)) · \(Fmt.duration(d.duration))\(d.direct ? " · direct" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(euros(d.price)).font(.body.weight(.bold))
                                Text(Day.short(d.date)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
