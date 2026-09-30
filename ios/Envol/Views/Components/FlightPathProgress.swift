import SwiftUI

/// Arc de vol : fine courbe, pleine derrière l'avion, en pointillés devant (même principe que le site).
struct FlightArc: Shape {
    static let y0 = 0.82, peak = 0.08
    static func point(_ t: Double, in size: CGSize) -> CGPoint {
        let y = (1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * peak + t * t * y0
        return CGPoint(x: t * size.width, y: y * size.height)
    }
    /// Angle de la tangente, en radians, dans le repère de l'écran
    static func angle(_ t: Double, in size: CGSize) -> Double {
        let dy = (2 * (1 - t) * (peak - y0) + 2 * t * (y0 - peak)) * size.height
        return atan2(dy, size.width)
    }
    var to: Double = 1
    var animatableData: Double { get { to } set { to = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = max(2, Int(60 * to))
        for i in 0...steps {
            let pt = Self.point(Double(i) / Double(steps) * to, in: rect.size)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// Avion posé sur l'arc ; animable pour glisser le long de la courbe (et non en ligne droite)
private struct PlaneOnArc: View, Animatable {
    var t: Double
    let size: CGSize
    let planeSize: CGFloat
    var animatableData: Double { get { t } set { t = newValue } }
    var body: some View {
        let p = FlightArc.point(t, in: size)
        Image(systemName: "airplane")
            .font(.inter(planeSize, .semibold))
            .foregroundStyle(.tint)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 4)
            .rotationEffect(.radians(FlightArc.angle(t, in: size)))
            .position(p)
    }
}

struct FlightPathProgress: View {
    let steps: [String]
    let current: Int
    var details: [String] = []
    var compact = false
    @State private var shown: Double = 0

    private func t(_ i: Int) -> Double { 0.04 + Double(i) * 0.92 / Double(max(steps.count - 1, 1)) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                FlightArc()
                    .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 6]))
                    .foregroundStyle(.tertiary)
                FlightArc(to: shown)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                ForEach(steps.indices, id: \.self) { i in
                    let p = FlightArc.point(t(i), in: size)
                    let state = i < current ? 0 : i == current ? 1 : 2
                    ZStack {
                        if state == 0 {
                            Circle().fill(.tint).frame(width: 8, height: 8)
                        } else if state == 2 {
                            Circle().strokeBorder(.tertiary, lineWidth: 1.5).background(Circle().fill(.background)).frame(width: 8, height: 8)
                        }
                    }
                    .position(p)
                    if !compact || i == current {
                        VStack(spacing: 1) {
                            Text(steps[i])
                                .font(i == current ? .inter(.caption, .bold) : .inter(.caption2))
                                .foregroundStyle(i == current ? Color.accentColor : i < current ? Color.primary : Color.secondary)
                            if i < details.count, !details[i].isEmpty, i <= current {
                                Text(details[i]).font(.inter(.caption2)).foregroundStyle(i == current ? Color.accentColor : Color.secondary)
                            }
                        }
                        .fixedSize()
                        .position(x: min(max(p.x, 30), size.width - 30), y: p.y + (i == current ? 26 : 20))
                    }
                }
                PlaneOnArc(t: shown, size: size, planeSize: compact ? 16 : 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(current + 1) sur \(steps.count) : \(steps[min(current, steps.count - 1)])")
        .onAppear { withAnimation(.spring(duration: 1.1, bounce: 0.15)) { shown = t(current) } }
        .onChange(of: current) { _, new in withAnimation(.spring(duration: 1.1, bounce: 0.15)) { shown = t(new) } }
    }
}
