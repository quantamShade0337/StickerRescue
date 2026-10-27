import Foundation
import Observation

@MainActor
@Observable
final class StickerLibraryModel {
    private(set) var library: StickerLibrary?
    private(set) var progress: ImportProgress?
    private(set) var isImporting = false
    var presentedError: PresentedError?

    @ObservationIgnored private let store: LocalLibraryStore
    @ObservationIgnored private let importer: StickerImportService
    @ObservationIgnored private var importTask: Task<Void, Never>?

    struct PresentedError: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(store: LocalLibraryStore = LocalLibraryStore()) {
        self.store = store
        self.importer = StickerImportService(store: store)
        Task { await loadSavedLibrary() }
    }

    func importFolder(_ url: URL) {
        importTask?.cancel()
        importTask = Task {
            isImporting = true
            progress = ImportProgress(stage: .discovering, completed: 0, total: 0, filename: nil)
            defer {
                isImporting = false
                progress = nil
            }

            do {
                library = try await importer.importFolder(url) { [weak self] update in
                    self?.progress = update
                }
            } catch is CancellationError {
                return
            } catch {
                showError(title: "Import Failed", error: error)
            }
        }
    }

    func addToWhatsApp(_ pack: RecoveredPack) {
        guard let library else { return }
        Task {
            do {
                guard Interoperability.canSend() else { throw StickerRescueError.whatsappUnavailable }
                let trayURL = await store.absoluteURL(batchID: library.batchID, relativePath: pack.trayImagePath)
                let exportPack = try StickerPack(
                    identifier: pack.id,
                    name: pack.name,
                    publisher: pack.publisher,
                    trayImagePNGData: Data(contentsOf: trayURL)
                )
                for path in pack.stickerPaths {
                    let url = await store.absoluteURL(batchID: library.batchID, relativePath: path)
                    try exportPack.addSticker(imageData: Data(contentsOf: url))
                }
                try exportPack.sendToWhatsApp { didSend in
                    if didSend {
                        Task { await self.markAdded(packID: pack.id) }
                    } else {
                        self.showError(
                            title: "Export Failed",
                            error: StickerRescueError.exportFailed("WhatsApp rejected the handoff.")
                        )
                    }
                }
            } catch {
                showError(title: "Export Failed", error: error)
            }
        }
    }

    func stickerURL(relativePath: String) async -> URL? {
        guard let library else { return nil }
        return await store.absoluteURL(batchID: library.batchID, relativePath: relativePath)
    }

    private func loadSavedLibrary() async {
        do {
            library = try await store.load()
        } catch {
            showError(title: "Saved Library Unavailable", error: error)
        }
    }

    private func markAdded(packID: String) async {
        do {
            library = try await store.updateAddedState(packID: packID, isAdded: true)
        } catch {
            showError(title: "Could Not Save Status", error: error)
        }
    }

    private func showError(title: String, error: Error) {
        presentedError = PresentedError(title: title, message: error.localizedDescription)
    }
}
