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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(legs.enumerated()), id: \.offset) { i, r in
                        EnvolSection(title: legs.count > 1 ? (i == 0 ? "Aller · \(Day.long(r.date))" : "Retour · \(Day.long(r.date))") : Day.long(r.date).capitalized) {
                            itinerary(r).padding(16)
                            RowDivider(inset: 16)
                            facts(r).padding(16)
                        }
                    }
                    if !pendingOutbound {
                        EnvolSection(title: "Tarif") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 8) {
                                    ForEach(fares.indices, id: \.self) { i in fareTile(i) }
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(fares[fareIndex].includes.enumerated()), id: \.offset) { _, item in
                                        HStack(spacing: 10) {
                                            Image(systemName: item.0 ? "checkmark" : "xmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(item.0 ? Theme.good : Theme.faint)
                                                .frame(width: 20, height: 20)
                                                .background((item.0 ? Theme.good : Theme.faint).opacity(0.1), in: Circle())
                                            Text(item.1).font(.inter(14)).foregroundStyle(item.0 ? Theme.ink : Theme.faint)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("\(item.1) : \(item.0 ? "inclus" : "non inclus")")
                                    }
                                }
                                .id(fareIndex)
                                .transition(.opacity)
                            }
                            .padding(14)
                            .animation(.smooth(duration: 0.25), value: fareIndex)
                            .sensoryFeedback(.selection, trigger: fareIndex)
                        }
                        EnvolSection(title: "Détail du prix") {
                            VStack(spacing: 10) {
                                priceLine("\(Fmt.plural(query.adults, "adulte")) × \(euros(fares[fareIndex].price))", euros(fares[fareIndex].price * query.adults))
                                if query.children > 0 { priceLine("\(Fmt.plural(query.children, "enfant")) (−25 %)", euros(Int(Double(fares[fareIndex].price) * 0.75) * query.children)) }
                                if query.infants > 0 { priceLine("\(Fmt.plural(query.infants, "bébé")) (10 %)", euros(Int(Double(fares[fareIndex].price) * 0.1) * query.infants)) }
                                priceLine("Frais Envol", "0 €", color: Theme.good)
                                Rectangle().fill(Theme.gray2).frame(height: 1)
                                HStack {
                                    Text("Total, payé à la compagnie").font(.inter(15, .semibold))
                                    Spacer()
                                    Text(euros(total)).font(.inter(17, .bold)).monospacedDigit()
                                        .contentTransition(.numericText(value: Double(total)))
                                }
                                .foregroundStyle(Theme.ink)
                            }
                            .padding(16)
                            .animation(.snappy, value: total)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                                .frame(width: 22, height: 22).background(Theme.accentBg, in: Circle())
                            Text("Prix de l'aller seul. Vous choisirez ensuite le retour ; le total sera recalculé.")
                                .font(.inter(14)).foregroundStyle(Theme.ink2)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetHeader(title: outbound != nil ? "Votre aller-retour" : "Détail du vol",
                            subtitle: "\(store.city(result.from)) → \(store.city(result.to))", buttonFill: .white) {
                    Button { user.toggleFavorite(result) } label: {
                        Image(systemName: user.isFavorite(result.key) ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(user.isFavorite(result.key) ? Color(hex: "#FF2D55") : Theme.ink)
                            .frame(width: 38, height: 38)
                            .background(.white, in: Circle())
                            .symbolEffect(.bounce, value: user.isFavorite(result.key))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(user.isFavorite(result.key) ? "Retirer des favoris" : "Ajouter aux favoris")
                    .sensoryFeedback(.success, trigger: user.isFavorite(result.key))
                }
                .background(Theme.gray)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pendingOutbound ? "Aller, par adulte" : "Total · \(Fmt.plural(query.passengers, "voyageur"))").font(.inter(12)).foregroundStyle(Theme.muted)
                        Text(euros(pendingOutbound ? result.price : total)).font(.inter(24, .bold)).tracking(-0.5).foregroundStyle(Theme.ink).monospacedDigit()
                            .contentTransition(.numericText(value: Double(pendingOutbound ? result.price : total)))
                    }
                    Spacer()
                    Button {
                        if pendingOutbound { onChoose() } else { showBooking = true }
                    } label: {
                        HStack(spacing: 8) { Text(pendingOutbound ? "Choisir cet aller" : "Continuer"); Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold)) }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .background(.white)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            .background(Theme.gray)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showBooking) {
                BookingView(legs: legs, fare: fares[fareIndex], query: query, total: total)
            }
        }
        .envolSheet(Theme.gray)
    }

    private func fareTile(_ i: Int) -> some View {
        let on = i == fareIndex
        let f = fares[i]
        return Button { fareIndex = i } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(f.name).font(.inter(13, .semibold)).foregroundStyle(on ? Theme.accent : Theme.muted)
                    if f.recommended { Circle().fill(Theme.accent).frame(width: 5, height: 5) }
                }
                Text(euros(f.price)).font(.inter(17, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                Text(i == 0 ? "base" : "+\(euros(f.price - fares[0].price))").font(.inter(12)).foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(on ? Color.white : Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Tarif \(f.name), \(euros(f.price))\(f.recommended ? ", recommandé" : "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func priceLine(_ label: String, _ value: String, color: Color = Theme.ink2) -> some View {
        HStack {
            Text(label).font(.inter(14)).foregroundStyle(color)
            Spacer()
            Text(value).font(.inter(14, .medium)).foregroundStyle(color).monospacedDigit()
        }
    }

    private func itinerary(_ r: FlightResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(r.from) → \(r.to)").display(20).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Fmt.duration(r.duration)) · \(r.stops == 0 ? "direct" : Fmt.plural(r.stops, "escale"))").font(.inter(14)).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 14)
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
                        .font(.inter(13, .medium))
                        .foregroundStyle(m >= 420 || st ? Theme.warn : Theme.muted)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(m >= 420 || st ? Theme.warn.opacity(0.08) : Theme.gray, in: Capsule())
                        .padding(.vertical, 8)
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
                Rectangle().fill(Theme.gray2).frame(width: 2).padding(.leading, 4)
                AirlineLogo(code: leg.airline, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(store.airlines[leg.airline]?.name ?? leg.airline) · \(Fmt.flight(leg.flightNumber))").font(.inter(14, .medium)).foregroundStyle(Theme.ink)
                    Text("\(leg.aircraft) · \(Fmt.duration(leg.minutes)) · \(Int(leg.km).formatted()) km").font(.inter(12)).foregroundStyle(Theme.muted)
                }
            }
            .frame(minHeight: 48)
            point(Fmt.time(arrLocal), leg.to, Day.add(r.date, Int(floor(Double(arrLocal) / 1440))))
        }
        .accessibilityElement(children: .combine)
    }

    private func point(_ time: String, _ code: String, _ date: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().strokeBorder(Theme.accent, lineWidth: 2.5).frame(width: 12, height: 12)
            Text(time).font(.inter(17, .semibold)).foregroundStyle(Theme.ink).monospacedDigit()
            Text(code).font(.inter(14, .semibold)).foregroundStyle(Theme.ink)
            Text(store.airportByCode[code]?.name ?? "").font(.inter(14)).foregroundStyle(Theme.muted).lineLimit(1)
            Spacer()
            Text(Day.format(date, "dMMM")).font(.inter(12)).foregroundStyle(Theme.faint)
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.warn)
                .frame(width: 22, height: 22).background(Theme.warn.opacity(0.12), in: Circle())
            Text(text).font(.inter(13)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    }

    private func fact(_ symbol: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.ink2)
                .frame(width: 30, height: 30).background(Theme.gray, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.inter(14, .medium)).foregroundStyle(Theme.ink)
                Text(label).font(.inter(12)).foregroundStyle(Theme.muted)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Récapitulatif
                VStack(spacing: 14) {
                    ForEach(Array(legs.enumerated()), id: \.offset) { i, r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.from).display(24).foregroundStyle(Theme.ink)
                                Text("\(Fmt.time(r.dep)) · \(Day.format(r.date, "dMMM"))").font(.inter(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            VStack(spacing: 3) {
                                Image(systemName: "airplane").font(.system(size: 13)).foregroundStyle(Theme.accent)
                                Text("\(i == 0 ? "Aller" : "Retour") · \(Fmt.duration(r.duration))").font(.inter(11)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(r.to).display(24).foregroundStyle(Theme.ink)
                                Text(Fmt.time(r.arr) + (r.dayOffset > 0 ? " (+\(r.dayOffset))" : "")).font(.inter(12)).foregroundStyle(Theme.muted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Rectangle().fill(Theme.gray2).frame(height: 1)
                    HStack {
                        Text("Total estimé · \(Fmt.plural(query.passengers, "voyageur")) · \(fare.name)").font(.inter(14)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(euros(total)).font(.inter(19, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    }
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                EnvolSection(title: "Avant de réserver · \(checks.count) sur \(checklist.count)") {
                    ForEach(checklist.indices, id: \.self) { i in
                        if i > 0 { RowDivider(inset: 50) }
                        let done = checks.contains(i)
                        Button {
                            withAnimation(.snappy) { if done { checks.remove(i) } else { checks.insert(i) } }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(done ? Color.white : Color.clear)
                                    .frame(width: 24, height: 24)
                                    .background(done ? Theme.good : Color.clear, in: Circle())
                                    .overlay(Circle().strokeBorder(done ? Color.clear : Theme.gray2, lineWidth: 2))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(checklist[i].0).font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                                        .strikethrough(done, color: Theme.faint)
                                    Text(checklist[i].1).font(.inter(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: done)
                        .accessibilityAddTraits(done ? .isSelected : [])
                    }
                }

                EnvolSection(title: "Réservation chez la compagnie",
                             footer: "Vous payez directement la compagnie ; Envol n'a pas accès à vos données bancaires. Démonstration : les liens ouvrent l'accueil du site de la compagnie.") {
                    ForEach(tickets.indices, id: \.self) { i in
                        let t = tickets[i]
                        if i > 0 { RowDivider(inset: 60) }
                        Button {
                            if let url = URL(string: store.airlines[t.airline]?.site ?? "") { openURL(url); opened = true }
                        } label: {
                            HStack(spacing: 12) {
                                AirlineLogo(code: t.airline, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(store.airlines[t.airline]?.siteHost ?? t.airline).font(.inter(15, .semibold)).foregroundStyle(Theme.ink)
                                    Text(t.label).font(.inter(13)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                HStack(spacing: 5) {
                                    Text("Réserver")
                                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                                }
                                .font(.inter(14, .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(Theme.accent, in: Capsule())
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Réserver sur \(store.airlines[t.airline]?.siteHost ?? t.airline), \(t.label)")
                    }
                }

                ShareLink(item: calendarFile, preview: SharePreview("Vols Envol", image: Image(systemName: "calendar"))) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus").font(.system(size: 15, weight: .semibold))
                        Text("Ajouter au calendrier")
                    }
                    .font(.inter(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(.white, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TopBar(title: "Réservation").padding(.top, 14).background(Theme.gray)
        }
        .background(Theme.gray)
        .toolbar(.hidden, for: .navigationBar)
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
