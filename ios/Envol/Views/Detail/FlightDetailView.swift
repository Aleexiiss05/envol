import SwiftUI

struct Fare: Identifiable, Hashable {
    let name: String
    let price: Int
    let includes: [(Bool, String)]
    var recommended = false
    var id: String { name }
    static func == (a: Fare, b: Fare) -> Bool { a.name == b.name }
    func hash(into h: inout Hasher) { h.combine(name) }
}

struct FlightDetailView: View {
    let result: FlightResult
    let outbound: FlightResult?
    let query: SearchQuery
    let pendingOutbound: Bool
    let onChoose: () -> Void

    @Environment(UserData.self) private var user
    @Environment(\.dismiss) private var dismiss
    @State private var fareIndex = 0
    @State private var showBooking = false
    private let store = FlightStore.shared

    private var legs: [FlightResult] { outbound.map { [$0, result] } ?? [result] }
    private var fares: [Fare] {
        let base = legs.reduce(0) { $0 + $1.price }
        let n = legs.count
        let low = legs.contains { $0.flights.contains { store.airlines[$0.airline]?.lowcost == true } }
        let hold = legs.allSatisfy(\.holdBag), cab = legs.allSatisfy(\.cabinBag)
        if low {
            return [
                Fare(name: "Basic", price: base, includes: [(true, "Petit sac sous le siège"), (cab, "Bagage cabine 10 kg"), (hold, "Bagage en soute"), (false, "Modification")]),
                Fare(name: "Regular", price: base + 28 * n, includes: [(true, "Petit sac"), (true, "Bagage cabine 10 kg"), (true, "Siège au choix"), (false, "Modification")], recommended: true),
                Fare(name: "Plus", price: base + 62 * n, includes: [(true, "Bagage cabine 10 kg"), (true, "Bagage soute 23 kg"), (true, "Embarquement prioritaire"), (true, "Modification gratuite")]),
            ]
        }
        return [
            Fare(name: "Light", price: base, includes: [(cab, "Bagage cabine 12 kg"), (hold, "Bagage soute 23 kg"), (false, "Modification"), (false, "Remboursement")]),
            Fare(name: "Standard", price: Int(Double(base) * 1.16) + (hold ? 0 : 20 * n), includes: [(true, "Bagage cabine 12 kg"), (true, "Bagage soute 23 kg"), (true, "Choix du siège"), (true, "Modification avec frais")], recommended: true),
            Fare(name: "Flex", price: Int(Double(base) * 1.45) + 30 * n, includes: [(true, "Bagage cabine 12 kg"), (true, "Deux bagages en soute"), (true, "Modification gratuite"), (true, "Remboursable")]),
        ]
    }
    private var total: Int { query.total(fares[fareIndex].price) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(legs.enumerated()), id: \.offset) { i, r in
                    Section { itinerary(r) } header: {
                        Text(legs.count > 1 ? (i == 0 ? "Aller · \(Day.long(r.date))" : "Retour · \(Day.long(r.date))") : Day.long(r.date)).textCase(nil)
                    }
                    Section { facts(r) }
                }
                if !pendingOutbound {
                    Section("Tarif") {
                        Picker("Tarif", selection: $fareIndex) {
                            ForEach(fares.indices, id: \.self) { i in Text(fares[i].name).tag(i) }
                        }
                        .pickerStyle(.segmented)
                        .sensoryFeedback(.selection, trigger: fareIndex)
                        ForEach(Array(fares[fareIndex].includes.enumerated()), id: \.offset) { _, item in
                            Label(item.1, systemImage: item.0 ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(item.0 ? Color.primary : Color.secondary)
                                .symbolRenderingMode(.multicolor)
                        }
                    }
                    Section("Détail du prix") {
                        LabeledContent("\(Fmt.plural(query.adults, "adulte")) × \(euros(fares[fareIndex].price))", value: euros(fares[fareIndex].price * query.adults))
                        if query.children > 0 { LabeledContent("\(Fmt.plural(query.children, "enfant")) (−25 %)", value: euros(Int(Double(fares[fareIndex].price) * 0.75) * query.children)) }
                        if query.infants > 0 { LabeledContent("\(Fmt.plural(query.infants, "bébé")) (10 %)", value: euros(Int(Double(fares[fareIndex].price) * 0.1) * query.infants)) }
                        LabeledContent("Frais Envol", value: euros(0)).foregroundStyle(.green)
                        LabeledContent { Text(euros(total)).bold() } label: { Text("Total, payé à la compagnie").bold() }
                    }
                } else {
                    Section { Text("Prix de l'aller seul. Vous choisirez ensuite le retour ; le total sera recalculé.").font(.inter(.footnote)).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(outbound != nil ? "Votre aller-retour" : "Détail du vol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { user.toggleFavorite(result) } label: { Image(systemName: user.isFavorite(result.key) ? "heart.fill" : "heart") }
                        .tint(.pink)
                        .accessibilityLabel(user.isFavorite(result.key) ? "Retirer des favoris" : "Ajouter aux favoris")
                        .sensoryFeedback(.success, trigger: user.isFavorite(result.key))
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pendingOutbound ? "Aller, par adulte" : "Total · \(Fmt.plural(query.passengers, "voyageur"))").font(.inter(.caption)).foregroundStyle(.secondary)
                        Text(euros(pendingOutbound ? result.price : total)).font(.inter(.title2, .bold)).monospacedDigit()
                    }
                    Spacer()
                    Button {
                        if pendingOutbound { onChoose() } else { showBooking = true }
                    } label: {
                        HStack(spacing: 8) { Text(pendingOutbound ? "Choisir cet aller" : "Continuer"); Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold)) }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .padding()
                .background(.bar)
            }
            .navigationDestination(isPresented: $showBooking) {
                BookingView(legs: legs, fare: fares[fareIndex], query: query, total: total)
            }
        }
    }

    private func itinerary(_ r: FlightResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(r.from) → \(r.to)").font(.inter(.title3, .bold))
                Spacer()
                Text("\(Fmt.duration(r.duration)) · \(r.stops == 0 ? "direct" : Fmt.plural(r.stops, "escale"))").font(.inter(.subheadline)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
            if r.isSelfTransfer {
                warning("Deux billets séparés : récupérez vos bagages et repassez l'enregistrement. En cas de retard, la seconde compagnie n'est pas tenue de vous réacheminer.")
            }
            if let transit = r.layovers.map({ $0.at }).first(where: { ["JFK", "MIA", "LAX", "SFO", "YUL", "LHR", "LGW"].contains($0) }) {
                warning(store.country(transit) == "États-Unis" ? "Escale aux États-Unis : ESTA obligatoire, même sans quitter l'aéroport."
                        : store.country(transit) == "Canada" ? "Escale au Canada : AVE obligatoire." : "Escale au Royaume-Uni : ETA ou visa de transit selon votre nationalité.")
            }
            ForEach(r.segments) { s in
                switch s.kind {
                case .leg(let leg):
                    legView(leg, s, r)
                case .layover(let at, let m, let st):
                    Label("\(st ? "Changement de billet" : "Escale") à \(store.city(at)) (\(at)) · \(Fmt.duration(m))\(m >= 420 ? " · nuit sur place" : "")",
                          systemImage: m >= 420 ? "moon.zzz" : "clock")
                        .font(.inter(.footnote))
                        .foregroundStyle(m >= 420 || st ? Color.orange : Color.secondary)
                        .padding(.vertical, 8).padding(.leading, 22)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func legView(_ leg: Leg, _ s: Segment, _ r: FlightResult) -> some View {
        let depLocal = s.startUTC + Int(store.tz(leg.from) * 60)
        let arrLocal = s.endUTC + Int(store.tz(leg.to) * 60)
        return VStack(alignment: .leading, spacing: 8) {
            point(Fmt.time(depLocal), leg.from, Day.add(r.date, Int(floor(Double(depLocal) / 1440))))
            HStack(spacing: 10) {
                Rectangle().fill(.quaternary).frame(width: 2).padding(.leading, 4)
                AirlineLogo(code: leg.airline, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(store.airlines[leg.airline]?.name ?? leg.airline) · \(Fmt.flight(leg.flightNumber))").font(.inter(.subheadline, .medium))
                    Text("\(leg.aircraft) · \(Fmt.duration(leg.minutes)) · \(Int(leg.km).formatted()) km").font(.inter(.caption)).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
            point(Fmt.time(arrLocal), leg.to, Day.add(r.date, Int(floor(Double(arrLocal) / 1440))))
        }
        .accessibilityElement(children: .combine)
    }

    private func point(_ time: String, _ code: String, _ date: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 10, height: 10)
            Text(time).font(.inter(.headline)).monospacedDigit()
            Text(code).font(.inter(.subheadline, .bold))
            Text(store.airportByCode[code]?.name ?? "").font(.inter(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(Day.format(date, "dMMM")).font(.inter(.caption)).foregroundStyle(.secondary)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.inter(.footnote))
            .foregroundStyle(.orange)
            .padding(10)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 10)
    }

    private func facts(_ r: FlightResult) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                fact("suitcase.rolling", r.cabinBag ? "Inclus" : "Petit sac seulement", "Bagage cabine")
                fact("suitcase", r.holdBag ? "1 × 23 kg" : "En option", "Bagage en soute")
            }
            GridRow {
                fact("fork.knife", r.meal ? "Inclus" : "Payant", "Repas")
                fact("wifi", r.wifi ? "Disponible" : "Non", "Wi-Fi")
            }
            GridRow {
                fact("leaf", "\(r.co2) kg CO₂", "Par passager")
                fact("clock.badge.checkmark", "\(r.ontime) %", "Ponctualité")
            }
        }
        .padding(.vertical, 4)
    }

    private func fact(_ symbol: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.inter(.subheadline, .medium))
                Text(label).font(.inter(.caption)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Accompagnement jusqu'au site de la compagnie

struct BookingView: View {
    let legs: [FlightResult]
    let fare: Fare
    let query: SearchQuery
    let total: Int
    @Environment(\.openURL) private var openURL
    @State private var checks = Set<Int>()
    @State private var opened = false
    private let store = FlightStore.shared

    private var tickets: [(airline: String, label: String)] {
        var out: [(airline: String, label: String)] = []
        let self_ = legs.contains(where: \.isSelfTransfer)
        for (i, r) in legs.enumerated() {
            for (j, f) in r.flights.enumerated() {
                let label = (i == 0 ? "Aller" : "Retour") + (r.isSelfTransfer ? " · billet \(j + 1)/\(r.flights.count)" : "")
                if !self_, let k = out.firstIndex(where: { $0.airline == f.airline }) { out[k].label = "Aller et retour" }
                else { out.append((f.airline, label)) }
            }
        }
        return out
    }
    private var checklist: [(String, String)] {
        var items = [
            ("Noms identiques au passeport", "Prénoms et nom exactement comme sur le document. Une erreur peut coûter un nouveau billet."),
            ("Document de voyage valide", "Passeport valide au moins six mois après le retour pour de nombreuses destinations."),
            ("Formalités d'entrée", visaNote),
            ("Bagages", "Tarif \(fare.name). Un bagage ajouté à l'aéroport coûte souvent deux fois plus cher."),
        ]
        if tickets.count > 1 { items.append(("\(tickets.count) réservations distinctes", "Vous réserverez \(tickets.count) billets sur \(tickets.count) sites.")) }
        return items
    }
    private var visaNote: String {
        switch store.country(legs[0].to) {
        case "États-Unis": "Autorisation ESTA obligatoire, au moins 72 h avant le départ."
        case "Canada": "Autorisation de voyage électronique (AVE) obligatoire."
        case "Royaume-Uni": "Autorisation ETA britannique requise pour de nombreux voyageurs."
        case "Australie": "Visa électronique (eVisitor ou ETA) obligatoire."
        default: "Vérifiez les formalités sur diplomatie.gouv.fr (Conseils aux voyageurs)."
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(legs.enumerated()), id: \.offset) { i, r in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.from).font(.inter(.title2, .bold))
                            Text("\(Fmt.time(r.dep)) · \(Day.format(r.date, "dMMM"))").font(.inter(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Image(systemName: "airplane").foregroundStyle(.secondary)
                            Text("\(i == 0 ? "Aller" : "Retour") · \(Fmt.duration(r.duration))").font(.inter(.caption2)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(r.to).font(.inter(.title2, .bold))
                            Text(Fmt.time(r.arr) + (r.dayOffset > 0 ? " (+\(r.dayOffset))" : "")).font(.inter(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent { Text(euros(total)).font(.inter(.title3, .bold)) } label: { Text("Total estimé · \(Fmt.plural(query.passengers, "voyageur")) · \(fare.name)") }
            } header: { Text("Récapitulatif").textCase(nil) }

            Section {
                ForEach(checklist.indices, id: \.self) { i in
                    Button {
                        if checks.contains(i) { checks.remove(i) } else { checks.insert(i) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: checks.contains(i) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checks.contains(i) ? Color.green : Color.secondary).font(.inter(.title3))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(checklist[i].0).font(.inter(.body, .medium))
                                Text(checklist[i].1).font(.inter(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: checks.contains(i))
                    .accessibilityAddTraits(checks.contains(i) ? .isSelected : [])
                }
            } header: { Text("Avant de réserver").textCase(nil) } footer: {
                Text("\(checks.count) sur \(checklist.count) vérifiés")
            }

            Section {
                ForEach(tickets.indices, id: \.self) { i in
                    let t = tickets[i]
                    Button {
                        if let url = URL(string: store.airlines[t.airline]?.site ?? "") { openURL(url); opened = true }
                    } label: {
                        HStack(spacing: 12) {
                            AirlineLogo(code: t.airline, size: 32)
                            VStack(alignment: .leading) {
                                Text("Réserver sur \(store.airlines[t.airline]?.siteHost ?? t.airline)").font(.inter(.body, .semibold))
                                Text(t.label).font(.inter(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
                ShareLink(item: calendarFile, preview: SharePreview("Vols Envol", image: Image(systemName: "calendar"))) {
                    Label("Ajouter au calendrier", systemImage: "calendar.badge.plus")
                }
            } header: { Text("Réservation chez la compagnie").textCase(nil) } footer: {
                Text("Vous payez directement la compagnie ; Envol n'a pas accès à vos données bancaires. Démonstration : les liens ouvrent l'accueil du site de la compagnie.")
            }
        }
        .navigationTitle("Réservation")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: opened)
    }

    /// Fichier .ics avec rappel 24 h avant chaque vol
    private var calendarFile: URL {
        func stamp(_ date: String, _ minutes: Int, _ tz: Double) -> String {
            let d = Day.date(date).addingTimeInterval(Double(minutes - Int(tz * 60)) * 60)
            let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return f.string(from: d)
        }
        let events = legs.enumerated().map { i, r in
            """
            BEGIN:VEVENT
            UID:envol-\(abs(r.key.hashValue))-\(i)@envol.app
            DTSTAMP:\(stamp(Day.today, 0, 0))
            DTSTART:\(stamp(r.date, r.dep, store.tz(r.from)))
            DTEND:\(stamp(r.date, r.arr, store.tz(r.to)))
            SUMMARY:Vol \(r.flightNumbers.joined(separator: " + ")) \(r.from) → \(r.to)
            LOCATION:\(store.airportByCode[r.from]?.name ?? r.from)
            BEGIN:VALARM
            TRIGGER:-PT24H
            ACTION:DISPLAY
            DESCRIPTION:Enregistrement en ligne
            END:VALARM
            END:VEVENT
            """
        }.joined(separator: "\n")
        let ics = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Envol//FR\n\(events)\nEND:VCALENDAR".replacingOccurrences(of: "\n", with: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("envol-\(legs[0].from)-\(legs[0].to).ics")
        try? ics.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
