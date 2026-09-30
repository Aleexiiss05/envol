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
        VStack(spacing: 18) {
            Image(systemName: "airplane")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .offset(x: fly ? 30 : -30, y: fly ? -8 : 8)
                .opacity(fly ? 1 : 0.4)
            Text("Envol").font(.system(size: 34, weight: .bold)).tracking(-0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { fly = true } }
    }
}

struct RootView: View {
    @Environment(UserData.self) private var user
    @State private var tab = Demo.tab
    var body: some View {
        TabView(selection: $tab) {
            SearchHomeView()
                .tabItem { Label("Vols", systemImage: "airplane") }
                .tag(0)
            ExploreView()
                .tabItem { Label("Explorer", systemImage: "map") }
                .tag(1)
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "heart") }
                .badge(user.favorites.count)
                .tag(2)
            AlertsView()
                .tabItem { Label("Alertes", systemImage: "bell") }
                .badge(user.alerts.count)
                .tag(3)
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .fullScreenCover(isPresented: Binding(get: { !user.onboarded }, set: { _ in })) {
            OnboardingView()
                .environment(user)
                .interactiveDismissDisabled()
        }
    }
}
