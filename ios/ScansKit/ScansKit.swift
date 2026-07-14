import UIKit
import NSDK

/// Kadastr Flutter ilovasi uchun ScansKit kirish nuqtasi.
///
/// Profildagi skan-picker'da **"#1"** bosilganda `AppDelegate` shu menyuni
/// present qiladi (`kadastr/nsdk_scanner` MethodChannel orqali). nsdk'ning
/// `AppDelegate`/`SceneDelegate`/`MainMenu`-root oqimi shu yerda modal present
/// oqimiga moslashtirilgan.
public enum ScansKit {

    /// Skan bu qurilmada mavjudmi (iOS 17+). LiDAR alohida — u bo'lmasa ham
    /// menyu ochiladi, skan ekrani ichida ogohlantiriladi.
    public static var isAvailable: Bool {
        if #available(iOS 17, *) { return true }
        return false
    }

    /// nsdk bosh menyusi: **3D Mesh skan** + **Xona xaritasi (VPS)**.
    ///
    /// Kadastr uni fullScreen modal qilib present qiladi. Butun oqim uchun bitta
    /// `NSDKSession` shu VC daraxti umriga bog'lanadi
    /// (`session` ← `ARManager` ← `MainMenuViewController` ← `nav` ← present).
    @available(iOS 17, *)
    public static func makeMainMenu() -> UIViewController {
        // NSDKSession init + UIKit main-actor-isolated. Flutter MethodChannel
        // handler main thread'da chaqiriladi, shuning uchun assumeIsolated xavfsiz
        // (nonisolated qolib, AppDelegate'dan to'g'ridan chaqirsa bo'ladi).
        MainActor.assumeIsolated {
            let nsdkSession = NSDKSession(
                accessToken: NSDKConfig.accessToken,
                useLidar: ARUtils.isLidarAvailable()
            )
            let arManager = ARManager(nsdkSession: nsdkSession)
            let menu = MainMenuViewController(arManager: arManager)
            let nav = UINavigationController(rootViewController: menu)
            // Modal ochilgani uchun yopish tugmasi (nsdk MainMenu nav-root deb
            // mo'ljallangan — Flutter'ga qaytish tugmasini qo'shamiz).
            menu.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Yopish",
                primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
            )
            nav.modalPresentationStyle = .fullScreen
            return nav
        }
    }
}

/// Runner (kadastr) `import ScansKit` QILMAYDI — ScansKit iOS 17, Runner iOS 15,
/// va Swift yuqori-min-deployment modulni past target'ga import qildirmaydi.
/// Shuning uchun Runner framework'ni ish vaqtida `Bundle.load()` bilan yuklab, shu
/// `@objc` entry'ni ObjC runtime orqali topib chaqiradi (dlopen pattern). iOS
/// 15/16'da framework umuman yuklanmaydi → app xavfsiz.
@objc(NSDKScannerEntry)
public final class NSDKScannerEntry: NSObject {
    /// nsdk bosh menyusini `presenter` ustidan modal ochadi (iOS 17+).
    @objc public func present(from presenter: UIViewController) {
        if #available(iOS 17, *) {
            presenter.present(ScansKit.makeMainMenu(), animated: true)
        }
    }
}
