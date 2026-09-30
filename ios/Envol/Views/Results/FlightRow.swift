import SwiftUI

struct FlightRow: View {
    let result: FlightResult
    let badge: String?
    let perAdultLabel: String
    let showBag: Bool
    let bag: Int
    let isFavorite: Bool
    private let store = FlightStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(result.carriers.prefix(2), id: \.self) { AirlineLogo(code: $0, size: 30) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.carriers.compactMap { store.airlines[$0]?.name }.joined(separator: " + ")).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(result.flightNumbers.map(Fmt.flight).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
                if let badge {
                    Text(badge).font(.caption.weight(.semibold))
                        .foregroundStyle(badge == "Le moins cher" ? Color.green : Color.accentColor)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.time(result.dep)).font(.title2.weight(.semibold)).monospacedDigit()
                    Text(result.from).font(.caption.weight(.semibold)) + Text(" \(store.city(result.from))").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text(Fmt.duration(result.duration)).font(.caption2).foregroundStyle(.secondary)
                    RouteTrack(result: result)
                    Text(result.stops == 0 ? "Direct" : "\(Fmt.plural(result.stops, "escale")) · \(result.layovers.map { $0.at }.joined(separator: ", "))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(result.stops == 0 ? Color.green : Color.orange)
                        .lineLimit(1)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .top, spacing: 1) {
                        Text(Fmt.time(result.arr)).font(.title2.weight(.semibold)).monospacedDigit()
                        if result.dayOffset != 0 {
                            Text("\(result.dayOffset > 0 ? "+" : "")\(result.dayOffset)").font(.caption2.weight(.bold)).foregroundStyle(.red)
                        }
                    }
                    Text(result.to).font(.caption.weight(.semibold)) + Text(" \(store.city(result.to))").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .lastTextBaseline) {
                HStack(spacing: 10) {
                    perk("suitcase.rolling", result.cabinBag, "Bagage cabine")
                    perk("suitcase", result.holdBag, "Bagage en soute")
                    if result.wifi { perk("wifi", true, "Wi-Fi") }
                    if result.isSelfTransfer { Text("Billets séparés").font(.caption2.weight(.semibold)).foregroundStyle(.orange) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(perAdultLabel).font(.caption2).foregroundStyle(.secondary)
                    Text(euros(result.price)).font(.title3.weight(.bold)).monospacedDigit().contentTransition(.numericText(value: Double(result.price)))
                    if showBag && bag > 0 { Text("dont bagage \(euros(bag))").font(.caption2).foregroundStyle(.secondary) }
                    if result.seats <= 3 { Text("\(Fmt.plural(result.seats, "place")) à ce prix").font(.caption2).foregroundStyle(.red) }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Touchez pour le détail. Balayez vers la gauche pour l'ajouter aux favoris.")
    }

    private func perk(_ symbol: String, _ ok: Bool, _ label: String) -> some View {
        Image(systemName: symbol).font(.caption)
            .foregroundStyle(ok ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.35))
            .overlay { if !ok { Rectangle().frame(height: 1).rotationEffect(.degrees(-45)).foregroundStyle(Color.secondary.opacity(0.5)) } }
            .accessibilityLabel("\(label) \(ok ? "inclus" : "non inclus")")
    }

    private var accessibilityText: String {
        let names = result.carriers.compactMap { store.airlines[$0]?.name }.joined(separator: " et ")
        let stops = result.stops == 0 ? "vol direct" : "\(Fmt.plural(result.stops, "escale")) à \(result.layovers.map { store.city($0.at) }.joined(separator: ", "))"
        return "\(names). Départ \(Fmt.time(result.dep)) de \(store.city(result.from)), arrivée \(Fmt.time(result.arr))\(result.dayOffset > 0 ? " le lendemain" : "") à \(store.city(result.to)). \(Fmt.duration(result.duration)), \(stops). \(euros(result.price)).\(badge.map { " \($0)." } ?? "")"
    }
}
