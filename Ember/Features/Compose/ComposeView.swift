// ComposeView.swift

import MessageUI
import SwiftData
import SwiftUI

/// The payoff screen of a nudge: context card, an editable AI-drafted opener,
/// and one button into Messages. Sent messages are logged as interactions —
/// automatically when the composer confirms, with a gentle question on the
/// sms:-URL fallback where the result is unknowable.
struct ComposeView: View {
    let person: Person

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @FocusState private var draftFocused: Bool
    @State private var draft = ""
    @State private var isGenerating = false
    @State private var phoneNumber: String?
    @State private var daysUntilBirthday: Int?
    @State private var showMessageSheet = false
    @State private var askIfSent = false
    @State private var awaitingSMSReturn = false

    private var lastInteractions: [Interaction] {
        person.interactions.sorted { $0.date > $1.date }.prefix(2).map { $0 }
    }

    private var openCommitments: [Commitment] {
        person.commitments.filter { !$0.isDone }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                contextCard
                draftSection
                sendButtons
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if draftFocused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) {
                        draftFocused = false
                    }
                }
            }
        }
        .navigationTitle(person.displayNameCache)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Close")) { dismiss() }
            }
        }
        .sheet(isPresented: $showMessageSheet) {
            if let phoneNumber {
                MessageComposeSheet(recipient: phoneNumber, body: draft) { result in
                    showMessageSheet = false
                    if result == .sent {
                        logSentInteraction()
                    }
                }
                .ignoresSafeArea()
            }
        }
        .confirmationDialog(String(localized: "Did you send it?"), isPresented: $askIfSent, titleVisibility: .visible) {
            Button(String(localized: "Yes — log it")) { logSentInteraction() }
            Button(String(localized: "Not this time"), role: .cancel) {}
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && awaitingSMSReturn {
                awaitingSMSReturn = false
                askIfSent = true
            }
        }
        .task {
            #if DEBUG
            // Demo people are unlinked; a stand-in number keeps the real send button in shot.
            if DemoSeed.isActive { phoneNumber = "+15550100" }
            #endif
            if let contactID = person.contactID {
                let resolved = await services.contacts.resolve(contactID)
                phoneNumber = resolved?.phoneNumbers.first?.number
                if let birthday = resolved?.birthday ?? person.manualBirthday {
                    daysUntilBirthday = BirthdayMath.daysUntilNextBirthday(birthday, from: .now)
                }
            } else if let birthday = person.manualBirthday {
                daysUntilBirthday = BirthdayMath.daysUntilNextBirthday(birthday, from: .now)
            }
            if draft.isEmpty {
                await generateDraft()
            }
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lastInteractions) { interaction in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: interaction.channel.symbolName)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(interaction.note?.isEmpty == false ? interaction.note! : interaction.channel.title)
                            .font(.subheadline)
                        Text(NeutralPhrases.phrase(for: interaction.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(openCommitments) { commitment in
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    Text(String(localized: "You said you'd \(commitment.text)"))
                        .font(.subheadline)
                }
            }
            if let daysUntilBirthday, daysUntilBirthday <= 7 {
                HStack(spacing: 8) {
                    Image(systemName: "gift")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    Text(daysUntilBirthday == 0
                        ? String(localized: "Birthday today 🎂")
                        : String(localized: "Birthday in \(daysUntilBirthday) days"))
                        .font(.subheadline)
                }
            }
            if lastInteractions.isEmpty && openCommitments.isEmpty && daysUntilBirthday == nil {
                Text(String(localized: "A fresh start — anything kind counts."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Your message"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await generateDraft() }
                } label: {
                    Label(String(localized: "Redraft"), systemImage: "sparkles")
                        .font(.subheadline)
                }
                .disabled(isGenerating)
            }
            TextEditor(text: $draft)
                .focused($draftFocused)
                .frame(minHeight: 90)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty && !isGenerating {
                        Text(String(localized: "Write something small — it counts."))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 18)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                    if isGenerating {
                        ProgressView()
                            .padding(18)
                    }
                }
        }
    }

    private var sendButtons: some View {
        VStack(spacing: 10) {
            if phoneNumber != nil {
                Button {
                    openMessages()
                } label: {
                    Label(String(localized: "Send in Messages"), systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text(String(localized: "No phone number on file — copy the message and send it your way."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                UIPasteboard.general.string = draft
            } label: {
                Label(String(localized: "Copy message"), systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func generateDraft() async {
        isGenerating = true
        defer { isGenerating = false }
        let context = DraftContext(
            displayName: person.displayNameCache,
            lastInteractionNotes: lastInteractions.compactMap(\.note),
            openCommitments: openCommitments.map(\.text),
            daysUntilBirthday: daysUntilBirthday.flatMap { $0 <= 7 ? $0 : nil }
        )
        if let generated = await services.drafts.draft(for: context) {
            draft = generated
        }
    }

    private func openMessages() {
        guard let phoneNumber else { return }
        if MessageComposeSheet.canSendText {
            showMessageSheet = true
        } else {
            var components = URLComponents()
            components.scheme = "sms"
            components.path = phoneNumber
            components.queryItems = [URLQueryItem(name: "body", value: draft)]
            if let url = components.url {
                awaitingSMSReturn = true
                openURL(url)
            }
        }
    }

    private func logSentInteraction() {
        modelContext.insert(Interaction(person: person, date: .now, channel: .message))
        try? modelContext.save()
        Task {
            let logs = (try? modelContext.fetch(FetchDescriptor<NudgeLog>())) ?? []
            if let pending = logs.filter({ $0.personID == person.id && $0.outcome == .pending }).max(by: { $0.date < $1.date }) {
                pending.outcome = .actedOn
                try? modelContext.save()
            }
        }
        dismiss()
    }
}
