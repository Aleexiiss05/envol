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
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? (prominent ? 0.05 : -0.03) : 0)
            .animation(configuration.isPressed ? .spring(response: 0.15, dampingFraction: 0.9) : .spring(response: 0.3, dampingFraction: 0.6),
                       value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: configuration.isPressed) { _, new in new }
    }
}

/// Bouton rond discret (retour, fermer)
struct CircleIconButton: View {
    let symbol: String
    let label: String
    var fill: Color = Theme.gray
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(fill, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Contrôle segmenté du site (piste grise, pastille blanche qui glisse)

/// Le doigt pilote la pastille : elle se tasse dès le contact, suit le doigt d'un segment à l'autre
/// et s'installe avec un léger rebond au relâchement.
struct SegmentedPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @State private var width: CGFloat = 0
    @State private var hover: Int?          // segment sous le doigt pendant l'appui
    @State private var pressing = false
    @State private var cancelled = false    // le geste est devenu un défilement vertical

    private static var follow: Animation { .spring(response: 0.24, dampingFraction: 0.82) }
    private static var settle: Animation { .spring(response: 0.32, dampingFraction: 0.68) }

    private var selectedIndex: Int { options.firstIndex { $0.0 == selection } ?? 0 }

    var body: some View {
        let count = max(options.count, 1)
        let segment = max(0, (width - 6) / CGFloat(count))
        let shown = hover ?? selectedIndex
        ZStack(alignment: .leading) {
            // Pastille blanche : se tasse et s'élargit un peu sous le doigt
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(pressing ? 0.08 : 0.13), radius: pressing ? 2 : 4, y: pressing ? 1 : 2)
                .frame(width: segment, height: 32)
                .scaleEffect(x: pressing ? 1.03 : 1, y: pressing ? 0.92 : 1)
                .offset(x: segment * CGFloat(shown))
                .opacity(width > 0 ? 1 : 0)

            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { i in
                    let on = i == shown
                    Text(options[i].1)
                        .font(.inter(14, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.ink : Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .scaleEffect(pressing && on ? 0.96 : 1)
                }
            }
        }
        .padding(3)
        .background(Color(hex: "#767680").opacity(pressing ? 0.16 : 0.12), in: Capsule())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if cancelled { return }
                    // un glissement surtout vertical : on laisse défiler la page
                    if abs(g.translation.height) > 14 && abs(g.translation.height) > abs(g.translation.width) * 1.4 {
                        cancelled = true
                        withAnimation(Self.settle) { pressing = false; hover = nil }
                        return
                    }
                    let i = index(at: g.location.x, segment: segment)
                    if !pressing || hover != i {
                        withAnimation(Self.follow) { pressing = true; hover = i }
                    }
                }
                .onEnded { g in
                    defer { cancelled = false }
                    guard !cancelled else { return }
                    let i = index(at: g.location.x, segment: segment)
                    withAnimation(Self.settle) {
                        pressing = false
                        hover = nil
                        selection = options[i].0
                    }
                }
        )
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: pressing) { _, new in new }
        .sensoryFeedback(.selection, trigger: hover) { old, new in old != nil && new != nil && old != new }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func index(at x: CGFloat, segment: CGFloat) -> Int {
        guard segment > 0 else { return selectedIndex }
        return min(max(Int((x - 3) / segment), 0), options.count - 1)
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

// MARK: - Écrans et feuilles sans barre système

/// En-tête de feuille : titre à gauche, boutons ronds à droite (remplace « Fermer » / « OK »)
struct SheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var buttonFill: Color = Theme.gray
    var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss
    init(title: String, subtitle: String? = nil, buttonFill: Color = Theme.gray, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.buttonFill = buttonFill; self.trailing = trailing
    }
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).display(24).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                if let subtitle { Text(subtitle).font(.inter(14)).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
            CircleIconButton(symbol: "xmark", label: "Fermer", fill: buttonFill) { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }
}
extension SheetHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, buttonFill: Color = Theme.gray) { self.init(title: title, subtitle: subtitle, buttonFill: buttonFill) { EmptyView() } }
}

/// Barre du haut d'un écran poussé : retour rond, titre centré, action ronde
struct TopBar<Trailing: View>: View {
    let title: String
    var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.trailing = trailing
    }
    var body: some View {
        ZStack {
            Text(title).font(.inter(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                .padding(.horizontal, 60)
                .accessibilityAddTraits(.isHeader)
            HStack {
                CircleIconButton(symbol: "chevron.left", label: "Retour", fill: .white) { dismiss() }
                Spacer()
                trailing()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
extension TopBar where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// En-tête d'onglet : grand titre Inter, comme les titres de section du site
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).display(34).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.inter(15)).foregroundStyle(Theme.muted) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// Section : petit libellé puis carte (blanche sur fond gris, grise sur fond blanc)
struct EnvolSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    var fill: Color = .white
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            if let footer {
                Text(footer).font(.inter(12)).foregroundStyle(Theme.faint).padding(.horizontal, 6)
            }
        }
    }
}

/// Séparateur fin dans une carte
struct RowDivider: View {
    var inset: CGFloat = 14
    var body: some View { Rectangle().fill(Theme.gray2).frame(height: 1).padding(.leading, inset) }
}

/// Ligne de carte : pastille d'icône, titre, sous-titre, contenu à droite
struct EnvolRow<Trailing: View>: View {
    var symbol: String? = nil
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32).background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.inter(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
extension EnvolRow where Trailing == EmptyView {
    init(symbol: String? = nil, title: String, subtitle: String? = nil) { self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() } }
}

/// Interrupteur Envol : piste bleue, pastille blanche cochée (pas l'interrupteur vert des Réglages)
struct EnvolToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.spring(duration: 0.3, bounce: 0.25)) { configuration.isOn.toggle() } } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                Capsule()
                    .fill(configuration.isOn ? Theme.accent : Theme.gray2)
                    .frame(width: 46, height: 28)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(3)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .overlay {
                                if configuration.isOn {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
                                }
                            }
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
extension ToggleStyle where Self == EnvolToggleStyle { static var envol: EnvolToggleStyle { .init() } }

/// Ligne avec interrupteur Envol dans une carte
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.inter(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .toggleStyle(.envol)
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .padding(.vertical, 4)
    }
}

/// Compteur − / + rond
struct EnvolStepper: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.inter(13)).foregroundStyle(Theme.muted) }
            }
            Spacer()
            stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)").font(.inter(17, .semibold)).monospacedDigit().frame(minWidth: 24)
                .contentTransition(.numericText(value: Double(value)))
            stepButton("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .animation(.snappy, value: value)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { dir in
            if dir == .increment, value < range.upperBound { value += 1 }
            if dir == .decrement, value > range.lowerBound { value -= 1 }
        }
    }
    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Theme.ink : Theme.faint.opacity(0.5))
                .frame(width: 34, height: 34)
                .background(Theme.gray, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// État vide : pastille d'icône, titre, texte
struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64).background(Theme.accentBg, in: Circle())
            Text(title).font(.inter(19, .semibold)).foregroundStyle(Theme.ink)
            Text(text).font(.inter(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Feuilles Envol : grand arrondi, fond au choix, poignée visible
    func envolSheet(_ background: Color = .white) -> some View {
        self.presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
            .presentationBackground(background)
    }
}

/// Garde le geste « balayer pour revenir » quand la barre de navigation système est masquée
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
