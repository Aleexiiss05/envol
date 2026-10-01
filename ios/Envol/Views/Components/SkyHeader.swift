import SwiftUI

/// Ciel du haut de l'accueil : dégradé bleu qui fond vers le blanc, lueur de soleil, nuages qui dérivent
/// et un petit avion qui traverse en laissant une traînée en pointillés. Immobile si « Réduire les animations ».
struct SkyHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let period = 18.0   // secondes pour une traversée

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 6.0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    // Dégradé du ciel : bleu en haut, blanc en bas pour se fondre dans la page
                    LinearGradient(stops: [
                        .init(color: Color(hex: "#9CCBFF"), location: 0),
                        .init(color: Color(hex: "#C4E0FF"), location: 0.35),
                        .init(color: Color(hex: "#E6F1FF"), location: 0.62),
                        .init(color: Color(hex: "#F7FAFF"), location: 0.82),
                        .init(color: .white, location: 1),
                    ], startPoint: .top, endPoint: .bottom)

                    // Lueur de soleil chaude, en haut à droite
                    RadialGradient(colors: [Color(hex: "#FFF1CC").opacity(0.95), Color(hex: "#FFE6B0").opacity(0.25), .clear],
                                   center: UnitPoint(x: 0.88, y: 0.36), startRadius: 4, endRadius: size.width * 0.55)
                        .blendMode(.plusLighter)

                    clouds(size: size, t: t)
                    plane(size: size, t: t)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Nuages : ellipses floues qui dérivent lentement
    private func clouds(size: CGSize, t: Double) -> some View {
        let specs: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, speed: Double, alpha: Double)] = [
            (0.08, 0.40, 0.55, 0.07, 0.010, 0.85),
            (0.62, 0.47, 0.70, 0.08, 0.007, 0.75),
            (0.30, 0.58, 0.80, 0.09, 0.005, 0.70),
            (0.85, 0.66, 0.60, 0.07, 0.009, 0.60),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(specs.indices, id: \.self) { i in
                let s = specs[i]
                // dérive en boucle, de gauche à droite, réapparaît de l'autre côté
                let drift = (Double(s.x) + t * s.speed).truncatingRemainder(dividingBy: 1.4) - 0.2
                Ellipse()
                    .fill(.white.opacity(s.alpha))
                    .frame(width: size.width * s.w, height: size.height * s.h)
                    .blur(radius: 18)
                    .position(x: size.width * CGFloat(drift), y: size.height * s.y)
            }
        }
    }

    // MARK: Avion sur un arc doux avec sa traînée
    private func point(_ p: Double, _ size: CGSize) -> CGPoint {
        // montée en diagonale : décolle en bas à gauche (derrière le titre), file vers le haut à droite
        let x = -0.08 + 1.16 * p
        let y = 0.66 - 0.30 * p - 0.05 * sin(.pi * p)
        return CGPoint(x: size.width * x, y: size.height * y)
    }

    private func plane(size: CGSize, t: Double) -> some View {
        let p = (t / period).truncatingRemainder(dividingBy: 1)
        let pos = point(p, size)
        let ahead = point(min(p + 0.005, 1), size)
        let angle = atan2(ahead.y - pos.y, ahead.x - pos.x)
        // apparition et disparition douces aux bords
        let fade = min(1, min(p, 1 - p) / 0.08)
        return ZStack(alignment: .topLeading) {
            // traînée : du point situé 30 % plus tôt jusqu'à l'avion, qui s'efface en arrière
            Path { path in
                let start = max(0, p - 0.3)
                let steps = 40
                for i in 0...steps {
                    let q = start + (p - start) * Double(i) / Double(steps)
                    let pt = point(q, size)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 5]))
            .mask(
                LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(1, pos.x), height: size.height)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            .opacity(0.9 * fade)

            Image(systemName: "airplane")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color(hex: "#0B3D91").opacity(0.25), radius: 4, y: 2)
                .rotationEffect(.radians(angle))
                .position(pos)
                .opacity(fade)
        }
    }
}
