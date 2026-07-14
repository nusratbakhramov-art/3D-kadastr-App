import UIKit
import Combine
import RealityKit
import NSDK

/// 3D mesh skan ekrani: xonaning geometrik meshini real vaqtda quradi,
/// teksturali ko'rish va OBJ eksport imkonini beradi. To'liq on-device.
///
/// Skan paytida Scaniverse uslubidagi qamrov ko'rsatiladi: skan qilinMAgan
/// joylar qizil chiziqli, qilingan joylar shaffof (kamera ko'rinadi).
final class MeshScanViewController: UIViewController {

    private let arManager: ARManager

    private var meshingSession: NSDKMeshingSession?
    private var scanningSession: NSDKScanningSession?
    private var viewModel: MeshScanViewModel!
    private var coverageViewModel: ScanCoverageViewModel?
    private let keyframeStore = KeyframeStore()

    /// Skan-vaqti tekstura qamrovi (qizil=yaqinroq kerak, yashil=olingan)
    private let coverageOverlay = CoverageOverlay()
    private var lastKeyframeCount = 0
    private var coverageOn = true

    private var isMeshing = false
    private var isProcessing = false
    private var isStoppingForMemory = false
    private var chunkIds = Set<Int64>()

    /// Skanni to'xtatgach saqlangan xom geometriya (darhol rangli mesh uchun)
    private var finalGeometries: [Int64: ChunkGeometry]?
    /// Joriy skanning doimiy arxiv papkasi (Documents/Scans/<id>)
    private var currentScanFolder: URL?
    /// Skan tugagach qayta ishlangan model: yagona mesh + yagona atlas
    private var atlasModel: AtlasModel?
    /// Dense rangli nuqta buluti (PLY eksport uchun)
    private var pointCloudPLY: Data?
    /// Fallback: eski chunk-boyicha bake natijasi (atlas yiqilsa)
    private var bakedModel: [Int64: TextureBaker.BakedChunk]?

    // MARK: - UI

    private var visualizationView: TextureView!
    private let meshButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let viewButton = UIButton(type: .system)
    private let hqButton = UIButton(type: .system)
    private let splatButton = UIButton(type: .system)
    private let infoLabel = UILabel()
    private let timerLabel = UILabel()
    private let hintLabel = UILabel()

    private var scanTimer: Timer?
    private var scanStartDate: Date?

    private var cancellables = Set<AnyCancellable>()

    init(arManager: ARManager) {
        self.arManager = arManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "3D Mesh skan"
        view.backgroundColor = .black
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Skanlar", style: .plain, target: self, action: #selector(openLibrary)),
            UIBarButtonItem(title: "Qamrov ✓", style: .plain, target: self, action: #selector(toggleCoverage))
        ]

        arManager.nsdkView.setup(in: view)
        setupVisualizationView()
        setupControls()

        // Meshing: geometriya yig'ish
        let meshing = arManager.nsdkSession.acquireMeshingSession()
        meshingSession = meshing
        viewModel = MeshScanViewModel(meshingSession: meshing)

        // Scanning: qamrov vizualizatsiyasi (chiziqlar skan qilinmagan joylarda)
        let scanning = arManager.nsdkSession.acquireScanningSession()
        var scanConfig = NSDKScanningSession.Configuration()
        scanConfig.enableRaycastVisualization = true
        scanConfig.enableVoxelVisualization = false
        scanConfig.generateDepthsIfLidarUnavailable = true
        do {
            try scanning.configure(with: scanConfig)
        } catch {
            print("[MeshScanViewController] Scanning configure failed: \(error)")
        }
        scanningSession = scanning

        let coverage = ScanCoverageViewModel(session: scanning)
        coverageViewModel = coverage
        coverage.$compositeTexture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] texture in
                guard let self, let texture, isMeshing else { return }
                visualizationView.setTexture(copyFrom: texture)
            }
            .store(in: &cancellables)

        // Tekstura uchun kamera keyframe'larini yig'amiz + xotira nazorati.
        // Katta xonada xotira to'lib crash bo'lmasligi uchun — kritik darajada
        // skanni avtomatik xavfsiz to'xtatamiz (crash o'rniga tayyor natija).
        arManager.nsdkView.scene.addAnchor(coverageOverlay.anchor)

        arManager.onFrame = { [weak self] frame in
            guard let self, isMeshing else { return }
            keyframeStore.maybeCapture(frame: frame)
            // Yangi keyframe olingan bo'lsa — qamrovni yangilaymiz
            if keyframeStore.count > lastKeyframeCount {
                lastKeyframeCount = keyframeStore.count
                let t = frame.camera.transform
                let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                let fwd = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
                DispatchQueue.main.async { [weak self] in self?.coverageOverlay.addKeyframe(position: pos, forward: fwd) }
            }
            if os_proc_available_memory() < 350 * 1024 * 1024, !isStoppingForMemory {
                isStoppingForMemory = true
                DispatchQueue.main.async { [weak self] in
                    guard let self, isMeshing else { return }
                    infoLabel.text = "Xotira to'ldi — skan avtomatik to'xtatildi"
                    stopMeshing()
                }
            }
        }

        // Chunk statistikasi (sahnaga entity qo'shmaymiz — qamrovni chiziqlar ko'rsatadi)
        viewModel.updatedMeshChunks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chunkChanges in
                guard let self else { return }
                for (id, entity) in chunkChanges {
                    if entity == nil {
                        chunkIds.remove(id)
                    } else {
                        chunkIds.insert(id)
                    }
                }
                // Qamrov overlay'iga uzatamiz (entity'ni qayta ishlatadi — rang beradi)
                coverageOverlay.apply(chunkChanges)
                if isMeshing {
                    let pct = Int(coverageOverlay.coverageFraction * 100)
                    // "Tekstura" — olingan YUZA qamrovi (xona to'liqligini EMAS: qora/bo'sh
                    // joylar hisobga olinmaydi, shuning uchun 100% ≠ xona tayyor).
                    infoLabel.text = "Tekstura: \(pct)% · rasm: \(keyframeStore.count) · chunk: \(chunkIds.count)"
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arManager.startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMeshing { stopMeshing() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arManager.stopSession()
        if isMovingFromParent {
            arManager.onFrame = nil
            meshingSession?.stop()
            meshingSession = nil
            scanningSession?.stop()
            scanningSession = nil
            keyframeStore.clear()
            cancellables.removeAll()
        }
    }

    // MARK: - Meshing Lifecycle

    private func startMeshing() {
        guard let meshingSession else { return }
        isMeshing = true

        chunkIds.removeAll()
        viewModel.clear()
        keyframeStore.clear()
        lastKeyframeCount = 0
        coverageOverlay.reset()
        coverageOverlay.setVisible(coverageOn)
        bakedModel = nil
        atlasModel = nil
        finalGeometries = nil
        currentScanFolder = nil
        isStoppingForMemory = false

        var config = NSDKMeshingSession.Configuration()
        config.fuseKeyframesOnly = true
        config.voxelSize = 0.02
        do {
            try meshingSession.configure(with: config)
            meshingSession.start()
        } catch {
            print("[MeshScanViewController] Meshing start failed: \(error)")
            isMeshing = false
            infoLabel.text = "Meshing'ni boshlab bo'lmadi"
            return
        }

        scanningSession?.start()
        visualizationView.reset()
        visualizationView.isHidden = false

        startScanTimer()
        hintLabel.isHidden = false

        meshButton.setTitle("Skanni to'xtatish", for: .normal)
        exportButton.isHidden = true
        viewButton.isHidden = true
        hqButton.isHidden = true
        splatButton.isHidden = true
        hqButton.setTitle("Yuqori sifat", for: .normal)
        atlasModel = nil
        infoLabel.text = ""
    }

    private func stopMeshing() {
        isMeshing = false
        meshingSession?.stop()
        scanningSession?.stop()
        coverageOverlay.setVisible(false)
        coverageOverlay.reset()

        visualizationView.isHidden = true
        visualizationView.reset()
        stopScanTimer()
        hintLabel.isHidden = true

        meshButton.setTitle("Skanni boshlash", for: .normal)

        guard viewModel.hasGeometry else {
            finalGeometries = nil
            exportButton.isHidden = true
            viewButton.isHidden = true
            hqButton.isHidden = true
            infoLabel.text = "Mesh yig'ilmadi — qayta urinib ko'ring"
            return
        }

        // Per-chunk foto-tekstura (xatlas/8K yo'q — tezroq, real xona ko'rinishi).
        let geometries = viewModel.snapshotGeometries()
        finalGeometries = geometries
        let keyframes = keyframeStore.snapshot()
        isProcessing = true
        meshButton.isEnabled = false
        exportButton.isHidden = true
        viewButton.isHidden = true
        infoLabel.text = "Teksturalanmoqda… 0%"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Xom skanni doimiy arxivga saqlash (keyframes + NSDK mesh) — keyin ko'rish/qayta ishlash
            let folder = ScanArchive.saveRaw(keyframes: keyframes, geometries: geometries)
            DispatchQueue.main.async { [weak self] in self?.currentScanFolder = folder }

            // Per-chunk foto-tekstura (real detal — "12:02" natijasi)
            let baked = TextureBaker.bake(geometries: geometries, keyframes: keyframes) { done, total in
                DispatchQueue.main.async { [weak self] in
                    let p = total > 0 ? done * 100 / total : 0
                    self?.infoLabel.text = "Teksturalanmoqda… \(p)%"
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isProcessing = false
                meshButton.isEnabled = true
                bakedModel = baked.isEmpty ? nil : baked
                let hasResult = bakedModel != nil
                exportButton.isHidden = !hasResult
                viewButton.isHidden = !hasResult
                hqButton.isHidden = !hasResult
                splatButton.isHidden = !hasResult
                infoLabel.text = hasResult
                    ? "Tayyor — \(baked.count) bo'lak, \(keyframes.count) rasm"
                    : "Teksturalab bo'lmadi — qayta urinib ko'ring"
            }
        }
    }

    // MARK: - Processing (bake)

    private func processModel() {
        guard !isProcessing else { return }
        isProcessing = true
        meshButton.isEnabled = false
        exportButton.isHidden = true
        viewButton.isHidden = true
        infoLabel.text = "Qayta ishlanmoqda… 0%"

        let geometries = viewModel.snapshotGeometries()
        let keyframes = keyframeStore.snapshot()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Geometriya = NSDK zich TSDF mesh (weld + tozalash), keyin yagona
            // 8192 atlas (GPU bake). Dekompilyatsiya: Scaniverse ham TSDF, Poisson emas.
            // Nuqta buluti (PLY) endi faqat eksportda quriladi — tezlik uchun.
            let atlas = GlobalTextureBaker.bake(
                geometries: geometries, keyframes: keyframes,
                overrideMesh: nil, resolution: 8192
            ) { stage, percent in
                DispatchQueue.main.async { [weak self] in
                    self?.infoLabel.text = "\(stage)… \(percent)%"
                }
            }

            // Fallback: atlas yiqilsa eski chunk-boyicha bake
            var fallback: [Int64: TextureBaker.BakedChunk]?
            if atlas == nil {
                fallback = TextureBaker.bake(
                    geometries: geometries, keyframes: keyframes
                ) { done, total in
                    DispatchQueue.main.async { [weak self] in
                        let percent = total > 0 ? done * 100 / total : 0
                        self?.infoLabel.text = "Qayta ishlanmoqda (fallback)… \(percent)%"
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isProcessing = false
                meshButton.isEnabled = true
                atlasModel = atlas
                pointCloudPLY = nil
                bakedModel = (fallback?.isEmpty == false) ? fallback : nil
                let hasResult = atlasModel != nil || bakedModel != nil
                exportButton.isHidden = !hasResult
                viewButton.isHidden = !hasResult
                if let atlas {
                    let tris = atlas.indices.count / 3
                    infoLabel.text = "Tayyor — \(tris) uchburchak, \(atlas.atlasWidth)px atlas"
                } else if bakedModel != nil {
                    infoLabel.text = "Tayyor (fallback rejim) — \(keyframes.count) rasm"
                } else {
                    infoLabel.text = "Qayta ishlab bo'lmadi — qayta skan qiling"
                }
            }
        }
    }

    // MARK: - Scan Timer

    private func startScanTimer() {
        scanStartDate = Date()
        timerLabel.text = "00:00"
        timerLabel.isHidden = false
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = scanStartDate else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func stopScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
        timerLabel.isHidden = true
    }

    // MARK: - Export

    @objc private func handleExportTap() {
        let baked = bakedModel
        let geometries = finalGeometries
        guard baked != nil || geometries != nil else { return }
        exportButton.isEnabled = false
        infoLabel.text = "Eksport tayyorlanmoqda…"

        let atlas = atlasModel
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let zipURL: URL
                if let atlas {
                    zipURL = try TexturedOBJExporter.exportAtlas(atlas)
                } else if let baked {
                    zipURL = try TexturedOBJExporter.exportBaked(baked)
                } else {
                    zipURL = try TexturedOBJExporter.exportPlainMesh(MeshWelder.weld(geometries!))
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    exportButton.isEnabled = true
                    infoLabel.text = "Eksport tayyor: \(zipURL.lastPathComponent)"
                    let share = UIActivityViewController(activityItems: [zipURL], applicationActivities: nil)
                    present(share, animated: true)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.exportButton.isEnabled = true
                    self?.infoLabel.text = "Eksportda xato: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Viewer

    @objc private func handleViewTap() {
        var entities: [ModelEntity] = []
        if let atlasModel, let entity = TexturedModelBuilder.makeEntity(atlas: atlasModel) {
            entities = [entity]
        } else if let bakedModel {
            entities = TexturedModelBuilder.makeEntities(baked: bakedModel)
        } else if let finalGeometries {
            entities = TexturedModelBuilder.makeColoredEntities(from: finalGeometries)
        }
        guard !entities.isEmpty else {
            infoLabel.text = "Model qurib bo'lmadi"
            return
        }
        let viewer = ModelViewerViewController(entities: entities)
        navigationController?.pushViewController(viewer, animated: true)
    }

    @objc private func handleMeshTap() {
        if isMeshing { stopMeshing() } else { startMeshing() }
    }

    // MARK: - Splat (beta) — LiDAR nuqta bulutidan Gaussian splat

    @objc private func handleSplatTap() {
        guard !isProcessing else { return }
        let keyframes = keyframeStore.snapshot()
        guard !keyframes.isEmpty else { return }
        isProcessing = true
        splatButton.isEnabled = false
        meshButton.isEnabled = false
        infoLabel.text = "Splat tayyorlanmoqda… (nuqta buluti)"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cloud = PointCloudBuilder.build(keyframes: keyframes)
            let model = GaussianSplatModel.initialize(from: cloud, initialScale: 0.02)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isProcessing = false
                splatButton.isEnabled = true
                meshButton.isEnabled = true
                guard !model.splats.isEmpty else {
                    infoLabel.text = "Splat qilib bo'lmadi"
                    return
                }
                infoLabel.text = "Splat: \(model.splats.count) ta"
                navigationController?.pushViewController(
                    SplatViewerViewController(model: model), animated: true
                )
            }
        }
    }

    // MARK: - Yuqori sifat (yagona atlas — Scaniverse darajasi)

    /// Yuqori sifat — ON-DEVICE. Mac'dagi mvs-texturing (texrecon) pipeline'ining aynan o'zi,
    /// iOS `libtexios.a` orqali: nuqta buluti → Hoppe sirt → scene(.cam/jpg) → ios_texture()
    /// (view selection + global/local seam leveling + atlas). Server yo'q, telefonда.
    @objc private func toggleCoverage() {
        coverageOn.toggle()
        coverageOverlay.setVisible(coverageOn && isMeshing)
        navigationItem.rightBarButtonItems?.last?.title = coverageOn ? "Qamrov ✓" : "Qamrov ✗"
    }

    @objc private func openLibrary() {
        navigationController?.pushViewController(ScanLibraryViewController(), animated: true)
    }

    @objc private func handleHQTap() {
        guard !isProcessing, let geometries = finalGeometries else { return }
        let keyframes = keyframeStore.snapshot()
        isProcessing = true
        hqButton.isEnabled = false
        meshButton.isEnabled = false
        infoLabel.text = "Yuqori sifat (on-device)… (\(keyframes.count) kadr)"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Xom skanni doimiy saqlash (keyframes + NSDK mesh.ply) — qayta ishlash/ko'rish uchun
            let scanFolder = self?.currentScanFolder ?? ScanArchive.saveRaw(keyframes: keyframes, geometries: geometries)
            DispatchQueue.main.async { [weak self] in self?.currentScanFolder = scanFolder }

            let result = OnDeviceTexturing.run(meshPLY: ScanArchive.meshPLY(in: scanFolder), keyframes: keyframes) { stage in
                DispatchQueue.main.async { [weak self] in self?.infoLabel.text = stage }
            }
            if let result { ScanArchive.saveResult(from: result.folder, into: scanFolder) }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isProcessing = false
                hqButton.isEnabled = true
                meshButton.isEnabled = true
                if let result {
                    hqButton.setTitle("Yuqori sifat ✓", for: .normal)
                    let stat = String(format: "Yuqori sifat: %.1f s, %d uchburchak", result.seconds, result.faces)
                    infoLabel.text = stat + " · saqlandi"
                    let viewer = OBJViewerViewController(objURL: result.objURL, stat: stat)
                    navigationController?.pushViewController(viewer, animated: true)
                } else {
                    infoLabel.text = "Yuqori sifat qilib bo'lmadi"
                }
            }
        }
    }

    // MARK: - UI Setup

    private func setupVisualizationView() {
        visualizationView = TextureView(
            frame: view.bounds,
            vertexShader: "scanningVertexShader",
            fragmentShader: "scanningFragmentShader"
        )
        visualizationView.isOpaque = false
        visualizationView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        visualizationView.isHidden = true
        visualizationView.isUserInteractionEnabled = false
        visualizationView.translatesAutoresizingMaskIntoConstraints = false
        arManager.nsdkView.addSubview(visualizationView)

        NSLayoutConstraint.activate([
            visualizationView.leadingAnchor.constraint(equalTo: arManager.nsdkView.leadingAnchor),
            visualizationView.topAnchor.constraint(equalTo: arManager.nsdkView.topAnchor),
            visualizationView.trailingAnchor.constraint(equalTo: arManager.nsdkView.trailingAnchor),
            visualizationView.bottomAnchor.constraint(equalTo: arManager.nsdkView.bottomAnchor),
        ])
    }

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

        style(meshButton, title: "Skanni boshlash", color: .systemBlue)
        style(exportButton, title: "Eksport (ZIP)", color: .systemGreen)
        style(viewButton, title: "Modelni ko'rish", color: .systemOrange)
        style(hqButton, title: "Yuqori sifat", color: .systemPurple)
        style(splatButton, title: "Splat (beta)", color: .systemTeal)
        exportButton.isHidden = true
        viewButton.isHidden = true
        hqButton.isHidden = true
        splatButton.isHidden = true

        meshButton.addTarget(self, action: #selector(handleMeshTap), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(handleExportTap), for: .touchUpInside)
        viewButton.addTarget(self, action: #selector(handleViewTap), for: .touchUpInside)
        hqButton.addTarget(self, action: #selector(handleHQTap), for: .touchUpInside)
        splatButton.addTarget(self, action: #selector(handleSplatTap), for: .touchUpInside)

        infoLabel.text = "Tayyor"
        infoLabel.textColor = .white
        infoLabel.font = .systemFont(ofSize: 14)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)

        // Ko'rsatma yozuvi (Scaniverse uslubida) — skan paytida ko'rinadi
        hintLabel.text = "🔴 qizil = yaqinroq skan qiling · 🟢 yashil = olindi\n⬛ rangsiz/qora joy = umuman ushlanmagan → o'sha yerni ham skan qiling\n⚠️ Shisha, oyna, ko'zgu 3D'ga tushmaydi (LiDAR ko'rmaydi)\nShift, pol va burchaklarni ham unutmang"
        hintLabel.textColor = .white
        hintLabel.font = .systemFont(ofSize: 16, weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        hintLabel.layer.cornerRadius = 10
        hintLabel.layer.masksToBounds = true
        hintLabel.isHidden = true
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        // Yozib olish taymeri — Scaniverse uslubidagi qizil pill
        timerLabel.text = "00:00"
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        timerLabel.textAlignment = .center
        timerLabel.backgroundColor = .systemRed
        timerLabel.layer.cornerRadius = 6
        timerLabel.layer.masksToBounds = true
        timerLabel.isHidden = true
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerLabel)

        NSLayoutConstraint.activate([
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            timerLabel.widthAnchor.constraint(equalToConstant: 88),
            timerLabel.heightAnchor.constraint(equalToConstant: 30),

            hintLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            hintLabel.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 12),
            hintLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),

            meshButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            meshButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            meshButton.widthAnchor.constraint(equalToConstant: 160),
            meshButton.heightAnchor.constraint(equalToConstant: 44),

            exportButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            exportButton.centerYAnchor.constraint(equalTo: meshButton.centerYAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 160),
            exportButton.heightAnchor.constraint(equalToConstant: 44),

            viewButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            viewButton.bottomAnchor.constraint(equalTo: exportButton.topAnchor, constant: -12),
            viewButton.widthAnchor.constraint(equalToConstant: 160),
            viewButton.heightAnchor.constraint(equalToConstant: 44),

            hqButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            hqButton.bottomAnchor.constraint(equalTo: meshButton.topAnchor, constant: -12),
            hqButton.widthAnchor.constraint(equalToConstant: 160),
            hqButton.heightAnchor.constraint(equalToConstant: 44),

            splatButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            splatButton.bottomAnchor.constraint(equalTo: hqButton.topAnchor, constant: -12),
            splatButton.widthAnchor.constraint(equalToConstant: 160),
            splatButton.heightAnchor.constraint(equalToConstant: 44),

            infoLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            infoLabel.bottomAnchor.constraint(equalTo: splatButton.topAnchor, constant: -12),
        ])
    }
}
