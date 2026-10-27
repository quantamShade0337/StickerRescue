import SwiftUI

struct DiagnosticsView: View {
    let library: StickerLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Import") {
                    DiagnosticRow(label: "Files discovered", value: library.diagnostics.filesDiscovered)
                    DiagnosticRow(label: "Valid stickers", value: library.diagnostics.validStickers)
                    DiagnosticRow(label: "Converted stickers", value: library.diagnostics.convertedStickers)
                    DiagnosticRow(label: "Duplicates removed", value: library.diagnostics.duplicatesRemoved)
                    DiagnosticRow(label: "Failed stickers", value: library.diagnostics.failedStickers)
                    DiagnosticRow(label: "Generated packs", value: library.diagnostics.generatedPacks)
                }

                Section("Source") {
                    LabeledContent("Folder", value: library.sourceFolderName)
                    LabeledContent("Imported", value: library.importedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if !library.failures.isEmpty {
                    Section {
                        ForEach(library.failures) { failure in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failure.filename).font(.headline)
                                Text(failure.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("Failed Files")
                    } footer: {
                        Text("The remaining stickers were processed normally.")
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: Int

    var body: some View {
        LabeledContent(label, value: value.formatted())
    }
}
