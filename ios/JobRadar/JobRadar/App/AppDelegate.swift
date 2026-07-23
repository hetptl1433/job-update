import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        BackgroundRefreshManager.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundRefreshManager.shared.schedule()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in try? await AppSession.shared.api.registerDeviceToken(token) }
    }
}
