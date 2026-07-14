import Foundation
import RoomPlan

/// M3 — Viewer ekranining holati va tahrirlash amallari.
@MainActor
final class ViewerViewModel: ObservableObject {

    let editableRoom: EditableRoom
    let controller: RoomSceneController
    let hasTexture: Bool

    /// Xona pol maydoni (m²) va perimetri (m) — polygonCorners bo'yicha aniqlangan.
    let floorArea: Float
    let floorPerimeter: Float

    @Published var mode: ViewMode
    @Published var unit: MeasurementUnit = .meters
    @Published var labelsVisible = true
    @Published var firstPerson = false
    @Published var selectedID: UUID?

    var selectedItem: EditableRoom.Item? {
        guard let selectedID else { return nil }
        return editableRoom.item(id: selectedID)
    }

    init(artifacts: ScanArtifacts) {
        let editable = EditableRoom(room: artifacts.capturedRoom)
        self.editableRoom = editable

        // Ustuvorlik: fusion mesh (mesh.bin + colors.bin) → Object Capture zaxirasi.
        let fm = FileManager.default
        let texturedRoomDir: URL? = nil   // projektiv panel usuli o'chirilgan
        let lidarMeshURL = fm.fileExists(atPath: artifacts.paths.lidarMeshURL.path)
            ? artifacts.paths.lidarMeshURL : nil
        let meshColorsURL = fm.fileExists(atPath: artifacts.paths.meshColorsURL.path)
            ? artifacts.paths.meshColorsURL : nil

        self.hasTexture = lidarMeshURL != nil || artifacts.texturedModelURL != nil
        self.floorArea = RoomGeometry.floorArea(of: artifacts.capturedRoom)
        self.floorPerimeter = RoomGeometry.floorPerimeter(of: artifacts.capturedRoom)
        self.mode = self.hasTexture ? .textured : .solid
        self.controller = RoomSceneController(
            room: artifacts.capturedRoom,
            editableRoom: editable,
            texturedModelURL: artifacts.texturedModelURL,
            lidarMeshURL: lidarMeshURL,
            meshColorsURL: meshColorsURL,
            texturedRoomDir: texturedRoomDir
        )
        controller.setMode(mode)
        controller.onSelectionChange = { [weak self] id in
            self?.selectedID = id
        }
    }

    // MARK: - Ko'rinish boshqaruvi

    func setMode(_ newMode: ViewMode) {
        mode = newMode
        controller.setMode(newMode)
    }

    func toggleUnit() {
        unit = (unit == .meters) ? .centimeters : .meters
        controller.setUnit(unit, objects: editableRoom.objects)
    }

    func toggleLabels() {
        labelsVisible.toggle()
        controller.setLabelsVisible(labelsVisible)
    }

    func toggleFirstPerson() {
        firstPerson.toggle()
        controller.setFirstPerson(firstPerson)
    }

    // MARK: - Tahrirlash (FR-9)

    func rename(to category: CapturedRoom.Object.Category) {
        guard let id = selectedID else { return }
        editableRoom.rename(id: id, to: category)
        controller.updateLabelsAfterRename(objects: editableRoom.objects)
        objectWillChange.send()
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        editableRoom.delete(id: id)
        controller.removeObject(id: id, remainingObjects: editableRoom.objects)
        selectedID = nil
    }

    func deselect() {
        controller.select(id: nil)
        selectedID = nil
    }
}
