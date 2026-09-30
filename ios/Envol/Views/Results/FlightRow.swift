import SwiftUI

/// Carte de vol, calquée sur .fcard du site : carte blanche, horaires en grand, prix et « Choisir » en bas.
struct FlightRow: View {
    let result: FlightResult
    let badge: String?
    let perAdultLabel: String
    let showBag: Bool
    let bag: Int
    let isFavorite: Bool
    var onFavorite: () -> Void = {}
    var onChoose: () -> Void = {}
    private let store = FlightStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Compagnie + badge + favori
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(result.carriers.prefix(2), id: \.self) { AirlineLogo(code: $0, size: 28) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.carriers.compactMap { store.airlines[$0]?.name }.joined(separator: " + "))
                        .font(.inter(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(result.flightNumbers.map(Fmt.flight).joined(separator: " · "))
                        .font(.inter(12)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.inter(12, .semibold))
                        .foregroundStyle(badge == "Le moins cher" ? Theme.good : Theme.accent)
                        .padding(.horizontal, 9).frame(height: 24)
                        .background((badge == "Le moins cher" ? Theme.good : Theme.accent).opacity(0.09), in: Capsule())
                }
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isFavorite ? Color(hex: "#FF2D55") : Theme.muted)
                        .frame(width: 34, height: 34)
                        .background(Theme.gray, in: Circle())
                        .symbolEffect(.bounce, value: isFavorite)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
            }

            // Horaires et trajet
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.time(result.dep)).font(.inter(24, .semibold)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.ink)
                    Text(result.from).font(.inter(12, .semibold)).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 5) {
                    Text(Fmt.duration(result.duration)).font(.inter(12)).foregroundStyle(Theme.muted)
                    RouteTrack(result: result)
                    Text(result.stops == 0 ? "Direct" : "\(Fmt.plural(result.stops, "escale")) · \(result.layovers.map { $0.at }.joined(separator: ", "))")
                        .font(.inter(12, .medium))
                        .foregroundStyle(result.stops == 0 ? Theme.good : Theme.warn)
                        .lineLimit(1)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .top, spacing: 1) {
                        Text(Fmt.time(result.arr)).font(.inter(24, .semibold)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.ink)
                        if result.dayOffset != 0 {
                            Text("\(result.dayOffset > 0 ? "+" : "")\(result.dayOffset)").font(.inter(11, .bold)).foregroundStyle(Theme.bad)
                        }
                    }
                    Text(result.to).font(.inter(12, .semibold)).foregroundStyle(Theme.muted)
                }
            }

            Rectangle().fill(Theme.gray2).frame(height: 1)

            // Inclus + prix + choisir
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        perk("suitcase.rolling", result.cabinBag, "Bagage cabine")
                        perk("suitcase", result.holdBag, "Bagage en soute")
                        if result.wifi { perk("wifi", true, "Wi-Fi") }
                    }
                    if result.isSelfTransfer {
                        Text("Billets séparés").font(.inter(11, .semibold)).foregroundStyle(Theme.warn)
                    } else if result.seats <= 3 {
                        Text("\(Fmt.plural(result.seats, "place")) à ce prix").font(.inter(11, .medium)).foregroundStyle(Theme.bad)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(euros(result.price)).font(.inter(21, .bold)).tracking(-0.4).monospacedDigit().foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: Double(result.price)))
                    Text(showBag && bag > 0 ? "dont bagage \(euros(bag))" : perAdultLabel).font(.inter(11)).foregroundStyle(Theme.faint)
                }
                Button(action: onChoose) { Text("Choisir") }
                    .buttonStyle(CompactPillStyle())
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Touchez pour le détail du vol.")
        .accessibilityAction(named: isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", onFavorite)
    }

    private func perk(_ symbol: String, _ ok: Bool, _ label: String) -> some View {
        Image(systemName: symbol).font(.system(size: 12))
            .foregroundStyle(ok ? Theme.ink2 : Theme.faint.opacity(0.45))
            .overlay { if !ok { Rectangle().frame(height: 1).rotationEffect(.degrees(-45)).foregroundStyle(Theme.faint.opacity(0.6)) } }
            .accessibilityLabel("\(label) \(ok ? "inclus" : "non inclus")")
    }

    private var accessibilityText: String {
        let names = result.carriers.compactMap { store.airlines[$0]?.name }.joined(separator: " et ")
        let stops = result.stops == 0 ? "vol direct" : "\(Fmt.plural(result.stops, "escale")) à \(result.layovers.map { store.city($0.at) }.joined(separator: ", "))"
        return "\(names). Départ \(Fmt.time(result.dep)) de \(store.city(result.from)), arrivée \(Fmt.time(result.arr))\(result.dayOffset > 0 ? " le lendemain" : "") à \(store.city(result.to)). \(Fmt.duration(result.duration)), \(stops). \(euros(result.price)).\(badge.map { " \($0)." } ?? "")"
    }
}

/// Petite pilule « Choisir » (34 pt), comme le bouton des cartes de vol du site
struct CompactPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(14, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Theme.accent, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}
