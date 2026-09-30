import SwiftUI
import UserNotifications

/// Accueil en 8 écrans : on apprend à connaître le voyageur pour personnaliser l'app dès la première recherche.
struct OnboardingView: View {
    @Environment(UserData.self) private var user
    @State private var page = 0
    @State private var profile = TravelProfile()
    @State private var forward = true
    @State private var cityQuery = ""
    @State private var locating = false
    @State private var suggestions: [FlightStore.Destination] = []
    @FocusState private var nameFocused: Bool
    private let store = FlightStore.shared
    private let titles = ["Bienvenue", "Prénom", "Départ", "Envies", "Voyageurs", "Budget", "Alertes", "Prêt"]

    var body: some View {
        VStack(spacing: 0) {
            if page > 0 {
                FlightPathProgress(steps: titles.dropFirst().map { _ in "" }, current: page - 1, compact: true)
                    .frame(height: 44)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
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
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(Color(.systemBackground))
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

    // MARK: Navigation
    private func go(_ delta: Int) {
        forward = delta > 0
        nameFocused = false
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) { page = max(0, min(7, page + delta)) }
        if page == 7 { loadSuggestions() }
    }
    private var footer: some View {
        VStack(spacing: 10) {
            Button { page == 7 ? finish() : go(1) } label: {
                Text(page == 0 ? "Commencer" : page == 7 ? "C'est parti" : "Continuer")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
            .disabled(page == 3 && profile.vibes.isEmpty)
            HStack {
                if page > 0 && page < 7 {
                    Button("Retour") { go(-1) }.foregroundStyle(.secondary)
                    Spacer()
                    Button(page == 3 ? "Tout m'intéresse" : "Passer") {
                        if page == 3 { profile.vibes = Set(Vibe.allCases) }
                        go(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .frame(height: 22)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
    private func finish() {
        user.profile = profile
        user.bagIncluded = profile.bagUsually
        withAnimation(.spring(duration: 0.6)) { user.onboarded = true }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    // MARK: 0 — Bienvenue
    @State private var drift = false
    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            ZStack {
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.2), radius: 24, y: 16)
                PlacePhoto(code: "HERO", width: 700)
                    .scaleEffect(1.25)
                    .offset(x: drift ? -26 : 26)
                    .clipShape(Capsule(style: .continuous))
                    .padding(14)
            }
            .frame(width: 210, height: 290)
            .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true } }
            VStack(spacing: 10) {
                Text("Envol").font(.system(size: 44, weight: .bold)).tracking(-1)
                Text("Le ciel, au juste prix.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("tag", "Le prix d'abord", "Chaque recherche commence par le vol le moins cher.")
                feature("bell.badge", "Prévenu des baisses", "Une notification quand un trajet devient moins cher.")
                feature("arrow.up.forward.app", "Réservé chez la compagnie", "Sans frais, sans intermédiaire.")
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
    }
    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 1 — Prénom
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            header("Comment vous appelez-vous ?", "Pour vous saluer à chaque ouverture. Facultatif, il reste sur votre iPhone.")
            TextField("Votre prénom", text: $profile.firstName)
                .font(.title2.weight(.semibold))
                .textContentType(.givenName)
                .submitLabel(.continue)
                .focused($nameFocused)
                .padding(18)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 24)
                .onSubmit { go(1) }
            if !profile.firstName.isEmpty {
                Text("Enchanté, \(profile.firstName) 👋").font(.title3).padding(.horizontal, 24).transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            Spacer()
        }
        .animation(.spring(duration: 0.3), value: profile.firstName.isEmpty)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true } }
    }

    // MARK: 2 — Ville de départ
    private var cityStep: some View {
        let popular = ["PAR", "LYS", "NCE", "MRS", "TLS", "BOD", "NTE", "LON", "BRU", "GVA", "YUL", "CMN"]
        let results = cityQuery.isEmpty ? popular : store.searchPlaces(cityQuery)
        return VStack(alignment: .leading, spacing: 16) {
            header("D'où partez-vous le plus souvent ?", "Votre ville de départ par défaut. Vous pourrez toujours en choisir une autre.")
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Ville ou aéroport", text: $cityQuery).autocorrectionDisabled()
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    locating = true
                    Task {
                        if let loc = await LocationHelper().currentLocation() {
                            withAnimation(.spring) { profile.homeCode = store.nearestPlace(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) }
                        }
                        locating = false
                    }
                } label: {
                    Group { if locating { ProgressView() } else { Image(systemName: "location.fill") } }
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Utiliser ma position")
            }
            .padding(.horizontal, 24)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                    ForEach(results, id: \.self) { code in
                        let selected = profile.homeCode == code
                        Button { withAnimation(.spring(duration: 0.3)) { profile.homeCode = code } } label: {
                            VStack(spacing: 8) {
                                PlacePhoto(code: code, width: 300)
                                    .frame(width: 76, height: 100)
                                    .clipShape(Capsule(style: .continuous))
                                    .overlay(Capsule(style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
                                    .overlay(alignment: .topTrailing) {
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.white, Color.accentColor)
                                                .offset(x: 6, y: -4).transition(.scale)
                                        }
                                    }
                                    .scaleEffect(selected ? 1.05 : 1)
                                Text(store.city(code)).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                                Text(code).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 20) {
            header("Qu'est-ce qui vous fait voyager ?", "Choisissez une ou plusieurs envies : nous vous suggérerons les bonnes destinations.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Vibe.allCases) { v in
                    let on = profile.vibes.contains(v)
                    Button {
                        withAnimation(.spring(duration: 0.3)) { if on { profile.vibes.remove(v) } else { profile.vibes.insert(v) } }
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            PlacePhoto(code: v.photoCode, width: 500)
                                .frame(height: 170)
                                .clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                            Text(v.label).font(.headline).foregroundStyle(.white).padding(12)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 3))
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(on ? Color.white : Color.white.opacity(0.8), on ? Color.accentColor : Color.clear)
                                .padding(10)
                        }
                        .scaleEffect(on ? 0.97 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(v.label)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .sensoryFeedback(.selection, trigger: profile.vibes)
    }

    // MARK: 4 — Voyageurs
    private var companionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Avec qui voyagez-vous ?", "Le nombre de voyageurs sera pré-rempli. Les prix affichés restent par adulte.")
            VStack(spacing: 10) {
                ForEach(Companions.allCases) { c in
                    let on = profile.companions == c
                    Button { withAnimation(.spring(duration: 0.3)) { profile.companions = c } } label: {
                        HStack(spacing: 16) {
                            Image(systemName: c.symbol).font(.title2).frame(width: 44, height: 44)
                                .foregroundStyle(on ? Color.white : Color.accentColor)
                                .background(on ? Color.accentColor : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.label).font(.headline)
                                Text(c.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if on { Image(systemName: "checkmark").font(.headline).foregroundStyle(.tint).transition(.scale) }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 22) {
            header("Votre budget par vol", "Par adulte et par trajet. Nous vous montrerons d'abord ce qui tient dedans.")
            VStack(spacing: 6) {
                Text(profile.budget >= 1500 ? "Sans limite" : euros(profile.budget))
                    .font(.system(size: 56, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(profile.budget)))
                    .animation(.snappy, value: profile.budget)
                Slider(value: Binding(get: { Double(profile.budget) }, set: { profile.budget = Int($0) }), in: 50...1500, step: 10)
                    .accessibilityValue(euros(profile.budget))
                HStack { Text("50 €"); Spacer(); Text("1 500 € et +") }.font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            VStack(spacing: 0) {
                Picker("Cabine", selection: $profile.cabin) {
                    ForEach([Cabin.eco, .prem, .bus]) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).padding(14)
                Divider().padding(.leading, 14)
                Toggle("Je voyage avec un bagage en soute", isOn: $profile.bagUsually).padding(14)
                Divider().padding(.leading, 14)
                Toggle("Je préfère les vols directs", isOn: $profile.directPreferred).padding(14)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)
            Spacer()
        }
        .sensoryFeedback(.selection, trigger: profile.budget / 50)
    }

    // MARK: 6 — Notifications
    @State private var bellBounce = 0
    private var notificationsStep: some View {
        VStack(spacing: 24) {
            header("Ne ratez plus une baisse de prix", "Surveillez un trajet d'un geste : nous vous prévenons dès qu'il devient moins cher.")
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 180, height: 180)
                Image(systemName: "bell.badge.fill").font(.system(size: 72)).foregroundStyle(Color.red, Color.accentColor)
                    .symbolEffect(.bounce, value: bellBounce)
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { bellBounce += 1 } }
            VStack(spacing: 4) {
                Text("\(store.city(profile.homeCode)) → Lisbonne").font(.headline)
                Text("Le prix a baissé de 18 € : 59 € le 14 nov.").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)
            Button {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { user.notificationsAllowed = granted; go(1) }
                }
            } label: {
                Label("Activer les alertes", systemImage: "bell").font(.headline)
            }
            .buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
            Spacer(minLength: 0)
        }
    }

    // MARK: 7 — Prêt
    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(profile.firstName.isEmpty ? "C'est prêt." : "C'est prêt, \(profile.firstName).",
                   "Au départ de \(store.city(profile.homeCode)), \(profile.budget >= 1500 ? "tous budgets" : "jusqu'à \(euros(profile.budget))") : voici de quoi commencer.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if suggestions.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 20).fill(.quaternary).frame(width: 170, height: 260)
                        }
                    }
                    ForEach(suggestions) { d in
                        VStack(alignment: .leading, spacing: 8) {
                            Porthole(code: d.code).frame(width: 170)
                            Text(store.city(d.code)).font(.headline)
                            Text("dès \(euros(d.price)) · \(Fmt.duration(d.duration))").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .scrollTransition { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.9).opacity(phase.isIdentity ? 1 : 0.6)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
            }
            .scrollTargetBehavior(.viewAligned)
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
