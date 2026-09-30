import SwiftUI
import UserNotifications

@main
struct EnvolApp: App {
    @State private var user = UserData()
    @State private var ready = false
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if ready {
                    RootView()
                        .transition(.opacity)
                } else {
                    SplashView()
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .environment(user)
            .environment(\.font, .inter(16))          // Inter partout par défaut, comme sur le site
            .tint(Theme.accent)
            .preferredColorScheme(.light)             // l'identité Envol est claire
            .task {
                // La base (10 000 vols) est chargée en arrière-plan pendant l'écran de lancement
                await Task.detached(priority: .userInitiated) { _ = FlightStore.shared }.value
                Demo.prepare(user)
                withAnimation(.smooth(duration: 0.45)) { ready = true }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && ready && Demo.screen == nil { user.checkAlerts() }
            }
        }
    }
}

/// Affiche les notifications de baisse de prix même quand l'app est ouverte.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct SplashView: View {
    @State private var fly = false
    var body: some View {
        VStack(spacing: 20) {
            BrandMark(height: 44)
                .scaleEffect(fly ? 1 : 0.9)
                .opacity(fly ? 1 : 0.5)
            Text("Envol").display(32, .semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { fly = true } }
    }
}

enum AppTab: Int, CaseIterable, Identifiable {
    case flights, explore, favorites, alerts, profile
    var id: Int { rawValue }
    var label: String { switch self { case .flights: "Vols"; case .explore: "Explorer"; case .favorites: "Favoris"; case .alerts: "Alertes"; case .profile: "Profil" } }
    var symbol: String { switch self { case .flights: "airplane"; case .explore: "map"; case .favorites: "heart"; case .alerts: "bell"; case .profile: "person" } }
}

struct RootView: View {
    @Environment(UserData.self) private var user
    @State private var tab = AppTab(rawValue: Demo.tab) ?? .flights

    var body: some View {
        TabView(selection: $tab) {
            SearchHomeView().tag(AppTab.flights).toolbar(.hidden, for: .tabBar).safeAreaPadding(.bottom, 76)
            ExploreView().tag(AppTab.explore).toolbar(.hidden, for: .tabBar).safeAreaPadding(.bottom, 76)
            FavoritesView().tag(AppTab.favorites).toolbar(.hidden, for: .tabBar).safeAreaPadding(.bottom, 76)
            AlertsView().tag(AppTab.alerts).toolbar(.hidden, for: .tabBar).safeAreaPadding(.bottom, 76)
            ProfileView().tag(AppTab.profile).toolbar(.hidden, for: .tabBar).safeAreaPadding(.bottom, 76)
        }
        .overlay(alignment: .bottom) { EnvolTabBar(tab: $tab, badges: [.favorites: user.favorites.count, .alerts: user.alerts.count]) }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: Binding(get: { !user.onboarded }, set: { _ in })) {
            OnboardingView()
                .environment(user)
                .environment(\.font, .inter(16))
                .interactiveDismissDisabled()
        }
    }
}

/// Barre d'onglets flottante en verre dépoli (même matière que les menus du site)
struct EnvolTabBar: View {
    @Binding var tab: AppTab
    var badges: [AppTab: Int] = [:]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { t in
                let on = t == tab
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.25)) { tab = t }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: on && t != .flights ? t.symbol + ".fill" : t.symbol)
                            .font(.system(size: 17, weight: on ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if let n = badges[t], n > 0, !on {
                                    Circle().fill(Theme.accent).frame(width: 8, height: 8).overlay(Circle().stroke(.white, lineWidth: 1.5)).offset(x: 4, y: -2)
                                }
                            }
                        if on { Text(t.label).font(.inter(14, .semibold)).lineLimit(1).fixedSize() }
                    }
                    .foregroundStyle(on ? Color.white : Theme.ink2)
                    .padding(.horizontal, on ? 16 : 12)
                    .frame(height: 44)
                    .frame(maxWidth: on ? nil : .infinity)
                    .background {
                        if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "tab", in: ns).shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 4) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.label + ((badges[t] ?? 0) > 0 ? ", \(badges[t]!)" : ""))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(.white.opacity(0.6)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: tab)
    }
}
