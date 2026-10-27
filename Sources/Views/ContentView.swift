import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: StickerLibraryModel
    @State private var isChoosingFolder = false
    @State private var showsDiagnostics = false

    private let columns = [GridItem(.adaptive(minimum: 310), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ImportHeader(
                        library: model.library,
                        isImporting: model.isImporting,
                        progress: model.progress,
                        chooseFolder: { isChoosingFolder = true }
                    )
                    if let library = model.library {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(library.packs) { pack in
                                PackCard(pack: pack, model: model)
                            }
                        }
                    } else if !model.isImporting {
                        ContentUnavailableView(
                            "No Sticker Packs Yet",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("Choose the recovered WhatsApp Stickers folder in Files to begin.")
                        )
                        .padding(.top, 32)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("StickerRescue")
            .toolbar {
                if model.library != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Diagnostics", systemImage: "waveform.path.ecg") { showsDiagnostics = true }
                    }
                }
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let folderURL = urls.first { model.importFolder(folderURL) }
                case .failure(let error):
                    model.presentedError = .init(title: "Folder Selection Failed", message: error.localizedDescription)
                }
            }
            .sheet(isPresented: $showsDiagnostics) {
                if let library = model.library { DiagnosticsView(library: library) }
            }
            .alert(
                model.presentedError?.title ?? "Error",
                isPresented: Binding(
                    get: { model.presentedError != nil },
                    set: { if !$0 { model.presentedError = nil } }
                ),
                presenting: model.presentedError
            ) { _ in
                Button("OK") { model.presentedError = nil }
            } message: { error in
                Text(error.message)
            }
        }
    }
}

private struct ImportHeader: View {
    let library: StickerLibrary?
    let isImporting: Bool
    let progress: ImportProgress?
    let chooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "lifepreserver.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.blue.gradient, in: .rect(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recover your stickers").font(.title2.bold())
                    if let library {
                        Text("\(library.diagnostics.validStickers) stickers in \(library.packs.count) packs")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Import once, then add each pack to WhatsApp.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isImporting, let progress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(progress.stage.rawValue).font(.headline)
                        Spacer()
                        if progress.total > 0 {
                            Text("\(progress.completed) / \(progress.total)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: progress.fraction)
                    if let filename = progress.filename {
                        Text(filename).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }

            Button(action: chooseFolder) {
                Label(library == nil ? "Select Sticker Folder" : "Select a Different Folder", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isImporting)
        }
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.separator.opacity(0.3), lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
    }
}

private struct PackCard: View {
    let pack: RecoveredPack
    let model: StickerLibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name).font(.headline)
                    Text("\(pack.stickerCount) stickers").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Label(pack.isAdded ? "Added" : "Not Added", systemImage: pack.isAdded ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pack.isAdded ? .green : .secondary)
            }
            HStack(spacing: 8) {
                ForEach(Array(pack.stickerPaths.prefix(5).enumerated()), id: \.element) { _, path in
                    StickerThumbnail(relativePath: path, model: model)
                }
            }
            Button { model.addToWhatsApp(pack) } label: {
                Label(pack.isAdded ? "Add Again" : "Add to WhatsApp", systemImage: "arrow.up.forward.app.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.separator.opacity(0.3), lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
    }
}

private struct StickerThumbnail: View {
    let relativePath: String
    let model: StickerLibraryModel
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .padding(5)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .task(id: relativePath) {
            guard let url = await model.stickerURL(relativePath: relativePath) else { return }
            image = UIImage(contentsOfFile: url.path)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView(model: StickerLibraryModel())
}
