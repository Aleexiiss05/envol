import SwiftUI
import UIKit

// MARK: - Identité Envol (identique au site : css/style.css)

enum Theme {
    static let ink = Color(hex: "#1D1D1F")
    static let ink2 = Color(hex: "#424245")
    static let muted = Color(hex: "#6E6E73")
    static let faint = Color(hex: "#86868B")
    static let gray = Color(hex: "#F5F5F7")
    static let gray2 = Color(hex: "#E8E8ED")
    static let field = Color(hex: "#F0F0F3")   // champs sur fond blanc
    static let line = Color.black.opacity(0.08)
    static let accent = Color(hex: "#0071E3")
    static let accentBg = Color(hex: "#0071E3").opacity(0.08)
    static let good = Color(hex: "#1D8638")
    static let warn = Color(hex: "#B25000")
    static let bad = Color(hex: "#D70015")
    static let radius: CGFloat = 18
    static let radiusM: CGFloat = 14

    /// Polices et barres de navigation UIKit aux couleurs d'Envol
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        nav.backgroundColor = UIColor(white: 1, alpha: 0.72)
        nav.shadowColor = UIColor.black.withAlphaComponent(0.08)
        if let f = UIFont(name: "Inter-SemiBold", size: 17) { nav.titleTextAttributes = [.font: f, .foregroundColor: UIColor(Theme.ink)] }
        if let f = UIFont(name: "Inter-Bold", size: 32) { nav.largeTitleTextAttributes = [.font: f, .foregroundColor: UIColor(Theme.ink), .kern: -1.0] }
        let button = UIBarButtonItemAppearance()
        if let f = UIFont(name: "Inter-Medium", size: 17) { button.normal.titleTextAttributes = [.font: f] }
        nav.buttonAppearance = button
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        if let f = UIFont(name: "Inter-Medium", size: 13) {
            UISegmentedControl.appearance().setTitleTextAttributes([.font: f], for: .normal)
        }
    }
}

extension Font {
    private static func interName(_ w: Font.Weight) -> String {
        switch w {
        case .black, .heavy: "Inter-ExtraBold"
        case .bold: "Inter-Bold"
        case .semibold: "Inter-SemiBold"
        case .medium: "Inter-Medium"
        default: "Inter-Regular"
        }
    }
    /// Inter à une taille donnée, qui suit quand même la taille de texte choisie par l'utilisateur
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(interName(weight), size: size, relativeTo: style)
    }
    /// Équivalent Inter des styles système (.title3, .caption…)
    static func inter(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let (size, def): (CGFloat, Font.Weight) = switch style {
        case .largeTitle: (32, .bold)
        case .title: (28, .bold)
        case .title2: (22, .bold)
        case .title3: (19, .semibold)
        case .headline: (17, .semibold)
        case .callout: (16, .regular)
        case .subheadline: (15, .regular)
        case .footnote: (13, .regular)
        case .caption: (12, .regular)
        case .caption2: (11, .regular)
        default: (16, .regular)
        }
        return .custom(interName(weight ?? def), size: size, relativeTo: style)
    }
}

extension View {
    /// Titre façon site : Inter gras, lettres resserrées
    func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> some View {
        font(.inter(size, weight, relativeTo: .largeTitle)).tracking(-size * 0.03)
    }
    /// Carte blanche arrondie, sans bordure (comme les cartes de vol du site)
    func card(_ radius: CGFloat = Theme.radius, padding: CGFloat = 16) -> some View {
        self.padding(padding).background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Boutons

/// Bouton principal : pilule bleue, hauteur raisonnable (44 pt), comme « Rechercher » sur le site
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(16, .semibold))
            .foregroundStyle(prominent ? Color.white : Theme.ink)
            .padding(.horizontal, 22)
            .frame(height: 46)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(prominent ? (enabled ? Theme.accent : Theme.faint.opacity(0.5)) : Theme.gray, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? (prominent ? 0.05 : -0.03) : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// Bouton rond discret (retour, fermer)
struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(Theme.gray, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Contrôle segmenté du site (piste grise, pastille blanche qui glisse)

struct SegmentedPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let label = options[i].1
                let on = value == selection
                Button { withAnimation(.spring(duration: 0.35, bounce: 0.2)) { selection = value } } label: {
                    Text(label)
                        .font(.inter(14, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.ink : Theme.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if on {
                                Capsule().fill(.white)
                                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(hex: "#767680").opacity(0.12), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Pastille de filtre (ambiances, mois) : grise, noire quand choisie
struct ChipButton: View {
    let label: String
    let on: Bool
    var offFill: Color = Theme.gray2
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.inter(14, on ? .semibold : .medium))
                .foregroundStyle(on ? Color.white : Theme.ink2)
                .padding(.horizontal, 14).frame(height: 34)
                .background(on ? Theme.ink : offFill, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Logo Envol (hublot stylisé, comme sur le site)

struct BrandMark: View {
    var height: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
            .strokeBorder(Theme.ink, lineWidth: height * 0.08)
            .overlay(RoundedRectangle(cornerRadius: height * 0.22, style: .continuous).fill(Theme.ink).padding(height * 0.17))
            .frame(width: height * 0.68, height: height)
            .accessibilityHidden(true)
    }
}

struct BrandWordmark: View {
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: size * 0.4) {
            BrandMark(height: size)
            Text("Envol").font(.inter(size, .semibold)).tracking(-size * 0.025).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Envol")
    }
}

/// En-tête d'écran façon site : grand titre Inter + sous-titre gris
struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).display(30)
            if let subtitle { Text(subtitle).font(.inter(16)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
