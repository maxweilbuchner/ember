// ExportView.swift

import SwiftUI

/// Export the whole store as a zip to Files/anywhere, and the delete-everything
/// flow behind a typed confirmation. Both exist for trust — the data is the
/// user's, completely.
struct ExportView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var zipURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showDeleteAlert = false
    @State private var deleteConfirmationText = ""
    @State private var deleteHint: String?

    var body: some View {
        List {
            Section {
                Text(String(localized: "Everything Ember knows — people, entries, interactions, commitments, ideas, and images — as one zip with readable JSON. Nothing is held back."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let zipURL {
                    ShareLink(item: zipURL) {
                        Label(String(localized: "Save or share export"), systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        runExport()
                    } label: {
                        if isExporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(String(localized: "Preparing…"))
                            }
                        } else {
                            Label(String(localized: "Create export"), systemImage: "archivebox")
                        }
                    }
                    .disabled(isExporting)
                }
                if let exportError {
                    Text(exportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(String(localized: "Export"))
            }

            Section {
                Button(role: .destructive) {
                    deleteConfirmationText = ""
                    deleteHint = nil
                    showDeleteAlert = true
                } label: {
                    Label(String(localized: "Delete everything"), systemImage: "trash")
                }
                if let deleteHint {
                    Text(deleteHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Danger"))
            } footer: {
                Text(String(localized: "Removes every person, entry, and image from this device. There is no cloud copy — export first if you want one."))
            }
        }
        .navigationTitle(String(localized: "Your data"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "Delete everything?"), isPresented: $showDeleteAlert) {
            TextField(String(localized: "Type \"delete\" to confirm"), text: $deleteConfirmationText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button(String(localized: "Delete everything"), role: .destructive) {
                confirmDelete()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This cannot be undone."))
        }
    }

    private func runExport() {
        isExporting = true
        exportError = nil
        Task {
            do {
                zipURL = try await services.export.exportZip()
            } catch {
                exportError = String(localized: "Export failed: \(error.localizedDescription)")
            }
            isExporting = false
        }
    }

    private func confirmDelete() {
        guard deleteConfirmationText.trimmingCharacters(in: .whitespaces).lowercased() == "delete" else {
            deleteHint = String(localized: "Nothing was deleted — type the word \"delete\" to confirm.")
            return
        }
        Task {
            await services.export.deleteEverything()
            services.entrySuggestions = [:]
            hasCompletedOnboarding = false
            dismiss()
        }
    }
}
