import UIKit
import NSDK

/// Bosh menyu: ikkala skan rejimidan birini tanlash.
final class MainMenuViewController: UIViewController {

    private let arManager: ARManager

    init(arManager: ARManager) {
        self.arManager = arManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scans"
        view.backgroundColor = .systemBackground

        let versionLabel = UILabel()
        let version = NSDKSession.version()
        versionLabel.text = version.isEmpty ? "NSDK" : "NSDK v\(version)"
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabel
        versionLabel.textAlignment = .center

        let meshButton = makeMenuButton(
            title: "3D Mesh skan",
            subtitle: "Xonaning 3D geometrik modeli + OBJ eksport",
            color: .systemBlue,
            action: #selector(openMeshScan)
        )
        let vpsButton = makeMenuButton(
            title: "Xona xaritasi (VPS)",
            subtitle: "Xonani eslab qolish va qayta lokalizatsiya",
            color: .systemPurple,
            action: #selector(openRoomScan)
        )

        let stack = UIStackView(arrangedSubviews: [meshButton, vpsButton, versionLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            meshButton.heightAnchor.constraint(equalToConstant: 72),
            vpsButton.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    @objc private func openMeshScan() {
        navigationController?.pushViewController(
            MeshScanViewController(arManager: arManager), animated: true
        )
    }

    @objc private func openRoomScan() {
        navigationController?.pushViewController(
            RoomScanViewController(arManager: arManager), animated: true
        )
    }

    private func makeMenuButton(
        title: String, subtitle: String, color: UIColor, action: Selector
    ) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.subtitle = subtitle
        config.baseBackgroundColor = color
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleAlignment = .center
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}
