import SwiftUI
import UserNotifications

/// Accueil en 8 écrans, dans l'identité du site : on apprend à connaître le voyageur pour personnaliser l'app.
struct OnboardingView: View {
    @Environment(UserData.self) private var user
    @State private var page = 0
    @State private var profile = TravelProfile()
    @State private var forward = true
    @State private var cityQuery = ""
    @State private var locating = false
    @State private var suggestions: [FlightStore.Destination] = []
    @State private var drift = false
    @State private var notifShown = false
    @FocusState private var nameFocused: Bool
    private let store = FlightStore.shared
    private let steps = 7   // écrans après la bienvenue

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Group {
                    switch page {
                    case 0: welcome
                    case 1: nameStep
                    case 2: cityStep
                    case 3: vibesStep
                    case 4: companionsStep
                    case 5: budgetStep
                    case 6: notificationsStep
                    default: readyStep
                    }
                }
                .id(page)
                .transition(.asymmetric(
                    insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                    removal: .offset(x: forward ? -40 : 40).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            bottomBar
        }
        .background(.white)
        .sensoryFeedback(.selection, trigger: page)
        .onAppear {
            profile = user.profile
            if Demo.isOnboarding {
                profile = Demo.profile
                page = Demo.onboardingPage
                if page == 7 { loadSuggestions() }
            }
        }
    }

    // MARK: Barres du haut et du bas (compactes, alignées sur une ligne)
    private var topBar: some View {
        HStack(spacing: 12) {
            Group {
                if page == 0 {
                    BrandWordmark(size: 20)
                } else {
                    CircleIconButton(symbol: "chevron.left", label: "Retour") { go(-1) }
                }
            }
            .frame(width: 90, alignment: .leading)
            Spacer(minLength: 0)
            if page > 0 {
                FlightPathProgress(steps: Array(repeating: "", count: steps), current: page - 1, compact: true)
                    .frame(width: 140, height: 30)
                    .accessibilityLabel("Étape \(page) sur \(steps)")
            }
            Spacer(minLength: 0)
            Button(page == 3 ? "Tout" : "Passer") {
                if page == 3 { profile.vibes = Set(Vibe.allCases) }
                go(1)
            }
            .font(.inter(15, .medium))
            .foregroundStyle(Theme.muted)
            .frame(width: 90, alignment: .trailing)
            .opacity(page > 0 && page < 7 ? 1 : 0)
            .disabled(!(page > 0 && page < 7))
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        HStack {
            if page > 0 && page < 7 {
                Text("Étape \(page) sur \(steps - 1)").font(.inter(14)).foregroundStyle(Theme.faint)
                    .contentTransition(.numericText(value: Double(page)))
            }
            Spacer(minLength: 0)
            Button { page == 7 ? finish() : go(1) } label: {
                HStack(spacing: 8) {
                    Text(page == 0 ? "Commencer" : page == 7 ? "C'est parti" : "Continuer")
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(PillButtonStyle(fullWidth: page == 0 || page == 7))
            .disabled(page == 3 && profile.vibes.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        nameFocused = false
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { page = max(0, min(7, page + delta)) }
        if page == 7 { loadSuggestions() }
    }
    private func finish() {
        user.profile = profile
        user.bagIncluded = profile.bagUsually
        withAnimation(.spring(duration: 0.6)) { user.onboarded = true }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).display(30).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.inter(16)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Fond d'option façon « tuile de tri » du site : gris, blanc cerclé de bleu quand choisi
    private func optionBackground(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .fill(on ? Color.white : Theme.gray)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
            .shadow(color: on ? Theme.accent.opacity(0.12) : .clear, radius: 10, y: 4)
    }

    // MARK: 0 — Bienvenue (reprend le hero du site)
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Le ciel,\nau juste prix.").display(40).foregroundStyle(Theme.ink)
                    Text("Comparez les vols de 48 compagnies et réservez directement sur leur site, sans frais.")
                        .font(.inter(17)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                HStack {
                    Spacer()
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [.white, Color(hex: "#F1F1F4"), Color(hex: "#E1E1E6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: .black.opacity(0.18), radius: 22, y: 16)
                        PlacePhoto(code: "HERO", width: 700)
                            .scaleEffect(1.3)
                            .offset(x: drift ? -22 : 22)
                            .clipShape(Capsule(style: .continuous))
                            .padding(12)
                            .overlay(Capsule(style: .continuous).inset(by: 12).strokeBorder(.black.opacity(0.06)))
                    }
                    .frame(width: 180, height: 246)
                    .onAppear { withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { drift = true } }
                    Spacer()
                }
                VStack(spacing: 8) {
                    feature("tag", "Le prix d'abord", "Chaque recherche commence par le moins cher.")
                    feature("bell", "Prévenu des baisses", "Une notification quand un trajet baisse.")
                    feature("arrow.up.right", "Réservé chez la compagnie", "Sans frais, sans intermédiaire.")
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36).background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(15, .semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.inter(14)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: 1 — Prénom
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Comment vous appelez-vous ?", "Pour vous saluer à chaque ouverture. Facultatif : il reste sur votre iPhone.")
            HStack(spacing: 12) {
                Image(systemName: "person").foregroundStyle(Theme.faint)
                TextField("Votre prénom", text: $profile.firstName)
                    .font(.inter(20, .semibold))
                    .textContentType(.givenName)
                    .submitLabel(.continue)
                    .focused($nameFocused)
                    .onSubmit { go(1) }
            }
            .padding(.horizontal, 18).frame(height: 58)
            .background(optionBackground(nameFocused))
            .padding(.horizontal, 24)
            if !profile.firstName.isEmpty {
                Text("Enchanté, \(profile.firstName).").font(.inter(17, .medium)).foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            Spacer()
        }
        .animation(.spring(duration: 0.3), value: profile.firstName.isEmpty)
        .animation(.easeOut(duration: 0.2), value: nameFocused)
        .onAppear { if !Demo.isOnboarding { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nameFocused = true } } }
    }

    // MARK: 2 — Ville de départ
    private var cityStep: some View {
        let popular = ["PAR", "LYS", "NCE", "MRS", "TLS", "BOD", "NTE", "LON", "BRU", "GVA", "YUL", "CMN"]
        let results = cityQuery.isEmpty ? popular : store.searchPlaces(cityQuery)
        return VStack(alignment: .leading, spacing: 16) {
            header("D'où partez-vous le plus souvent ?", "Votre ville de départ par défaut. Vous pourrez toujours en choisir une autre.")
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
                    TextField("Ville ou aéroport", text: $cityQuery).font(.inter(16)).autocorrectionDisabled()
                }
                .padding(.horizontal, 16).frame(height: 46)
                .background(Theme.gray, in: Capsule())
                Button {
                    locating = true
                    Task {
                        if let loc = await LocationHelper().currentLocation() {
                            withAnimation(.spring) { profile.homeCode = store.nearestPlace(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) }
                        }
                        locating = false
                    }
                } label: {
                    Group { if locating { ProgressView() } else { Image(systemName: "location").font(.system(size: 16, weight: .semibold)) } }
                        .foregroundStyle(Theme.accent)
                        .frame(width: 46, height: 46)
                        .background(Theme.accentBg, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Utiliser ma position")
            }
            .padding(.horizontal, 24)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 18) {
                    ForEach(results, id: \.self) { code in
                        let selected = profile.homeCode == code
                        Button { withAnimation(.spring(duration: 0.3)) { profile.homeCode = code } } label: {
                            VStack(spacing: 8) {
                                PlacePhoto(code: code, width: 300)
                                    .frame(width: 72, height: 96)
                                    .clipShape(Capsule(style: .continuous))
                                    .padding(4)
                                    .overlay(Capsule(style: .continuous).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2.5))
                                    .overlay(alignment: .topTrailing) {
                                        if selected {
                                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                                .frame(width: 22, height: 22).background(Theme.accent, in: Circle())
                                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                                .transition(.scale)
                                        }
                                    }
                                    .scaleEffect(selected ? 1.04 : 1)
                                VStack(spacing: 1) {
                                    Text(store.city(code)).font(.inter(14, selected ? .semibold : .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Text(code).font(.inter(11, .medium)).foregroundStyle(Theme.faint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(store.city(code)), \(code)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .sensoryFeedback(.selection, trigger: profile.homeCode)
    }

    // MARK: 3 — Envies
    private var vibesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header("Qu'est-ce qui vous fait voyager ?", "Une ou plusieurs envies : nous vous suggérerons les bonnes destinations.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Vibe.allCases) { v in
                        let on = profile.vibes.contains(v)
                        Button {
                            withAnimation(.spring(duration: 0.3)) { if on { profile.vibes.remove(v) } else { profile.vibes.insert(v) } }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                PlacePhoto(code: v.photoCode, width: 500)
                                    .frame(height: 116)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: on ? "checkmark" : "plus")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(on ? Color.white : Theme.ink)
                                            .frame(width: 26, height: 26)
                                            .background(on ? Theme.accent : Color.white.opacity(0.92), in: Circle())
                                            .padding(8)
                                    }
                                Text(v.label).font(.inter(15, .semibold)).foregroundStyle(Theme.ink)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .padding(.horizontal, 6).padding(.bottom, 4)
                            }
                            .padding(6)
                            .background(optionBackground(on))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(v.label)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.selection, trigger: profile.vibes)
    }

    // MARK: 4 — Voyageurs
    private var companionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Avec qui voyagez-vous ?", "Le nombre de voyageurs sera pré-rempli. Les prix restent affichés par adulte.")
            VStack(spacing: 10) {
                ForEach(Companions.allCases) { c in
                    let on = profile.companions == c
                    Button { withAnimation(.spring(duration: 0.3)) { profile.companions = c } } label: {
                        HStack(spacing: 14) {
                            Image(systemName: c.symbol).font(.system(size: 17, weight: .medium))
                                .foregroundStyle(on ? Color.white : Theme.accent)
                                .frame(width: 42, height: 42)
                                .background(on ? Theme.accent : Theme.accentBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.label).font(.inter(16, .semibold)).foregroundStyle(Theme.ink)
                                Text(c.detail).font(.inter(14)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Circle().strokeBorder(on ? Theme.accent : Theme.gray2, lineWidth: on ? 7 : 2).frame(width: 22, height: 22)
                        }
                        .padding(12)
                        .background(optionBackground(on))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .sensoryFeedback(.selection, trigger: profile.companions)
    }

    // MARK: 5 — Budget & habitudes
    private var budgetStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header("Votre budget par vol", "Par adulte et par trajet. Nous montrerons d'abord ce qui tient dedans.")
                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.budget >= 1500 ? "Sans limite" : euros(profile.budget))
                        .display(46)
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(profile.budget)))
                        .animation(.snappy, value: profile.budget)
                    Slider(value: Binding(get: { Double(profile.budget) }, set: { profile.budget = Int($0) }), in: 50...1500, step: 10)
                        .tint(Theme.accent)
                        .accessibilityValue(euros(profile.budget))
                    HStack { Text("50 €"); Spacer(); Text("1 500 € et +") }.font(.inter(12)).foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 24)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cabine").font(.inter(14, .semibold)).foregroundStyle(Theme.muted)
                    SegmentedPicker(options: [(Cabin.eco, "Économique"), (Cabin.prem, "Premium"), (Cabin.bus, "Affaires")], selection: $profile.cabin)
                }
                .padding(.horizontal, 24)
                VStack(spacing: 0) {
                    Toggle("Je voyage avec un bagage en soute", isOn: $profile.bagUsually).font(.inter(15)).padding(14)
                    Divider().padding(.leading, 14)
                    Toggle("Je préfère les vols directs", isOn: $profile.directPreferred).font(.inter(15)).padding(14)
                }
                .tint(Color(hex: "#34C759"))
                .background(Theme.gray, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.selection, trigger: profile.budget / 50)
    }

    // MARK: 6 — Notifications
    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            header("Ne ratez plus une baisse de prix", "Surveillez un trajet d'un geste : nous vous prévenons dès qu'il devient moins cher.")
            // Aperçu de notification, comme dans l'encart « app » du site
            HStack(alignment: .top, spacing: 12) {
                BrandMark(height: 20)
                    .frame(width: 38, height: 38)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(store.city(profile.homeCode)) → Lisbonne").font(.inter(15, .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("maintenant").font(.inter(12)).foregroundStyle(Theme.faint)
                    }
                    Text("Le prix a baissé de 18 € : 59 € le 14 nov.").font(.inter(14)).foregroundStyle(Theme.ink2)
                }
            }
            .padding(14)
            .background(Theme.gray, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
            .offset(y: notifShown ? 0 : -14)
            .opacity(notifShown ? 1 : 0)
            .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.3).delay(0.3)) { notifShown = true } }
            Button {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { user.notificationsAllowed = granted; go(1) }
                }
            } label: { Label("Activer les alertes", systemImage: "bell") }
            .buttonStyle(PillButtonStyle(prominent: false))
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: 7 — Prêt
    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            header(profile.firstName.isEmpty ? "C'est prêt." : "C'est prêt, \(profile.firstName).",
                   "Au départ de \(store.city(profile.homeCode)), \(profile.budget >= 1500 ? "tous budgets" : "jusqu'à \(euros(profile.budget))") : de quoi commencer.")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    if suggestions.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule(style: .continuous).fill(Theme.gray).frame(width: 150, height: 200).shimmering()
                        }
                    }
                    ForEach(suggestions) { d in
                        VStack(alignment: .leading, spacing: 10) {
                            Porthole(code: d.code).frame(width: 150)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.city(d.code)).font(.inter(17, .semibold)).foregroundStyle(Theme.ink)
                                Text("dès \(euros(d.price)) · \(Fmt.duration(d.duration))").font(.inter(14)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 4)
                        }
                        .scrollTransition { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.92).opacity(phase.isIdentity ? 1 : 0.6)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: 270)
            Spacer()
        }
    }
    private func loadSuggestions() {
        let p = profile
        Task.detached(priority: .userInitiated) {
            let list = FlightStore.shared.suggestions(for: p, limit: 6)
            await MainActor.run { withAnimation(.spring) { suggestions = list } }
        }
    }
}
