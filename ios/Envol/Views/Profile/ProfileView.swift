import SwiftUI

/// Profil : carte d'identité du voyageur puis ses préférences, en cartes Envol (pas une liste de Réglages)
struct ProfileView: View {
    @Environment(UserData.self) private var user
    @State private var pickingHome = false
    @State private var confirmClear = false
    @FocusState private var nameFocused: Bool
    private let store = FlightStore.shared

    var body: some View {
        @Bindable var user = user
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(title: "Profil")
                    idCard.padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 24) {
                        EnvolSection(title: "Vous") {
                            HStack(spacing: 12) {
                                Text("Prénom").font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                                TextField("Facultatif", text: $user.profile.firstName)
                                    .font(.inter(15)).multilineTextAlignment(.trailing)
                                    .textContentType(.givenName).focused($nameFocused).submitLabel(.done)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56)
                            RowDivider()
                            Button { pickingHome = true } label: {
                                EnvolRow(title: "Ville de départ") {
                                    Text("\(store.city(user.profile.homeCode)) · \(user.profile.homeCode)").font(.inter(15)).foregroundStyle(Theme.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        EnvolSection(title: "Avec qui voyagez-vous ?") {
                            FlowChips(items: Companions.allCases.map { ($0, $0.label) }, isOn: { user.profile.companions == $0 }) { c in
                                withAnimation(.snappy) { user.profile.companions = c }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        EnvolSection(title: "Envies") {
                            FlowChips(items: Vibe.allCases.map { ($0, $0.label) }, isOn: { user.profile.vibes.contains($0) }) { v in
                                withAnimation(.snappy) { if user.profile.vibes.contains(v) { user.profile.vibes.remove(v) } else { user.profile.vibes.insert(v) } }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        EnvolSection(title: "Habitudes", footer: "Ces réglages pré-remplissent vos recherches et orientent les suggestions de l'accueil.") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Budget par vol").font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(user.profile.budget >= 1500 ? "Sans limite" : euros(user.profile.budget))
                                        .font(.inter(20, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                                        .contentTransition(.numericText(value: Double(user.profile.budget)))
                                        .animation(.snappy, value: user.profile.budget)
                                }
                                Slider(value: Binding(get: { Double(user.profile.budget) }, set: { user.profile.budget = Int($0) }), in: 50...1500, step: 10)
                                    .tint(Theme.accent)
                                    .accessibilityValue(euros(user.profile.budget))
                            }
                            .padding(14)
                            RowDivider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Cabine").font(.inter(15, .medium)).foregroundStyle(Theme.ink)
                                SegmentedPicker(options: Cabin.allCases.map { ($0, $0.label) }, selection: $user.profile.cabin)
                            }
                            .padding(14)
                            RowDivider()
                            ToggleRow(title: "Bagage en soute", subtitle: "Prix affichés bagage compris", isOn: $user.profile.bagUsually)
                            RowDivider()
                            ToggleRow(title: "Vols directs de préférence", isOn: $user.profile.directPreferred)
                        }

                        EnvolSection(title: "Alertes de prix") {
                            EnvolRow(symbol: user.notificationsAllowed ? "bell.fill" : "bell.slash",
                                     title: user.notificationsAllowed ? "Notifications activées" : "Notifications désactivées",
                                     subtitle: user.notificationsAllowed ? "Vous êtes prévenu quand un trajet surveillé baisse." : "Activez-les pour être prévenu des baisses.") {
                                if !user.notificationsAllowed {
                                    Button("Activer") { user.requestNotifications() }.buttonStyle(CompactPillStyle())
                                }
                            }
                        }

                        EnvolSection(footer: "Vos données restent sur cet iPhone. Envol ne crée pas de compte et ne vend aucune donnée.") {
                            Button { user.resetOnboarding() } label: {
                                EnvolRow(symbol: "sparkles", title: "Revoir l'accueil")
                            }
                            .buttonStyle(.plain)
                            RowDivider(inset: 58)
                            Button { confirmClear = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.bad)
                                        .frame(width: 32, height: 32).background(Theme.bad.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    Text("Effacer l'historique de recherche").font(.inter(15, .medium)).foregroundStyle(Theme.bad)
                                    Spacer()
                                }
                                .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.gray)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $pickingHome) {
                PlacePicker(title: "Ville de départ", current: user.profile.homeCode) { user.profile.homeCode = $0 }
            }
            .confirmationDialog("Effacer l'historique ?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { user.recents = []; user.searchCount = 0 }
            }
            .onAppear { UNUserNotificationCenterWrapper.status { user.notificationsAllowed = $0 } }
            .sensoryFeedback(.selection, trigger: user.profile)
        }
    }

    /// Carte d'identité : initiale, prénom, ville, puis trois compteurs
    private var idCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Text(initials)
                    .font(.inter(24, .semibold)).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Theme.ink, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.profile.firstName.isEmpty ? "Voyageur" : user.profile.firstName).display(22).foregroundStyle(Theme.ink)
                    Text("Au départ de \(store.city(user.profile.homeCode)) · depuis \(Day.format(user.profile.memberSince, "MMMMyyyy"))")
                        .font(.inter(13)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                stat(user.searchCount, "recherches")
                stat(user.favorites.count, "favoris")
                stat(user.alerts.count, "alertes")
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var initials: String {
        let n = user.profile.firstName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "✈︎" : String(n.prefix(1)).uppercased()
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.inter(20, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(label).font(.inter(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.gray, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Pastilles qui passent à la ligne (envies, voyageurs, compagnies)
struct FlowChips<T: Hashable>: View {
    let items: [(T, String)]
    let isOn: (T) -> Bool
    let toggle: (T) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                let value = items[i].0
                ChipButton(label: items[i].1, on: isOn(value), offFill: Theme.gray) { toggle(value) }
            }
        }
    }
}

/// Disposition en lignes qui se replient
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
