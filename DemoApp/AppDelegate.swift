import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = ViewController()
        let navigationController = PlayerNavigationController(rootViewController: viewController)
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        return true
    }

    // 根據全屏狀態決定支援的方向
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let isPlayerFullScreen = UserDefaults.standard.bool(forKey: "DXPlayerSDK.isPlayerFullScreen")
        if isPlayerFullScreen {
            // 全屏時支援橫屏
            return .landscape
        }
        // 非全屏時支援豎屏和橫屏（允許自動旋轉）
        return .allButUpsideDown
    }
}

// 自定義 NavigationController 支持方向旋轉
class PlayerNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        let isPlayerFullScreen = UserDefaults.standard.bool(forKey: "DXPlayerSDK.isPlayerFullScreen")
        if isPlayerFullScreen {
            // 全屏時支援橫屏
            return .landscape
        }
        // 非全屏時支援豎屏和橫屏（允許自動旋轉）
        return .allButUpsideDown
    }

    override var shouldAutorotate: Bool {
        return true
    }
}
