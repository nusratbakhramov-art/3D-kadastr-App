import UIKit

/// Saqlangan skanlar ro'yxati. Har skanni: natijasini ko'rish, QAYTA ISHLASH
/// (bug tuzatgandan keyin), yoki o'chirish mumkin.
final class ScanLibraryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var entries: [ScanArchive.Entry] = []
    private var isProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Skanlar"
        view.backgroundColor = .systemBackground
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        view.addSubview(table)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        entries = ScanArchive.list()
        table.reloadData()
    }

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { entries.count }

    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip)
        let e = entries[ip.row]
        var cfg = cell.defaultContentConfiguration()
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        cfg.text = df.string(from: e.date)
        cfg.secondaryText = "\(e.keyframeCount) kadr" + (e.hasResult ? " · ✓ natija bor" : "")
        cell.contentConfiguration = cfg
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        guard !isProcessing else { return }
        let e = entries[ip.row]
        let sheet = UIAlertController(title: e.name, message: "\(e.keyframeCount) kadr", preferredStyle: .actionSheet)
        if let obj = ScanArchive.resultOBJ(in: e.folder) {
            sheet.addAction(UIAlertAction(title: "Natijani ko'rish", style: .default) { [weak self] _ in
                self?.navigationController?.pushViewController(OBJViewerViewController(objURL: obj), animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "Qayta ishlash (Yuqori sifat)", style: .default) { [weak self] _ in
            self?.reprocess(e)
        })
        sheet.addAction(UIAlertAction(title: "O'chirish", style: .destructive) { [weak self] _ in
            ScanArchive.delete(e); self?.reload()
        })
        sheet.addAction(UIAlertAction(title: "Bekor", style: .cancel))
        sheet.popoverPresentationController?.sourceView = table.cellForRow(at: ip)
        present(sheet, animated: true)
    }

    private func reprocess(_ e: ScanArchive.Entry) {
        isProcessing = true
        let hud = UIAlertController(title: "Qayta ishlanmoqda…", message: "\n", preferredStyle: .alert)
        present(hud, animated: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let keyframes = ScanArchive.loadKeyframes(from: e.folder)
            // mesh.ply bo'lsa (yangi skan) ishlatiladi, aks holda keyframe'lardan qayta quriladi
            let result = OnDeviceTexturing.run(meshPLY: ScanArchive.meshPLY(in: e.folder), keyframes: keyframes) { stage in
                DispatchQueue.main.async { hud.message = "\n\(stage)" }
            }
            if let result { ScanArchive.saveResult(from: result.folder, into: e.folder) }
            DispatchQueue.main.async { [weak self] in
                self?.isProcessing = false
                hud.dismiss(animated: true) {
                    guard let self else { return }
                    if let result {
                        let stat = String(format: "%.1f s · %d uchburchak", result.seconds, result.faces)
                        self.navigationController?.pushViewController(
                            OBJViewerViewController(objURL: result.objURL, stat: stat), animated: true)
                    } else {
                        let a = UIAlertController(title: "Xato", message: "Qayta ishlab bo'lmadi (kadr: \(keyframes.count))", preferredStyle: .alert)
                        a.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(a, animated: true)
                    }
                    self.reload()
                }
            }
        }
    }
}
