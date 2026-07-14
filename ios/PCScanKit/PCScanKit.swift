import UIKit
import SwiftUI

/// Kadastr Flutter ilovasi uchun PCScanKit kirish nuqtasi.
///
/// Profildagi skan-picker'da **"#2"** bosilganda `AppDelegate` shu ekranni
/// present qiladi (`kadastr/pcscan_scanner` MethodChannel orqali). PCScan'ning
/// `@main App` / `WindowGroup` oqimi shu yerda modal present oqimiga
/// moslashtirilgan: `RootView` + `AppState` bitta `UIHostingController` ga
/// o'raladi, uning umri modal umriga bog'lanadi.
public enum PCScanKit {

    /// Skan bu qurilmada mavjudmi (iOS 17+ — RoomPlan/Object Capture). LiDAR
    /// alohida tekshiriladi (`DeviceCapability`), yo'q bo'lsa onboarding
    /// ogohlantiradi — shuning uchun bu yerda faqat OS versiyasi tekshiriladi.
    public static var isAvailable: Bool {
        if #available(iOS 17, *) { return true }
        return false
    }

    /// PCScan ildiz ekrani (onboarding → scanning → processing → viewer).
    ///
    /// Kadastr uni fullScreen modal qilib present qiladi. PCScan SwiftUI UI'siga
    /// tegmasdan yopish uchun hosting controller ustiga suzuvchi "Yopish" tugmasi
    /// qo'yiladi (PCScan o'zini butun oyna deb hisoblaydi, ichki close yo'q).
    @available(iOS 17, *)
    public static func makeRoot() -> UIViewController {
        MainActor.assumeIsolated {
            let appState = AppState()
            let root = RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
            let host = UIHostingController(rootView: root)
            let container = PCScanContainerViewController(child: host)
            container.modalPresentationStyle = .fullScreen
            return container
        }
    }
}

/// `UIHostingController` ni to'liq ekranga joylab, tepa-chapga suzuvchi "Yopish"
/// tugmasi qo'shadigan konteyner. Tugma butun modalni yopadi (Flutter'ga qaytish).
@available(iOS 17, *)
final class PCScanContainerViewController: UIViewController {
    private let child: UIViewController

    init(child: UIViewController) {
        self.child = child
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) ishlatilmaydi") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        child.didMove(toParent: self)

        let close = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: "xmark")
        cfg.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        close.configuration = cfg
        close.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }
}

/// Runner (kadastr) `import PCScanKit` QILMAYDI — PCScanKit iOS 17, Runner iOS 15,
/// va Swift yuqori-min-deployment modulni past target'ga import qildirmaydi.
/// Shuning uchun Runner framework'ni ish vaqtida `Bundle.load()` bilan yuklab, shu
/// `@objc` entry'ni ObjC runtime orqali topib chaqiradi (dlopen pattern). iOS
/// 15/16'da framework umuman yuklanmaydi → app xavfsiz.
@objc(PCScanEntry)
public final class PCScanEntry: NSObject {
    /// PCScan ildiz ekranini `presenter` ustidan modal ochadi (iOS 17+).
    @objc public func present(from presenter: UIViewController) {
        if #available(iOS 17, *) {
            presenter.present(PCScanKit.makeRoot(), animated: true)
        }
    }
}
