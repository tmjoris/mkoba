import MkobaAssist
import MkobaCore
import SwiftUI

/// The treasurer pastes the M-Pesa messages members' payments produced. Each one becomes a
/// proposed contribution that plain code has checked against the message and the books.
/// Only entries that passed every check are ticked; nothing is recorded until Record.
struct ImportMessagesView: View {
    @Bindable var session: GroupSession
    @Environment(\.dismiss) private var dismiss
    @State private var paste = ""
    @State private var reviews: [ImportReview] = []
    @State private var chosen: Set<Int> = []
    @State private var isReading = false
    @State private var error: String?
    @FocusState private var pasteFocused: Bool
    private let importer = MessageImporter.best()

    var body: some View {
        Form {
            Section {
                TextEditor(text: $paste)
                    .frame(minHeight: 140)
                    .font(.callout)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($pasteFocused)
                    .accessibilityIdentifier("import-paste")
                Button {
                    Task { await read() }
                } label: {
                    Label(isReading ? "Reading…" : "Read messages", systemImage: "text.viewfinder")
                }
                .disabled(isReading || paste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("import-read")
            } header: {
                Text("Paste M-Pesa messages")
            } footer: {
                Text(importer.engine == .onDeviceModel
                     ? "Standard M-Pesa SMS are read by Mkoba's rules and anything else by Apple's on-device model, then every entry is checked against its message and the books. Nothing leaves the phone."
                     : "Read with Mkoba's M-Pesa SMS rules, then checked against the books. Turn on Apple Intelligence to read notes and Swahili messages too.")
            }
            if !reviews.isEmpty {
                Section("What they say") {
                    ForEach(Array(reviews.enumerated()), id: \.offset) { index, review in
                        ImportRow(review: review, member: review.member.flatMap(session.member),
                                  isOn: binding(index))
                    }
                }
            }
            ErrorBanner(message: error)
        }
        .navigationTitle("Import from SMS")
        .toolbar {
            Button("Record \(chosen.count)") { Task { await record() } }
                .disabled(chosen.isEmpty)
                .accessibilityIdentifier("import-record")
        }
    }

    private func binding(_ index: Int) -> Binding<Bool> {
        Binding(get: { chosen.contains(index) },
                set: { isOn in if isOn { chosen.insert(index) } else { chosen.remove(index) } })
    }

    private func read() async {
        pasteFocused = false // put the keyboard away so the results are visible
        isReading = true
        defer { isReading = false }
        error = nil
        reviews = await importer.review(paste: paste, against: session.state)
        chosen = Set(reviews.indices.filter { reviews[$0].decision == .record })
    }

    private func record() async {
        var refused: [String] = []
        for index in chosen.sorted() {
            guard let kind = reviews[index].event else { continue }
            do {
                let event = try await session.record(kind)
                if let rejection = session.rejection(of: event) { refused.append(rejection.userMessage) }
            } catch {
                refused.append(error.localizedDescription)
            }
        }
        if refused.isEmpty {
            dismiss()
        } else {
            error = refused.joined(separator: "\n")
        }
    }
}

private struct ImportRow: View {
    let review: ImportReview
    let member: Member?
    @Binding var isOn: Bool

    /// A duplicate code must never be recorded, even by hand.
    private var canRecord: Bool {
        review.event != nil
            && !review.issues.contains(.receiptAlreadyRecorded)
            && !review.issues.contains(.receiptRepeated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                badge
                Spacer()
                if let amount = review.amount, review.decision != .skip {
                    MoneyText(amount: amount, font: .headline)
                }
            }
            if review.decision == .skip {
                Text(review.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else {
                HStack {
                    Text(member?.name ?? "Unknown member").font(.subheadline)
                    if let cycle = review.cycle {
                        Text("· cycle \(cycle.index)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let reference = review.reference {
                    Text(reference.mpesaReceipt).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                ForEach(review.issues, id: \.self) { issue in
                    Label(issue.explanation, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                if canRecord {
                    Toggle("Record this", isOn: $isOn).font(.footnote)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import-row")
    }

    private var badge: some View {
        let (title, color): (String, Color) = switch review.decision {
        case .record: ("Ready", Theme.green)
        case .check: ("Check", Theme.gold)
        case .skip: ("Not a payment", .secondary)
        }
        return Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}
