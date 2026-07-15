import UIKit
import Combine
import RealityKit
import NSDK

/// Xona skani ekrani: skan qilish → xaritani saqlash → qayta lokalizatsiya.
///
/// Hammasi on-device ishlaydi (Device Mapping): server va token talab qilinmaydi.
final class RoomScanViewController: UIViewController {

    private let maxDisplayedPoints = 4000

    private let arManager: ARManager

    private var mappingSession: NSDKDeviceMappingSession!
    private var mapStorage: NSDKMapStorage!
    private var vps2Session: NSDKVps2Session!
    private var viewModel: RoomScanViewModel!

    private var isMapping = false
    private var isVpsRunning = false

    // MARK: - UI

    private let scanButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let loadButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    // MARK: - Scene

    private var mapAnchorEntity: AnchorEntity?
    private var cachedPointMaterial: UnlitMaterial?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
    private var vmCancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(arManager: ARManager) {
        self.arManager = arManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Xona skani"
        view.backgroundColor = .black

        arManager.nsdkView.setup(in: view)
        setupControls()
        setupSessions()
        setupViewModel()
        bindTrackingOverlay()

        loadButton.isHidden = listSavedMaps().isEmpty
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arManager.startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMapping {
            stopMapping()
        } else if isVpsRunning {
            vps2Session.stop()
            isVpsRunning = false
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arManager.stopSession()
        if isMovingFromParent {
            if let vps2Session {
                arManager.nsdkSession.destroy(vps2Session)
                self.vps2Session = nil
            }
            if let mappingSession {
                arManager.nsdkSession.destroy(mappingSession)
                self.mappingSession = nil
            }
            clearVisualization()
            cancellables.removeAll()
            vmCancellables.removeAll()
        }
    }

    // MARK: - Session Setup

    private func setupSessions() {
        let nsdkSession = arManager.nsdkSession

        mappingSession = nsdkSession.acquireDeviceMappingSession()
        mapStorage = nsdkSession.acquireMapStorage()
        vps2Session = nsdkSession.acquireVps2Session()

        // Faqat on-device rejim: lokal xaritaga lokalizatsiya, cloud o'chirilgan.
        var vpsConfig = NSDKVps2Session.Configuration()
        vpsConfig.deviceMapLocalizationEnabled = true
        vpsConfig.universalLocalizationEnabled = false
        vpsConfig.vpsMapLocalizationEnabled = false
        do {
            try vps2Session.configure(with: vpsConfig)
        } catch {
            print("[RoomScanViewController] VPS2 configure failed: \(error)")
        }
    }

    /// ViewModel'ni yaratadi (yoki qayta yaratadi) va obunalarni bog'laydi.
    /// Diskdan xarita yuklangandan keyin ham chaqiriladi — yangi VM storage'dagi
    /// xaritadan o'zini bootstrap qiladi.
    private func setupViewModel() {
        vmCancellables.removeAll()

        viewModel = RoomScanViewModel(
            mappingSession: mappingSession,
            mapStorage: mapStorage,
            vps2Session: vps2Session
        )

        // Root anchor paydo bo'lishi bilan VPS tracking'ni boshlaymiz.
        viewModel.$rootAnchorPayload
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] anchor in
                guard let self else { return }
                do {
                    _ = try vps2Session.trackAnchor(payload: anchor)
                } catch {
                    print("[RoomScanViewController] trackAnchor failed: \(error)")
                }
            }
            .store(in: &vmCancellables)

        // Yangi nuqtalar kelganda nuqta bulutini qayta chizamiz.
        viewModel.$points
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                guard let self, let transform = viewModel.anchorTransform,
                      !points.isEmpty else { return }
                visualizeMapPoints(points: points, anchorTransform: transform)
                statusLabel.text = "Lokalizatsiya qilindi — \(points.count) nuqta"
                statusLabel.textColor = .systemGreen
                saveButton.isHidden = isMapping
            }
            .store(in: &vmCancellables)

        // Anchor pozasini har freymda yangilaymiz — geometriya qayta qurilmaydi.
        viewModel.$anchorTransform
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transform in
                self?.mapAnchorEntity?.transform = Transform(matrix: transform)
            }
            .store(in: &vmCancellables)
    }

    private func bindTrackingOverlay() {
        arManager.frameState.$trackingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, !isMapping, !isVpsRunning else { return }
                switch state {
                case .normal:
                    statusLabel.text = "Tayyor — skan boshlashingiz mumkin"
                    statusLabel.textColor = .white
                case .limited:
                    statusLabel.text = "Tracking cheklangan — telefonni sekin harakatlantiring"
                    statusLabel.textColor = .systemOrange
                case .notAvailable:
                    statusLabel.text = "Tracking mavjud emas"
                    statusLabel.textColor = .systemRed
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Mapping Lifecycle

    private func startMapping() {
        setupViewModel()
        viewModel.resetForNewMapping()
        clearVisualization()
        if isVpsRunning {
            vps2Session.stop()
            isVpsRunning = false
        }

        mappingSession.start()
        mappingSession.startMapping()
        vps2Session.start()
        isVpsRunning = true
        isMapping = true

        scanButton.setTitle("Skanni to'xtatish", for: .normal)
        saveButton.isHidden = true
        loadButton.isHidden = true
        statusLabel.text = "Skan ketmoqda — xonani sekin aylaning…"
        statusLabel.textColor = .white
    }

    private func stopMapping() {
        mappingSession.stopMapping()
        mappingSession.stop()
        vps2Session.stop()
        isVpsRunning = false
        isMapping = false

        scanButton.setTitle("Skanni boshlash", for: .normal)
        saveButton.isHidden = viewModel.points.isEmpty
        loadButton.isHidden = listSavedMaps().isEmpty
        statusLabel.text = viewModel.points.isEmpty
            ? "Nuqta yig'ilmadi — qayta urinib ko'ring"
            : "Skan tugadi — xaritani saqlashingiz mumkin"
        statusLabel.textColor = .white
    }

    // MARK: - Actions

    @objc private func handleScanTap() {
        if isMapping { stopMapping() } else { startMapping() }
    }

    @objc private func handleSaveTap() {
        saveButton.isEnabled = false
        statusLabel.text = "Xarita tayyorlanmoqda…"
        statusLabel.textColor = .white

        // mapData() native xaritani serializatsiya qiladi — main thread'ni bloklamaslik
        // uchun background'da bajaramiz.
        let storage = mapStorage!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = storage.mapData()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                saveButton.isEnabled = true
                guard let buffer else {
                    statusLabel.text = "Saqlash uchun xarita topilmadi"
                    statusLabel.textColor = .systemRed
                    return
                }
                saveMapToDisk(buffer: buffer)
            }
        }
    }

    @objc private func handleLoadTap() {
        let maps = listSavedMaps()
        guard !maps.isEmpty else { return }

        let alert = UIAlertController(
            title: "Xaritani yuklash",
            message: "Saqlangan xonalardan birini tanlang",
            preferredStyle: .actionSheet
        )
        for name in maps {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                self?.loadMapFromDisk(fileName: name)
            })
        }
        alert.addAction(UIAlertAction(title: "Bekor qilish", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Save / Load

    private func saveMapToDisk(buffer: NSDKBuffer) {
        let mapData = Data(bytes: buffer.data, count: Int(buffer.dataSize))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "Xona-\(formatter.string(from: Date())).map"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let dir = try Self.mapsDirectory()
                try mapData.write(to: dir.appendingPathComponent(fileName))
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    saveButton.isHidden = true
                    loadButton.isHidden = false
                    statusLabel.text = "Xarita saqlandi: \(fileName)"
                    statusLabel.textColor = .systemGreen
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.statusLabel.text = "Saqlashda xato: \(error.localizedDescription)"
                    self?.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    private func loadMapFromDisk(fileName: String) {
        do {
            // VPS ishlayotganda storage'ga tegish mumkin emas — avval to'xtatamiz.
            if isVpsRunning {
                vps2Session.stop()
                isVpsRunning = false
            }
            mapStorage.clear()
            clearVisualization()

            let url = try Self.mapsDirectory().appendingPathComponent(fileName)
            let data = try Data(contentsOf: url)
            try mapStorage.addMap(map: NSDKBuffer(data: data))

            // Yangi VM yuklangan xaritadan rootAnchorPayload'ni bootstrap qiladi,
            // obuna darhol otiladi va quyidagi start()dan keyin trackAnchor chaqiriladi.
            setupViewModel()
            vps2Session.start()
            isVpsRunning = true

            statusLabel.text = "Lokalizatsiya kutilmoqda — skan qilingan joyga qarang…"
            statusLabel.textColor = .systemOrange
        } catch {
            statusLabel.text = "Yuklashda xato: \(error.localizedDescription)"
            statusLabel.textColor = .systemRed
        }
    }

    private static func mapsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("RoomMaps")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func listSavedMaps() -> [String] {
        guard let dir = try? Self.mapsDirectory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return urls.filter { $0.pathExtension == "map" }
            .map { $0.lastPathComponent }
            .sorted(by: >)
    }

    // MARK: - Point Cloud Rendering

    private func visualizeMapPoints(points: [SIMD3<Float>], anchorTransform: simd_float4x4) {
        clearVisualization()
        guard !points.isEmpty else { return }

        let step = max(1, points.count / maxDisplayedPoints)
        let halfSize: Float = 0.0035

        let baseVerts: [SIMD3<Float>] = [
            [-halfSize, -halfSize,  halfSize], [ halfSize, -halfSize,  halfSize],
            [ halfSize,  halfSize,  halfSize], [-halfSize,  halfSize,  halfSize],
            [-halfSize, -halfSize, -halfSize], [ halfSize, -halfSize, -halfSize],
            [ halfSize,  halfSize, -halfSize], [-halfSize,  halfSize, -halfSize],
        ]
        let baseIdx: [UInt32] = [
            0,1,2, 0,2,3,  5,4,7, 5,7,6,
            3,2,6, 3,6,7,  4,5,1, 4,1,0,
            1,5,6, 1,6,2,  4,0,3, 4,3,7,
        ]

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var vertexOffset: UInt32 = 0

        for i in stride(from: 0, to: points.count, by: step) {
            guard positions.count / baseVerts.count < maxDisplayedPoints else { break }
            let center = points[i]
            positions.append(contentsOf: baseVerts.map { $0 + center })
            indices.append(contentsOf: baseIdx.map { $0 + vertexOffset })
            vertexOffset += UInt32(baseVerts.count)
        }

        var descriptor = MeshDescriptor(name: "mapPoints")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            print("[RoomScanViewController] Failed to generate point mesh")
            return
        }

        if cachedPointMaterial == nil {
            cachedPointMaterial = UnlitMaterial(color: .init(red: 0.3, green: 0.8, blue: 0.0, alpha: 1.0))
        }

        let entity = ModelEntity(mesh: mesh, materials: [cachedPointMaterial!])
        let anchor = AnchorEntity()
        anchor.transform = Transform(matrix: anchorTransform)
        anchor.addChild(entity)

        arManager.nsdkView.scene.addAnchor(anchor)
        mapAnchorEntity = anchor
    }

    private func clearVisualization() {
        if let anchor = mapAnchorEntity {
            arManager.nsdkView.scene.removeAnchor(anchor)
        }
        mapAnchorEntity = nil
    }

    // MARK: - UI Setup

    private func setupControls() {
        func style(_ button: UIButton, title: String, color: UIColor) {
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = color
            button.layer.cornerRadius = 8
            button.titleLabel?.font = .boldSystemFont(ofSize: 16)
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }

        style(scanButton, title: "Skanni boshlash", color: .systemBlue)
        style(saveButton, title: "Xaritani saqlash", color: .systemGreen)
        style(loadButton, title: "Xaritani yuklash", color: .systemPurple)
        saveButton.isHidden = true
        loadButton.isHidden = true

        scanButton.addTarget(self, action: #selector(handleScanTap), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(handleSaveTap), for: .touchUpInside)
        loadButton.addTarget(self, action: #selector(handleLoadTap), for: .touchUpInside)

        statusLabel.text = ""
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scanButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            scanButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            scanButton.widthAnchor.constraint(equalToConstant: 160),
            scanButton.heightAnchor.constraint(equalToConstant: 44),

            // Save va Load chapda bitta joyni egallaydi — bir vaqtda faqat bittasi ko'rinadi.
            saveButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            saveButton.centerYAnchor.constraint(equalTo: scanButton.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 160),
            saveButton.heightAnchor.constraint(equalToConstant: 44),

            loadButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            loadButton.centerYAnchor.constraint(equalTo: scanButton.centerYAnchor),
            loadButton.widthAnchor.constraint(equalToConstant: 160),
            loadButton.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: scanButton.topAnchor, constant: -12),
        ])
    }
}
