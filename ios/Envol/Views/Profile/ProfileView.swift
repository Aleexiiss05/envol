import SwiftUI

struct ProfileView: View {
    @Environment(UserData.self) private var user
    @State private var pickingHome = false
    private let store = FlightStore.shared

    var body: some View {
        @Bindable var user = user
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Theme.ink)
                            Text(initials).font(.inter(.title2, .bold)).foregroundStyle(.white)
                        }
                        .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.profile.firstName.isEmpty ? "Voyageur" : user.profile.firstName).font(.inter(.title2, .bold))
                            Text("Au départ de \(store.city(user.profile.homeCode)) · membre depuis \(Day.format(user.profile.memberSince, "MMMMyyyy"))")
                                .font(.inter(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    HStack {
                        stat("\(user.searchCount)", "recherches")
                        Divider()
                        stat("\(user.favorites.count)", "favoris")
                        Divider()
                        stat("\(user.alerts.count)", "alertes")
                    }
                    .padding(.vertical, 4)
                }

                Section("Vous") {
                    TextField("Prénom", text: $user.profile.firstName).textContentType(.givenName)
                    Button { pickingHome = true } label: {
                        LabeledContent("Ville de départ") { Text("\(store.city(user.profile.homeCode)) (\(user.profile.homeCode))") }
                    }
                    .foregroundStyle(.primary)
                    Picker("Voyageurs", selection: $user.profile.companions) {
                        ForEach(Companions.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                }

                Section("Envies") {
                    ForEach(Vibe.allCases) { v in
                        Toggle(isOn: Binding(get: { user.profile.vibes.contains(v) }, set: { on in
                            if on { user.profile.vibes.insert(v) } else { user.profile.vibes.remove(v) }
                        })) { Text(v.label) }
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack { Text("Budget par vol"); Spacer(); Text(user.profile.budget >= 1500 ? "Sans limite" : euros(user.profile.budget)).foregroundStyle(.secondary).monospacedDigit().contentTransition(.numericText()) }
                        Slider(value: Binding(get: { Double(user.profile.budget) }, set: { user.profile.budget = Int($0) }), in: 50...1500, step: 10)
                    }
                    Picker("Cabine", selection: $user.profile.cabin) { ForEach(Cabin.allCases) { Text($0.label).tag($0) } }
                    Toggle("Bagage en soute habituellement", isOn: $user.profile.bagUsually)
                    Toggle("Vols directs de préférence", isOn: $user.profile.directPreferred)
                } header: { Text("Habitudes") } footer: {
                    Text("Ces réglages pré-remplissent vos recherches et orientent les suggestions de l'accueil.")
                }

                Section("Notifications") {
                    LabeledContent("Alertes de prix", value: user.notificationsAllowed ? "Activées" : "Désactivées")
                    if !user.notificationsAllowed {
                        Button("Activer les alertes") { user.requestNotifications() }
                    }
                }

                Section {
                    Button("Revoir l'accueil") { user.resetOnboarding() }
                    Button("Effacer l'historique de recherche", role: .destructive) { user.recents = []; user.searchCount = 0 }
                } footer: {
                    Text("Vos données restent sur cet iPhone. Envol ne crée pas de compte et ne vend aucune donnée.")
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $pickingHome) {
                PlacePicker(title: "Ville de départ", current: user.profile.homeCode) { user.profile.homeCode = $0 }
            }
            .onAppear { UNUserNotificationCenterWrapper.status { user.notificationsAllowed = $0 } }
            .sensoryFeedback(.selection, trigger: user.profile)
        }
    }

    private var initials: String {
        let n = user.profile.firstName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "✈︎" : String(n.prefix(1)).uppercased()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.inter(.title3, .bold)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.inter(.caption)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
