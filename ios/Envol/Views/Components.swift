import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Montant en euros, sans décimales
func euros(_ v: Int) -> String {
    v.formatted(.currency(code: "EUR").precision(.fractionLength(0)).locale(Locale(identifier: "fr_FR")))
}

/// Logo de compagnie : image distante, monogramme aux couleurs de la compagnie en repli
struct AirlineLogo: View {
    let code: String
    var size: CGFloat = 32
    var body: some View {
        let airline = FlightStore.shared.airlines[code]
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color(hex: airline?.color ?? "#1D1D1F"))
            Text(code).font(.inter(size * 0.32, .semibold)).foregroundStyle(.white)
            AsyncImage(url: FlightStore.shared.logoURL(code)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit().padding(size * 0.08).background(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
        .accessibilityLabel(airline?.name ?? code)
    }
}

/// Photo de destination (Unsplash)
struct PlacePhoto: View {
    let code: String
    var width = 800
    var body: some View {
        // Color.clear prend exactement la taille proposée : la photo remplit son cadre sans jamais le déborder
        Color.clear
            .overlay {
                AsyncImage(url: FlightStore.shared.photoURL(code, width: width), transaction: .init(animation: .easeOut(duration: 0.3))) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { Rectangle().fill(.quaternary) }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Hublot : photo dans un cadre arrondi, clin d'œil au thème du site
struct Porthole: View {
    let code: String
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 10)
            PlacePhoto(code: code, width: 500)
                .clipShape(Capsule(style: .continuous))
                .padding(9)
                .overlay(Capsule(style: .continuous).inset(by: 9).strokeBorder(.black.opacity(0.08), lineWidth: 1))
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }
}

/// Ligne de trajet : points de départ/arrivée et escales
struct RouteTrack: View {
    let result: FlightResult
    var body: some View {
        GeometryReader { geo in
            let start = result.segments.first?.startUTC ?? 0
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 1.5)
                Circle().fill(Theme.faint).frame(width: 6, height: 6)
                Circle().fill(Theme.faint).frame(width: 6, height: 6).offset(x: geo.size.width - 6)
                ForEach(Array(result.segments.enumerated()), id: \.offset) { _, s in
                    if case .layover(_, let m, let st) = s.kind {
                        let mid = Double(s.startUTC - start) + Double(m) / 2
                        Circle().strokeBorder(st ? Color.red : Color.orange, lineWidth: 2).background(Circle().fill(.background))
                            .frame(width: 9, height: 9)
                            .offset(x: geo.size.width * mid / Double(max(result.duration, 1)) - 4.5)
                    }
                }
            }
            .frame(height: 9)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .accentColor
    var body: some View {
        Text(text).font(.inter(.caption, .semibold)).foregroundStyle(color)
    }
}

/// Bouton qui s'enfonce légèrement sous le doigt, avec un ressort
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            // enfoncement immédiat, retour avec un petit rebond
            .animation(configuration.isPressed ? .spring(response: 0.15, dampingFraction: 0.9) : .spring(response: 0.3, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}


/// Reflet qui balaie les squelettes de chargement
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                        .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
                .clipped()
            }
            .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}
extension View { func shimmering() -> some View { modifier(Shimmer()) } }
